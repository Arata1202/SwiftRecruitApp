import XCTest
@testable import SwiftRecruitApp

final class RelativeNotificationTimingTests: XCTestCase {
    func testNewDraftDefaultsUseVisiblePresets() {
        for var draft in [SelectionStepDraft(), SelectionStepDraft(date: Date())] {
            XCTAssertEqual(draft.resolvedNotificationDatePreset, .previousDay)
            draft.dateKind = .schedule
            XCTAssertEqual(draft.resolvedNotificationTimedPreset, .oneHour)
            draft.dateKind = .deadline
            XCTAssertEqual(draft.resolvedNotificationTimedPreset, .oneDay)
            XCTAssertEqual(draft.notificationTimedCustom, .relative(1, unit: .days).withNotificationClock(hour: 9, minute: 0))
            XCTAssertNil(draft.notificationDateCustom)
        }
        for draft in [RecruitTaskDraft(), RecruitTaskDraft(dueDate: Date())] {
            XCTAssertEqual(draft.notificationTimedPreset, .oneHour)
            XCTAssertEqual(draft.notificationDatePreset, .previousDay)
            XCTAssertNil(draft.notificationTimedCustom)
            XCTAssertNil(draft.notificationDateCustom)
        }
        // Stored nil values retain their historical meaning, not new-editor defaults.
        XCTAssertEqual(NotificationAnchor.taskDue.defaultTimedPreset, .atTime)
        XCTAssertEqual(NotificationAnchor.taskDue.defaultDatePreset, .sameDay)
        XCTAssertEqual(NotificationAnchor.selectionStart.defaultDatePreset, .sameDay)
    }

    func testClockValidationAgreesWithDatabaseFixtures() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "notification-clock-cases", withExtension: "tsv"))
        let rows = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            let fields = row.split(separator: "\t")
            guard fields.count == 3 else { return XCTFail("Invalid fixture: \(row)") }
            let timing = try JSONDecoder().decode(CustomNotificationTiming.self, from: Data(fields[0].utf8))
            XCTAssertEqual(timing.isValid(hasTime: true), fields[1] == "true", String(row))
            XCTAssertEqual(timing.isValid(hasTime: false), fields[2] == "true", String(row))
        }
    }

    func testInvalidClockEditPreservesStoredTimeAndPreset() {
        let value = RelativeNotificationTiming(value: 2, unit: .days)
        let original = CustomNotificationTiming.relative(2, unit: .days).withNotificationClock(hour: 16, minute: 30)
        var stored: CustomNotificationTiming? = original
        var preset: TimedNotificationPreset?
        value.updateClock(hour: 24, minute: 0, kind: .taskDue, preset: &preset, custom: &stored)
        XCTAssertEqual(stored, original)
        XCTAssertNil(preset)
    }

    func testPerItemClockSurvivesPresetChangesAndRoundTrip() throws {
        var editor = Editor()
        editor.date = .calendar(daysBefore: 1, hour: 18, minute: 30)
        for timing in [RelativeNotificationTiming(value: 2, unit: .days), .init(value: 1, unit: .months), .init(value: 30, unit: .minutes)] {
            editor.relative(timing, hasTime: false)
            let custom = try XCTUnwrap(editor.date)
            XCTAssertEqual(custom.hour, 18)
            XCTAssertEqual(custom.minute, 30)
            XCTAssertTrue(custom.isValid(hasTime: false))
            XCTAssertEqual(try JSONDecoder().decode(CustomNotificationTiming.self, from: JSONEncoder().encode(custom)), custom)
            XCTAssertEqual(RelativeNotificationTiming(custom: custom.standardClockRepresentation, hasTime: false), timing)
        }
        let original = editor
        var draft = editor
        draft.date = draft.date?.withNotificationClock(hour: 0, minute: 0)
        XCTAssertEqual(original.date?.hour, 18)
        XCTAssertEqual(draft.date?.hour, 0)
        XCTAssertFalse(CustomNotificationTiming.relative(1, unit: .days).withNotificationClock(hour: 24, minute: 0).isValid(hasTime: false))
        XCTAssertTrue(CustomNotificationTiming.relative(1, unit: .days).withNotificationClock(hour: 9, minute: 0).isValid(hasTime: true))
        let cal = calendar("Asia/Tokyo")
        let anchor = try XCTUnwrap(cal.date(from: DateComponents(year: 2030, month: 6, day: 10)))
        let custom = CustomNotificationTiming.relative(30, unit: .minutes).withNotificationClock(hour: 18, minute: 30)
        let fireDate = try XCTUnwrap(fire(custom, timed: false, anchor: anchor, calendar: cal))
        XCTAssertEqual(cal.component(.hour, from: fireDate), 18)
        XCTAssertEqual(cal.component(.minute, from: fireDate), 0)
    }

    func testTimedCalendarClockSelectionAndUnitSwitches() throws {
        var editor = Editor()
        editor.reminder(.init(value: 1, unit: .days))
        XCTAssertEqual(editor.timed, .relative(1, unit: .days).withNotificationClock(hour: 9, minute: 0))
        editor.timed = editor.timed?.withNotificationClock(hour: 18, minute: 30)
        editor.reminder(.init(value: 2, unit: .weeks))
        XCTAssertEqual(editor.timed?.hour, 18)
        XCTAssertEqual(editor.timed?.minute, 30)
        editor.reminder(.init(value: 1, unit: .months))
        XCTAssertEqual(editor.timed?.hour, 18)
        let saved = try XCTUnwrap(editor.timed)
        XCTAssertEqual(try JSONDecoder().decode(CustomNotificationTiming.self, from: JSONEncoder().encode(saved)), saved)
        var draft = editor
        draft.timed = draft.timed?.withNotificationClock(hour: 0, minute: 0)
        XCTAssertEqual(editor.timed?.hour, 18)
        editor.reminder(.init(value: 24, unit: .hours))
        XCTAssertEqual(editor.timed, .relative(24, unit: .hours))
        XCTAssertFalse(RelativeNotificationTiming(value: 24, unit: .hours).usesNotificationClock)
        XCTAssertFalse(CustomNotificationTiming.relative(1, unit: .hours).withNotificationClock(hour: 9, minute: 0).isValid(hasTime: true))
    }

    func testDateOnlyOffsetResolvesClockOnDayBeforeSpringForward() throws {
        let cal = calendar("America/New_York")
        let anchor = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 3, day: 8)))
        let timing = CustomNotificationTiming.relative(1, unit: .days).withNotificationClock(hour: 2, minute: 30)
        let result = try XCTUnwrap(fire(timing, timed: false, anchor: anchor, calendar: cal))
        XCTAssertEqual(cal.dateComponents([.day, .hour, .minute], from: result),
                       DateComponents(day: 7, hour: 2, minute: 30))
    }

    func testReturningToDayOffsetRestoresEditedClock() {
        var editor = Editor()
        editor.reminder(.init(value: 1, unit: .days))
        editor.timed = editor.timed?.withNotificationClock(hour: 16, minute: 30)
        editor.reminder(.init(value: 15, unit: .minutes))
        editor.reminder(.init(value: 1, unit: .days))
        XCTAssertEqual(editor.timed?.hour, 16)
        XCTAssertEqual(editor.timed?.minute, 30)
    }

    func testTimedCalendarClockUsesTargetDayAcrossDSTMonthEndAndAnchorEdits() throws {
        for zone in ["Asia/Tokyo", "America/New_York", "Europe/Berlin"] {
            let cal = calendar(zone)
            let anchor = try XCTUnwrap(cal.date(from: DateComponents(year: 2028, month: 3, day: 31, hour: 15)))
            for unit in [RelativeNotificationTiming.Unit.days, .weeks, .months] {
                let custom = try XCTUnwrap(RelativeNotificationTiming(value: 1, unit: unit).clockCustom())
                let result = try XCTUnwrap(fire(custom, timed: true, anchor: anchor, calendar: cal))
                XCTAssertEqual(cal.component(.hour, from: result), 9)
                XCTAssertEqual(cal.component(.minute, from: result), 0)
                let moved = anchor.addingTimeInterval(3600)
                XCTAssertEqual(fire(custom, timed: true, anchor: moved, calendar: cal), result)
                if unit == .months {
                    XCTAssertEqual(cal.component(.month, from: result), 2)
                    XCTAssertEqual(cal.component(.day, from: result), 29)
                }
            }
            let dstAnchor = try XCTUnwrap(cal.date(from: DateComponents(year: 2030, month: 3, day: 11, hour: 15)))
            let custom = try XCTUnwrap(RelativeNotificationTiming(value: 2, unit: .days).clockCustom())
            let result = try XCTUnwrap(fire(custom, timed: true, anchor: dstAnchor, calendar: cal))
            XCTAssertEqual(cal.component(.day, from: result), 9)
            XCTAssertEqual(cal.component(.hour, from: result), 9)
            let legacy = CustomNotificationTiming.elapsed(48, unit: .hours)
            XCTAssertEqual(dstAnchor.timeIntervalSince(try XCTUnwrap(fire(legacy, timed: true, anchor: dstAnchor, calendar: cal))), 172800)
        }
    }

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
        mutating func reminder(_ value: RelativeNotificationTiming) {
            choices.selectReminder(value, hasTime: true, kind: .taskDue,
                enabled: &enabled, absoluteAt: &absolute,
                timedPreset: &timedPreset, datePreset: &datePreset,
                timedCustom: &timed, dateCustom: &date)
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
        XCTAssertEqual(RelativeNotificationTiming.units(hasTime: true), [.minutes, .hours, .days, .weeks, .months])
        XCTAssertEqual(RelativeNotificationTiming.units(hasTime: false), [.minutes, .hours, .days, .weeks, .months])
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
                XCTAssertFalse(value.wheelValues(hasTime: timed).contains(value.value))
            }
        }
        XCTAssertNotNil(RelativeNotificationTiming(value: 0, unit: .days).custom(hasTime: false))
        XCTAssertEqual(RelativeNotificationTiming(value: 0, unit: .days).custom(hasTime: true), .calendar())
        XCTAssertEqual(RelativeNotificationTiming(value: 1, unit: .hours).custom(hasTime: false), .relative(1, unit: .hours))
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
        XCTAssertEqual(editor.date, .calendar(daysBefore: 7, hour: 21, minute: 37))
        editor.select("custom", hasTime: false)
        XCTAssertEqual(editor.date, .calendar(daysBefore: 4, hour: 21, minute: 37))
        XCTAssertEqual(editor.timed, .elapsed(97))
    }

    func testLegacyCustomRemainsAvailableAfterRelativeAndPresetSwitches() {
        for timed in [true, false] {
            for finalChoice in ["relative_7", timed ? "one_hour" : "same_day"] {
                var editor = Editor()
                let old = CustomNotificationTiming.calendar(daysBefore: 1, hour: 20, minute: 0)
                if timed { editor.timed = old } else { editor.date = old }
                editor.relative(.init(value: 2, unit: .days), hasTime: timed)
                if finalChoice == "relative_7" {
                    editor.relative(.init(value: 1, unit: .weeks), hasTime: timed)
                } else {
                    editor.select(finalChoice, hasTime: timed)
                }
                XCTAssertTrue(editor.choices.hasRememberedLegacyCustom(hasTime: timed))
                editor.select("custom", hasTime: timed)
                XCTAssertEqual(timed ? editor.timed : editor.date, old)
            }
        }
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
    func testInlineWheelKeepsChosenNumberAndUnitAtPresetBoundaries() throws {
        var presentation = RelativeNotificationPresentation()
        for chosen in [RelativeNotificationTiming(value: 2, unit: .days),
                       .init(value: 7, unit: .days), .init(value: 24, unit: .hours),
                       .init(value: 1_440, unit: .minutes)] {
            presentation.edit(chosen)
            XCTAssertTrue(presentation.isCustom)
            let wire = try XCTUnwrap(chosen.custom(hasTime: true))
            XCTAssertEqual(presentation.value(custom: wire, hasTime: true), chosen)
            presentation.selectPreset()
            XCTAssertFalse(presentation.isCustom)
            XCTAssertEqual(presentation.value(custom: wire, hasTime: true), RelativeNotificationTiming(custom: wire, hasTime: true))
        }
    }

    func testWheelUnitsRespect200ForEveryUnit() {
        for unit in [RelativeNotificationTiming.Unit.minutes, .hours, .days] {
            let value = RelativeNotificationTiming(value: 200, unit: unit)
            XCTAssertTrue(value.isSelectable(hasTime: true))
            XCTAssertTrue(value.supports(.days, hasTime: true))
            XCTAssertTrue(value.supports(.weeks, hasTime: true))
            XCTAssertFalse(RelativeNotificationTiming(value: 201, unit: unit).isSelectable(hasTime: true))
        }
        XCTAssertTrue(RelativeNotificationTiming(value: 52, unit: .weeks).isSelectable(hasTime: true))
        XCTAssertTrue(RelativeNotificationTiming(value: 53, unit: .weeks).isSelectable(hasTime: true))
        XCTAssertTrue(RelativeNotificationTiming(value: 200, unit: .weeks).isSelectable(hasTime: true))
        XCTAssertTrue(RelativeNotificationTiming(value: 200, unit: .days).isSelectable(hasTime: false))
        XCTAssertFalse(RelativeNotificationTiming(value: 201, unit: .days).isSelectable(hasTime: false))
        XCTAssertTrue(RelativeNotificationTiming(value: 52, unit: .weeks).isSelectable(hasTime: false))
        XCTAssertTrue(RelativeNotificationTiming(value: 53, unit: .weeks).isSelectable(hasTime: false))
        XCTAssertTrue(RelativeNotificationTiming(value: 0, unit: .days).isSelectable(hasTime: false))
        XCTAssertFalse(RelativeNotificationTiming(value: 0, unit: .days).supports(.weeks, hasTime: false))
        XCTAssertTrue(RelativeNotificationTiming(value: 0, unit: .days).isSelectable(hasTime: true))
        XCTAssertTrue(RelativeNotificationTiming(value: 1, unit: .days).supports(.minutes, hasTime: false))
    }

    func testChosenEquivalentUnitRestoresOriginalWireAfterPreset() {
        var editor = Editor()
        editor.timed = .elapsed(1_440)
        let chosen = RelativeNotificationTiming(value: 1_440, unit: .minutes)
        editor.relative(chosen)
        XCTAssertEqual(editor.timed, .elapsed(1_440))
        editor.select("one_hour")
        editor.relative(chosen)
        XCTAssertEqual(editor.timed, .elapsed(1_440))
    }

    func testInlinePrecisionStateAndResetAreIndependent() {
        var timed = RelativeNotificationPresentation()
        var date = RelativeNotificationPresentation()
        timed.edit(.init(value: 24, unit: .hours))
        date.edit(.init(value: 7, unit: .days))
        XCTAssertEqual(timed.value(custom: .elapsed(24, unit: .hours), hasTime: true), .init(value: 24, unit: .hours))
        XCTAssertEqual(date.value(custom: .calendar(daysBefore: 7), hasTime: false), .init(value: 7, unit: .days))
        timed = RelativeNotificationPresentation()
        XCTAssertFalse(timed.isCustom)
        XCTAssertTrue(date.isCustom)
        XCTAssertEqual(timed.value(custom: .calendar(hour: 20), hasTime: true), .init(value: 0, unit: .days))
    }

    func testInlineDraftCancelSaveAndRevert() throws {
        var initial = RecruitTaskDraft()
        initial.hasDueDate = true
        initial.dueHasTime = true
        initial.notificationTimedCustom = .elapsed(97)
        var draft = initial
        var choices = AbsoluteNotificationSelection()
        choices.selectRelative(.init(value: 200, unit: .days), hasTime: true, kind: .taskDue,
                               enabled: &draft.notificationEnabled, absoluteAt: &draft.notificationAbsoluteAt,
                               timedPreset: &draft.notificationTimedPreset, datePreset: &draft.notificationDatePreset,
                               timedCustom: &draft.notificationTimedCustom, dateCustom: &draft.notificationDateCustom)
        XCTAssertTrue(draft.hasTaskEditorChanges(comparedTo: initial))
        XCTAssertEqual(initial.notificationTimedCustom, .elapsed(97))
        let saved = try JSONDecoder().decode(CustomNotificationTiming.self,
            from: JSONEncoder().encode(try XCTUnwrap(draft.notificationTimedCustom)))
        XCTAssertEqual(saved, .elapsed(4_800, unit: .hours))
        draft = initial
        XCTAssertFalse(draft.hasTaskEditorChanges(comparedTo: initial))
        XCTAssertEqual(draft.notificationTimedCustom, .elapsed(97))
    }

    func testWheelHasNoOutOfRangeStoredValueEscape() {
        for timed in [true, false] {
            for unit in RelativeNotificationTiming.units(hasTime: timed) {
                for storedValue in [1, 200, 201, 12_347] {
                    let value = RelativeNotificationTiming(value: storedValue, unit: unit)
                    let values = value.wheelValues(hasTime: timed)
                    XCTAssertEqual(values.lowerBound, value.minimum(hasTime: timed))
                    XCTAssertEqual(values.upperBound, 200)
                    XCTAssertFalse(values.contains(201))
                }
            }
        }
    }

    func testExplicitCustomSelectionDoesNotRestoreOutOfRangeWheelValue() {
        let legacy = RelativeNotificationTiming(value: 201, unit: .days)
        XCTAssertEqual(legacy.custom(hasTime: true), .elapsed(4_824, unit: .hours))
        XCTAssertEqual(RelativeNotificationTiming.initialSelection(current: legacy, remembered: legacy, hasTime: true), .init())
        let allowed = RelativeNotificationTiming(value: 200, unit: .hours)
        XCTAssertEqual(RelativeNotificationTiming.initialSelection(current: allowed, remembered: legacy, hasTime: true), allowed)
        XCTAssertEqual(RelativeNotificationTiming.initialSelection(current: nil, remembered: allowed, hasTime: true), allowed)
    }

    func testOver200StoredValuesSurviveOpeningUnrelatedSaveAndCancel() throws {
        for (wire, timed) in [(CustomNotificationTiming.elapsed(12_347), true),
                              (.elapsed(201, unit: .hours), true), (.calendar(daysBefore: 201), false)] {
            var initial = RecruitTaskDraft()
            initial.dueHasTime = timed
            initial.notificationTimedCustom = timed ? wire : nil
            initial.notificationDateCustom = timed ? nil : wire
            let presentation = RelativeNotificationPresentation()
            let relative = try XCTUnwrap(presentation.value(custom: wire, hasTime: timed))
            XCTAssertFalse(relative.isSelectable(hasTime: timed))
            XCTAssertEqual(relative.custom(hasTime: timed), wire)
            var draft = initial
            draft.title = "Unrelated title change"
            let unchanged = timed ? draft.notificationTimedCustom : draft.notificationDateCustom
            let data = try JSONEncoder().encode(try XCTUnwrap(unchanged))
            XCTAssertEqual(try JSONDecoder().decode(CustomNotificationTiming.self, from: data), wire)
            var choices = AbsoluteNotificationSelection()
            let selection = RelativeNotificationTiming.initialSelection(current: relative, remembered: nil, hasTime: timed)
            choices.selectRelative(selection, hasTime: timed, kind: .taskDue,
                                   enabled: &draft.notificationEnabled, absoluteAt: &draft.notificationAbsoluteAt,
                                   timedPreset: &draft.notificationTimedPreset, datePreset: &draft.notificationDatePreset,
                                   timedCustom: &draft.notificationTimedCustom, dateCustom: &draft.notificationDateCustom)
            XCTAssertNotEqual(timed ? draft.notificationTimedCustom : draft.notificationDateCustom, wire)
            draft = initial
            XCTAssertEqual(timed ? draft.notificationTimedCustom : draft.notificationDateCustom, wire)
            XCTAssertFalse(draft.hasTaskEditorChanges(comparedTo: initial))
        }
    }

    func testExistingAbsoluteAndCalendarSurviveUnrelatedDraftSaveAndCancel() throws {
        var initial = RecruitTaskDraft()
        initial.notificationAbsoluteAt = Date(timeIntervalSince1970: 1_900_000_000)
        initial.notificationTimedCustom = .calendar(daysBefore: 2, hour: 20, minute: 37)
        initial.notificationDateCustom = .calendar(daysBefore: 3, hour: 17, minute: 12)
        var draft = initial
        draft.title = "Changed title only"
        XCTAssertEqual(draft.notificationAbsoluteAt, initial.notificationAbsoluteAt)
        XCTAssertEqual(draft.notificationTimedCustom, initial.notificationTimedCustom)
        XCTAssertEqual(draft.notificationDateCustom, initial.notificationDateCustom)
        let data = try JSONEncoder().encode(draft.notificationTimedCustom)
        XCTAssertEqual(try JSONDecoder().decode(CustomNotificationTiming.self, from: data), initial.notificationTimedCustom)
        draft.notificationAbsoluteAt = nil
        draft.notificationTimedCustom = .elapsed(200)
        draft = initial
        XCTAssertEqual(draft.notificationAbsoluteAt, initial.notificationAbsoluteAt)
        XCTAssertEqual(draft.notificationTimedCustom, initial.notificationTimedCustom)
        XCTAssertFalse(draft.hasTaskEditorChanges(comparedTo: initial))
    }

    func testExplicitRelativeReplacesActiveLegacyWhileNoneOnlyDisables() {
        var original = Editor()
        original.absolute = Date(timeIntervalSince1970: 1_900_000_000)
        original.timed = .calendar(daysBefore: 2, hour: 20, minute: 37)
        original.date = .calendar(daysBefore: 3, hour: 17, minute: 12)
        var draft = original
        draft.select("none")
        XCTAssertFalse(draft.enabled)
        XCTAssertEqual(draft.absolute, original.absolute)
        XCTAssertEqual(draft.timed, original.timed)
        draft.relative(.init(value: 200, unit: .minutes))
        XCTAssertTrue(draft.enabled)
        XCTAssertNil(draft.absolute)
        XCTAssertEqual(draft.timed, .elapsed(200))
        XCTAssertEqual(draft.date, original.date)
        draft = original
        XCTAssertEqual(draft.absolute, original.absolute)
        XCTAssertEqual(draft.timed, original.timed)
    }

    func testReferenceMenuItemsAndOrder() {
        XCTAssertEqual(ReminderMenuOption.options(hasTime: true).map(\.id), [
            "reminder_0_days", "reminder_5_minutes", "reminder_15_minutes", "reminder_30_minutes",
            "reminder_1_hours", "reminder_2_hours", "reminder_1_days", "reminder_2_days",
            "reminder_1_weeks", "reminder_1_months",
        ])
        XCTAssertEqual(ReminderMenuOption.options(hasTime: false).map(\.id), [
            "reminder_0_days", "reminder_1_days", "reminder_2_days", "reminder_1_weeks",
            "reminder_2_weeks", "reminder_1_months", "reminder_3_months", "reminder_6_months",
        ])
        XCTAssertEqual(ReminderMenuOption.options(hasTime: true).map(\.title),
                       ["当日", "5分前", "15分前", "30分前", "1時間前", "2時間前", "1日前", "2日前", "1週間前", "1か月前"])
        XCTAssertEqual(ReminderMenuOption.options(hasTime: false).map(\.title),
                       ["当日", "1日前", "2日前", "1週間前", "2週間前", "1か月前", "3か月前", "6か月前"])
    }

    func testMonthsAreCalendarOffsetsAndRoundTripBothPrecisions() throws {
        let cal = calendar("Asia/Tokyo")
        let anchor = try XCTUnwrap(cal.date(from: DateComponents(year: 2028, month: 3, day: 31, hour: 18)))
        for timed in [true, false] {
            let custom = try XCTUnwrap(RelativeNotificationTiming(value: 1, unit: .months).custom(hasTime: timed))
            let result = try XCTUnwrap(fire(custom, timed: timed, anchor: anchor, calendar: cal))
            XCTAssertEqual(cal.component(.month, from: result), 2)
            XCTAssertEqual(cal.component(.day, from: result), 29)
            XCTAssertEqual(cal.component(.hour, from: result), timed ? 18 : 9)
            let encoded = try JSONEncoder().encode(custom)
            XCTAssertEqual(try JSONDecoder().decode(CustomNotificationTiming.self, from: encoded), custom)
            let maximum = try XCTUnwrap(RelativeNotificationTiming(value: 200, unit: .months).custom(hasTime: timed))
            XCTAssertNotNil(fire(maximum, timed: timed, anchor: anchor, calendar: cal))
            XCTAssertFalse(RelativeNotificationTiming(value: 201, unit: .months).isSelectable(hasTime: timed))
            XCTAssertFalse(CustomNotificationTiming.relative(201, unit: .months).isValid(hasTime: timed))
        }
    }

    func testDateOnlySupportsMinuteAndHourOffsetsFromNine() throws {
        let cal = calendar("Asia/Tokyo")
        let anchor = try XCTUnwrap(cal.date(from: DateComponents(year: 2030, month: 5, day: 20)))
        for (unit, hour, minute) in [(RelativeNotificationTiming.Unit.minutes, 8, 55), (.hours, 4, 0)] {
            let custom = try XCTUnwrap(RelativeNotificationTiming(value: 5, unit: unit).custom(hasTime: false))
            let result = try XCTUnwrap(fire(custom, timed: false, anchor: anchor, calendar: cal))
            XCTAssertEqual(cal.component(.hour, from: result), hour)
            XCTAssertEqual(cal.component(.minute, from: result), minute)
        }
    }

}
