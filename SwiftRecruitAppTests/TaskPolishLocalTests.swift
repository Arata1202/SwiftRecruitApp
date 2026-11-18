import Foundation
import XCTest
@testable import SwiftRecruitApp

final class TaskPolishLocalTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: hour))!
    }

    func testEveryEditableFieldIsProtectedAndRevertingIsClean() {
        var initial = RecruitTaskDraft(dueDate: date(12))
        initial.title = "応募する"
        for field in ["title", "memo", "company", "deadline", "time", "date", "notification"] {
            var draft = initial
            switch field {
            case "title": draft.title += " "
            case "memo": draft.memo = "メモ"
            case "company": draft.companyID = UUID()
            case "deadline": draft.hasDueDate = false
            case "time": draft.dueHasTime = true
            case "date": draft.dueAt = date(12).addingTimeInterval(86_400)
            default: draft.notificationEnabled = false
            }
            XCTAssertTrue(draft.hasTaskEditorChanges(comparedTo: initial, calendar: calendar), field)
            draft = initial
            XCTAssertFalse(draft.hasTaskEditorChanges(comparedTo: initial, calendar: calendar), field)
        }
    }

    func testHiddenTimeAndDisabledDeadlineDoNotMakeDraftDirty() {
        var initial = RecruitTaskDraft(dueDate: date(12))
        var draft = initial
        draft.dueAt = date(18)
        XCTAssertFalse(draft.hasTaskEditorChanges(comparedTo: initial, calendar: calendar))
        initial.hasDueDate = false
        draft = initial
        draft.dueAt = date(12).addingTimeInterval(86_400)
        draft.dueHasTime = true
        XCTAssertFalse(draft.hasTaskEditorChanges(comparedTo: initial, calendar: calendar))
    }

    func testExplicitTimeChangeIsDirty() {
        var initial = RecruitTaskDraft(dueDate: date(12))
        initial.dueHasTime = true
        var draft = initial
        draft.dueAt = date(18)
        XCTAssertTrue(draft.hasTaskEditorChanges(comparedTo: initial, calendar: calendar))
    }

    func testHiddenSecondsDoNotMakeTimedDraftDirty() {
        var initial = RecruitTaskDraft(dueDate: date(12))
        initial.dueHasTime = true
        var draft = initial
        draft.dueAt = initial.dueAt.addingTimeInterval(30)
        XCTAssertFalse(draft.hasTaskEditorChanges(comparedTo: initial, calendar: calendar))
        draft.dueAt = initial.dueAt.addingTimeInterval(60)
        XCTAssertTrue(draft.hasTaskEditorChanges(comparedTo: initial, calendar: calendar))
    }

    func testTimedNotificationBoundaryMatchesCalculator() {
        for now in [date(11), date(12), date(13)] {
            let text = TaskNotificationDescription.text(
                enabled: true, isCompleted: false, dueAt: date(12), hasTime: true,
                calendar: calendar, now: now
            )
            let scheduled = NotificationScheduleCalculator.taskDate(
                dueAt: date(12), hasTime: true, calendar: calendar, now: now
            ) != nil
            XCTAssertEqual(text.contains("通知予定"), scheduled)
            XCTAssertEqual(text.contains("過ぎている"), !scheduled)
        }
    }

    func testDateOnlyNotificationUsesNineAMNotDeadlineEndOfDay() {
        let before = TaskNotificationDescription.text(
            enabled: true, isCompleted: false, dueAt: date(0), hasTime: false,
            calendar: calendar, now: date(8)
        )
        let after = TaskNotificationDescription.text(
            enabled: true, isCompleted: false, dueAt: date(0), hasTime: false,
            calendar: calendar, now: date(9)
        )
        XCTAssertTrue(before.contains("2026年11月18日 9:00"))
        XCTAssertTrue(after.contains("過ぎている"))
    }

    func testCompletedDisabledAndUndatedNotificationsNeverPromiseDelivery() {
        let completed = TaskNotificationDescription.text(
            enabled: true, isCompleted: true, dueAt: date(12), hasTime: true, now: date(8)
        )
        let disabled = TaskNotificationDescription.text(
            enabled: false, isCompleted: false, dueAt: date(12), hasTime: true, now: date(8)
        )
        let undated = TaskNotificationDescription.text(
            enabled: true, isCompleted: false, dueAt: nil, hasTime: false, now: date(8)
        )
        XCTAssertTrue(completed.contains("完了中は通知されません"))
        XCTAssertTrue(disabled.contains("オフ"))
        XCTAssertTrue(undated.contains("期限が未設定"))
    }
}
