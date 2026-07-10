import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store
    @Environment(AppContainer.self) private var container
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var confirmsSignOut = false
    @State private var showsAccountDeletion = false

    var body: some View {
        List {
            Section("通知") {
                LabeledContent("通知") {
                    Text(notificationStatusTitle)
                        .foregroundStyle(notificationStatus == .denied ? Color.red : Color.secondary)
                }
                if notificationStatus == .denied {
                    Button("iOSの設定を開く") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            }

            Section("情報") {
                Link(destination: AppLinks.support) {
                    Label("サポート", systemImage: "questionmark.circle")
                }

                Link(destination: AppLinks.privacyPolicy) {
                    Label("プライバシーポリシー", systemImage: "hand.raised")
                }

                LabeledContent("バージョン", value: appVersion)
            }

            Section("アカウント") {
                Button("ログアウト") { confirmsSignOut = true }
                Button("アカウントを削除", role: .destructive) { showsAccountDeletion = true }
            }
        }
        .navigationTitle("設定")
        .task { notificationStatus = await container.notifications.authorizationStatus() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { notificationStatus = await container.notifications.authorizationStatus() }
        }
        .confirmationDialog("ログアウトしますか？", isPresented: $confirmsSignOut, titleVisibility: .visible) {
            Button("ログアウト", role: .destructive) {
                Task {
                    await session.signOut()
                    if session.userID == nil { await store.reset() }
                }
            }
        }
        .sheet(isPresented: $showsAccountDeletion) {
            AccountDeletionView()
        }
    }

    private var notificationStatusTitle: String {
        switch notificationStatus {
        case .notDetermined: "未設定"
        case .denied: "許可されていません"
        case .authorized: "許可済み"
        case .provisional: "仮許可"
        case .ephemeral: "一時的に許可"
        @unknown default: "不明"
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "\(version) (\(build))"
    }

}
