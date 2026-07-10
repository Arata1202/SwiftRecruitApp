import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store
    @Environment(AppContainer.self) private var container
    @Environment(\.openURL) private var openURL

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var confirmsSignOut = false
    @State private var confirmsAccountDeletion = false
    @State private var deletionError: String?

    var body: some View {
        List {
            Section("通知") {
                LabeledContent("通知") {
                    Text(notificationStatusTitle)
                        .foregroundStyle(notificationStatus == .denied ? .red : .secondary)
                }
                if notificationStatus == .denied {
                    Button("iOSの設定を開く") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            }

            Section("情報") {
                NavigationLink("プライバシーポリシー") {
                    LegalDocumentView(title: "プライバシーポリシー", body: LegalText.privacy)
                }
                NavigationLink("利用規約") {
                    LegalDocumentView(title: "利用規約", body: LegalText.terms)
                }
                LabeledContent("バージョン", value: appVersion)
            }

            Section("アカウント") {
                Button("ログアウト") { confirmsSignOut = true }
                Button("アカウントを削除", role: .destructive) { confirmsAccountDeletion = true }
            }
        }
        .navigationTitle("設定")
        .task { notificationStatus = await container.notifications.authorizationStatus() }
        .confirmationDialog("ログアウトしますか？", isPresented: $confirmsSignOut, titleVisibility: .visible) {
            Button("ログアウト", role: .destructive) {
                Task {
                    await session.signOut()
                    if session.userID == nil { await store.reset() }
                }
            }
        }
        .confirmationDialog(
            "アカウントを削除しますか？",
            isPresented: $confirmsAccountDeletion,
            titleVisibility: .visible
        ) {
            Button("アカウントとすべてのデータを削除", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text("企業、選考、ToDoがすべて削除されます。この操作は取り消せません。")
        }
        .alert("削除できませんでした", isPresented: Binding(
            get: { deletionError != nil },
            set: { if $0 == false { deletionError = nil } }
        )) {
            Button("閉じる", role: .cancel) { deletionError = nil }
        } message: {
            Text(deletionError ?? "時間をおいてもう一度お試しください。")
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

    private func deleteAccount() async {
        do {
            try await session.deleteAccount()
            await store.reset()
        } catch {
            deletionError = error.localizedDescription
        }
    }
}

private struct LegalDocumentView: View {
    let title: String
    let body: String

    var body: some View {
        ScrollView {
            Text(body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private enum LegalText {
    static let privacy = """
    リクビジョンは、アプリの機能提供に必要な範囲で、Appleアカウントに紐づく識別情報と、利用者が登録した企業・選考・ToDoの情報をSupabaseへ保存します。

    保存した情報は本人のアカウントにのみ紐づけ、第三者への販売や広告目的の追跡には使用しません。設定画面からアカウントを削除すると、関連するデータも削除されます。

    正式な公開前に、運営者情報、問い合わせ先、保存期間を含む最終版へ更新してください。
    """

    static let terms = """
    リクビジョンは、就職活動に関する情報整理を支援するアプリです。登録内容、締切、通知の正確性は利用者自身でも確認してください。本アプリは選考結果や就職を保証するものではありません。

    不正利用、他者の権利を侵害する利用、サービスの運営を妨げる行為は禁止します。

    正式な公開前に、運営者情報、免責、サービス変更・終了条件を含む最終版へ更新してください。
    """
}
