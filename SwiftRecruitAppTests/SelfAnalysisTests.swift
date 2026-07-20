import Foundation
import XCTest
@testable import SwiftRecruitApp

final class SelfAnalysisTests: XCTestCase {
    func testAnswerDraftProvidesPromptForCategory() {
        let draft = SelfAnalysisAnswerDraft(category: .workStyle)

        XCTAssertEqual(draft.category, .workStyle)
        XCTAssertFalse(draft.question.isEmpty)
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

    private func answer(category: SelfAnalysisCategory, updatedAt: Date) -> SelfAnalysisAnswer {
        SelfAnalysisAnswer(
            id: UUID(), userID: UUID(), category: category,
            question: category.defaultQuestion, answer: "回答",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000), updatedAt: updatedAt
        )
    }

    private func point(age: Int, updatedAt: Date) -> MotivationPoint {
        MotivationPoint(
            id: UUID(), userID: UUID(), age: age, happiness: 5, reason: "理由",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000), updatedAt: updatedAt
        )
    }
}
