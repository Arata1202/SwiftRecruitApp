import Foundation
import Supabase
import XCTest
@testable import SwiftRecruitApp

final class AuthenticatedReadRecoveryTests: XCTestCase {
    func testRefreshesExpiredJWTBeforeRetrying() async throws {
        var attempts = 0
        var recoveries = 0

        let value = try await AuthenticatedReadRecovery.run(
            operationName: "test"
        ) {
            attempts += 1
            if attempts == 1 {
                throw PostgrestError(code: "PGRST301", message: "JWT expired")
            }
            return "loaded"
        } recoverSession: {
            recoveries += 1
        }

        XCTAssertEqual(value, "loaded")
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(recoveries, 1)
    }

    func testRetriesConnectionPoolTimeout() async throws {
        var attempts = 0
        var sleeps = 0

        let value = try await AuthenticatedReadRecovery.run(
            operationName: "test",
            policy: .immediate(retryCount: 2),
            sleep: { _ in sleeps += 1 }
        ) {
            attempts += 1
            if attempts < 3 {
                throw PostgrestError(
                    code: "PGRST003",
                    message: "Timed out acquiring connection from connection pool."
                )
            }
            return "loaded"
        } recoverSession: {
            XCTFail("A pool timeout must not refresh authentication")
        }

        XCTAssertEqual(value, "loaded")
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(sleeps, 2)
    }

    func testRetriesTransientHTTPFailure() async throws {
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: URL(string: "https://example.com/rest/v1/tasks")!,
                statusCode: 504,
                httpVersion: nil,
                headerFields: nil
            )
        )
        var attempts = 0

        let value = try await AuthenticatedReadRecovery.run(
            operationName: "test",
            policy: .immediate(retryCount: 1),
            sleep: { _ in }
        ) {
            attempts += 1
            if attempts == 1 {
                throw HTTPError(data: Data(), response: response)
            }
            return "loaded"
        } recoverSession: {
            XCTFail("An HTTP 504 must not refresh authentication")
        }

        XCTAssertEqual(value, "loaded")
        XCTAssertEqual(attempts, 2)
    }

    func testDoesNotRetrySchemaFailures() async {
        var attempts = 0
        var recoveries = 0

        do {
            let _: String = try await AuthenticatedReadRecovery.run(
                operationName: "test",
                policy: .immediate(retryCount: 2),
                sleep: { _ in }
            ) {
                attempts += 1
                throw PostgrestError(code: "PGRST204", message: "column not found")
            } recoverSession: {
                recoveries += 1
            }
            XCTFail("Expected the read to fail")
        } catch let error as PostgrestError {
            XCTAssertEqual(error.code, "PGRST204")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(recoveries, 0)
    }

    func testDoesNotDuplicateSDKTransportRetries() async {
        var attempts = 0

        do {
            let _: String = try await AuthenticatedReadRecovery.run(
                operationName: "test",
                policy: .immediate(retryCount: 2),
                sleep: { _ in }
            ) {
                attempts += 1
                throw URLError(.timedOut)
            } recoverSession: {
                XCTFail("A transport failure must not refresh authentication")
            }
            XCTFail("Expected the read to fail")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(attempts, 1)
    }

    func testDoesNotRefreshSessionForInsufficientPrivilege() async {
        var attempts = 0
        var recoveries = 0

        do {
            let _: String = try await AuthenticatedReadRecovery.run(
                operationName: "test"
            ) {
                attempts += 1
                throw PostgrestError(code: "42501", message: "permission denied")
            } recoverSession: {
                recoveries += 1
            }
            XCTFail("Expected permission denial")
        } catch let error as PostgrestError {
            XCTAssertEqual(error.code, "42501")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(recoveries, 0)
    }

    func testDoesNotRetryCancellation() async {
        var attempts = 0

        do {
            let _: String = try await AuthenticatedReadRecovery.run(
                operationName: "test",
                policy: .immediate(retryCount: 2),
                sleep: { _ in }
            ) {
                attempts += 1
                throw CancellationError()
            } recoverSession: {
                XCTFail("Cancellation must not refresh authentication")
            }
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(attempts, 1)
    }
}
