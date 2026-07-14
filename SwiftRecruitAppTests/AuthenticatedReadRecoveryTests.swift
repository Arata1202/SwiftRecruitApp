import Supabase
import XCTest
@testable import SwiftRecruitApp

final class AuthenticatedReadRecoveryTests: XCTestCase {
    func testRetriesPermissionFailureAfterRecoveringSession() async throws {
        var attempts = 0
        var recoveries = 0

        let value = try await AuthenticatedReadRecovery.run {
            attempts += 1
            if attempts == 1 {
                throw PostgrestError(code: "42501", message: "permission denied")
            }
            return "loaded"
        } recoverSession: {
            recoveries += 1
        }

        XCTAssertEqual(value, "loaded")
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(recoveries, 1)
    }

    func testDoesNotRetryOtherPostgrestFailures() async {
        var attempts = 0
        var recoveries = 0

        do {
            let _: String = try await AuthenticatedReadRecovery.run {
                attempts += 1
                throw PostgrestError(code: "PGRST116", message: "not found")
            } recoverSession: {
                recoveries += 1
            }
            XCTFail("Expected the read to fail")
        } catch let error as PostgrestError {
            XCTAssertEqual(error.code, "PGRST116")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(recoveries, 0)
    }

    func testRetriesOnlyOnce() async {
        var attempts = 0
        var recoveries = 0

        do {
            let _: String = try await AuthenticatedReadRecovery.run {
                attempts += 1
                throw PostgrestError(code: "42501", message: "permission denied")
            } recoverSession: {
                recoveries += 1
            }
            XCTFail("Expected the second read to fail")
        } catch let error as PostgrestError {
            XCTAssertEqual(error.code, "42501")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(recoveries, 1)
    }
}
