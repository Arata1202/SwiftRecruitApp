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

    init(client: SupabaseClient?) {
        self.client = client
    }

    func restore() async {
        defer { isRestoring = false }
        guard let client else { return }
        do {
            userID = try await client.auth.session.user.id
        } catch {
            userID = nil
        }
    }

    func observeAuthChanges() async {
        guard let client else { return }

        for await (_, authSession) in await client.auth.authStateChanges {
            guard Task.isCancelled == false else { return }
            userID = authSession?.user.id
        }
    }

    func signInWithApple(credential: ASAuthorizationAppleIDCredential, nonce: String) async {
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
            let session = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: idToken,
                    nonce: nonce
                )
            )
            userID = session.user.id
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
            userID = nil
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
        userID = nil
    }
}
