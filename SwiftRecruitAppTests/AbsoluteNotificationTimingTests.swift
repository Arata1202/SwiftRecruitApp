import XCTest
@testable import SwiftRecruitApp

final class AbsoluteNotificationTimingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private func task() -> RecruitTask {
        RecruitTask(id: UUID(), userID: UUID(), companyID: nil, title: "準備", memo: nil,
                    dueAt: now.addingTimeInterval(86_400), dueHasTime: true, completedAt: nil,
                    notificationEnabled: true, createdAt: now, updatedAt: now)
    }
    private func step() -> SelectionStep {
        SelectionStep(id: UUID(), userID: UUID(), companyID: UUID(), type: .interview,
                      customTitle: nil, startsAt: now.addingTimeInterval(86_400), startsHasTime: true,
                      deadlineAt: nil, deadlineHasTime: false, status: .scheduled, memo: nil,
                      notificationEnabled: true, createdAt: now, updatedAt: now)
    }
    private func json<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }
    func testFixedInstantAcrossAnchorPrecisionKindAndTimezone() {
        let absolute = now.addingTimeInterval(3_600)
        for zone in ["Asia/Tokyo", "America/New_York", "UTC"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: zone)!
            for hasTime in [false, true] {
                for kind in [NotificationAnchor.selectionStart, .selectionDeadline, .taskDue] {
                    for anchor in [now, now.addingTimeInterval(172_800)] {
                        XCTAssertEqual(NotificationScheduleCalculator.reminderDate(anchor: anchor, hasTime: hasTime,
                            kind: kind, timedPreset: .oneDay, datePreset: .previousDay,
                            timedCustom: .elapsed(97), dateCustom: .calendar(hour: 21),
                            absoluteAt: absolute, calendar: calendar), absolute)
                    }
                }
            }
        }
    }
    func testPastBoundaryAndUnchangedExpiredDraft() {
        XCTAssertNotNil(AbsoluteNotificationTiming.validationMessage(now, original: nil, now: now))
        XCTAssertNil(AbsoluteNotificationTiming.validationMessage(now.addingTimeInterval(1), original: nil, now: now))
        var saved = task()
        saved.notificationAbsoluteAt = now.addingTimeInterval(-60)
        var draft = RecruitTaskDraft(task: saved)
        draft.memo = "changed"
        draft.dueAt = now.addingTimeInterval(600)
        XCTAssertNil(draft.notificationValidationMessage(now: now))
        draft.notificationAbsoluteAt = now.addingTimeInterval(-120)
        XCTAssertNotNil(draft.notificationValidationMessage(now: now))
        XCTAssertNil(draft.notificationValidationMessage(isCompleted: true, now: now))
        draft.notificationEnabled = false
        XCTAssertNil(draft.notificationValidationMessage(now: now))
        XCTAssertTrue(TaskNotificationDescription.text(enabled: true, isCompleted: false, dueAt: saved.dueAt,
            hasTime: true, absoluteAt: saved.notificationAbsoluteAt, now: now).contains("過ぎている"))
    }
    func testSelectionExpiredEditsAndTerminalStatuses() {
        var saved = step()
        saved.notificationAbsoluteAt = now.addingTimeInterval(-60)
        var draft = SelectionStepDraft(step: saved)
        draft.memo = "changed"
        XCTAssertNil(draft.notificationValidationMessage(now: now))
        draft.notificationAbsoluteAt = now.addingTimeInterval(-120)
        XCTAssertNotNil(draft.notificationValidationMessage(now: now))
        for status in [SelectionStepStatus.completed, .cancelled] {
            draft.status = status
            XCTAssertNil(draft.notificationValidationMessage(now: now))
        }
    }
    func testSinglePlanAndNoPastFallbackOrTerminalScheduling() {
        var saved = step()
        saved.deadlineAt = now.addingTimeInterval(172_800)
        saved.endsAt = now.addingTimeInterval(259_200)
        saved.notificationAbsoluteAt = now.addingTimeInterval(600)
        func plan(_ value: SelectionStep) -> [NotificationPlanItem] {
            NotificationPlanBuilder.make(steps: [value], tasks: [], companyNames: [:], now: now)
        }
        XCTAssertEqual(plan(saved).count, 1)
        XCTAssertEqual(plan(saved).first?.fireDate, saved.notificationAbsoluteAt)
        XCTAssertEqual(plan(saved).first?.identifier, NotificationPlanBuilder.selectionIdentifiers(saved.id)[0])
        saved.notificationAbsoluteAt = now
        XCTAssertTrue(plan(saved).isEmpty)
        saved.notificationAbsoluteAt = now.addingTimeInterval(600)
        for status in [SelectionStepStatus.completed, .cancelled] {
            saved.status = status
            XCTAssertTrue(plan(saved).isEmpty)
        }
        var todo = task()
        todo.notificationAbsoluteAt = now.addingTimeInterval(600)
        todo.completedAt = now
        XCTAssertTrue(NotificationPlanBuilder.make(steps: [], tasks: [todo], companyNames: [:], now: now).isEmpty)
        todo.completedAt = nil
        todo.dueAt = nil
        XCTAssertTrue(NotificationPlanBuilder.make(steps: [], tasks: [todo], companyNames: [:], now: now).isEmpty)
    }
    func testRoundTripLegacyPreservationAndExplicitNullClearing() throws {
        var saved = task()
        saved.notificationTimedCustom = .elapsed(97)
        saved.notificationDateCustom = .calendar(daysBefore: 17, hour: 23, minute: 41)
        saved.notificationAbsoluteAt = now.addingTimeInterval(600)
        let restored = try JSONDecoder().decode(RecruitTask.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(restored, saved)
        var draft = RecruitTaskDraft(task: restored)
        XCTAssertEqual(draft.notificationTimedCustom, saved.notificationTimedCustom)
        XCTAssertEqual(draft.notificationDateCustom, saved.notificationDateCustom)
        draft.dueAt = now
        draft.dueHasTime = false
        XCTAssertEqual(draft.notificationAbsoluteAt, saved.notificationAbsoluteAt)
        var selection = SelectionStepDraft()
        selection.notificationAbsoluteAt = saved.notificationAbsoluteAt
        for value in [try json(RecruitTaskWrite(userID: saved.userID, draft: draft)), try json(RecruitTaskUpdate(draft: draft)),
                      try json(SelectionStepWrite(userID: UUID(), companyID: UUID(), draft: selection)), try json(SelectionStepUpdate(draft: selection))] {
            XCTAssertNotNil(value["notification_absolute_at"] as? Double)
        }
        draft.notificationAbsoluteAt = nil
        selection.notificationAbsoluteAt = nil
        XCTAssertTrue(try json(RecruitTaskUpdate(draft: draft))["notification_absolute_at"] is NSNull)
        XCTAssertTrue(try json(SelectionStepUpdate(draft: selection))["notification_absolute_at"] is NSNull)
        for explicitNull in [false, true] {
            var value = try json(saved)
            value["notification_absolute_at"] = explicitNull ? NSNull() : nil
            XCTAssertNil(try JSONDecoder().decode(RecruitTask.self, from: JSONSerialization.data(withJSONObject: value)).notificationAbsoluteAt)
        }
    }
    func testDirtyRestoreAndLegacyNoConversion() {
        var saved = task()
        saved.notificationTimedCustom = .elapsed(97)
        var draft = RecruitTaskDraft(task: saved)
        let initial = draft
        XCTAssertNil(draft.notificationAbsoluteAt)
        XCTAssertFalse(draft.hasTaskEditorChanges(comparedTo: initial))
        draft.notificationAbsoluteAt = now.addingTimeInterval(600)
        XCTAssertTrue(draft.hasTaskEditorChanges(comparedTo: initial))
        draft.notificationAbsoluteAt = nil
        XCTAssertFalse(draft.hasTaskEditorChanges(comparedTo: initial))
        XCTAssertEqual(draft.notificationTimedCustom, .elapsed(97))
        var selection = SelectionStepDraft()
        let old = selection
        selection.notificationAbsoluteAt = now
        XCTAssertTrue(selection.hasChanges(comparedTo: old))
    }
    func testDateOnlySameDayClockHasNoMidnightCutoff() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let midnight = cal.startOfDay(for: now)
        let evening = midnight.addingTimeInterval(21 * 3_600)
        XCTAssertNil(AbsoluteNotificationTiming.anchorWarning(evening, anchor: midnight, hasTime: false, kind: .taskDue, calendar: cal))
        XCTAssertNotNil(AbsoluteNotificationTiming.anchorWarning(evening, anchor: midnight, hasTime: true, kind: .taskDue, calendar: cal))
        XCTAssertNotNil(AbsoluteNotificationTiming.anchorWarning(evening.addingTimeInterval(86_400), anchor: midnight, hasTime: false, kind: .taskDue, calendar: cal))
    }
    func testInitialValueFutureMinuteAndDSTFoldInstantPreserved() {
        XCTAssertGreaterThan(AbsoluteNotificationTiming.initialDate(computed: now, now: now), now)
        let future = AbsoluteNotificationTiming.minute(now.addingTimeInterval(600))
        XCTAssertEqual(AbsoluteNotificationTiming.initialDate(computed: future, now: now), future)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let first = ISO8601DateFormatter().date(from: "2030-11-03T05:30:35Z")!
        let second = first.addingTimeInterval(3_600)
        XCTAssertEqual(AbsoluteNotificationTiming.minute(second, calendar: cal).timeIntervalSince(AbsoluteNotificationTiming.minute(first, calendar: cal)), 3_600)
    }
    func testAbsoluteCapacityUsesCommonOrdering() {
        let tasks = (1...65).map { index in
            var value = task()
            value.notificationAbsoluteAt = now.addingTimeInterval(Double(index * 60))
            return value
        }
        let plan = NotificationPlanBuilder.assessment(steps: [], tasks: tasks, companyNames: [:], now: now)
        XCTAssertEqual(plan.admitted.count, 64)
        XCTAssertEqual(plan.overflow.count, 1)
        XCTAssertEqual(plan.overflow.first?.fireDate, tasks.last?.notificationAbsoluteAt)
    }
    func testMenuSwitchesRestoreLegacyAndAbsoluteWithoutLosingInactivePreset() {
        var state = AbsoluteNotificationSelection()
        var enabled = true
        var absolute: Date?
        var timed: TimedNotificationPreset? = .thirtyMinutes
        var date: DateNotificationPreset? = .previousDay
        var custom: CustomNotificationTiming? = .elapsed(97)
        var inactive: CustomNotificationTiming? = .calendar(daysBefore: 17, hour: 23, minute: 41)
        func select(_ value: String) {
            state.select(value, hasTime: true, kind: .taskDue, computed: now.addingTimeInterval(600),
                         enabled: &enabled, absoluteAt: &absolute, timedPreset: &timed, datePreset: &date,
                         timedCustom: &custom, dateCustom: &inactive, now: now)
        }
        select("absolute")
        let first = absolute
        XCTAssertNotNil(first)
        XCTAssertEqual(custom, .elapsed(97))
        select("none")
        XCTAssertFalse(enabled)
        XCTAssertEqual(absolute, first)
        select("custom")
        XCTAssertTrue(enabled)
        XCTAssertNil(absolute)
        XCTAssertEqual(custom, .elapsed(97))
        select("one_hour")
        XCTAssertNil(custom)
        XCTAssertEqual(timed, .oneHour)
        XCTAssertEqual(date, .previousDay)
        select("custom")
        XCTAssertEqual(custom, .elapsed(97))
        XCTAssertEqual(timed, .thirtyMinutes)
        select("absolute")
        XCTAssertEqual(absolute, first)
        select("at_time")
        XCTAssertNil(absolute)
        XCTAssertNil(custom)
    }

    func testFreshMenuCannotCreateLegacyAndInactiveMemoryIsSeparate() {
        var state = AbsoluteNotificationSelection()
        var enabled = false
        var absolute: Date?
        var timed: TimedNotificationPreset?
        var date: DateNotificationPreset?
        var custom: CustomNotificationTiming?
        var inactive: CustomNotificationTiming?
        state.select("custom", hasTime: false, kind: .taskDue, computed: nil,
                     enabled: &enabled, absoluteAt: &absolute, timedPreset: &timed, datePreset: &date,
                     timedCustom: &inactive, dateCustom: &custom, now: now)
        XCTAssertFalse(enabled)
        XCTAssertNil(custom)
        custom = .calendar(daysBefore: 17, hour: 23, minute: 41)
        state.select("same_day", hasTime: false, kind: .taskDue, computed: nil,
                     enabled: &enabled, absoluteAt: &absolute, timedPreset: &timed, datePreset: &date,
                     timedCustom: &inactive, dateCustom: &custom, now: now)
        XCTAssertNil(custom)
        XCTAssertNil(state.rememberedCustom(hasTime: true))
        XCTAssertEqual(state.rememberedCustom(hasTime: false), .calendar(daysBefore: 17, hour: 23, minute: 41))
    }

    func testSafeErrorMessageSurvivesRepositorySaveRace() {
        XCTAssertEqual(UserFacingError.message(for: NotificationTimingError.invalidAbsolute, fallback: "network"),
                       "これからの通知日時を指定してください。")
    }
    func testAbsolutePresetRoundTripRestoresWholeSnapshotAndDirtyState() {
        var saved = task()
        saved.notificationTimedPreset = .thirtyMinutes
        saved.notificationDatePreset = .previousDay
        saved.notificationTimedCustom = .elapsed(97)
        saved.notificationDateCustom = .calendar(daysBefore: 17, hour: 23, minute: 41)
        saved.notificationAbsoluteAt = now.addingTimeInterval(600)
        var draft = RecruitTaskDraft(task: saved)
        let initial = draft
        var state = AbsoluteNotificationSelection()
        for value in ["one_hour", "absolute"] {
            state.select(value, hasTime: true, kind: .taskDue, computed: nil,
                         enabled: &draft.notificationEnabled, absoluteAt: &draft.notificationAbsoluteAt,
                         timedPreset: &draft.notificationTimedPreset, datePreset: &draft.notificationDatePreset,
                         timedCustom: &draft.notificationTimedCustom, dateCustom: &draft.notificationDateCustom, now: now)
        }
        XCTAssertFalse(draft.hasTaskEditorChanges(comparedTo: initial))
        XCTAssertEqual(draft.notificationTimedCustom, .elapsed(97))
        XCTAssertEqual(draft.notificationDateCustom, saved.notificationDateCustom)
        XCTAssertEqual(draft.notificationTimedPreset, saved.notificationTimedPreset)
        XCTAssertEqual(draft.notificationAbsoluteAt, saved.notificationAbsoluteAt)
    }
}
