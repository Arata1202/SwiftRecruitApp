import XCTest
@testable import SwiftRecruitApp

final class NotificationTimingChoiceTests: XCTestCase {
    func testNilMapsToConcreteExistingTimingWithoutChangingPreferences() {
        for hasTime in [true, false] {
            XCTAssertEqual(value(.selectionDeadline, hasTime), "previous_day_20")
            XCTAssertEqual(value(.selectionStart, hasTime), hasTime ? "one_hour" : "same_day")
            XCTAssertEqual(value(.taskDue, hasTime), hasTime ? "at_time" : "same_day")
        }
    }

    func testAtTimeLabelDescribesTheAnchor() {
        XCTAssertEqual(NotificationTimingChoice.title(for: .atTime, kind: .selectionStart), "開始時刻")
        XCTAssertEqual(NotificationTimingChoice.title(for: .atTime, kind: .selectionDeadline), "期限時刻")
        XCTAssertEqual(NotificationTimingChoice.title(for: .atTime, kind: .taskDue), "期限時刻")
    }

    func testLegacyDeadlineCanBeSelectedAgainAndPersistsExplicitNull() throws {
        for hasTime in [true, false] {
            var enabled = true
            var timed: TimedNotificationPreset? = nil
            var date: DateNotificationPreset? = nil
            let original = value(.selectionDeadline, hasTime)
            NotificationTimingChoice.select("three_days", hasTime: hasTime, kind: .selectionDeadline,
                                            enabled: &enabled, timed: &timed, date: &date)
            XCTAssertEqual(NotificationTimingChoice.value(enabled: enabled, hasTime: hasTime,
                            kind: .selectionDeadline, timed: timed, date: date), "three_days")
            NotificationTimingChoice.select(original, hasTime: hasTime, kind: .selectionDeadline,
                                            enabled: &enabled, timed: &timed, date: &date)
            XCTAssertNil(timed)
            XCTAssertNil(date)
            var draft = SelectionStepDraft()
            draft.dateKind = .deadline
            draft.hasTime = hasTime
            draft.notificationTimedPreset = timed
            draft.notificationDatePreset = date
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(
                SelectionStepUpdate(draft: draft))) as? [String: Any])
            XCTAssertTrue(object["notification_timed_preset"] is NSNull)
            XCTAssertTrue(object["notification_date_preset"] is NSNull)
        }
    }

    func testOrdinaryLegacyChoicesCanBeReselectedWithoutDuplicateLegacyOption() {
        for kind in [NotificationAnchor.selectionStart, .taskDue] {
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
        XCTAssertEqual(NotificationTimingChoice.value(enabled: enabled, hasTime: false,
                        kind: .selectionDeadline, timed: timed, date: date), "none")
        NotificationTimingChoice.select("previous_day_20", hasTime: false, kind: .selectionDeadline,
                                        enabled: &enabled, timed: &timed, date: &date)
        XCTAssertTrue(enabled)
        XCTAssertNil(date)
        XCTAssertEqual(timed, .tenMinutes)
        XCTAssertEqual(NotificationTimingChoice.value(enabled: enabled, hasTime: true,
                        kind: .selectionDeadline, timed: timed, date: date), "ten_minutes")
    }

    func testPreviousDayTwentyIsNotTwentyFourHoursBefore() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2030, month: 1, day: 3, hour: 12)))
        let legacy = try XCTUnwrap(NotificationScheduleCalculator.reminderDate(
            anchor: anchor, hasTime: true, kind: .selectionDeadline,
            timedPreset: nil, datePreset: nil, calendar: calendar))
        let day = try XCTUnwrap(NotificationScheduleCalculator.reminderDate(
            anchor: anchor, hasTime: true, kind: .selectionDeadline,
            timedPreset: .oneDay, datePreset: nil, calendar: calendar))
        XCTAssertEqual(calendar.component(.day, from: legacy), 2)
        XCTAssertEqual(calendar.component(.hour, from: legacy), 20)
        XCTAssertEqual(calendar.component(.hour, from: day), 12)
        XCTAssertNotEqual(legacy, day)
    }

    func testLegacyReselectionOnlyClearsActivePrecisionInBothDirections() {
        for hasTime in [true, false] {
            var enabled = true
            var timed: TimedNotificationPreset? = .oneHour
            var date: DateNotificationPreset? = .threeDays
            NotificationTimingChoice.select("previous_day_20", hasTime: hasTime, kind: .selectionDeadline,
                                            enabled: &enabled, timed: &timed, date: &date)
            XCTAssertEqual(timed, hasTime ? nil : .oneHour)
            XCTAssertEqual(date, hasTime ? .threeDays : nil)
        }
    }

    func testTaskUpdateExplicitlyPreservesNullLegacyPreferences() throws {
        var draft = RecruitTaskDraft()
        draft.notificationTimedPreset = nil
        draft.notificationDatePreset = nil
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(
            RecruitTaskUpdate(draft: draft))) as? [String: Any])
        XCTAssertTrue(object["notification_timed_preset"] is NSNull)
        XCTAssertTrue(object["notification_date_preset"] is NSNull)
    }

    private func value(_ kind: NotificationAnchor, _ hasTime: Bool) -> String {
        NotificationTimingChoice.value(enabled: true, hasTime: hasTime, kind: kind, timed: nil, date: nil)
    }
}
