import AuthenticationServices
import SwiftUI

struct AccountDeletionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    @State private var confirmsDeletion = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ContentUnavailableView {
                        Label("アカウントを削除", systemImage: "person.crop.circle.badge.minus")
                    } description: {
                        Text("企業、選考、ToDoを含むすべてのデータが削除されます。この操作は取り消せません。")
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

                    SignInWithAppleButton(.continue) { _ in
                        errorMessage = nil
                    } onCompletion: { result in
                        handleAuthorization(result)
                    }
                    .signInWithAppleButtonStyle(appleButtonStyle)
                    .frame(height: 52)
                    .clipShape(.rect(cornerRadius: 12))
                    .disabled(confirmsDeletion == false || session.isWorking)
                    .overlay {
                        if session.isWorking {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(colorScheme == .dark ? Color.white : Color.black)
                            ProgressView()
                                .tint(colorScheme == .dark ? .black : .white)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityLabel(session.isWorking ? "削除しています" : "Appleで続ける")
                    .accessibilityHint("本人確認後、アカウントを完全に削除します")

                    Spacer(minLength: 0)
                }
                .padding(24)
            }
            .navigationTitle("アカウント削除")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .disabled(session.isWorking)
                }
            }
        }
        .interactiveDismissDisabled(session.isWorking)
        .alert("削除できませんでした", isPresented: errorPresented) {
            Button("閉じる", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "時間をおいてもう一度お試しください。")
        }
    }

    private var appleButtonStyle: SignInWithAppleButton.Style {
        colorScheme == .dark ? .white : .black
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

    private func deleteAccount(authorizationCode: String) async {
        do {
            try await session.deleteAccount(authorizationCode: authorizationCode)
            await store.reset()
            dismiss()
        } catch {
            errorMessage = UserFacingError.message(
                for: error,
                fallback: "アカウントを削除できませんでした。しばらくしてからもう一度お試しください。"
            )
        }
    }
}
