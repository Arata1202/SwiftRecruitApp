import XCTest
@testable import SwiftRecruitApp

final class NotificationTimingPresetTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(_ day: Int = 11, hour: Int = 0, minute: Int = 5) -> Date {
        calendar.date(from: DateComponents(year: 2030, month: 3, day: day, hour: hour, minute: minute))!
    }

    func testEveryTimedPresetUsesElapsedOffsetIncludingMidnightAndDST() throws {
        let expected: [(TimedNotificationPreset, TimeInterval)] = [
            (.atTime, 0), (.tenMinutes, 600), (.thirtyMinutes, 1_800),
            (.oneHour, 3_600), (.oneDay, 86_400), (.threeDays, 259_200),
        ]
        for kind in [NotificationAnchor.selectionStart, .selectionDeadline, .taskDue] {
            for (preset, seconds) in expected {
                let fire = try XCTUnwrap(NotificationScheduleCalculator.reminderDate(
                    anchor: date(), hasTime: true, kind: kind,
                    timedPreset: preset, datePreset: .sameDay, calendar: calendar
                ))
                XCTAssertEqual(date().timeIntervalSince(fire), seconds)
            }
        }
    }

    func testEveryDateOnlyPresetUsesLocalNineAcrossDSTAndMonthBoundary() throws {
        for anchor in [date(), date(1)] {
            for kind in [NotificationAnchor.selectionStart, .selectionDeadline, .taskDue] {
                for preset in DateNotificationPreset.allCases {
                    let fire = try XCTUnwrap(NotificationScheduleCalculator.reminderDate(
                        anchor: anchor, hasTime: false, kind: kind,
                        timedPreset: .threeDays, datePreset: preset, calendar: calendar
                    ))
                    let expectedDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -preset.daysBefore, to: anchor))
                    XCTAssertTrue(calendar.isDate(fire, inSameDayAs: expectedDay))
                    XCTAssertEqual(calendar.component(.hour, from: fire), 9)
                    XCTAssertEqual(calendar.component(.minute, from: fire), 0)
                }
            }
        }
    }

    func testUnspecifiedDeadlineUsesApprovedDefaultsForBothPrecisions() throws {
        for hasTime in [false, true] {
            let fire = try XCTUnwrap(NotificationScheduleCalculator.reminderDate(
                anchor: date(), hasTime: hasTime, kind: .selectionDeadline,
                timedPreset: nil, datePreset: nil, calendar: calendar
            ))
            if hasTime {
                XCTAssertEqual(date().timeIntervalSince(fire), 86_400)
            } else {
                XCTAssertEqual(calendar.component(.hour, from: fire), 9)
            }
        }
    }

    func testDateEditRecomputesAndNoDateNeverProducesReminder() throws {
        let before = try XCTUnwrap(NotificationScheduleCalculator.reminderDate(
            anchor: date(), hasTime: true, kind: .taskDue,
            timedPreset: .threeDays, datePreset: nil
        ))
        let after = try XCTUnwrap(NotificationScheduleCalculator.reminderDate(
            anchor: date().addingTimeInterval(600), hasTime: true, kind: .taskDue,
            timedPreset: .threeDays, datePreset: nil
        ))
        XCTAssertEqual(after.timeIntervalSince(before), 600)
        XCTAssertNil(NotificationScheduleCalculator.reminderDate(
            anchor: nil, hasTime: true, kind: .taskDue, timedPreset: .atTime, datePreset: .sameDay
        ))
    }

    func testPlanMatchesPreviewAndSuppressesPastDisabledCompletedUndated() throws {
        var task = makeTask()
        task.notificationTimedPreset = .tenMinutes
        let fire = task.dueAt!.addingTimeInterval(-600)
        func plan(_ now: Date) -> [NotificationPlanItem] {
            NotificationPlanBuilder.make(steps: [], tasks: [task], companyNames: [:], calendar: calendar, now: now)
        }
        XCTAssertEqual(plan(fire.addingTimeInterval(-1)).map(\.fireDate), [fire])
        for now in [fire, fire.addingTimeInterval(1)] {
            XCTAssertTrue(plan(now).isEmpty)
            XCTAssertTrue(TaskNotificationDescription.text(
                enabled: true, isCompleted: false, dueAt: task.dueAt, hasTime: true,
                timedPreset: task.notificationTimedPreset, calendar: calendar, now: now
            ).contains("過ぎている"))
        }
        let early = fire.addingTimeInterval(-100)
        task.notificationEnabled = false
        XCTAssertTrue(plan(early).isEmpty)
        XCTAssertEqual(task.notificationTimedPreset, .tenMinutes)
        task.notificationEnabled = true
        task.completedAt = early
        XCTAssertTrue(plan(early).isEmpty)
        task.completedAt = nil
        task.dueAt = nil
        XCTAssertTrue(plan(early).isEmpty)
    }

    func testSelectionPlanAnchorsToStartOrDeadlineAndPreservesStatusPreference() {
        for kind in SelectionDateKind.allCases {
            var step = makeStep()
            if kind == .deadline { step.deadlineAt = step.startsAt; step.startsAt = nil; step.deadlineHasTime = true }
            step.notificationTimedPreset = .threeDays
            let fire = date().addingTimeInterval(-259_200)
            let early = fire.addingTimeInterval(-1)
            XCTAssertEqual(NotificationPlanBuilder.make(steps: [step], tasks: [], companyNames: [:], now: early).map(\.fireDate), [fire])
            XCTAssertTrue(NotificationPlanBuilder.make(steps: [step], tasks: [], companyNames: [:], now: fire).isEmpty)
            for status in [SelectionStepStatus.completed, .cancelled] {
                step.status = status
                XCTAssertTrue(NotificationPlanBuilder.make(steps: [step], tasks: [], companyNames: [:], now: early).isEmpty)
                let draft = SelectionStepDraft(step: step)
                XCTAssertTrue(draft.notificationEnabled)
                XCTAssertEqual(SelectionStepUpdate(draft: draft).notificationTimedPreset, .threeDays)
            }
        }
    }

    func testPrecisionToggleRetainsChoicesAndUnsavedProtection() {
        var draft = SelectionStepDraft(step: makeStep())
        let initial = draft
        draft.notificationTimedPreset = .thirtyMinutes
        draft.notificationDatePreset = .previousDay
        draft.setHasTime(false, calendar: calendar)
        draft.setHasTime(true, calendar: calendar)
        XCTAssertEqual(draft.notificationTimedPreset, .thirtyMinutes)
        XCTAssertEqual(draft.notificationDatePreset, .previousDay)
        XCTAssertTrue(draft.hasChanges(comparedTo: initial))
        var task = RecruitTaskDraft(task: makeTask())
        let initialTask = task
        task.notificationDatePreset = .threeDays
        task.setDueHasTime(false, calendar: calendar)
        task.setDueHasTime(true, calendar: calendar)
        XCTAssertEqual(task.notificationDatePreset, .threeDays)
        XCTAssertTrue(task.hasTaskEditorChanges(comparedTo: initialTask))
    }

    func testPayloadsAndCodableRoundTripPreferencesWithoutChangingDisabledFlag() throws {
        var task = makeTask()
        task.notificationEnabled = false
        task.notificationTimedPreset = .threeDays
        task.notificationDatePreset = .previousDay
        let restored = try JSONDecoder().decode(RecruitTask.self, from: JSONEncoder().encode(task))
        let draft = RecruitTaskDraft(task: restored)
        for object in [try json(RecruitTaskWrite(userID: task.userID, draft: draft)), try json(RecruitTaskUpdate(draft: draft))] {
            XCTAssertEqual(object["notification_timed_preset"] as? String, "three_days")
            XCTAssertEqual(object["notification_date_preset"] as? String, "previous_day")
            XCTAssertEqual(object["notification_enabled"] as? Bool, false)
        }
        var step = makeStep()
        step.notificationEnabled = false
        step.notificationTimedPreset = .tenMinutes
        step.notificationDatePreset = .threeDays
        let decoded = try JSONDecoder().decode(SelectionStep.self, from: JSONEncoder().encode(step))
        let selection = SelectionStepDraft(step: decoded)
        for object in [try json(SelectionStepWrite(userID: step.userID, companyID: step.companyID, draft: selection)), try json(SelectionStepUpdate(draft: selection))] {
            XCTAssertEqual(object["notification_timed_preset"] as? String, "ten_minutes")
            XCTAssertEqual(object["notification_date_preset"] as? String, "three_days")
            XCTAssertEqual(object["notification_enabled"] as? Bool, false)
        }
    }

    func testMissingLegacyFieldsDecodeToNilAndNormalizeInDrafts() throws {
        let task = try JSONDecoder().decode(RecruitTask.self, from: JSONEncoder().encode(makeTask()))
        let step = try JSONDecoder().decode(SelectionStep.self, from: JSONEncoder().encode(makeStep()))
        XCTAssertNil(task.notificationTimedPreset)
        XCTAssertEqual(RecruitTaskDraft(task: task).notificationDatePreset, .sameDay)
        XCTAssertNil(step.notificationDatePreset)
        XCTAssertEqual(SelectionStepDraft(step: step).notificationTimedPreset, .oneHour)
    }

    func testNewDefaultsUseVisibleMenuPresets() {
        XCTAssertEqual(SelectionStepDraft().resolvedNotificationTimedPreset, .oneHour)
        XCTAssertEqual(SelectionStepDraft().resolvedNotificationDatePreset, .previousDay)
        XCTAssertEqual(RecruitTaskDraft().notificationTimedPreset, .oneHour)
        XCTAssertEqual(RecruitTaskDraft().notificationDatePreset, .previousDay)
    }

    func testEveryPresetPersistsThroughBothWriteAndUpdatePayloads() throws {
        for timed in TimedNotificationPreset.allCases {
            for day in DateNotificationPreset.allCases {
                var task = RecruitTaskDraft(task: makeTask())
                task.notificationTimedPreset = timed
                task.notificationDatePreset = day
                var step = SelectionStepDraft(step: makeStep())
                step.notificationTimedPreset = timed
                step.notificationDatePreset = day
                let objects = [
                    try json(RecruitTaskWrite(userID: UUID(), draft: task)),
                    try json(RecruitTaskUpdate(draft: task)),
                    try json(SelectionStepWrite(userID: UUID(), companyID: UUID(), draft: step)),
                    try json(SelectionStepUpdate(draft: step)),
                ]
                for object in objects {
                    XCTAssertEqual(object["notification_timed_preset"] as? String, timed.rawValue)
                    XCTAssertEqual(object["notification_date_preset"] as? String, day.rawValue)
                }
            }
        }
    }

    func testExplicitNullAndMissingLegacyPresetsPreserveBothDisabledStates() throws {
        for enabled in [true, false] {
            for explicitNull in [true, false] {
                var task = makeTask()
                task.notificationEnabled = enabled
                var step = makeStep()
                step.notificationEnabled = enabled
                var taskJSON = try json(task)
                var stepJSON = try json(step)
                for key in ["notification_timed_preset", "notification_date_preset"] {
                    taskJSON[key] = explicitNull ? NSNull() : nil
                    stepJSON[key] = explicitNull ? NSNull() : nil
                }
                let restoredTask = try JSONDecoder().decode(RecruitTask.self, from: JSONSerialization.data(withJSONObject: taskJSON))
                let restoredStep = try JSONDecoder().decode(SelectionStep.self, from: JSONSerialization.data(withJSONObject: stepJSON))
                XCTAssertEqual(restoredTask.notificationEnabled, enabled)
                XCTAssertEqual(restoredStep.notificationEnabled, enabled)
                XCTAssertNil(restoredTask.notificationTimedPreset)
                XCTAssertNil(restoredStep.notificationDatePreset)
                XCTAssertEqual(RecruitTaskUpdate(draft: RecruitTaskDraft(task: restoredTask)).notificationDatePreset, .sameDay)
                XCTAssertEqual(SelectionStepUpdate(draft: SelectionStepDraft(step: restoredStep)).notificationTimedPreset, .oneHour)
            }
        }
    }

    func testLocalDatePlanningUsesDeviceTimezoneNotCompatibilityTimestamp() throws {
        for zone in ["Asia/Tokyo", "UTC", "America/Los_Angeles"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
            var task = makeTask()
            task.dueOn = LocalDate(year: 2030, month: 1, day: 1)
            task.dueAt = task.dueOn?.compatibilityTimestamp
            task.dueHasTime = false
            task.notificationDatePreset = .threeDays
            let result = try XCTUnwrap(NotificationPlanBuilder.make(
                steps: [], tasks: [task], companyNames: [:], calendar: calendar,
                now: Date(timeIntervalSince1970: 0)
            ).first)
            let parts = calendar.dateComponents([.year, .month, .day, .hour], from: result.fireDate)
            XCTAssertEqual(parts.year, 2029)
            XCTAssertEqual(parts.month, 12)
            XCTAssertEqual(parts.day, 29)
            XCTAssertEqual(parts.hour, 9)
        }
    }

    func testReturningToOriginalPresetsClearsDirtyStateAndDisablingKeepsChoices() {
        var step = SelectionStepDraft(step: makeStep())
        let initial = step
        step.notificationTimedPreset = .threeDays
        step.notificationTimedPreset = initial.notificationTimedPreset
        XCTAssertFalse(step.hasChanges(comparedTo: initial))
        var task = RecruitTaskDraft(task: makeTask())
        task.notificationTimedPreset = .oneHour
        task.notificationDatePreset = .previousDay
        task.notificationEnabled = false
        task.setDueHasTime(false)
        XCTAssertFalse(task.notificationEnabled)
        XCTAssertEqual(task.notificationTimedPreset, .oneHour)
        XCTAssertEqual(task.notificationDatePreset, .previousDay)
    }

    private func json<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    private func makeTask() -> RecruitTask {
        RecruitTask(id: UUID(), userID: UUID(), companyID: nil, title: "準備", memo: nil,
                    dueAt: date(), dueHasTime: true, completedAt: nil, notificationEnabled: true,
                    createdAt: date(), updatedAt: date())
    }

    private func makeStep() -> SelectionStep {
        SelectionStep(id: UUID(), userID: UUID(), companyID: UUID(), type: .interview,
                      customTitle: nil, startsAt: date(), startsHasTime: true, deadlineAt: nil,
                      deadlineHasTime: false, status: .scheduled, memo: nil, notificationEnabled: true,
                      createdAt: date(), updatedAt: date())
    }
}
