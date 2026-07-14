import Supabase

enum AuthenticatedReadRecovery {
    static func run<Value>(
        operation: () async throws -> Value,
        recoverSession: () async throws -> Void
    ) async throws -> Value {
        do {
            return try await operation()
        } catch let error as PostgrestError where error.code == "42501" {
            // Authenticated-only tables return 42501 when a read reaches PostgREST as anon.
            try await recoverSession()
            return try await operation()
        }
    }
}
