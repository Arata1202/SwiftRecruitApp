import Foundation
import OSLog
import Supabase

enum AuthenticatedReadRecovery {
    struct RetryPolicy: Sendable {
        let delays: [Duration]
        let maximumJitterMilliseconds: Int

        static let startup = RetryPolicy(
            delays: [.milliseconds(300), .milliseconds(900)],
            maximumJitterMilliseconds: 150
        )

        static func immediate(retryCount: Int) -> RetryPolicy {
            RetryPolicy(
                delays: Array(repeating: .zero, count: retryCount),
                maximumJitterMilliseconds: 0
            )
        }

        func delay(at index: Int) -> Duration {
            guard maximumJitterMilliseconds > 0 else { return delays[index] }
            return delays[index]
                + .milliseconds(Int.random(in: 0...maximumJitterMilliseconds))
        }
    }

    typealias Sleep = (Duration) async throws -> Void

    private static let authenticationErrorCodes: Set<String> = [
        "PGRST301",
        "PGRST302",
        "PGRST303",
    ]
    private static let transientPostgrestErrorCodes: Set<String> = [
        // PGRST000...002 use HTTP 503 and are already retried by supabase-swift.
        "PGRST003", // Connection-pool acquisition timeout (HTTP 504).
    ]
    // Transport errors plus HTTP 503/520 are intentionally omitted because
    // supabase-swift already retries those requests three times.
    private static let transientHTTPStatusCodes: Set<Int> = [
        408,
        425,
        429,
        500,
        502,
        504,
    ]
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SwiftRecruitApp",
        category: "AuthenticatedRead"
    )

    static func run<Value>(
        operationName: String,
        policy: RetryPolicy = .startup,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        operation: () async throws -> Value,
        recoverSession: () async throws -> Void
    ) async throws -> Value {
        var didRecoverSession = false
        var retryIndex = 0

        while true {
            do {
                return try await operation()
            } catch {
                if error is CancellationError {
                    throw error
                }

                var failure = error
                if isAuthenticationError(error), didRecoverSession == false {
                    do {
                        try await recoverSession()
                        didRecoverSession = true
                        logger.notice(
                            "Recovered authentication before retrying \(operationName, privacy: .public)"
                        )
                        continue
                    } catch {
                        failure = error
                    }
                }

                guard isTransient(failure), retryIndex < policy.delays.count else {
                    logFinalFailure(failure, operationName: operationName)
                    throw failure
                }

                let delay = policy.delay(at: retryIndex)
                retryIndex += 1
                logRetry(
                    failure,
                    operationName: operationName,
                    attempt: retryIndex,
                    delay: delay
                )
                try await sleep(delay)
            }
        }
    }

    static func isAuthenticationError(_ error: Error) -> Bool {
        guard let code = (error as? PostgrestError)?.code else { return false }
        return authenticationErrorCodes.contains(code)
    }

    static func isTransient(_ error: Error) -> Bool {
        if let error = error as? HTTPError {
            // Let a later refresh handle a rate limit with a server-defined retry window.
            if error.response.statusCode == 429, error.response.value(forHTTPHeaderField: "Retry-After") != nil {
                return false
            }
            return transientHTTPStatusCodes.contains(error.response.statusCode)
        }

        guard let code = (error as? PostgrestError)?.code else { return false }
        return transientPostgrestErrorCodes.contains(code)
    }

    private static func diagnosticCode(for error: Error) -> String {
        if let error = error as? HTTPError {
            return "http_\(error.response.statusCode)"
        }
        if let error = error as? PostgrestError {
            return "postgrest_\(error.code ?? "unknown")"
        }
        if error is DecodingError {
            return "decoding"
        }
        return String(reflecting: type(of: error))
    }

    private static func logRetry(
        _ error: Error,
        operationName: String,
        attempt: Int,
        delay: Duration
    ) {
        let code = diagnosticCode(for: error)
        logger.notice(
            """
            Retrying \(operationName, privacy: .public), \
            attempt \(attempt, privacy: .public), \
            delay \(String(describing: delay), privacy: .public), \
            reason \(code, privacy: .public)
            """
        )
    }

    private static func logFinalFailure(_ error: Error, operationName: String) {
        let code = diagnosticCode(for: error)
        logger.error(
            "Read failed for \(operationName, privacy: .public), reason \(code, privacy: .public)"
        )
    }
}
