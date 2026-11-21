import XCTest
@testable import SwiftRecruitApp

final class CustomNotificationTimingTests: XCTestCase {
    func testInvalidPreferenceCopyKeepsBoundsAndIdentifiesHiddenPrecision() {
        XCTAssertEqual(NotificationScheduleCalculator.preferenceValidationMessage(
            timedCustom: .elapsed(0), dateCustom: nil
        ), "時刻を指定する場合の通知：1〜2,016,000分前で入力してください。")
        XCTAssertEqual(NotificationScheduleCalculator.preferenceValidationMessage(
            timedCustom: .elapsed(33_601, unit: .hours), dateCustom: nil
        ), "時刻を指定する場合の通知：1〜33,600時間前で入力してください。")
        XCTAssertEqual(NotificationScheduleCalculator.preferenceValidationMessage(
            timedCustom: nil, dateCustom: .calendar(daysBefore: 1_401)
        ), "日付のみの場合の通知：0〜1,400日前と有効な時刻を入力してください。")
        XCTAssertNil(NotificationScheduleCalculator.preferenceValidationMessage(
            timedCustom: .elapsed(1), dateCustom: .calendar(daysBefore: 1_400)
        ))
    }

    private func calendar(_ zone: String = "America/New_York") -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: zone)!
        return result
    }

    private func date(_ month: Int = 3, _ day: Int = 11, hour: Int = 12, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2030, month: month, day: day, hour: hour))!
    }

    private func fire(_ custom: CustomNotificationTiming, anchor: Date, timed: Bool = true, calendar: Calendar) -> Date? {
        NotificationScheduleCalculator.reminderDate(
            anchor: anchor, hasTime: timed, kind: .selectionStart,
            timedPreset: .oneHour, datePreset: .previousDay,
            timedCustom: timed ? custom : nil, dateCustom: timed ? nil : custom, calendar: calendar
        )
    }

    func testElapsedMinutesAndHoursAreExactAcrossDST() throws {
        let cal = calendar()
        let anchor = date(calendar: cal)
        for (custom, seconds) in [(CustomNotificationTiming.elapsed(97), 5_820.0), (.elapsed(24, unit: .hours), 86_400.0)] {
            XCTAssertEqual(anchor.timeIntervalSince(try XCTUnwrap(fire(custom, anchor: anchor, calendar: cal))), seconds)
        }
        let calendarFire = try XCTUnwrap(fire(.calendar(daysBefore: 1, hour: 12), anchor: date(3, 10, calendar: cal), calendar: cal))
        XCTAssertEqual(date(3, 10, calendar: cal).timeIntervalSince(calendarFire), 23 * 3_600)
    }

    func testCalendarAvailableForBothPrecisionsAndDateOnlyAfterMidnightIsValid() throws {
        let cal = calendar("Asia/Tokyo")
        let midnight = date(hour: 0, calendar: cal)
        let custom = CustomNotificationTiming.calendar(hour: 21, minute: 37)
        XCTAssertNil(fire(custom, anchor: midnight, calendar: cal))
        let result = try XCTUnwrap(fire(custom, anchor: midnight, timed: false, calendar: cal))
        XCTAssertEqual(cal.component(.hour, from: result), 21)
        XCTAssertEqual(cal.component(.minute, from: result), 37)
        XCTAssertTrue(cal.isDate(result, inSameDayAs: midnight))
        XCTAssertNotNil(fire(.calendar(hour: 8), anchor: date(calendar: cal), calendar: cal))
    }

    func testDSTGapUsesNextValidTimeOnSameDayAndFoldUsesFirstOccurrence() throws {
        let cal = calendar()
        let gap = try XCTUnwrap(fire(.calendar(hour: 2, minute: 37), anchor: date(3, 10, calendar: cal), calendar: cal))
        XCTAssertEqual(cal.component(.hour, from: gap), 3)
        XCTAssertEqual(cal.component(.minute, from: gap), 0)
        XCTAssertEqual(cal.component(.day, from: gap), 10)
        let fold = try XCTUnwrap(fire(.calendar(hour: 1, minute: 30), anchor: date(11, 3, calendar: cal), calendar: cal))
        XCTAssertEqual(cal.timeZone.secondsFromGMT(for: fold), -4 * 3_600)
    }

    func testBoundsAndIncompatibleDateOnlyElapsedNeverSchedule() {
        let cal = calendar()
        let anchor = date(calendar: cal)
        for custom in [CustomNotificationTiming.elapsed(0), .elapsed(-1), .elapsed(2_016_001), .elapsed(33_601, unit: .hours),
                       .calendar(daysBefore: -1), .calendar(daysBefore: 1_401), .calendar(hour: 24), .calendar(minute: 60)] {
            XCTAssertNil(fire(custom, anchor: anchor, calendar: cal))
        }
        XCTAssertNotNil(fire(.elapsed(2_016_000), anchor: anchor, calendar: cal))
        XCTAssertNotNil(fire(.elapsed(33_600, unit: .hours), anchor: anchor, calendar: cal))
        XCTAssertNotNil(fire(.calendar(daysBefore: 1_400), anchor: anchor, calendar: cal))
        XCTAssertNil(fire(.elapsed(), anchor: anchor, timed: false, calendar: cal))
    }

    func testCalendarClockUsesDeviceZoneAndRecomputesAfterAnchorEdit() throws {
        for zone in ["Asia/Tokyo", "UTC", "America/Los_Angeles"] {
            let cal = calendar(zone)
            let anchor = LocalDate(year: 2030, month: 1, day: 1).date(calendar: cal)!
            let custom = CustomNotificationTiming.calendar(daysBefore: 3, hour: 17, minute: 23)
            let result = try XCTUnwrap(fire(custom, anchor: anchor, timed: false, calendar: cal))
            let components = cal.dateComponents([.year, .month, .day, .hour, .minute], from: result)
            XCTAssertEqual(components.year, 2029)
            XCTAssertEqual(components.month, 12)
            XCTAssertEqual(components.day, 29)
            XCTAssertEqual(components.hour, 17)
            XCTAssertEqual(components.minute, 23)
            let moved = cal.date(byAdding: .day, value: 2, to: anchor)!
            XCTAssertEqual(cal.component(.day, from: try XCTUnwrap(fire(custom, anchor: moved, timed: false, calendar: cal))), 31)
        }
    }

    func testInvalidSaveAndPastExplanationShareCalculation() throws {
        let cal = calendar()
        var draft = SelectionStepDraft(date: date(hour: 8, calendar: cal))
        draft.hasTime = true
        draft.notificationTimedCustom = .calendar(hour: 9)
        XCTAssertEqual(draft.notificationValidationMessage(calendar: cal), "通知時刻は選考の開始時刻までに設定してください。")
        XCTAssertEqual(NotificationScheduleCalculator.validationMessage(
            anchor: draft.date, hasTime: true, kind: .selectionDeadline,
            timedCustom: draft.notificationTimedCustom, dateCustom: nil, calendar: cal
        ), "通知時刻は選考の締切までに設定してください。")
        draft.notificationTimedCustom = .elapsed(45)
        XCTAssertNil(draft.notificationValidationMessage(calendar: cal))
        let result = try XCTUnwrap(fire(.elapsed(45), anchor: draft.date, calendar: cal))
        XCTAssertTrue(draft.notificationDescription(calendar: cal, now: result)!.contains("過ぎている"))
        draft.hasEnd = true
        draft.endDate = draft.date.addingTimeInterval(86_400)
        XCTAssertTrue(draft.notificationDescription(calendar: cal, now: result)!.contains("過ぎている"))
        var task = RecruitTaskDraft(dueDate: draft.date)
        task.dueHasTime = true
        task.notificationTimedCustom = .calendar(hour: 9)
        XCTAssertEqual(task.notificationValidationMessage(calendar: cal), "通知時刻はToDoの期限までに設定してください。")
        XCTAssertEqual(TaskNotificationDescription.text(enabled: true, isCompleted: false, dueAt: task.dueAt,
            hasTime: true, timedCustom: task.notificationTimedCustom, calendar: cal), "通知時刻はToDoの期限までに設定してください。")
    }

    func testPrecisionAndDisabledPreferencesStayIndependentAndDirtyStateRestores() {
        var task = RecruitTaskDraft()
        let initial = task
        task.notificationTimedCustom = .elapsed(7, unit: .hours)
        task.notificationDateCustom = .calendar(daysBefore: 2, hour: 20)
        task.notificationEnabled = false
        task.setDueHasTime(true)
        task.setDueHasTime(false)
        XCTAssertFalse(task.notificationEnabled)
        XCTAssertEqual(task.notificationTimedCustom, .elapsed(7, unit: .hours))
        XCTAssertEqual(task.notificationDateCustom, .calendar(daysBefore: 2, hour: 20))
        XCTAssertTrue(task.hasTaskEditorChanges(comparedTo: initial))
        task = initial
        XCTAssertFalse(task.hasTaskEditorChanges(comparedTo: initial))
        var step = SelectionStepDraft()
        let selectionInitial = step
        step.notificationDateCustom = .calendar(hour: 15)
        XCTAssertTrue(step.hasChanges(comparedTo: selectionInitial))
        step.notificationDateCustom = nil
        XCTAssertFalse(step.hasChanges(comparedTo: selectionInitial))
    }

    func testAllPayloadsPreserveCustomAndExplicitPresetAndUpdatesClearWithNull() throws {
        var task = RecruitTaskDraft()
        task.notificationTimedPreset = .thirtyMinutes
        task.notificationTimedCustom = .elapsed(17)
        task.notificationDateCustom = .calendar(daysBefore: 4, hour: 18, minute: 23)
        task.notificationEnabled = false
        var step = SelectionStepDraft()
        step.notificationTimedPreset = task.notificationTimedPreset
        step.notificationTimedCustom = task.notificationTimedCustom
        step.notificationDateCustom = task.notificationDateCustom
        step.notificationEnabled = false
        for object in [try json(RecruitTaskWrite(userID: UUID(), draft: task)), try json(RecruitTaskUpdate(draft: task)),
                       try json(SelectionStepWrite(userID: UUID(), companyID: UUID(), draft: step)), try json(SelectionStepUpdate(draft: step))] {
            XCTAssertEqual(object["notification_timed_preset"] as? String, "thirty_minutes")
            XCTAssertEqual(object["notification_enabled"] as? Bool, false)
            let timed = try XCTUnwrap(object["notification_timed_custom"] as? [String: Any])
            XCTAssertEqual(timed["value"] as? Int, 17)
            XCTAssertNil(timed["hour"])
            let day = try XCTUnwrap(object["notification_date_custom"] as? [String: Any])
            XCTAssertEqual(day["minute"] as? Int, 23)
            XCTAssertNil(day["unit"])
        }
        task.notificationTimedCustom = nil
        step.notificationDateCustom = nil
        XCTAssertTrue(try json(RecruitTaskUpdate(draft: task))["notification_timed_custom"] is NSNull)
        XCTAssertTrue(try json(SelectionStepUpdate(draft: step))["notification_date_custom"] is NSNull)
    }

    func testModelRoundTripAndMissingOrNullFieldsRemainCompatible() throws {
        let now = Date()
        var task = RecruitTask(id: UUID(), userID: UUID(), companyID: nil, title: "準備", memo: nil, dueAt: nil, dueHasTime: false, completedAt: nil,
                               notificationEnabled: false, createdAt: now, updatedAt: now)
        task.notificationDateCustom = .calendar(hour: 16, minute: 45)
        let restored = try JSONDecoder().decode(RecruitTask.self, from: JSONEncoder().encode(task))
        XCTAssertEqual(RecruitTaskDraft(task: restored).notificationDateCustom, task.notificationDateCustom)
        for explicitNull in [false, true] {
            var object = try json(task)
            object["notification_date_custom"] = explicitNull ? NSNull() : nil
            let decoded = try JSONDecoder().decode(RecruitTask.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertNil(decoded.notificationDateCustom)
            XCTAssertFalse(decoded.notificationEnabled)
        }
    }

    func testInvalidNumericTextCannotRetainPreviousValidValue() {
        for text in ["", "abc", "1.5", "-1", "99999999999999999999999999999999"] {
            XCTAssertNil(CustomNotificationTiming.parsedInput(text))
            var draft = RecruitTaskDraft()
            let initial = draft
            draft.notificationTimedCustom = .elapsed(CustomNotificationTiming.parsedInput(text) ?? -1)
            XCTAssertNotNil(draft.notificationValidationMessage())
            XCTAssertTrue(draft.hasTaskEditorChanges(comparedTo: initial))
            draft.notificationTimedCustom = .elapsed(CustomNotificationTiming.parsedInput("17")!)
            XCTAssertNil(draft.notificationValidationMessage())
            draft.notificationTimedCustom = initial.notificationTimedCustom
            XCTAssertFalse(draft.hasTaskEditorChanges(comparedTo: initial))
        }
        XCTAssertEqual(CustomNotificationTiming.parsedInput("0"), 0)
    }

    func testTerminalSelectionRetainsPreferenceWithoutAnchorValidation() {
        let cal = calendar()
        var draft = SelectionStepDraft(date: date(hour: 8, calendar: cal))
        draft.hasTime = true
        draft.notificationTimedCustom = .calendar(hour: 9)
        for status in [SelectionStepStatus.completed, .cancelled] {
            draft.status = status
            XCTAssertNil(draft.notificationValidationMessage(calendar: cal))
        }
        draft.status = .scheduled
        XCTAssertNotNil(draft.notificationValidationMessage(calendar: cal))
    }

    func testCustomPlansUseStartDeadlineAndDueExactlyOnceAndExcludePast() throws {
        let cal = calendar("Asia/Tokyo")
        let anchor = date(calendar: cal)
        let now = anchor.addingTimeInterval(-172_800)
        var step = SelectionStep(id: UUID(), userID: UUID(), companyID: UUID(), type: .interview,
            customTitle: nil, startsAt: anchor, startsHasTime: true, deadlineAt: nil,
            deadlineHasTime: false, status: .scheduled, memo: nil, notificationEnabled: true,
            createdAt: now, updatedAt: now)
        step.endsAt = anchor.addingTimeInterval(86_400)
        step.notificationTimedCustom = .elapsed(17)
        var plan = NotificationPlanBuilder.make(steps: [step], tasks: [], companyNames: [:], calendar: cal, now: now)
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan.first?.fireDate, anchor.addingTimeInterval(-1_020))
        XCTAssertTrue(plan.first!.identifier.hasPrefix("selection-start-"))
        step.startsAt = nil
        step.endsAt = nil
        step.deadlineAt = anchor
        step.deadlineHasTime = true
        step.notificationTimedCustom = .calendar(daysBefore: 1, hour: 18, minute: 23)
        let expected = try XCTUnwrap(fire(step.notificationTimedCustom!, anchor: anchor, calendar: cal))
        plan = NotificationPlanBuilder.make(steps: [step], tasks: [], companyNames: [:], calendar: cal, now: now)
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan.first?.fireDate, expected)
        XCTAssertTrue(plan.first!.identifier.hasPrefix("selection-deadline-"))
        var task = RecruitTask(id: UUID(), userID: UUID(), companyID: nil, title: "Custom", memo: nil,
            dueAt: anchor, dueHasTime: true, completedAt: nil, notificationEnabled: true, createdAt: now, updatedAt: now)
        task.notificationTimedCustom = .elapsed(7, unit: .hours)
        plan = NotificationPlanBuilder.make(steps: [], tasks: [task], companyNames: [:], calendar: cal, now: now)
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan.first?.fireDate, anchor.addingTimeInterval(-25_200))
        XCTAssertTrue(NotificationPlanBuilder.make(steps: [step], tasks: [task], companyNames: [:], calendar: cal, now: anchor).isEmpty)
        task.dueHasTime = false
        task.notificationDateCustom = .calendar(hour: 21, minute: 37)
        plan = NotificationPlanBuilder.make(steps: [], tasks: [task], companyNames: [:], calendar: cal, now: now)
        XCTAssertEqual(cal.component(.hour, from: try XCTUnwrap(plan.first?.fireDate)), 21)
    }

    func testCompletedTaskSkipsOnlyAnchorValidationAndRestoreDoesNotScheduleInvalidTime() {
        let cal = calendar("Asia/Tokyo")
        let due = date(hour: 8, calendar: cal)
        let now = due.addingTimeInterval(-86_400)
        var task = RecruitTask(id: UUID(), userID: UUID(), companyID: nil, title: "Done", memo: nil,
            dueAt: due, dueHasTime: true, completedAt: now, notificationEnabled: true, createdAt: now, updatedAt: now)
        task.notificationTimedCustom = .calendar(hour: 9)
        var draft = RecruitTaskDraft(task: task)
        XCTAssertNil(draft.notificationValidationMessage(isCompleted: true, calendar: cal))
        XCTAssertNotNil(draft.notificationValidationMessage(isCompleted: false, calendar: cal))
        XCTAssertNotNil(draft.notificationValidationMessage(calendar: cal))
        XCTAssertTrue(NotificationPlanBuilder.make(steps: [], tasks: [task], companyNames: [:], calendar: cal, now: now).isEmpty)
        task.completedAt = nil
        XCTAssertTrue(NotificationPlanBuilder.make(steps: [], tasks: [task], companyNames: [:], calendar: cal, now: now).isEmpty)
        draft.notificationDateCustom = .calendar(daysBefore: 1_401)
        XCTAssertNotNil(draft.notificationValidationMessage(isCompleted: true, calendar: cal))
        draft.notificationDateCustom = nil
        draft.notificationTimedCustom = .elapsed(0)
        XCTAssertNotNil(draft.notificationValidationMessage(isCompleted: true, calendar: cal))
        draft.notificationEnabled = false
        XCTAssertNotNil(draft.notificationValidationMessage(isCompleted: true, calendar: cal))
    }

    private func json<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }
}
