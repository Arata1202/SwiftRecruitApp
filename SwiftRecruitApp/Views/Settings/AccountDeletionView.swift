import AuthenticationServices
import SwiftUI

struct AccountDeletionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session

    @State private var confirmsDeletion = false
    @State private var errorMessage: String?
    @State private var isPreparingDeletion = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ContentUnavailableView {
                        Label("アカウントを削除", systemImage: "person.crop.circle.badge.minus")
                    } description: {
                        Text("この操作は取り消せません。")
                            .foregroundStyle(RecruitTextColor.supporting)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("削除されるデータ")
                            .font(.headline)
                        Text("企業・選考・ToDo・企業研究の記録などのデータを削除します。")
                            .font(.subheadline)
                            .foregroundStyle(RecruitTextColor.supporting)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("本人確認が必要です")
                            .font(.headline)
                        Text("このアプリとAppleの連携を解除するため、Appleで本人確認します。")
                            .font(.subheadline)
                            .foregroundStyle(RecruitTextColor.supporting)
                    }

                    Toggle("すべてのデータが削除されることを確認しました", isOn: $confirmsDeletion)
                        .tint(.red)
                        .disabled(isDeleting)

                    Text("本人確認が完了すると、リクビジョンのアカウントとデータが削除されます。")
                        .font(.subheadline)

                    ZStack {
                        SignInWithAppleButton(.continue) { _ in
                            errorMessage = nil
                        } onCompletion: { result in
                            handleAuthorization(result)
                        }
                        .signInWithAppleButtonStyle(appleButtonStyle)
                        .disabled(confirmsDeletion == false || isDeleting)
                        .accessibilityHint("本人確認後、リクビジョンのアカウントとデータを削除します")
                        .opacity(isDeleting ? 0 : (confirmsDeletion ? 1 : 0.45))
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
        .alert("アカウント削除の確認", isPresented: errorPresented) {
            Button("閉じる", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "時間をおいてもう一度お試しください。")
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
        authorizationCode: String
    ) async {
        guard isDeleting == false else { return }
        guard session.userID != nil else {
            errorMessage = "ログイン状態を確認できませんでした。もう一度ログインしてお試しください。"
            return
        }
        isPreparingDeletion = true
        defer { isPreparingDeletion = false }

        do {
            isPreparingDeletion = false
            try await session.deleteAccount(authorizationCode: authorizationCode)
            dismiss()
        } catch {
            if session.accountDeletionNotice == nil {
                errorMessage = UserFacingError.message(
                    for: error,
                    fallback: "アカウントを削除できませんでした。しばらくしてからもう一度お試しください。"
                )
            }
        }
    }
}
