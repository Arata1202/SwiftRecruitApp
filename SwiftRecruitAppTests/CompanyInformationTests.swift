import Foundation
import XCTest
@testable import SwiftRecruitApp

final class CompanyInformationTests: XCTestCase {
    func testInterviewDraftDefaultsToDatedEntry() {
        let draft = CompanyInformationDraft(category: .interview)

        XCTAssertEqual(draft.title, "面接記録")
        XCTAssertTrue(draft.hasDate)
    }

    func testEditingDraftPreservesAllValues() throws {
        let date = LocalDate(year: 2026, month: 7, day: 20)
        let item = makeItem(category: .motivation, occurredOn: date)

        let draft = CompanyInformationDraft(item: item)

        XCTAssertEqual(draft.category, .motivation)
        XCTAssertEqual(draft.title, item.title)
        XCTAssertEqual(draft.body, item.body)
        XCTAssertTrue(draft.hasDate)
        XCTAssertEqual(LocalDate(date: draft.date), date)
    }

    func testPayloadTrimsTextAndCanClearDate() throws {
        var draft = CompanyInformationDraft(category: .custom)
        draft.title = "  福利厚生  "
        draft.body = "  リモート制度を確認  \n"
        draft.hasDate = false

        let payload = CompanyInformationUpdate(draft: draft)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]
        )

        XCTAssertEqual(object["title"] as? String, "福利厚生")
        XCTAssertEqual(object["body"] as? String, "リモート制度を確認")
        XCTAssertTrue(object.keys.contains("occurred_on"))
        XCTAssertTrue(object["occurred_on"] is NSNull)
    }

    func testSortingGroupsCategoriesAndUsesNewestDateFirst() {
        let olderInterview = makeItem(
            category: .interview,
            occurredOn: LocalDate(year: 2026, month: 6, day: 1)
        )
        let newerInterview = makeItem(
            category: .interview,
            occurredOn: LocalDate(year: 2026, month: 7, day: 1)
        )
        let research = makeItem(category: .research, occurredOn: nil)

        let sorted = CompanyInformationSorting.sorted([olderInterview, newerInterview, research])

        XCTAssertEqual(sorted.map(\.category), [.research, .interview, .interview])
        XCTAssertEqual(sorted[1].occurredOn, LocalDate(year: 2026, month: 7, day: 1))
    }

    private func makeItem(
        category: CompanyInformationCategory,
        occurredOn: LocalDate?
    ) -> CompanyInformationItem {
        CompanyInformationItem(
            id: UUID(),
            userID: UUID(),
            companyID: UUID(),
            category: category,
            title: category.title,
            body: "内容",
            occurredOn: occurredOn,
            createdAt: Date(timeIntervalSince1970: 1_900_000_000),
            updatedAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
    }
}
