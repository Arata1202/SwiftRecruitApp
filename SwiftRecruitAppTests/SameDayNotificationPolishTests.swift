import XCTest
@testable import SwiftRecruitApp

final class SameDayNotificationPolishTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return value
    }
    private func day(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2030, month: 6, day: 10, hour: hour, minute: minute))!
    }
    private func fire(_ custom: CustomNotificationTiming, hasTime: Bool) -> Date? {
        NotificationScheduleCalculator.reminderDate(anchor: day(hasTime ? 15 : 0), hasTime: hasTime,
            kind: .selectionStart, timedPreset: .atTime, datePreset: .previousDay,
            timedCustom: custom, dateCustom: custom, calendar: calendar)
    }
    private func detail(_ custom: CustomNotificationTiming? = nil, hasTime: Bool = true,
                        enabled: Bool = true, kind: NotificationAnchor = .selectionStart,
                        timed: TimedNotificationPreset? = .atTime) -> NotificationTimingDetailPresentation {
        NotificationTimingDetailPresentation(enabled: enabled, hasTime: hasTime, kind: kind,
            anchor: day(15), timed: timed, date: .sameDay, timedCustom: custom,
            dateCustom: custom, calendar: calendar)
    }

    func testNormalSameDayOptionPersistsExistingCalendarFormatAndReloads() throws {
        for hasTime in [true, false] {
            let option = try XCTUnwrap(ReminderMenuOption.options(hasTime: hasTime).first)
            XCTAssertEqual(option.title, "当日")
            var selection = AbsoluteNotificationSelection()
            var enabled = false
            var absolute: Date? = day(12)
            var timed: TimedNotificationPreset? = .atTime
            var date: DateNotificationPreset? = .previousDay
            var timedCustom: CustomNotificationTiming? = .relative(1, unit: .days).withNotificationClock(hour: 8, minute: 25)
            var dateCustom: CustomNotificationTiming? = .calendar(daysBefore: 2, hour: 7, minute: 35)
            let inactive = hasTime ? dateCustom : timedCustom
            selection.selectReminder(option.timing, hasTime: hasTime, kind: .selectionStart,
                enabled: &enabled, absoluteAt: &absolute, timedPreset: &timed, datePreset: &date,
                timedCustom: &timedCustom, dateCustom: &dateCustom)
            XCTAssertTrue(enabled)
            XCTAssertNil(absolute)
            XCTAssertEqual(hasTime ? dateCustom : timedCustom, inactive)
            let stored = try XCTUnwrap(hasTime ? timedCustom : dateCustom)
            XCTAssertEqual(stored.mode, .calendar)
            XCTAssertEqual(stored.value, 0)
            XCTAssertEqual(stored.hour, hasTime ? 8 : 7)
            XCTAssertEqual(stored.minute, hasTime ? 25 : 35)
            let decoded = try JSONDecoder().decode(CustomNotificationTiming.self, from: JSONEncoder().encode(stored))
            let reopened = RelativeNotificationTiming(custom: hasTime ? decoded : decoded.standardClockRepresentation, hasTime: hasTime)
            XCTAssertEqual(reopened, option.timing)
            XCTAssertEqual(detail(decoded, hasTime: hasTime).timing, "当日")
        }
    }

    func testSameDayClockIsDistinctFromAtTimeAndRetainsAnchorAndPastRules() throws {
        let timing = RelativeNotificationTiming(value: 0, unit: .days)
        let custom = try XCTUnwrap(timing.clockCustom(hour: 9, minute: 20))
        XCTAssertEqual(fire(custom, hasTime: true), day(9, 20))
        XCTAssertEqual(detail(custom).clock, "9:20")
        XCTAssertEqual(detail().timing, "開始時刻")
        XCTAssertEqual(detail(kind: .selectionDeadline).timing, "期限時刻")
        XCTAssertNil(detail().clock)
        XCTAssertNil(fire(.calendar(hour: 16), hasTime: true))
        XCTAssertEqual(fire(.calendar(hour: 15), hasTime: true), day(15))
        XCTAssertEqual(fire(.calendar(hour: 23, minute: 59), hasTime: false), day(23, 59))
        XCTAssertTrue(NotificationScheduleCalculator.reminderDescription(fire(custom, hasTime: true), now: day(10), calendar: calendar).contains("過ぎている"))
        XCTAssertNotNil(NotificationScheduleCalculator.validationMessage(anchor: day(15), hasTime: true,
            kind: .selectionStart, timedCustom: .calendar(hour: 16), dateCustom: nil, calendar: calendar))
        XCTAssertNil(NotificationScheduleCalculator.validationMessage(anchor: day(0), hasTime: false,
            kind: .selectionDeadline, timedCustom: nil, dateCustom: .calendar(hour: 23), calendar: calendar))
    }

    func testClockAndNumericBoundsStillApply() {
        for hasTime in [true, false] {
            XCTAssertTrue(RelativeNotificationTiming(value: 0, unit: .days).isSelectable(hasTime: hasTime))
            for unit in [RelativeNotificationTiming.Unit.minutes, .hours, .weeks, .months] {
                XCTAssertFalse(RelativeNotificationTiming(value: 0, unit: unit).isSelectable(hasTime: hasTime))
            }
            XCTAssertFalse(RelativeNotificationTiming(value: 201, unit: .days).isSelectable(hasTime: hasTime))
            XCTAssertFalse(CustomNotificationTiming.calendar(hour: 24).isValid(hasTime: hasTime))
            XCTAssertFalse(CustomNotificationTiming.calendar(minute: 60).isValid(hasTime: hasTime))
        }
    }

    func testReadonlyTimingLabelsAndSeparateClocks() {
        XCTAssertEqual(detail(.relative(2, unit: .hours)).timing, "2時間前")
        XCTAssertNil(detail(.relative(2, unit: .hours)).clock)
        XCTAssertEqual(detail(.calendar(daysBefore: 2, hour: 8, minute: 5)).timing, "2日前")
        XCTAssertEqual(detail(.calendar(daysBefore: 2, hour: 8, minute: 5)).clock, "8:05")
        XCTAssertEqual(detail(.relative(1, unit: .months).withNotificationClock(hour: 7, minute: 30)).timing, "1か月前")
        XCTAssertEqual(detail(timed: .oneDay).clock, "15:00")
        XCTAssertEqual(detail(hasTime: false).timing, "当日")
        XCTAssertEqual(detail(hasTime: false).clock, "9:00")
        XCTAssertEqual(detail(.calendar(hour: 24)).timing, "この通知タイミングは使用できません。編集画面で選び直してください。")
        XCTAssertEqual(detail(.calendar(), enabled: false).timing, "なし")
        XCTAssertNil(detail(.calendar(), enabled: false).clock)
    }
}
