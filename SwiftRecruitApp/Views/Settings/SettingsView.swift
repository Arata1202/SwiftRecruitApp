import EventKit
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
    @State private var isRequestingNotifications = false
    @State private var notificationErrorMessage: String?
    @State private var confirmsSignOut = false
    @State private var showsAccountDeletion = false
    @State private var calendarAuthorizationStatus: EKAuthorizationStatus = .notDetermined
    @State private var isRequestingCalendarAccess = false
    @State private var calendarAccessError: String?
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue
    @ScaledMetric(relativeTo: .body) private var githubIconSize: CGFloat = 24

    var body: some View {
        Form {
            Section {
                LabeledContent("通知の許可") {
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
            } header: {
                Text("通知")
            } footer: {
                Text("選考予定・締切やToDoの通知を受け取れます。通知のオン・オフは各項目の編集画面で設定します。")
            }

            Section {
                LabeledContent("カレンダーの許可") {
                    Text(calendarAuthorizationTitle)
                        .foregroundStyle(calendarAuthorizationStatus == .denied ? Color.red : Color.secondary)
                }
                if calendarAuthorizationStatus == .notDetermined {
                    Button(isRequestingCalendarAccess ? "許可を確認中" : "カレンダーを有効にする") {
                        Task { await requestCalendarAccess() }
                    }
                    .disabled(isRequestingCalendarAccess)
                } else if calendarAuthorizationStatus != .fullAccess {
                    Button("iOSの設定を開く") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            } header: {
                Text("Appleカレンダー")
            } footer: {
                Text("選考やToDoをAppleカレンダーに追加できます。")
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
                    Label("お問い合わせ", systemImage: "envelope")
                        .fullWidthTappableArea()
                }

                Link(destination: AppLinks.privacyPolicy) {
                    Label("プライバシーポリシー", systemImage: "hand.raised")
                        .fullWidthTappableArea()
                }

                Link(destination: AppLinks.github) {
                    Label {
                        Text("GitHub")
                    } icon: {
                        Image("GitHubMark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: githubIconSize, height: githubIconSize)
                            .foregroundStyle(.primary)
                    }
                    .fullWidthTappableArea()
                }

                Link(destination: AppLinks.termsOfUse) {
                    Label("利用規約", systemImage: "doc.text")
                        .fullWidthTappableArea()
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
        .task {
            await refreshNotificationStatus(rescheduleOnAuthorization: false)
            refreshCalendarAuthorizationStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshNotificationStatus(rescheduleOnAuthorization: false) }
            refreshCalendarAuthorizationStatus()
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
        .alert("カレンダーの許可を確認できませんでした", isPresented: Binding(
            get: { calendarAccessError != nil },
            set: { if !$0 { calendarAccessError = nil } }
        )) {
            Button("閉じる", role: .cancel) { calendarAccessError = nil }
        } message: {
            Text(calendarAccessError ?? "もう一度お試しください。")
        }
        .recruitErrorAlert(store: store)
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

    private var calendarAuthorizationTitle: String {
        switch calendarAuthorizationStatus {
        case .notDetermined: "未設定"
        case .fullAccess: "許可済み"
        case .writeOnly: "フルアクセスが必要"
        case .denied: "許可されていません"
        case .restricted: "制限されています"
        @unknown default: "不明"
        }
    }

    private func refreshCalendarAuthorizationStatus() {
        calendarAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    private func requestCalendarAccess() async {
        isRequestingCalendarAccess = true
        defer {
            isRequestingCalendarAccess = false
            refreshCalendarAuthorizationStatus()
        }
        do {
            try await store.requestAppleCalendarAccess()
        } catch AppleCalendarError.accessDenied {
            // The permission status provides the next step without a second dialog.
        } catch is CancellationError {
            return
        } catch {
            calendarAccessError = "時間をおいてもう一度お試しください。"
        }
    }

    private func requestNotifications() async {
        isRequestingNotifications = true
        defer { isRequestingNotifications = false }
        do {
            _ = try await container.notifications.requestAuthorizationIfNeeded()
        } catch {
            notificationErrorMessage = "通知の許可を確認できませんでした。もう一度お試しください。"
        }
        await refreshNotificationStatus(rescheduleOnAuthorization: true)
    }

    private func refreshNotificationStatus(rescheduleOnAuthorization: Bool) async {
        let previousStatus = notificationStatus
        let currentStatus = await container.notifications.authorizationStatus()
        notificationStatus = currentStatus

        guard rescheduleOnAuthorization,
              Self.isAuthorized(currentStatus),
              Self.isAuthorized(previousStatus) == false
        else { return }
        await store.rescheduleAllNotificationsIfAuthorized()
    }

    private static func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: true
        case .notDetermined, .denied: false
        @unknown default: false
        }
    }

}
