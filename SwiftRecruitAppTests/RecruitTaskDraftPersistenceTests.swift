import Foundation
import XCTest
@testable import SwiftRecruitApp

final class RecruitTaskDraftPersistenceTests: XCTestCase {
    func testEditingDraftPreservesExistingMemo() {
        let task = RecruitTask(
            id: UUID(), userID: UUID(), companyID: nil,
            title: "書類を提出", memo: "PDF化して送付",
            dueAt: nil, dueHasTime: false, completedAt: nil,
            notificationEnabled: false, createdAt: Date(), updatedAt: Date()
        )

        XCTAssertEqual(RecruitTaskDraft(task: task).memo, "PDF化して送付")
    }

    func testWriteAndUpdateNormalizeMemo() {
        var draft = RecruitTaskDraft()
        draft.title = "書類を提出"
        draft.memo = "  PDF化して送付  "

        XCTAssertEqual(RecruitTaskWrite(userID: UUID(), draft: draft).memo, "PDF化して送付")
        XCTAssertEqual(RecruitTaskUpdate(draft: draft).memo, "PDF化して送付")
    }

    func testBlankMemoIsPersistedAsNil() {
        var draft = RecruitTaskDraft()
        draft.memo = "  \n "

        XCTAssertNil(RecruitTaskWrite(userID: UUID(), draft: draft).memo)
        XCTAssertNil(RecruitTaskUpdate(draft: draft).memo)
    }
}
