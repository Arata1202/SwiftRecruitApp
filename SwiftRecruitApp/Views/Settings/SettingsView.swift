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

            Section("表示") {
                Picker("テーマ", selection: $appAppearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance.rawValue)
                    }
                }
                .pickerStyle(.segmented)
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

                if calendarAuthorizationStatus == .fullAccess || store.hasExistingCalendarConfiguration {
                    Toggle(isOn: calendarAutoSyncBinding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("予定を自動追加")
                            Text(calendarAutoSyncStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(isUpdatingCalendarSync || (calendarAuthorizationStatus != .fullAccess && !calendarAutoSyncEnabled))

                    if calendarAutoSyncEnabled {
                        Text("自動追加の対象")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        calendarCategoryToggles
                    } else {
                        DisclosureGroup(isExpanded: $showsCalendarCategories) {
                            calendarCategoryToggles
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("自動追加の対象")
                                Text(enabledCalendarCategories.isEmpty
                                    ? "未選択"
                                    : enabledCalendarCategories.map(\.title).joined(separator: "、"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                }
            } header: {
                Text("Appleカレンダー")
            } footer: {
                Text("選考やToDoをAppleカレンダーに追加できます。")
                if calendarAuthorizationStatus == .fullAccess || store.hasExistingCalendarConfiguration {
                    if calendarAutoSyncEnabled {
                        Text("自動追加をオフにしても、追加済み予定は残り、変更・削除を反映します。")
                    } else {
                        Text("停止中は対象を外しても追加済み予定は残り、変更・削除を反映します。")
                    }
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
            refreshCalendarAuthorizationStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshNotificationStatus(rescheduleOnAuthorization: false) }
            refreshCalendarAuthorizationStatus()
            if !isUpdatingCalendarSync { refreshCalendarSyncSettings() }
        }
        .onChange(of: store.loadedUserID) { _, _ in
            refreshCalendarSyncSettings()
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
        .alert("Appleカレンダーへ予定を自動追加しますか？", isPresented: $confirmsCalendarAutoSync) {
            Button("自動追加する") {
                Task { await enableCalendarAutoSync() }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("現在の対象は\(store.appleCalendarAutoSyncItemCount)件です。今後の変更・削除もカレンダーに反映します。")
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
            .disabled(isUpdatingCalendarSync || calendarAuthorizationStatus != .fullAccess)
            .accessibilityHint(
                calendarAutoSyncEnabled
                    ? "自動追加する対象を変更します"
                    : "自動追加を有効にしたときの対象を選びます"
            )
        }
        if calendarAutoSyncEnabled {
            Text("対象をオンにすると、登録済みの今後の予定も追加します。対象をオフにすると、自動追加した予定を削除します。個別に追加した予定は残ります。")
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
                    let succeeded = await store.setAppleCalendarCategory(category, enabled: enabled)
                    if succeeded == false { refreshCalendarSyncSettings() }
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
        } else {
            refreshCalendarSyncSettings()
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

    private var calendarAutoSyncStatus: String {
        guard calendarAutoSyncEnabled else { return "新しい予定の自動追加は停止中" }
        guard calendarAuthorizationStatus == .fullAccess else {
            return "カレンダーへのフルアクセスが必要です"
        }
        guard enabledCalendarCategories.isEmpty == false else { return "自動追加の対象が選択されていません" }
        return "自動追加はオンです"
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
