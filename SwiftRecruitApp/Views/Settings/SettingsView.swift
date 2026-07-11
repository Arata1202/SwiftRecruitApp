import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(AppContainer.self) private var container
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isRequestingNotifications = false
    @State private var notificationErrorMessage: String?
    @State private var confirmsSignOut = false
    @State private var showsAccountDeletion = false
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue

    var body: some View {
        Form {
            Section("通知") {
                LabeledContent("通知") {
                    Text(notificationStatusTitle)
                        .foregroundStyle(notificationStatus == .denied ? Color.red : Color.secondary)
                }
                if notificationStatus == .denied {
                    Button("iOSの設定を開く") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                } else if notificationStatus == .notDetermined {
                    Button {
                        Task { await requestNotifications() }
                    } label: {
                        if isRequestingNotifications {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text("通知を有効にする")
                        }
                    }
                    .disabled(isRequestingNotifications)
                    .accessibilityLabel(isRequestingNotifications ? "通知の許可を確認中" : "通知を有効にする")
                }
            }

            Section("表示") {
                Picker("テーマ", selection: $appAppearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("サポート") {
                Link(destination: AppLinks.support) {
                    Label("サポート", systemImage: "questionmark.circle")
                }

                Link(destination: AppLinks.privacyPolicy) {
                    Label("プライバシーポリシー", systemImage: "hand.raised")
                }

                Link(destination: AppLinks.termsOfUse) {
                    Label("利用規約", systemImage: "doc.text")
                }
            }

            Section("アプリ情報") {
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
        .alert("ログアウトしますか？", isPresented: $confirmsSignOut) {
            Button("ログアウト", role: .destructive) {
                Task { await session.signOut() }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この端末からログアウトします。保存済みのデータは削除されません。")
        }
        .sheet(isPresented: $showsAccountDeletion) {
            AccountDeletionView()
        }
        .alert("ログアウトできませんでした", isPresented: sessionErrorPresented) {
            Button("閉じる", role: .cancel) { session.errorMessage = nil }
        } message: {
            Text(session.errorMessage ?? "通信状態を確認して、もう一度お試しください。")
        }
        .alert("通知を設定できませんでした", isPresented: notificationErrorPresented) {
            Button("閉じる", role: .cancel) { notificationErrorMessage = nil }
        } message: {
            Text(notificationErrorMessage ?? "時間をおいてもう一度お試しください。")
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
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    private var sessionErrorPresented: Binding<Bool> {
        Binding(
            get: { session.errorMessage != nil },
            set: { if $0 == false { session.errorMessage = nil } }
        )
    }

    private var notificationErrorPresented: Binding<Bool> {
        Binding(
            get: { notificationErrorMessage != nil },
            set: { if $0 == false { notificationErrorMessage = nil } }
        )
    }

    private func requestNotifications() async {
        isRequestingNotifications = true
        defer { isRequestingNotifications = false }
        do {
            _ = try await container.notifications.requestAuthorizationIfNeeded()
        } catch {
            notificationErrorMessage = "通知の許可を確認できませんでした。もう一度お試しください。"
        }
        notificationStatus = await container.notifications.authorizationStatus()
    }

}
