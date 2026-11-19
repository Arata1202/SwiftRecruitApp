import XCTest
@testable import SwiftRecruitApp

final class NotificationTimingPresentationTests: XCTestCase {
    func testOpeningAndReadingSelectionsNeverChangesDraft() {
        var draft = SelectionStepDraft()
        draft.notificationTimedCustom = .elapsed(45)
        draft.notificationDateCustom = .calendar(daysBefore: 1, hour: 18)
        let initial = draft
        for kind in [NotificationAnchor.selectionStart, .selectionDeadline, .taskDue] {
            for hasTime in [true, false] {
                let custom = hasTime ? draft.notificationTimedCustom : draft.notificationDateCustom
                XCTAssertEqual(NotificationTimingPresentation.selection(enabled: true, hasTime: hasTime, kind: kind,
                    timed: draft.notificationTimedPreset, date: draft.notificationDatePreset, custom: custom), "custom")
                XCTAssertFalse(NotificationTimingPresentation.customTitle(custom).isEmpty)
            }
        }
        XCTAssertFalse(draft.hasChanges(comparedTo: initial))
    }

    func testReloadedArbitraryInputStaysVisibleWhileTyping() {
        for hasTime in [true, false] {
            var presentation = NotificationTimingPresentation()
            var custom = CustomNotificationTiming.calendar(daysBefore: 12, hour: 18)
            for text in ["", "1", "15", "0"] {
                presentation.editNumber(text, custom: &custom, hasTime: hasTime)
                XCTAssertEqual(presentation.dayChoice(custom, hasTime: hasTime), .arbitrary)
            }
        }
    }

    func testResetSynchronizesCrossModeAndArbitraryDaySelection() {
        for originalDays in [0, 1, 6] {
            var presentation = NotificationTimingPresentation()
            let initial = CustomNotificationTiming.calendar(daysBefore: originalDays, hour: 18)
            var custom = initial
            presentation.changeDay(.previousDay, custom: &custom, hasTime: true)
            presentation.changeMode(.elapsed, custom: &custom, hasTime: true)
            presentation.editNumber("", custom: &custom, hasTime: true)
            custom = initial
            presentation.reset(custom: custom, hasTime: true)
            XCTAssertEqual(presentation.dayChoice(custom, hasTime: true), originalDays == 0 ? .sameDay : originalDays == 1 ? .previousDay : .arbitrary)
            presentation.changeDay(.arbitrary, custom: &custom, hasTime: true)
            presentation.editNumber("", custom: &custom, hasTime: true)
            custom = initial
            presentation.reset(custom: custom, hasTime: true)
            XCTAssertEqual(presentation.dayChoice(custom, hasTime: true), originalDays == 0 ? .sameDay : originalDays == 1 ? .previousDay : .arbitrary)
        }
    }

    func testContextLabelsAndStableCustomTitle() {
        XCTAssertEqual(NotificationTimingPresentation.elapsedInputTitle(kind: .selectionStart, unit: .minutes), "開始の何分前")
        for kind in [NotificationAnchor.selectionDeadline, .taskDue] {
            XCTAssertEqual(NotificationTimingPresentation.elapsedInputTitle(kind: kind, unit: .hours), "期限の何時間前")
        }
        XCTAssertEqual(NotificationTimingPresentation.elapsedTitle(kind: .selectionStart), "開始の前")
        for kind in [NotificationAnchor.selectionDeadline, .taskDue] {
            XCTAssertEqual(NotificationTimingPresentation.elapsedTitle(kind: kind), "期限の前")
        }
        XCTAssertEqual(NotificationTimingPresentation.customTitle(.calendar(daysBefore: 1, hour: 18)), "カスタム")
        XCTAssertEqual(NotificationTimingPresentation.customTitle(.elapsed(45)), "カスタム")
        XCTAssertEqual(NotificationTimingPresentation.customTitle(.elapsed(7, unit: .hours)), "カスタム")
        XCTAssertEqual(NotificationTimingPresentation.customTitle(nil), "カスタム")
        XCTAssertEqual(NotificationTimingPresentation.customTitle(.elapsed(-1)), "カスタム")
    }

    func testDayChoicesRestoreArbitraryDaysAndKeepClockForEachPrecision() {
        var presentation = NotificationTimingPresentation()
        for hasTime in [true, false] {
            var custom = CustomNotificationTiming.calendar(daysBefore: hasTime ? 12 : 6, hour: 18, minute: 37)
            let original = custom
            presentation.changeDay(.sameDay, custom: &custom, hasTime: hasTime)
            XCTAssertEqual(presentation.dayChoice(custom, hasTime: hasTime), .sameDay)
            XCTAssertEqual(custom.value, 0)
            presentation.changeDay(.previousDay, custom: &custom, hasTime: hasTime)
            XCTAssertEqual(presentation.dayChoice(custom, hasTime: hasTime), .previousDay)
            XCTAssertEqual(custom.value, 1)
            XCTAssertEqual(custom.hour, 18)
            XCTAssertEqual(custom.minute, 37)
            presentation.changeDay(.arbitrary, custom: &custom, hasTime: hasTime)
            XCTAssertEqual(custom, original)
        }
    }

    func testArbitraryInputDoesNotDisappearWhileTypingZeroOrOne() {
        var presentation = NotificationTimingPresentation()
        var custom = CustomNotificationTiming.calendar()
        presentation.changeDay(.arbitrary, custom: &custom, hasTime: false)
        for value in [1, 12, 0] {
            custom.value = value
            XCTAssertEqual(presentation.dayChoice(custom, hasTime: false), .arbitrary)
        }
        presentation.changeDay(.previousDay, custom: &custom, hasTime: false)
        presentation.changeDay(.arbitrary, custom: &custom, hasTime: false)
        XCTAssertEqual(custom.value, 0)
        XCTAssertEqual(presentation.dayChoice(custom, hasTime: false), .arbitrary)
    }

    func testMethodSwitchRestoresElapsedHoursAndCalendarClock() {
        var presentation = NotificationTimingPresentation()
        var custom = CustomNotificationTiming.elapsed(7, unit: .hours)
        presentation.changeMode(.calendar, custom: &custom, hasTime: true)
        custom = .calendar(daysBefore: 9, hour: 20, minute: 15)
        presentation.changeMode(.elapsed, custom: &custom, hasTime: true)
        XCTAssertEqual(custom, .elapsed(7, unit: .hours))
        presentation.changeMode(.calendar, custom: &custom, hasTime: true)
        XCTAssertEqual(custom, .calendar(daysBefore: 9, hour: 20, minute: 15))
    }

    func testNonePrecisionAndAnchorSwitchesPreserveCustomValues() {
        var presentation = NotificationTimingPresentation()
        var enabled = true
        var timed: TimedNotificationPreset? = .tenMinutes
        var date: DateNotificationPreset? = .previousDay
        var timedCustom: CustomNotificationTiming? = .elapsed(7, unit: .hours)
        var dateCustom: CustomNotificationTiming? = .calendar(daysBefore: 12, hour: 18, minute: 37)
        for kind in [NotificationAnchor.selectionStart, .selectionDeadline, .taskDue] {
            presentation.select("none", hasTime: true, kind: kind, enabled: &enabled,
                                timedPreset: &timed, datePreset: &date, custom: &timedCustom)
            XCTAssertFalse(enabled)
            XCTAssertEqual(NotificationTimingPresentation.selection(enabled: enabled, hasTime: false, kind: kind,
                timed: timed, date: date, custom: dateCustom), "none")
            presentation.select("custom", hasTime: false, kind: kind, enabled: &enabled,
                                timedPreset: &timed, datePreset: &date, custom: &dateCustom)
            presentation.select("custom", hasTime: true, kind: kind, enabled: &enabled,
                                timedPreset: &timed, datePreset: &date, custom: &timedCustom)
            XCTAssertTrue(enabled)
            XCTAssertEqual(timedCustom, .elapsed(7, unit: .hours))
            XCTAssertEqual(dateCustom, .calendar(daysBefore: 12, hour: 18, minute: 37))
            XCTAssertEqual(timed, .tenMinutes)
            XCTAssertEqual(date, .previousDay)
        }
    }

    func testEveryPresetCompletesSelectionWithoutCustomDetails() {
        var presentation = NotificationTimingPresentation()
        var enabled = false
        var timed: TimedNotificationPreset?
        var date: DateNotificationPreset?
        for hasTime in [true, false] {
            let values = hasTime ? TimedNotificationPreset.allCases.map(\.rawValue) : DateNotificationPreset.allCases.map(\.rawValue)
            for value in values {
                var custom: CustomNotificationTiming? = .calendar(daysBefore: 1, hour: 18)
                presentation.select(value, hasTime: hasTime, kind: .selectionStart, enabled: &enabled,
                                    timedPreset: &timed, datePreset: &date, custom: &custom)
                XCTAssertTrue(enabled)
                XCTAssertNil(custom)
                XCTAssertEqual(NotificationTimingPresentation.selection(enabled: enabled, hasTime: hasTime,
                    kind: .selectionStart, timed: timed, date: date, custom: custom), value)
                presentation.select("custom", hasTime: hasTime, kind: .selectionStart, enabled: &enabled,
                                    timedPreset: &timed, datePreset: &date, custom: &custom)
                XCTAssertEqual(custom, .calendar(daysBefore: 1, hour: 18))
            }
        }
    }

    func testInvalidInputKeepsActionableBoundsOnlyWhenNeeded() {
        XCTAssertNil(NotificationTimingPresentation.inputMessage(.elapsed(45), hasTime: true))
        XCTAssertNil(NotificationTimingPresentation.inputMessage(.calendar(daysBefore: 1, hour: 18), hasTime: false))
        XCTAssertTrue(NotificationTimingPresentation.inputMessage(.elapsed(33_601, unit: .hours), hasTime: true)!.contains("33,600"))
        XCTAssertTrue(NotificationTimingPresentation.inputMessage(.calendar(daysBefore: 1_401), hasTime: false)!.contains("1,400"))
        var presentation = NotificationTimingPresentation()
        var custom = CustomNotificationTiming.calendar(daysBefore: -1, hour: 18)
        presentation.changeDay(.sameDay, custom: &custom, hasTime: false)
        presentation.changeDay(.arbitrary, custom: &custom, hasTime: false)
        XCTAssertEqual(custom.value, -1)
        XCTAssertNotNil(NotificationTimingPresentation.inputMessage(custom, hasTime: false))
    }

    func testPresentationSelectionSurvivesSaveReloadWithoutChangingPayload() throws {
        var presentation = NotificationTimingPresentation()
        var draft = RecruitTaskDraft()
        draft.notificationTimedCustom = .elapsed(7, unit: .hours)
        draft.notificationDateCustom = .calendar(daysBefore: 6, hour: 18, minute: 37)
        var custom = draft.notificationDateCustom
        presentation.select("none", hasTime: false, kind: .taskDue, enabled: &draft.notificationEnabled,
            timedPreset: &draft.notificationTimedPreset, datePreset: &draft.notificationDatePreset, custom: &custom)
        draft.notificationDateCustom = custom
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(RecruitTaskWrite(userID: UUID(), draft: draft))) as? [String: Any])
        XCTAssertEqual(payload["notification_enabled"] as? Bool, false)
        let savedCustom = try XCTUnwrap(payload["notification_date_custom"])
        let restoredCustom = try JSONDecoder().decode(CustomNotificationTiming.self, from: JSONSerialization.data(withJSONObject: savedCustom))
        XCTAssertEqual(restoredCustom, custom)
        let now = Date()
        var task = RecruitTask(id: UUID(), userID: UUID(), companyID: nil, title: "準備", memo: nil,
            dueAt: nil, dueHasTime: false, completedAt: nil, notificationEnabled: false, createdAt: now, updatedAt: now)
        task.notificationTimedCustom = draft.notificationTimedCustom
        task.notificationDateCustom = restoredCustom
        let restored = try JSONDecoder().decode(RecruitTask.self, from: JSONEncoder().encode(task))
        var reopened = RecruitTaskDraft(task: restored)
        var newPresentation = NotificationTimingPresentation()
        var reopenedCustom = reopened.notificationDateCustom
        newPresentation.select("custom", hasTime: false, kind: .taskDue, enabled: &reopened.notificationEnabled,
            timedPreset: &reopened.notificationTimedPreset, datePreset: &reopened.notificationDatePreset, custom: &reopenedCustom)
        XCTAssertTrue(reopened.notificationEnabled)
        XCTAssertEqual(reopenedCustom, .calendar(daysBefore: 6, hour: 18, minute: 37))
        XCTAssertEqual(reopened.notificationTimedCustom, .elapsed(7, unit: .hours))
    }
}
