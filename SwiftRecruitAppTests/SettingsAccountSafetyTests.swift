import Foundation
import Supabase
import XCTest
@testable import SwiftRecruitApp

final class SettingsAccountSafetyTests: XCTestCase {
    func testAppleMismatchUsesStableCodeNotEnglishMessage() {
        let error = FunctionsError.httpError(
            code: 403, data: Data(#"{"code":"apple_identity_mismatch","error":"changed wording"}"#.utf8)
        )
        XCTAssertEqual(AccountDeletionError.knownRejection(error), .appleIdentityMismatch)
        XCTAssertTrue(UserFacingError.message(for: AccountDeletionError.appleIdentityMismatch, fallback: "fallback").contains("ログインに使用したApple ID"))
    }

    func testGenericForbiddenDoesNotClaimAppleIdentityMismatch() {
        let error = FunctionsError.httpError(code: 403, data: Data())
        XCTAssertEqual(AccountDeletionError.knownRejection(error), .rejected)
    }

    func testExplicitPreDeletionFailuresHaveDefiniteRecoveryActions() {
        let revoke = FunctionsError.httpError(code: 502, data: Data(#"{"code":"apple_revocation_failed"}"#.utf8))
        let outage = FunctionsError.httpError(code: 503, data: Data(#"{"code":"auth_unavailable"}"#.utf8))
        XCTAssertEqual(AccountDeletionError.knownRejection(revoke), .rejected)
        XCTAssertEqual(AccountDeletionError.knownRejection(outage), .serviceUnavailable)
    }

    func testTransportAndServerFailuresRemainUncertain() {
        for status in [500, 502, 503, 504] {
            XCTAssertNil(AccountDeletionError.knownRejection(FunctionsError.httpError(code: status, data: Data())))
        }
        XCTAssertNil(AccountDeletionError.knownRejection(URLError(.timedOut)))
        XCTAssertNil(AccountDeletionError.knownRejection(FunctionsError.relayError))
    }

    func testNetworkFailureDoesNotDiscardLocalAuthentication() {
        XCTAssertFalse(AccountDeletionError.requiresLocalSignOut(after: URLError(.notConnectedToInternet)))
        XCTAssertFalse(AccountDeletionError.requiresLocalSignOut(after: URLError(.timedOut)))
    }

    func testMissingSessionRequiresCleanupButMessageNeverClaimsDeletion() {
        XCTAssertTrue(AccountDeletionError.requiresLocalSignOut(after: AuthError.sessionMissing))
        let message = UserFacingError.message(for: AccountDeletionError.resultUnknown, fallback: "fallback")
        XCTAssertTrue(message.contains("削除結果を確認できません"))
        XCTAssertTrue(message.contains("可能性"))
    }

    @MainActor
    func testConcurrentAccountActionsAreRejectedWithoutResettingBusyState() async {
        let session = AppSession(client: nil, initialUserID: UUID())
        session.isWorking = true
        await session.signOut()
        XCTAssertTrue(session.isWorking)
        do {
            try await session.deleteAccount(authorizationCode: "unused")
            XCTFail("Duplicate deletion must be rejected")
        } catch {
            XCTAssertEqual(error as? AccountDeletionError, .operationInProgress)
        }
        XCTAssertTrue(session.isWorking)
        XCTAssertNotNil(session.userID)
    }
}
