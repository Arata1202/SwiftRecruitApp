import XCTest
@testable import SwiftRecruitApp

final class KeysetPaginatedFetchTests: XCTestCase {
    func testLoadsEveryPageUntilAShortPage() async throws {
        let values = (1...5).map {
            TestValue(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))!)
        }
        var cursors: [UUID?] = []

        let result = try await KeysetPaginatedFetch.all(pageSize: 2) { afterID, limit in
            cursors.append(afterID)
            let start = afterID.flatMap { id in values.firstIndex { $0.id == id } }.map { $0 + 1 } ?? 0
            return Array(values.dropFirst(start).prefix(limit))
        }

        XCTAssertEqual(result, values)
        XCTAssertEqual(cursors.count, 3)
        XCTAssertNil(cursors[0])
        XCTAssertEqual(cursors[1], values[1].id)
        XCTAssertEqual(cursors[2], values[3].id)
    }

    func testRejectsAFullPageThatDoesNotAdvanceTheCursor() async {
        let id = UUID()

        do {
            _ = try await KeysetPaginatedFetch.all(pageSize: 1) { _, _ in
                [TestValue(id: id)]
            }
            XCTFail("Expected invalid pagination response")
        } catch let error as RepositoryError {
            guard case .invalidPaginationResponse = error else {
                return XCTFail("Unexpected repository error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private struct TestValue: Identifiable, Equatable {
    let id: UUID
}
