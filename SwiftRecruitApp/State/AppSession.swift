import AuthenticationServices
import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class AppSession {
    private let client: SupabaseClient?

    var userID: UUID?
    var isRestoring = true
    var isWorking = false
    var errorMessage: String?
    private(set) var credentialRevision = 0

    init(client: SupabaseClient?, initialUserID: UUID? = nil) {
        self.client = client
        userID = initialUserID
        isRestoring = initialUserID == nil
    }

    func observeAuthChanges() async {
        guard let client else {
            isRestoring = false
            return
        }

        for await (event, authSession) in client.auth.authStateChanges {
            guard Task.isCancelled == false else { return }

            if event == .signedOut {
                userID = nil
            } else if let authSession {
                userID = authSession.user.id
            }

            if event == .tokenRefreshed {
                credentialRevision &+= 1
            }

            if event == .initialSession {
                isRestoring = false
            }
        }
    }

    func signInWithApple(credential: ASAuthorizationAppleIDCredential, nonce: String) async {
        guard isWorking == false else { return }
        guard let client else {
            errorMessage = RepositoryError.notConfigured.localizedDescription
            return
        }
        guard let tokenData = credential.identityToken else {
            errorMessage = AuthFlowError.missingIdentityToken.localizedDescription
            return
        }
        guard let idToken = String(data: tokenData, encoding: .utf8) else {
            errorMessage = AuthFlowError.invalidIdentityToken.localizedDescription
            return
        }

        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            _ = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: idToken,
                    nonce: nonce
                )
            )
        } catch {
            errorMessage = UserFacingError.message(
                for: error,
                fallback: "ログインできませんでした。しばらくしてからもう一度お試しください。"
            )
        }
    }

    func signOut() async {
        guard let client else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await client.auth.signOut()
        } catch {
            errorMessage = UserFacingError.message(
                for: error,
                fallback: "ログアウトできませんでした。通信状態を確認してください。"
            )
        }
    }

    func deleteAccount(authorizationCode: String) async throws {
        guard let client else { throw RepositoryError.notConfigured }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        try await client.functions.invoke(
            "delete-account",
            options: FunctionInvokeOptions(
                body: ["authorization_code": authorizationCode]
            )
        )
        try? await client.auth.signOut()
    }
}
