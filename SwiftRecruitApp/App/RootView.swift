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
                ProgressView("データを読み込み中")
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
                  store.loadErrorMessage != nil,
                  store.isLoading == false
            else { return }
            Task { await store.reload(userID: userID, force: true) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, let userID = session.userID else { return }
            Task {
                if store.loadErrorMessage != nil, store.isLoading == false {
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
            Label("接続設定が必要です", systemImage: "wrench.and.screwdriver")
        } description: {
            Text("アプリの接続情報を確認できませんでした。設定を確認して、もう一度起動してください。")
        }
        .padding()
    }
}
