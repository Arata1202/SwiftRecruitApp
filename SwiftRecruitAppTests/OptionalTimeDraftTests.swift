import Foundation
import XCTest
@testable import SwiftRecruitApp

final class OptionalTimeDraftTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 9 * 3_600)!
        return value
    }

    func testNewDraftsUseCurrentLocalMinuteOnSelectedDate() {
        let selected = date(day: 25, hour: 0)
        let now = date(day: 3, hour: 23, minute: 47, second: 58)
        let expected = date(day: 25, hour: 23, minute: 47)
        for kind in SelectionDateKind.allCases {
            var selection = SelectionStepDraft(date: selected)
            selection.dateKind = kind
            selection.setHasTime(false, now: now, calendar: calendar)
            XCTAssertEqual(selection.date, selected)
            selection.setHasTime(true, now: now, calendar: calendar)
            XCTAssertEqual(selection.date, expected)
            XCTAssertTrue(selection.hasTime)
            XCTAssertTrue(selection.notificationEnabled)
        }
        var task = RecruitTaskDraft(dueDate: selected)
        task.setDueHasTime(false, now: now, calendar: calendar)
        XCTAssertEqual(task.dueAt, selected)
        task.setDueHasTime(true, now: now, calendar: calendar)
        XCTAssertEqual(task.dueAt, expected)
        XCTAssertTrue(task.dueHasTime)
        XCTAssertTrue(task.notificationEnabled)
    }

    func testExistingDateOnlyDraftsInitializeTimeWithoutChangingModels() {
        let calendar = Calendar.current
        let selected = date(day: 25, hour: 0)
        let now = date(day: 3, hour: 15, minute: 26, second: 59)
        let time = calendar.dateComponents([.hour, .minute], from: now)
        for kind in SelectionDateKind.allCases {
            var step = makeStep(date: selected, timed: false)
            if kind == .deadline {
                step.deadlineAt = step.startsAt
                step.startsAt = nil
                step.deadlineOn = LocalDate(date: selected, calendar: calendar)
            } else {
                step.startsOn = LocalDate(date: selected, calendar: calendar)
            }
            let original = step
            var draft = SelectionStepDraft(step: step)
            let originalDate = draft.date
            draft.setHasTime(true, now: now, calendar: calendar)
            XCTAssertTrue(calendar.isDate(draft.date, inSameDayAs: originalDate))
            XCTAssertEqual(calendar.component(.hour, from: draft.date), time.hour)
            XCTAssertEqual(calendar.component(.minute, from: draft.date), time.minute)
            XCTAssertEqual(calendar.component(.second, from: draft.date), 0)
            XCTAssertEqual(draft.dateKind, kind)
            XCTAssertEqual(step, original)
        }
        var task = makeTask(date: selected, timed: false)
        task.dueOn = LocalDate(date: selected, calendar: calendar)
        let original = task
        var draft = RecruitTaskDraft(task: task)
        let originalDate = draft.dueAt
        draft.setDueHasTime(true, now: now, calendar: calendar)
        XCTAssertTrue(calendar.isDate(draft.dueAt, inSameDayAs: originalDate))
        XCTAssertEqual(calendar.component(.hour, from: draft.dueAt), time.hour)
        XCTAssertEqual(calendar.component(.minute, from: draft.dueAt), time.minute)
        XCTAssertEqual(calendar.component(.second, from: draft.dueAt), 0)
        XCTAssertEqual(task, original)
    }

    func testRepeatedTogglesPreserveUserChosenTimeAndDate() {
        let selected = date(day: 25, hour: 0)
        let now = date(day: 3, hour: 15, minute: 26)
        let chosen = date(day: 28, hour: 10, minute: 12)
        var selection = SelectionStepDraft(date: selected)
        var task = RecruitTaskDraft(dueDate: selected)
        selection.setHasTime(true, now: now, calendar: calendar)
        task.setDueHasTime(true, now: now, calendar: calendar)
        selection.date = chosen
        task.dueAt = chosen
        for _ in 0..<3 {
            selection.setHasTime(false, calendar: calendar)
            task.setDueHasTime(false, calendar: calendar)
            XCTAssertEqual(selection.date, chosen)
            XCTAssertEqual(task.dueAt, chosen)
            selection.setHasTime(true, now: now.addingTimeInterval(3_600), calendar: calendar)
            task.setDueHasTime(true, now: now.addingTimeInterval(3_600), calendar: calendar)
            XCTAssertEqual(selection.date, chosen)
            XCTAssertEqual(task.dueAt, chosen)
        }
    }

    func testExistingExplicitTimesSurviveEditingAndToggles() {
        let existing = date(day: 25, hour: 10, minute: 12, second: 34)
        for kind in SelectionDateKind.allCases {
            var step = makeStep(date: existing, timed: true)
            if kind == .deadline {
                step.startsAt = nil
                step.deadlineAt = existing
                step.deadlineHasTime = true
            }
            var draft = SelectionStepDraft(step: step)
            XCTAssertEqual(draft.date, existing)
            draft.setHasTime(true, calendar: calendar)
            XCTAssertEqual(draft.date, existing)
            draft.setHasTime(false, calendar: calendar)
            draft.setHasTime(true, calendar: calendar)
            XCTAssertEqual(draft.date, existing)
        }
        var task = RecruitTaskDraft(task: makeTask(date: existing, timed: true))
        XCTAssertEqual(task.dueAt, existing)
        task.setDueHasTime(true, calendar: calendar)
        XCTAssertEqual(task.dueAt, existing)
        task.setDueHasTime(false, calendar: calendar)
        task.setDueHasTime(true, calendar: calendar)
        XCTAssertEqual(task.dueAt, existing)
    }

    func testSavingAfterTravelPreservesDateOnlyFieldsAndTimedInstants() throws {
        let previousZone = NSTimeZone.default
        defer { NSTimeZone.default = previousZone }
        NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let start = LocalDate(year: 2027, month: 5, day: 15)
        let end = LocalDate(year: 2027, month: 5, day: 16)
        let instant = try XCTUnwrap(start.date())
        var step = makeStep(date: instant, timed: false)
        step.startsOn = start
        step.endsOn = end
        var selection = SelectionStepDraft(step: step)
        var deadline = SelectionStepDraft(date: instant)
        deadline.setDateKind(.deadline)
        var original = makeTask(date: instant, timed: false)
        original.dueOn = start
        var task = RecruitTaskDraft(task: original)
        var info = CompanyInformationDraft(category: .interview)
        info.date = instant
        var timed = RecruitTaskDraft(task: makeTask(date: instant, timed: true))

        NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        task.memo = "更新"
        selection.memo = task.memo
        XCTAssertEqual(RecruitTaskUpdate(draft: task).dueOn, start)
        let update = SelectionStepUpdate(draft: selection)
        XCTAssertEqual(update.startsOn, start)
        XCTAssertEqual(update.endsOn, end)
        XCTAssertEqual(SelectionStepUpdate(draft: deadline).deadlineOn, start)
        XCTAssertEqual(CompanyInformationUpdate(draft: info).occurredOn, start)
        XCTAssertEqual(RecruitTaskUpdate(draft: timed).dueAt, instant)
        timed.setDueHasTime(false)
        XCTAssertEqual(RecruitTaskUpdate(draft: timed).dueOn, LocalDate(date: instant))
    }

    func testDSTGapDoesNotMoveSelectedDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let selected = calendar.date(from: DateComponents(year: 2030, month: 3, day: 10))!
        let now = calendar.date(from: DateComponents(year: 2030, month: 3, day: 9, hour: 2, minute: 30))!
        var selection = SelectionStepDraft(date: selected)
        var task = RecruitTaskDraft(dueDate: selected)
        selection.setHasTime(true, now: now, calendar: calendar)
        task.setDueHasTime(true, now: now, calendar: calendar)
        XCTAssertTrue(calendar.isDate(selection.date, inSameDayAs: selected))
        XCTAssertEqual(selection.date, task.dueAt)
        XCTAssertEqual(calendar.component(.second, from: selection.date), 0)
    }

    private func date(day: Int, hour: Int, minute: Int = 0, second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2030, month: 1, day: day, hour: hour, minute: minute, second: second))!
    }

    private func makeStep(date: Date, timed: Bool) -> SelectionStep {
        SelectionStep(
            id: UUID(), userID: UUID(), companyID: UUID(), type: .interview,
            customTitle: nil, startsAt: date, startsHasTime: timed,
            deadlineAt: nil, deadlineHasTime: false, status: .scheduled,
            memo: nil, notificationEnabled: true, createdAt: date, updatedAt: date
        )
    }

    private func makeTask(date: Date, timed: Bool) -> RecruitTask {
        RecruitTask(
            id: UUID(), userID: UUID(), companyID: nil, title: "準備", memo: nil,
            dueAt: date, dueHasTime: timed, completedAt: nil,
            notificationEnabled: true, createdAt: date, updatedAt: date
        )
    }
}
