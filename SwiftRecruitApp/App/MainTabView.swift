import SwiftUI
import UIKit

struct MainTabView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var presentationController: UIViewController?

    private struct RoutingKey: Equatable {
        let target: NotificationTarget?
        let phase: ScenePhase
    }

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            HomeView()
                .tabItem { Label("ホーム", systemImage: "house") }
                .tag(AppTab.home)

            RecruitCalendarView()
                .tabItem { Label("カレンダー", systemImage: "calendar") }
                .tag(AppTab.calendar)

            CompaniesView()
                .tabItem { Label("企業", systemImage: "building.2") }
                .tag(AppTab.companies)

            TasksView()
                .tabItem { Label("ToDo", systemImage: "checklist") }
                .tag(AppTab.tasks)

        }
        .background(NotificationPresentationProbe { presentationController = $0 }.frame(width: 0, height: 0))
        .sheet(item: Binding(
            get: { router.notificationRoute.active },
            set: { if $0 == nil { router.notificationRoute.dismiss() } }
        )) { request in
            NotificationRoutePresentation(request: request)
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveRecruitNotification)) { notification in
            PendingNotificationStore.clear()
            enqueue(notification.userInfo)
        }
        .onAppear { enqueue(PendingNotificationStore.take()) }
        .task(id: RoutingKey(target: router.notificationRoute.pending, phase: scenePhase)) {
            guard scenePhase == .active else { return }
            // Poll only for a queued tap: covers sheets, alerts and interactive dismissal
            // without taking over delegates or discarding any existing draft.
            while router.notificationRoute.pending != nil {
                if scenePhase == .active, !session.isRestoring, !store.isSaving,
                   let request = router.notificationRoute.begin(
                       userID: session.userID,
                       blocked: NotificationPresentationProbe.isBlocked(presentationController)
                   ) {
                    switch request.target.kind {
                    case .task: router.openTasks()
                    case .selection:
                        router.selectedTab = .companies
                        router.companyPath = []
                    }
                }
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
        }
    }

    private func enqueue(_ userInfo: [AnyHashable: Any]?) {
        guard let userInfo, let target = NotificationTarget(userInfo: userInfo) else { return }
        router.notificationRoute.enqueue(target, currentUserID: session.userID)
    }
}
