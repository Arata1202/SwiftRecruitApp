import XCTest
@testable import SwiftRecruitApp

final class NotificationTimingChoiceTests: XCTestCase {
    func testUnspecifiedChoicesUseContextDefaults() {
        for hasTime in [true, false] {
            XCTAssertEqual(value(.selectionDeadline, hasTime), hasTime ? "one_day" : "previous_day")
            XCTAssertEqual(value(.selectionStart, hasTime), hasTime ? "one_hour" : "same_day")
            XCTAssertEqual(value(.taskDue, hasTime), hasTime ? "at_time" : "same_day")
        }
    }

    func testAtTimeLabelsAndElapsedDayLabels() {
        XCTAssertEqual(NotificationTimingChoice.title(for: .atTime, kind: .selectionStart), "開始時刻")
        XCTAssertEqual(NotificationTimingChoice.title(for: .atTime, kind: .selectionDeadline), "期限時刻")
        XCTAssertEqual(NotificationTimingChoice.title(for: .atTime, kind: .taskDue), "期限時刻")
        XCTAssertEqual(TimedNotificationPreset.oneDay.title, "24時間前")
        XCTAssertEqual(TimedNotificationPreset.threeDays.title, "72時間前")
    }

    func testEveryContextCanReselectItsDefault() {
        for kind in [NotificationAnchor.selectionStart, .selectionDeadline, .taskDue] {
            for hasTime in [true, false] {
                var enabled = true
                var timed: TimedNotificationPreset? = nil
                var date: DateNotificationPreset? = nil
                let original = value(kind, hasTime)
                NotificationTimingChoice.select("three_days", hasTime: hasTime, kind: kind,
                                                enabled: &enabled, timed: &timed, date: &date)
                NotificationTimingChoice.select(original, hasTime: hasTime, kind: kind,
                                                enabled: &enabled, timed: &timed, date: &date)
                XCTAssertEqual(NotificationTimingChoice.value(enabled: enabled, hasTime: hasTime,
                                kind: kind, timed: timed, date: date), original)
            }
        }
    }

    func testNoneAndPrecisionChangesPreserveBothChoices() {
        var enabled = true
        var timed: TimedNotificationPreset? = .tenMinutes
        var date: DateNotificationPreset? = .previousDay
        NotificationTimingChoice.select("none", hasTime: true, kind: .selectionDeadline,
                                        enabled: &enabled, timed: &timed, date: &date)
        XCTAssertFalse(enabled)
        XCTAssertEqual(timed, .tenMinutes)
        XCTAssertEqual(date, .previousDay)
        NotificationTimingChoice.select("three_days", hasTime: false, kind: .selectionDeadline,
                                        enabled: &enabled, timed: &timed, date: &date)
        XCTAssertTrue(enabled)
        XCTAssertEqual(date, .threeDays)
        XCTAssertEqual(timed, .tenMinutes)
    }

    func testNewUnselectedDefaultsFollowDateKindButChosenValuesDoNot() {
        var draft = SelectionStepDraft()
        XCTAssertEqual(draft.resolvedNotificationTimedPreset, .oneHour)
        draft.dateKind = .deadline
        XCTAssertEqual(draft.resolvedNotificationTimedPreset, .oneDay)
        XCTAssertEqual(draft.resolvedNotificationDatePreset, .previousDay)
        draft.notificationTimedPreset = .tenMinutes
        draft.dateKind = .schedule
        XCTAssertEqual(draft.resolvedNotificationTimedPreset, .tenMinutes)
        XCTAssertEqual(draft.resolvedNotificationDatePreset, .sameDay)
        draft.notificationDatePreset = .threeDays
        draft.dateKind = .deadline
        XCTAssertEqual(draft.resolvedNotificationTimedPreset, .tenMinutes)
        XCTAssertEqual(draft.resolvedNotificationDatePreset, .threeDays)
    }

    func testExistingNilDeadlineIsNormalizedOnceAndStaysSelectedOnKindChange() {
        for enabled in [true, false] {
            let now = Date()
            let step = SelectionStep(id: UUID(), userID: UUID(), companyID: UUID(), type: .document,
                customTitle: nil, startsAt: nil, startsHasTime: false, deadlineAt: now,
                deadlineHasTime: true, status: .scheduled, memo: nil, notificationEnabled: enabled,
                createdAt: now, updatedAt: now)
            var draft = SelectionStepDraft(step: step)
            XCTAssertEqual(draft.notificationTimedPreset, .oneDay)
            XCTAssertEqual(draft.notificationDatePreset, .previousDay)
            draft.dateKind = .schedule
            XCTAssertEqual(draft.resolvedNotificationTimedPreset, .oneDay)
            XCTAssertEqual(draft.resolvedNotificationDatePreset, .previousDay)
            XCTAssertEqual(draft.notificationEnabled, enabled)
        }
    }

    func testNewDefaultsPersistAsConcreteChoicesForBothKinds() throws {
        for kind in SelectionDateKind.allCases {
            var draft = SelectionStepDraft()
            draft.dateKind = kind
            for object in [try json(SelectionStepWrite(userID: UUID(), companyID: UUID(), draft: draft)),
                           try json(SelectionStepUpdate(draft: draft))] {
                XCTAssertEqual(object["notification_timed_preset"] as? String, kind == .schedule ? "one_hour" : "one_day")
                XCTAssertEqual(object["notification_date_preset"] as? String, kind == .schedule ? "same_day" : "previous_day")
            }
        }
    }

    func testRemovedSpecialChoiceCannotChangePreferences() {
        var enabled = false
        var timed: TimedNotificationPreset? = .tenMinutes
        var date: DateNotificationPreset? = .threeDays
        NotificationTimingChoice.select("previous_day_20", hasTime: true, kind: .selectionDeadline,
                                        enabled: &enabled, timed: &timed, date: &date)
        XCTAssertFalse(enabled)
        XCTAssertEqual(timed, .tenMinutes)
        XCTAssertEqual(date, .threeDays)
    }

    private func value(_ kind: NotificationAnchor, _ hasTime: Bool) -> String {
        NotificationTimingChoice.value(enabled: true, hasTime: hasTime, kind: kind, timed: nil, date: nil)
    }

    private func json<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }
}
