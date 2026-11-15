import AuthenticationServices
import SwiftUI
import UIKit

struct AccountDeletionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    @State private var confirmsDeletion = false
    @State private var errorMessage: String?
    @State private var isPreparingDeletion = false
    @State private var pendingAuthorizationCode: String?
    @State private var showsCalendarCleanupChoice = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ContentUnavailableView {
                        Label("アカウントを削除", systemImage: "person.crop.circle.badge.minus")
                    } description: {
                        Text("この操作は取り消せません。")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("削除されるデータ")
                            .font(.headline)
                        Text("企業・選考・ToDo・自己分析・ESなどのデータを削除します。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("この端末からカレンダーに追加した予定も削除します。アカウントの削除に失敗しても、予定は先に削除される場合があります。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("本人確認が必要です")
                            .font(.headline)
                        Text("Appleで本人確認したあと、Appleの認可を解除してアカウントを削除します。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Toggle("すべてのデータが削除されることを確認しました", isOn: $confirmsDeletion)
                        .tint(.red)

                    ZStack {
                        SignInWithAppleButton(.continue) { _ in
                            errorMessage = nil
                            pendingAuthorizationCode = nil
                        } onCompletion: { result in
                            handleAuthorization(result)
                        }
                        .signInWithAppleButtonStyle(appleButtonStyle)
                        .disabled(confirmsDeletion == false || isDeleting)
                        .accessibilityHint("本人確認後、アカウントを完全に削除します")
                        .opacity(isDeleting ? 0 : 1)
                        .accessibilityHidden(isDeleting)

                        if isDeleting {
                            ProgressView(isPreparingDeletion ? "削除準備中" : "削除中")
                        }
                    }
                    .frame(height: 52)

                    Spacer(minLength: 0)
                }
                .padding(24)
            }
            .navigationTitle("アカウント削除")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .disabled(isDeleting)
                }
            }
        }
        .interactiveDismissDisabled(isDeleting)
        .alert("削除できませんでした", isPresented: errorPresented) {
            Button("閉じる", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "時間をおいてもう一度お試しください。")
        }
        .confirmationDialog(
            "Appleカレンダーの予定を削除できませんでした",
            isPresented: $showsCalendarCleanupChoice,
            titleVisibility: .visible
        ) {
            Button("iOSの設定を開く") {
                pendingAuthorizationCode = nil
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            Button("予定を残してアカウントを削除", role: .destructive) {
                guard let authorizationCode = pendingAuthorizationCode else { return }
                pendingAuthorizationCode = nil
                Task {
                    await deleteAccount(
                        authorizationCode: authorizationCode,
                        skipsCalendarCleanup: true
                    )
                }
            }
            Button("キャンセル", role: .cancel) {
                pendingAuthorizationCode = nil
            }
        } message: {
            Text("カレンダーへのアクセス設定を確認して再試行するか、予定を残してアカウント削除を続けてください。再試行には本人確認が必要です。")
        }
    }

    private var appleButtonStyle: SignInWithAppleButton.Style {
        colorScheme == .dark ? .white : .black
    }

    private var isDeleting: Bool {
        isPreparingDeletion || session.isWorking
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if $0 == false { errorMessage = nil } }
        )
    }

    private func handleAuthorization(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let codeData = credential.authorizationCode,
                  let authorizationCode = String(data: codeData, encoding: .utf8),
                  authorizationCode.isEmpty == false
            else {
                errorMessage = "Appleから削除に必要な認証情報を受け取れませんでした。"
                return
            }

            Task { await deleteAccount(authorizationCode: authorizationCode) }

        case let .failure(error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = UserFacingError.message(
                    for: error,
                    fallback: "Appleで本人確認できませんでした。もう一度お試しください。"
                )
            }
        }
    }

    private func deleteAccount(
        authorizationCode: String,
        skipsCalendarCleanup: Bool = false
    ) async {
        guard let userID = session.userID else {
            errorMessage = "ログイン状態を確認できませんでした。もう一度ログインしてお試しください。"
            return
        }
        isPreparingDeletion = true
        defer { isPreparingDeletion = false }

        do {
            if skipsCalendarCleanup == false {
                try await store.removeAppleCalendarEventsForAccountDeletion()
            }
            try await session.deleteAccount(authorizationCode: authorizationCode)
            store.purgeAppleCalendarPreferences(userID: userID)
            dismiss()
        } catch {
            if error is AccountDeletionPreparationError {
                pendingAuthorizationCode = authorizationCode
                showsCalendarCleanupChoice = true
            } else {
                errorMessage = UserFacingError.message(
                    for: error,
                    fallback: "アカウントを削除できませんでした。しばらくしてからもう一度お試しください。"
                )
            }
        }
    }
}
