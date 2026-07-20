import XCTest
@testable import SwiftRecruitApp

final class CalendarCreationDraftTests: XCTestCase {
    func testSelectionDraftUsesSelectedCalendarDate() {
        let selectedDate = Date(timeIntervalSince1970: 2_000_000_000)

        let draft = SelectionStepDraft(date: selectedDate)

        XCTAssertEqual(draft.date, selectedDate)
        XCTAssertFalse(draft.hasTime)
        XCTAssertEqual(draft.dateKind, .schedule)
    }

    func testTaskDraftUsesSelectedCalendarDateAndEnablesDeadline() {
        let selectedDate = Date(timeIntervalSince1970: 2_000_000_000)

        let draft = RecruitTaskDraft(dueDate: selectedDate)

        XCTAssertEqual(draft.dueAt, selectedDate)
        XCTAssertTrue(draft.hasDueDate)
        XCTAssertFalse(draft.dueHasTime)
    }
}
