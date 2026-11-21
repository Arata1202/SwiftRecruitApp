import SwiftUI
import UIKit

struct NotificationRoutePresentation: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store
    let request: NotificationRouteState.Request

    var body: some View {
        Group {
            if session.userID != request.ownerUserID {
                Color.clear
            } else if router.notificationRoute.phase == .ready {
                switch request.target.kind {
                case .task:
                    TaskDetailView(taskID: request.target.itemID, ownerUserID: request.ownerUserID,
                                   onDeleted: close)
                case .selection:
                    SelectionStepDetailView(stepID: request.target.itemID, ownerUserID: request.ownerUserID,
                                            onDeleted: close)
                }
            } else {
                NavigationStack {
                    Group {
                        switch router.notificationRoute.phase {
                        case .failed:
                            DataLoadFailureView(
                                title: "項目を読み込めませんでした",
                                message: "通信状態を確認して、もう一度お試しください。"
                            ) {
                                router.notificationRoute.retry()
                            }
                        case .missing:
                            ContentUnavailableView {
                                Label("項目が見つかりません", systemImage: "questionmark.folder")
                            } description: {
                                Text("この項目は見つかりません。削除された可能性があります")
                            } actions: {
                                Button("一覧へ") { close() }
                            }
                        default:
                            ProgressView("項目を読み込み中")
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("閉じる", action: close)
                        }
                    }
                }
            }
        }
        .task(id: router.notificationRoute.phase) {
            guard router.notificationRoute.phase == .loading else { return }
            // Other reloads/saves can be in flight on foreground. Do not mistake
            // a skipped reload or retained cache for an authoritative absence.
            while store.isLoading || store.isSaving {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard isCurrent else { return }
            }
            guard isCurrent else { return }
            let revision = store.successfulReloadRevision
            await store.reload(userID: request.ownerUserID, force: true)
            guard !Task.isCancelled, isCurrent else { return }
            let succeeded = store.loadedUserID == request.ownerUserID
                && store.successfulReloadRevision != revision
            router.notificationRoute.finish(request, currentUserID: session.userID,
                                             succeeded: succeeded, exists: targetExists)
        }
    }

    private var isCurrent: Bool {
        session.userID == request.ownerUserID && router.notificationRoute.active == request
    }

    private var targetExists: Bool {
        switch request.target.kind {
        case .task:
            store.tasks.contains { $0.id == request.target.itemID && $0.userID == request.ownerUserID }
        case .selection:
            store.selectionSteps.contains { step in
                step.id == request.target.itemID && step.userID == request.ownerUserID
                    && store.companies.contains { $0.id == step.companyID && $0.userID == request.ownerUserID }
            }
        }
    }

    private func close() { router.notificationRoute.dismiss() }
}

/// Reads the actual presentation tree rather than changing every independent sheet binding.
/// Checked only while a tap is pending; never dismisses another presentation.
struct NotificationPresentationProbe: UIViewControllerRepresentable {
    let onReady: (UIViewController) -> Void
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isUserInteractionEnabled = false
        DispatchQueue.main.async { onReady(controller) }
        return controller
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    @MainActor static func isBlocked(_ controller: UIViewController?) -> Bool {
        guard let controller, let window = controller.viewIfLoaded?.window,
              let root = window.rootViewController else { return true }
        func busy(_ viewController: UIViewController) -> Bool {
            viewController.presentedViewController != nil || viewController.isBeingPresented
                || viewController.isBeingDismissed || viewController.transitionCoordinator != nil
                || viewController.children.contains(where: busy)
        }
        return busy(root)
    }
}
