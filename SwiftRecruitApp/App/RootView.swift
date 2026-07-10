import SwiftUI

struct RootView: View {
    @Environment(AppContainer.self) private var container
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    var body: some View {
        Group {
            if container.configuration.isConfigured == false {
                ConfigurationMissingView()
            } else if session.isRestoring {
                ProgressView("ログイン状態を確認中")
            } else if session.userID == nil {
                LoginView()
            } else {
                MainTabView()
            }
        }
        .task {
            await session.restore()
            if let userID = session.userID {
                await store.reload(userID: userID)
            }
        }
        .task {
            await session.observeAuthChanges()
        }
        .onChange(of: session.userID) { oldValue, newValue in
            Task {
                if let newValue {
                    await store.reload(userID: newValue, force: oldValue != newValue)
                } else {
                    container.router.reset()
                    await store.reset()
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
