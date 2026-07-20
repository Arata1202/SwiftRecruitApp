import Foundation
import XCTest
@testable import SwiftRecruitApp

final class CompanyInformationTests: XCTestCase {
    func testInterviewDraftDefaultsToDatedEntry() {
        let draft = CompanyInformationDraft(category: .interview)

        XCTAssertEqual(draft.title, "")
        XCTAssertTrue(draft.hasDate)
    }

    func testNewNonInterviewDraftStartsWithoutTitleOrDate() {
        let draft = CompanyInformationDraft(category: .research)

        XCTAssertEqual(draft.title, "")
        XCTAssertFalse(draft.hasDate)
    }

    func testCategoriesProvideSpecificTitleExamples() {
        XCTAssertEqual(CompanyInformationCategory.research.titlePlaceholder, "例：競合との違い")
        XCTAssertEqual(CompanyInformationCategory.motivation.titlePlaceholder, "例：この企業を志望する理由")
        XCTAssertEqual(CompanyInformationCategory.interview.titlePlaceholder, "例：一次面接")
        XCTAssertEqual(CompanyInformationCategory.questions.titlePlaceholder, "例：現場社員への質問")
        XCTAssertEqual(CompanyInformationCategory.custom.titlePlaceholder, "例：福利厚生について")
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

    func testRecordedDateDisplayIncludesYear() {
        let date = LocalDate(year: 2026, month: 7, day: 20)

        XCTAssertEqual(DateFormatting.localDateWithYear(date), "2026年7月20日")
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
