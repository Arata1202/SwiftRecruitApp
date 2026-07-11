import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppSession.self) private var session
    @State private var currentNonce: String?
    @State private var isSigningIn = false

    var body: some View {
        GeometryReader { proxy in
            let verticalPadding: CGFloat = 12

            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 32)

                    Image("BrandIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 92, height: 92)
                        .clipShape(.rect(cornerRadius: 21))
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                        .accessibilityHidden(true)

                    VStack(spacing: 8) {
                        Text("リクビジョン")
                            .font(.largeTitle.bold())
                        Text("企業と選考予定を、迷わずひとつに。")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Spacer(minLength: 36)

                    VStack(spacing: 16) {
                        SignInWithAppleButton(.continue) { request in
                            prepare(request)
                        } onCompletion: { result in
                            complete(result)
                        }
                        .signInWithAppleButtonStyle(appleButtonStyle)
                        .id(colorScheme)
                        .frame(height: 52)
                        .clipShape(.rect(cornerRadius: 12))
                        .disabled(isSigningIn)
                        .overlay {
                            if isSigningIn {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(colorScheme == .dark ? Color.white : Color.black)
                                ProgressView()
                                    .tint(colorScheme == .dark ? .black : .white)
                                    .accessibilityHidden(true)
                            }
                        }
                        .accessibilityLabel(isSigningIn ? "ログイン中" : "Appleで続ける")
                        .accessibilityHint("Apple IDで安全にログインします")

                        VStack(spacing: 8) {
                            Text("続ける前に、データの取り扱いをご確認ください。")
                                .foregroundStyle(.secondary)

                            ViewThatFits {
                                HStack(spacing: 16) {
                                    Link("プライバシーポリシー", destination: AppLinks.privacyPolicy)
                                    Link("利用規約", destination: AppLinks.termsOfUse)
                                }
                                VStack(spacing: 8) {
                                    Link("プライバシーポリシー", destination: AppLinks.privacyPolicy)
                                    Link("利用規約", destination: AppLinks.termsOfUse)
                                }
                            }
                        }
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: 520)
                .frame(minHeight: max(0, proxy.size.height - verticalPadding * 2))
                .padding(.horizontal, 24)
                .padding(.vertical, verticalPadding)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .alert("ログインできませんでした", isPresented: errorPresented) {
            Button("閉じる", role: .cancel) { session.errorMessage = nil }
        } message: {
            Text(session.errorMessage ?? "時間をおいてもう一度お試しください。")
        }
    }

    private var appleButtonStyle: SignInWithAppleButton.Style {
        colorScheme == .dark ? .white : .black
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { session.errorMessage != nil },
            set: { if $0 == false { session.errorMessage = nil } }
        )
    }

    private func prepare(_ request: ASAuthorizationAppleIDRequest) {
        currentNonce = nil
        do {
            let nonce = try NonceGenerator.random()
            currentNonce = nonce
            request.nonce = NonceGenerator.sha256(nonce)
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }

    private func complete(_ result: Result<ASAuthorization, Error>) {
        defer { currentNonce = nil }
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = currentNonce
            else {
                session.errorMessage = AuthFlowError.invalidCredential.localizedDescription
                return
            }
            isSigningIn = true
            Task {
                await session.signInWithApple(credential: credential, nonce: nonce)
                isSigningIn = false
            }
        case let .failure(error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                session.errorMessage = UserFacingError.message(
                    for: error,
                    fallback: "Appleでログインできませんでした。もう一度お試しください。"
                )
            }
        }
    }
}
