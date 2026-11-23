import SwiftUI

struct RootView: View {
    @Environment(AppContainer.self) private var container
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if container.configuration.isConfigured == false && container.isScreenshotMode == false {
                ConfigurationMissingView()
            } else if session.isRestoring {
                ProgressView("ログイン状態を確認中")
            } else if session.userID == nil {
                LoginView()
            } else if let userID = session.userID,
                      store.loadedUserID != userID,
                      store.loadErrorMessage == nil {
                if store.isLoading {
                    ProgressView("データを読み込み中")
                } else {
                    ContentUnavailableView {
                        Label("データの読み込みが必要です", systemImage: "arrow.clockwise")
                    } description: {
                        Text("再読み込みして続けてください。")
                            .foregroundStyle(RecruitTextColor.supporting)
                    } actions: {
                        Button("再読み込み") {
                            Task { await store.reload(userID: userID, force: true) }
                        }
                        .prominentAction()
                    }
                }
            } else {
                MainTabView()
            }
        }
        .task {
            await session.observeAuthChanges()
        }
        .alert("アカウント削除の確認", isPresented: Binding(
            get: { session.accountDeletionNotice != nil },
            set: { if !$0 { session.accountDeletionNotice = nil } }
        )) {
            Button("閉じる", role: .cancel) { session.accountDeletionNotice = nil }
        } message: {
            Text(session.accountDeletionNotice ?? "")
        }
        .onChange(of: session.userID) { oldValue, newValue in
            if oldValue != nil { container.router.reset() }
            Task {
                if let newValue {
                    if let oldValue, oldValue != newValue {
                        await store.reset()
                    }
                    await store.reload(userID: newValue, force: oldValue != newValue)
                } else {
                    container.router.reset()
                    await store.reset()
                }
            }
        }
        .onChange(of: session.credentialRevision) {
            guard let userID = session.userID,
                  (store.loadErrorMessage != nil || store.loadedUserID != userID),
                  store.isLoading == false
            else { return }
            Task { await store.reload(userID: userID, force: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            guard !container.isScreenshotMode, scenePhase == .active, let userID = session.userID,
                  store.loadedUserID == userID else { return }
            Task { await store.rescheduleAllNotificationsIfAuthorized() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            guard !container.isScreenshotMode, scenePhase == .active, let userID = session.userID,
                  store.loadedUserID == userID else { return }
            Task { await store.rescheduleAllNotificationsIfAuthorized() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard !container.isScreenshotMode, phase == .active, let userID = session.userID else { return }
            Task {
                if (store.loadErrorMessage != nil || store.loadedUserID != userID), store.isLoading == false {
                    await store.reload(userID: userID, force: true)
                } else if store.loadedUserID == userID {
                    let didReload = await store.reloadIfStale(userID: userID)
                    if didReload == false,
                       session.userID == userID,
                       store.loadedUserID == userID {
                        await store.rescheduleAllNotificationsIfAuthorized()
                    }
                }
            }
        }
    }
}

private struct ConfigurationMissingView: View {
    var body: some View {
        ContentUnavailableView {
            Label("アプリを利用できません", systemImage: "wrench.and.screwdriver")
        } description: {
            Text("アプリの接続設定に問題があります。お問い合わせください。")
                .foregroundStyle(RecruitTextColor.supporting)
        } actions: {
            Link("お問い合わせ", destination: AppLinks.support)
        }
        .padding()
    }
}
