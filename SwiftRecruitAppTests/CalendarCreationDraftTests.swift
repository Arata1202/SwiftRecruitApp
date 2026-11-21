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

    func testTodayStartsWithoutTaskNotifications() {
        XCTAssertFalse(RecruitTaskDraft().notificationEnabled)
        XCTAssertFalse(RecruitTaskDraft(dueDate: Calendar.current.startOfDay(for: Date())).notificationEnabled)
    }

    func testFutureDateKeepsDefaultTaskReminder() throws {
        let future = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 3, to: Date()))
        let draft = RecruitTaskDraft(dueDate: future)
        XCTAssertTrue(draft.notificationEnabled)
        XCTAssertEqual(draft.notificationDatePreset, .previousDay)
    }

    func testTaskDraftUsesSelectedCalendarDateAndEnablesDeadline() {
        let selectedDate = Date(timeIntervalSince1970: 2_000_000_000)

        let draft = RecruitTaskDraft(dueDate: selectedDate)

        XCTAssertEqual(draft.dueAt, selectedDate)
        XCTAssertTrue(draft.hasDueDate)
        XCTAssertFalse(draft.dueHasTime)
    }
}
