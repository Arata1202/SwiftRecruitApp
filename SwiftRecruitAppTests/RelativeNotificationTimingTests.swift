import XCTest
@testable import SwiftRecruitApp

final class RelativeNotificationTimingTests: XCTestCase {
    private struct Editor {
        var choices = AbsoluteNotificationSelection()
        var enabled = true
        var absolute: Date?
        var timedPreset: TimedNotificationPreset? = .oneHour
        var datePreset: DateNotificationPreset? = .sameDay
        var timed: CustomNotificationTiming?
        var date: CustomNotificationTiming?
        mutating func select(_ value: String, hasTime: Bool = true) {
            choices.select(value, hasTime: hasTime, kind: .selectionStart, computed: nil,
                           enabled: &enabled, absoluteAt: &absolute, timedPreset: &timedPreset,
                           datePreset: &datePreset, timedCustom: &timed, dateCustom: &date)
        }
        mutating func relative(_ value: RelativeNotificationTiming, hasTime: Bool = true) {
            choices.selectRelative(value, hasTime: hasTime, kind: .selectionStart,
                                   enabled: &enabled, absoluteAt: &absolute, timedPreset: &timedPreset,
                                   datePreset: &datePreset, timedCustom: &timed, dateCustom: &date)
        }
    }
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }
    private func fire(_ custom: CustomNotificationTiming, timed: Bool, anchor: Date, calendar: Calendar) -> Date? {
        NotificationScheduleCalculator.reminderDate(anchor: anchor, hasTime: timed, kind: .taskDue,
            timedPreset: nil, datePreset: nil, timedCustom: timed ? custom : nil,
            dateCustom: timed ? nil : custom, calendar: calendar)
    }

    func testAllowedUnitsAndNewWireShapes() {
        XCTAssertEqual(RelativeNotificationTiming.units(hasTime: true), [.minutes, .hours, .days, .weeks])
        XCTAssertEqual(RelativeNotificationTiming.units(hasTime: false), [.days, .weeks])
        for (value, unit, expected) in [(10, RelativeNotificationTiming.Unit.minutes, CustomNotificationTiming.elapsed(10)),
                                      (2, .hours, .elapsed(2, unit: .hours)),
                                      (2, .days, .elapsed(48, unit: .hours)),
                                      (1, .weeks, .elapsed(168, unit: .hours))] {
            XCTAssertEqual(RelativeNotificationTiming(value: value, unit: unit).custom(hasTime: true), expected)
        }
        XCTAssertEqual(RelativeNotificationTiming(value: 2, unit: .days).custom(hasTime: false), .calendar(daysBefore: 2))
        XCTAssertEqual(RelativeNotificationTiming(value: 1, unit: .weeks).custom(hasTime: false), .calendar(daysBefore: 7))
    }

    func testRangesAndUnitChangeDoNotClamp() {
        for timed in [true, false] {
            for unit in RelativeNotificationTiming.units(hasTime: timed) {
                var value = RelativeNotificationTiming(value: 1, unit: unit)
                value.value = value.maximum(hasTime: timed)
                XCTAssertNotNil(value.custom(hasTime: timed))
                value.value += 1
                XCTAssertNil(value.custom(hasTime: timed))
                XCTAssertTrue(value.wheelValues(hasTime: timed).contains(value.value))
            }
        }
        XCTAssertNotNil(RelativeNotificationTiming(value: 0, unit: .days).custom(hasTime: false))
        XCTAssertNil(RelativeNotificationTiming(value: 0, unit: .days).custom(hasTime: true))
        XCTAssertNil(RelativeNotificationTiming(value: 1, unit: .hours).custom(hasTime: false))
        XCTAssertNil(RelativeNotificationTiming(value: Int.max, unit: .weeks).custom(hasTime: true))
    }

    func testLegacyRepresentationAndReopeningAreLossless() throws {
        for original in [CustomNotificationTiming.elapsed(97), .elapsed(1_440), .elapsed(72, unit: .hours), .elapsed(8_760, unit: .hours)] {
            var editor = Editor()
            editor.timed = original
            let relative = try XCTUnwrap(RelativeNotificationTiming(custom: original, hasTime: true))
            editor.relative(relative)
            XCTAssertEqual(editor.timed, original)
            editor.select("ten_minutes")
            XCTAssertNil(editor.timed)
            editor.relative(relative)
            XCTAssertEqual(editor.timed, original)
            XCTAssertEqual(editor.timedPreset, .oneHour)
            let reloaded = try JSONDecoder().decode(CustomNotificationTiming.self, from: JSONEncoder().encode(try XCTUnwrap(editor.timed)))
            XCTAssertEqual(reloaded, original)
            XCTAssertEqual(RelativeNotificationTiming(custom: reloaded, hasTime: true), relative)
        }
    }

    func testNoneAndPrecisionSwitchPreserveBothPreferences() {
        var editor = Editor()
        editor.timed = .elapsed(97)
        editor.date = .calendar(daysBefore: 4, hour: 21, minute: 37)
        editor.select("none")
        XCTAssertFalse(editor.enabled)
        XCTAssertEqual(editor.timed, .elapsed(97))
        editor.relative(.init(value: 1, unit: .weeks), hasTime: false)
        XCTAssertEqual(editor.timed, .elapsed(97))
        XCTAssertEqual(editor.date, .calendar(daysBefore: 7))
        editor.select("custom", hasTime: false)
        XCTAssertEqual(editor.date, .calendar(daysBefore: 4, hour: 21, minute: 37))
        XCTAssertEqual(editor.timed, .elapsed(97))
    }

    func testCalendarCompatibilitySurvivesSeveralRelativeChoices() {
        for timed in [true, false] {
            var editor = Editor()
            let old = CustomNotificationTiming.calendar(daysBefore: 3, hour: 17, minute: 23)
            if timed { editor.timed = old } else { editor.date = old }
            editor.relative(.init(value: 2, unit: .days), hasTime: timed)
            editor.relative(.init(value: 1, unit: .weeks), hasTime: timed)
            XCTAssertEqual(editor.choices.rememberedCustom(hasTime: timed), old)
            editor.select("custom", hasTime: timed)
            XCTAssertEqual(timed ? editor.timed : editor.date, old)
        }
    }

    func testAbsoluteRestorePreservesBothInactiveCustomsAndPresets() {
        var editor = Editor()
        let timestamp = Date(timeIntervalSince1970: 1_900_000_000)
        editor.absolute = timestamp
        editor.timed = .elapsed(97)
        editor.date = .calendar(daysBefore: 2, hour: 20)
        editor.relative(.init(value: 2, unit: .days))
        XCTAssertNil(editor.absolute)
        XCTAssertTrue(editor.choices.hasRememberedAbsolute)
        editor.select("absolute")
        XCTAssertEqual(editor.absolute, timestamp)
        XCTAssertEqual(editor.timed, .elapsed(97))
        XCTAssertEqual(editor.date, .calendar(daysBefore: 2, hour: 20))
        XCTAssertEqual(editor.timedPreset, .oneHour)
        XCTAssertEqual(editor.datePreset, .sameDay)
    }

    func testLegacyPresetVisibilityAndRestore() {
        var editor = Editor()
        XCTAssertFalse(editor.choices.timedChoices(activeSelection: "one_hour").contains(.threeDays))
        XCTAssertFalse(editor.choices.dateChoices(activeSelection: "same_day").contains(.threeDays))
        editor.timedPreset = .threeDays
        editor.relative(.init(value: 2, unit: .days))
        XCTAssertTrue(editor.choices.timedChoices(activeSelection: "relative_2").contains(.threeDays))
        editor.select("three_days")
        XCTAssertNil(editor.timed)
        XCTAssertEqual(editor.timedPreset?.secondsBefore, 259_200)
        editor.datePreset = .threeDays
        editor.relative(.init(value: 1, unit: .weeks), hasTime: false)
        XCTAssertTrue(editor.choices.dateChoices(activeSelection: "relative_7").contains(.threeDays))
        editor.select("three_days", hasTime: false)
        XCTAssertEqual(editor.datePreset, .threeDays)
        XCTAssertNil(editor.date)
    }

    func testInactiveLegacyPresetDoesNotLeakIntoNormalMenu() {
        var editor = Editor()
        editor.timedPreset = .threeDays
        editor.timed = .elapsed(97)
        editor.select("none")
        XCTAssertFalse(editor.choices.timedChoices(activeSelection: "none").contains(.threeDays))
        editor.relative(.init(value: 2, unit: .days))
        XCTAssertFalse(editor.choices.timedChoices(activeSelection: "relative_2").contains(.threeDays))
    }

    func testInvalidCommitLeavesDraftAndCompatibilityUntouched() {
        var editor = Editor()
        editor.absolute = Date(timeIntervalSince1970: 100)
        editor.timed = .elapsed(97)
        editor.enabled = false
        editor.relative(.init(value: -1, unit: .weeks))
        XCTAssertEqual(editor.absolute, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(editor.timed, .elapsed(97))
        XCTAssertFalse(editor.enabled)
        XCTAssertFalse(editor.choices.hasRememberedAbsolute)
    }

    func testNewDaysAndWeeksKeepElapsedSemanticsAcrossDSTAndAnchorEdits() throws {
        for zone in ["America/New_York", "Asia/Tokyo", "Europe/Berlin"] {
            let cal = calendar(zone)
            for month in [3, 11] {
                let anchor = try XCTUnwrap(cal.date(from: DateComponents(year: 2030, month: month, day: 10, hour: 12)))
                for (number, unit, seconds) in [(2, RelativeNotificationTiming.Unit.days, 172_800.0), (1, .weeks, 604_800.0)] {
                    let custom = try XCTUnwrap(RelativeNotificationTiming(value: number, unit: unit).custom(hasTime: true))
                    let result = try XCTUnwrap(fire(custom, timed: true, anchor: anchor, calendar: cal))
                    XCTAssertEqual(anchor.timeIntervalSince(result), seconds)
                    let moved = anchor.addingTimeInterval(3_600)
                    XCTAssertEqual(try XCTUnwrap(fire(custom, timed: true, anchor: moved, calendar: cal)).timeIntervalSince(result), 3_600)
                }
            }
        }
    }

    func testDateOnlyCalendarDaysKeepNineAcrossDSTAndTimezone() throws {
        for zone in ["America/New_York", "Asia/Tokyo", "Europe/Berlin"] {
            let cal = calendar(zone)
            let anchor = try XCTUnwrap(cal.date(from: DateComponents(year: 2030, month: 3, day: 11)))
            let custom = try XCTUnwrap(RelativeNotificationTiming(value: 2, unit: .days).custom(hasTime: false))
            let result = try XCTUnwrap(fire(custom, timed: false, anchor: anchor, calendar: cal))
            XCTAssertEqual(cal.component(.day, from: result), 9)
            XCTAssertEqual(cal.component(.hour, from: result), 9)
            XCTAssertEqual(cal.component(.minute, from: result), 0)
        }
    }

    func testCalendarClockAndAbsoluteRemainCompatibilityNotNormalRelative() {
        XCTAssertNil(RelativeNotificationTiming(custom: .calendar(daysBefore: 2, hour: 9), hasTime: true))
        XCTAssertNil(RelativeNotificationTiming(custom: .calendar(daysBefore: 2, hour: 17), hasTime: false))
        XCTAssertEqual(RelativeNotificationTiming(custom: .calendar(daysBefore: 14), hasTime: false), .init(value: 2, unit: .weeks))
    }
}
