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
    @State private var calendarAutoSyncEnabled = false
    @State private var showsCalendarCategories = false
    @State private var calendarSelectionSyncEnabled = false
    @State private var calendarDeadlineSyncEnabled = false
    @State private var calendarTaskSyncEnabled = false
    @State private var confirmsCalendarAutoSync = false
    @State private var isUpdatingCalendarSync = false
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue
    @ScaledMetric(relativeTo: .body) private var githubIconSize: CGFloat = 24

    var body: some View {
        Form {
            Section {
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
            } header: {
                Text("通知")
            } footer: {
                Text("選考予定・締切やToDoの通知を受け取れます。通知のオン・オフは各項目の編集画面で設定します。")
            }

            Section("表示") {
                Picker("テーマ", selection: $appAppearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Toggle(isOn: calendarAutoSyncBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("予定を自動追加")
                        Text(
                            calendarAutoSyncEnabled
                                ? (enabledCalendarCategories.isEmpty
                                    ? "自動追加の対象が選択されていません"
                                    : "選択した項目を自動追加しています")
                                : "新しい予定の自動追加は停止中"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .disabled(isUpdatingCalendarSync)

                if calendarAutoSyncEnabled {
                    Text("自動追加中の項目")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    calendarCategoryToggles
                } else {
                    DisclosureGroup(isExpanded: $showsCalendarCategories) {
                        calendarCategoryToggles
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("オンにしたときの対象")
                            Text(enabledCalendarCategories.isEmpty
                                ? "未選択"
                                : enabledCalendarCategories.map(\.title).joined(separator: "、"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if EKEventStore.authorizationStatus(for: .event) == .denied
                    || EKEventStore.authorizationStatus(for: .event) == .restricted {
                    Button("iOSのカレンダー設定を開く") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            } header: {
                Text("Appleカレンダー")
            } footer: {
                if calendarAutoSyncEnabled {
                    Text("個別に追加した予定は残ります。自動追加をオフにしても、追加済み予定の変更と削除は引き続き反映されます。")
                } else {
                    Text("停止中に対象をオフにしても、追加済みの予定は残ります。再開後も、それらの予定への変更・削除は反映されます。新しい予定は自動追加をオンにするまで追加されません。")
                }
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
            refreshCalendarSyncSettings()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshNotificationStatus(rescheduleOnAuthorization: false) }
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
        .alert("Appleカレンダーへ予定を自動追加しますか？", isPresented: $confirmsCalendarAutoSync) {
            Button("自動追加する") {
                Task { await enableCalendarAutoSync() }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("現在の対象予定\(store.appleCalendarAutoSyncItemCount)件を同期し、今後の作成・変更・削除を自動反映します。追加済みの予定は重複しません。")
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

    @ViewBuilder
    private var calendarCategoryToggles: some View {
        ForEach(AppleCalendarSyncCategory.allCases) { category in
            Toggle(isOn: calendarCategoryBinding(category)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                    Text(calendarCategoryDescription(category))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(isUpdatingCalendarSync)
            .accessibilityHint(
                calendarAutoSyncEnabled
                    ? "自動追加する対象を変更します"
                    : "自動追加を有効にしたときの対象を選びます"
            )
        }
        if calendarAutoSyncEnabled {
            Text("自動追加中に対象をオフにすると、その種類の自動追加済み予定はAppleカレンダーから削除されます。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func calendarCategoryDescription(_ category: AppleCalendarSyncCategory) -> String {
        switch category {
        case .selection: "予定中の面接や説明会などの日時"
        case .deadline: "予定中の選考に設定した締切"
        case .task: "期限を設定した未完了のToDo"
        }
    }

    private var calendarAutoSyncBinding: Binding<Bool> {
        Binding(
            get: { calendarAutoSyncEnabled },
            set: { enabled in
                if enabled {
                    if enabledCalendarCategories.isEmpty {
                        Task { await enableCalendarAutoSync() }
                    } else {
                        confirmsCalendarAutoSync = true
                    }
                } else {
                    calendarAutoSyncEnabled = false
                    isUpdatingCalendarSync = true
                    Task {
                        let succeeded = await store.setAppleCalendarAutoSyncEnabled(false)
                        if succeeded == false {
                            calendarAutoSyncEnabled = true
                        }
                        isUpdatingCalendarSync = false
                    }
                }
            }
        )
    }

    private func calendarCategoryBinding(_ category: AppleCalendarSyncCategory) -> Binding<Bool> {
        Binding(
            get: { isCalendarCategoryEnabled(category) },
            set: { enabled in
                switch category {
                case .selection:
                    calendarSelectionSyncEnabled = enabled
                case .deadline:
                    calendarDeadlineSyncEnabled = enabled
                case .task:
                    calendarTaskSyncEnabled = enabled
                }
                isUpdatingCalendarSync = true
                Task {
                    await store.setAppleCalendarCategory(category, enabled: enabled)
                    isUpdatingCalendarSync = false
                }
            }
        )
    }

    private func refreshCalendarSyncSettings() {
        calendarAutoSyncEnabled = store.isAppleCalendarAutoSyncEnabled
        calendarSelectionSyncEnabled = store.isAppleCalendarCategoryEnabled(.selection)
        calendarDeadlineSyncEnabled = store.isAppleCalendarCategoryEnabled(.deadline)
        calendarTaskSyncEnabled = store.isAppleCalendarCategoryEnabled(.task)
    }

    private func enableCalendarAutoSync() async {
        isUpdatingCalendarSync = true
        defer { isUpdatingCalendarSync = false }
        if await store.setAppleCalendarAutoSyncEnabled(true) {
            calendarAutoSyncEnabled = true
        }
    }

    private func isCalendarCategoryEnabled(_ category: AppleCalendarSyncCategory) -> Bool {
        switch category {
        case .selection: calendarSelectionSyncEnabled
        case .deadline: calendarDeadlineSyncEnabled
        case .task: calendarTaskSyncEnabled
        }
    }

    private var enabledCalendarCategories: [AppleCalendarSyncCategory] {
        AppleCalendarSyncCategory.allCases.filter(isCalendarCategoryEnabled)
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
