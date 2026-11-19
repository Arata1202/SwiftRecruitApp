import XCTest
@testable import SwiftRecruitApp

final class ReviewPolishBehaviorTests: XCTestCase {
    func testNewRecordsUseCategoryTitleWithoutRequiringTitleInput() {
        for category in CompanyInformationCategory.allCases {
            var draft = CompanyInformationDraft(category: category)
            draft.body = "本文だけの記録"
            XCTAssertEqual(CompanyInformationWrite(userID: UUID(), companyID: UUID(), draft: draft).title, category.title)
            XCTAssertEqual(CompanyInformationUpdate(draft: draft).body, draft.body)
        }
    }

    func testExistingTitleSurvivesBodyCategoryAndDateEdits() {
        var item = CompanyInformationItem(id: UUID(), userID: UUID(), companyID: UUID(),
            category: .research, title: " 以前の個別タイトル ", body: "以前の本文",
            occurredOn: nil, createdAt: .now, updatedAt: .now)
        for category in CompanyInformationCategory.allCases {
            var draft = CompanyInformationDraft(item: item)
            draft.body = "更新した本文"
            draft.category = category
            draft.hasDate = true
            let payload = CompanyInformationUpdate(draft: draft)
            XCTAssertEqual(payload.title, item.title)
            XCTAssertEqual(payload.category, category)
            XCTAssertNotNil(payload.occurredOn)
            item.category = category
        }
    }
}
