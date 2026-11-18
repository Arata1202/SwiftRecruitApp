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
    var accountDeletionNotice: String?
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
        guard isWorking == false else { return }
        guard let client else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await client.auth.signOut(scope: .local)
            userID = nil
        } catch {
            // SDK clears local credentials before contacting the server.
            if client.auth.currentSession == nil {
                userID = nil
                credentialRevision &+= 1
                return
            }
            errorMessage = UserFacingError.message(
                for: error,
                fallback: "ログアウトできませんでした。通信状態を確認してください。"
            )
        }
    }

    func deleteAccount(authorizationCode: String) async throws {
        guard isWorking == false else { throw AccountDeletionError.operationInProgress }
        guard let client else { throw RepositoryError.notConfigured }
        guard let deletingUserID = userID else { throw AuthError.sessionMissing }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let result: AccountDeletionResponse = try await client.functions.invoke(
                "delete-account",
                options: FunctionInvokeOptions(body: ["authorization_code": authorizationCode])
            )
            guard result.deleted else { throw AccountDeletionError.resultUnknown }
        } catch {
            if let rejection = AccountDeletionError.knownRejection(error) { throw rejection }
            // A lost response is not proof of deletion or failure. Never retry
            // this mutation automatically; check authentication once instead.
            await reconcileUncertainDeletion(client: client, userID: deletingUserID)
            throw AccountDeletionError.resultUnknown
        }
        await endLocalSession(client: client)
    }

    private func reconcileUncertainDeletion(client: SupabaseClient, userID: UUID) async {
        do {
            _ = try await client.auth.user()
            // Even a readable account may have a deletion request in flight.
        } catch {
            guard AccountDeletionError.requiresLocalSignOut(after: error),
                  self.userID == userID || self.userID == nil else { return }
            // Invalid auth does NOT establish deletion. Keep this notice outside
            // the sheet, which disappears when the local session ends.
            accountDeletionNotice = AccountDeletionError.resultUnknown.localizedDescription
                + " ログイン状態を確認できないため、この端末からログアウトしました。削除済みと確認できたわけではありません。"
            await endLocalSession(client: client)
        }
    }

    private func endLocalSession(client: SupabaseClient) async {
        // SDK removes persisted credentials even if remote revocation fails.
        try? await client.auth.signOut(scope: .local)
        userID = nil
        credentialRevision &+= 1
    }
}

private struct AccountDeletionResponse: Decodable {
    let deleted: Bool
}
