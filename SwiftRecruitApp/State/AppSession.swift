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
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        guard let client else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await client.auth.signOut()
            userID = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAccount() async throws {
        guard let client else { throw RepositoryError.notConfigured }
        isWorking = true
        defer { isWorking = false }
        try await client.functions.invoke("delete-account")
        try? await client.auth.signOut()
        userID = nil
    }
}
