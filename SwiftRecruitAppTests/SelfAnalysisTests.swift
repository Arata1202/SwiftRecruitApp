import Foundation
import XCTest
@testable import SwiftRecruitApp

final class SelfAnalysisTests: XCTestCase {
    func testAnswerDraftProvidesPromptForCategory() {
        let draft = SelfAnalysisAnswerDraft(category: .workStyle)

        XCTAssertEqual(draft.category, .workStyle)
        XCTAssertEqual(draft.question, SelfAnalysisCategory.workStyle.defaultQuestion)
    }

    func testCustomAnswerDraftStartsWithAnEmptyQuestion() {
        let draft = SelfAnalysisAnswerDraft(category: .custom)

        XCTAssertEqual(draft.category, .custom)
        XCTAssertTrue(draft.question.isEmpty)
    }

    func testEditingAnswerDraftPreservesAllEditableValues() {
        let existing = answer(category: .future, updatedAt: Date())

        let draft = SelfAnalysisAnswerDraft(answer: existing)

        XCTAssertEqual(draft.category, existing.category)
        XCTAssertEqual(draft.question, existing.question)
        XCTAssertEqual(draft.answer, existing.answer)
    }

    func testAnswerPayloadTrimsText() {
        var draft = SelfAnalysisAnswerDraft(category: .custom)
        draft.question = "  得意なことは？  "
        draft.answer = "  問題を整理すること  \n"

        let payload = SelfAnalysisAnswerWrite(userID: UUID(), draft: draft)

        XCTAssertEqual(payload.question, "得意なことは？")
        XCTAssertEqual(payload.answer, "問題を整理すること")
    }

    func testMotivationPayloadTrimsReasonAndKeepsScore() {
        var draft = MotivationPointDraft()
        draft.age = 20
        draft.happiness = 8
        draft.reason = "  開発が楽しかった  "

        let payload = MotivationPointWrite(userID: UUID(), draft: draft)

        XCTAssertEqual(payload.age, 20)
        XCTAssertEqual(payload.happiness, 8)
        XCTAssertEqual(payload.reason, "開発が楽しかった")
    }

    func testEditingMotivationDraftPreservesAllEditableValues() {
        let existing = point(age: 21, happiness: 8, reason: "開発経験", updatedAt: Date())

        let draft = MotivationPointDraft(point: existing)

        XCTAssertEqual(draft.age, existing.age)
        XCTAssertEqual(draft.happiness, existing.happiness)
        XCTAssertEqual(draft.reason, existing.reason)
    }

    func testAnswersSortByCategoryThenNewestFirst() {
        let olderValues = answer(category: .values, updatedAt: Date(timeIntervalSince1970: 1_900_000_000))
        let newerValues = answer(category: .values, updatedAt: Date(timeIntervalSince1970: 2_000_000_000))
        let future = answer(category: .future, updatedAt: Date(timeIntervalSince1970: 2_100_000_000))

        let sorted = SelfAnalysisSorting.answers([olderValues, future, newerValues])

        XCTAssertEqual(sorted.map(\.category), [.values, .values, .future])
        XCTAssertEqual(sorted.first?.updatedAt, newerValues.updatedAt)
    }

    func testMotivationPointsSortByAge() {
        let age22 = point(age: 22, updatedAt: Date(timeIntervalSince1970: 2_000_000_000))
        let age18 = point(age: 18, updatedAt: Date(timeIntervalSince1970: 2_100_000_000))

        XCTAssertEqual(SelfAnalysisSorting.motivationPoints([age22, age18]).map(\.age), [18, 22])
    }

    func testMotivationPointsWithSameAgeUseStableCreationOrder() {
        let older = point(
            age: 20,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 2_100_000_000)
        )
        let newer = point(
            age: 20,
            createdAt: Date(timeIntervalSince1970: 1_900_000_000),
            updatedAt: Date(timeIntervalSince1970: 2_000_000_000)
        )

        XCTAssertEqual(SelfAnalysisSorting.motivationPoints([newer, older]).map(\.id), [older.id, newer.id])
    }

    func testDuplicateMotivationAgeExcludesThePointBeingEdited() {
        let existing = point(age: 20, updatedAt: Date())
        let another = point(age: 21, updatedAt: Date())
        let points = [existing, another]

        XCTAssertTrue(
            SelfAnalysisValidation.hasDuplicateMotivationAge(
                20,
                excluding: nil,
                in: points
            )
        )
        XCTAssertFalse(
            SelfAnalysisValidation.hasDuplicateMotivationAge(
                20,
                excluding: existing.id,
                in: points
            )
        )
    }

    func testDuplicateAgeRepositoryErrorExplainsHowToResolveIt() {
        XCTAssertEqual(
            RepositoryError.duplicateMotivationAge.localizedDescription,
            "同じ年齢の記録がすでにあります。既存の記録を編集してください。"
        )
    }

    private func answer(category: SelfAnalysisCategory, updatedAt: Date) -> SelfAnalysisAnswer {
        SelfAnalysisAnswer(
            id: UUID(), userID: UUID(), category: category,
            question: category.defaultQuestion, answer: "回答",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000), updatedAt: updatedAt
        )
    }

    private func point(
        age: Int,
        happiness: Int = 5,
        reason: String = "理由",
        createdAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
        updatedAt: Date
    ) -> MotivationPoint {
        MotivationPoint(
            id: UUID(), userID: UUID(), age: age, happiness: happiness, reason: reason,
            createdAt: createdAt, updatedAt: updatedAt
        )
    }
}
