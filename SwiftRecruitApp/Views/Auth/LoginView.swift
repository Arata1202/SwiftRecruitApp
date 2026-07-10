import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @Environment(AppSession.self) private var session
    @State private var currentNonce: String?

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "briefcase.fill")
                .font(.system(size: 58))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("リクビジョン")
                    .font(.largeTitle.bold())
                Text("企業と選考予定を、迷わずひとつに。")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            SignInWithAppleButton(.continue) { request in
                prepare(request)
            } onCompletion: { result in
                complete(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .clipShape(.rect(cornerRadius: 10))
            .disabled(session.isWorking)

            if session.isWorking {
                ProgressView()
            }

            VStack(spacing: 6) {
                Text("Appleで続ける前に、データの取り扱いをご確認ください。")
                    .foregroundStyle(.secondary)

                Link("プライバシーポリシー", destination: AppLinks.privacyPolicy)
            }
            .font(.footnote)
            .multilineTextAlignment(.center)
        }
        .padding(24)
        .alert("ログインできませんでした", isPresented: errorPresented) {
            Button("閉じる", role: .cancel) { session.errorMessage = nil }
        } message: {
            Text(session.errorMessage ?? "時間をおいてもう一度お試しください。")
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { session.errorMessage != nil },
            set: { if $0 == false { session.errorMessage = nil } }
        )
    }

    private func prepare(_ request: ASAuthorizationAppleIDRequest) {
        do {
            let nonce = try NonceGenerator.random()
            currentNonce = nonce
            request.requestedScopes = [.email]
            request.nonce = NonceGenerator.sha256(nonce)
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }

    private func complete(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let currentNonce
            else {
                session.errorMessage = AuthFlowError.invalidCredential.localizedDescription
                return
            }
            Task { await session.signInWithApple(credential: credential, nonce: currentNonce) }
        case let .failure(error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                session.errorMessage = error.localizedDescription
            }
        }
    }
}
