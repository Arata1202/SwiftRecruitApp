import Foundation

enum KeysetPaginatedFetch {
    static let defaultPageSize = 500

    static func all<Value: Identifiable>(
        pageSize: Int = defaultPageSize,
        fetchPage: (_ afterID: UUID?, _ limit: Int) async throws -> [Value]
    ) async throws -> [Value] where Value.ID == UUID {
        precondition(pageSize > 0)

        var values: [Value] = []
        var afterID: UUID?

        while true {
            let page = try await fetchPage(afterID, pageSize)
            values.append(contentsOf: page)

            guard page.count == pageSize else { return values }
            guard let nextID = page.last?.id, nextID != afterID else {
                throw RepositoryError.invalidPaginationResponse
            }
            afterID = nextID
        }
    }
}
