import Foundation
import XCTest
@testable import SwiftRecruitApp

final class ESTemplateTests: XCTestCase {
    func testDraftUsesCategoryAsDefaultTitle() {
        let draft = ESTemplateDraft(category: .selfPromotion)

        XCTAssertEqual(draft.category, .selfPromotion)
        XCTAssertEqual(draft.title, "自己PR")
    }

    func testEditingDraftPreservesTemplate() {
        let template = makeTemplate(category: .motivation, updatedAt: Date())

        let draft = ESTemplateDraft(template: template)

        XCTAssertEqual(draft.category, template.category)
        XCTAssertEqual(draft.title, template.title)
        XCTAssertEqual(draft.body, template.body)
    }

    func testWriteAndUpdatePayloadsTrimText() {
        var draft = ESTemplateDraft(category: .custom)
        draft.title = "  研究テーマ  "
        draft.body = "  説明文  \n"

        let write = ESTemplateWrite(userID: UUID(), draft: draft)
        let update = ESTemplateUpdate(draft: draft)

        XCTAssertEqual(write.title, "研究テーマ")
        XCTAssertEqual(write.body, "説明文")
        XCTAssertEqual(update.title, "研究テーマ")
        XCTAssertEqual(update.body, "説明文")
    }

    func testSortingGroupsCategoriesThenUsesMostRecentFirst() {
        let oldSelfPromotion = makeTemplate(
            category: .selfPromotion,
            updatedAt: Date(timeIntervalSince1970: 1_900_000_000)
        )
        let newSelfPromotion = makeTemplate(
            category: .selfPromotion,
            updatedAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
        let studentExperience = makeTemplate(
            category: .studentExperience,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let sorted = ESTemplateSorting.sorted([
            oldSelfPromotion, newSelfPromotion, studentExperience
        ])

        XCTAssertEqual(sorted.map(\.category), [
            .studentExperience, .selfPromotion, .selfPromotion
        ])
        XCTAssertEqual(sorted[1].updatedAt, newSelfPromotion.updatedAt)
    }

    private func makeTemplate(category: ESTemplateCategory, updatedAt: Date) -> ESTemplate {
        ESTemplate(
            id: UUID(),
            userID: UUID(),
            category: category,
            title: category.title,
            body: "本文",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: updatedAt
        )
    }
}
