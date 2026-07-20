import XCTest
@testable import SwiftRecruitApp

final class CompanyPriorityCompatibilityTests: XCTestCase {
    func testNewDraftUsesCompatibleDefaultPriority() {
        XCTAssertEqual(CompanyDraft().priority, 3)
    }

    func testEditingDraftPreservesExistingPriority() {
        let company = Company(
            id: UUID(),
            userID: UUID(),
            name: "テスト株式会社",
            priority: 5,
            status: .active,
            url: nil,
            memo: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertEqual(CompanyDraft(company: company).priority, 5)
    }
}
