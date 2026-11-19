import XCTest
@testable import SwiftRecruitApp

final class TwoHundredWeekNotificationTests: XCTestCase {
    func testEveryUnitOffers200ButNot201() {
        for hasTime in [true, false] {
            for unit in RelativeNotificationTiming.units(hasTime: hasTime) {
                let value = RelativeNotificationTiming(value: 200, unit: unit)
                XCTAssertEqual(value.wheelValues(hasTime: hasTime).upperBound, 200)
                XCTAssertTrue(value.isSelectable(hasTime: hasTime))
                XCTAssertNotNil(value.custom(hasTime: hasTime))
                XCTAssertFalse(RelativeNotificationTiming(value: 201, unit: unit).isSelectable(hasTime: hasTime))
            }
        }
        XCTAssertTrue(RelativeNotificationTiming(value: 200, unit: .days).supports(.weeks, hasTime: false))
        XCTAssertFalse(RelativeNotificationTiming(value: 0, unit: .days).supports(.weeks, hasTime: false))
        XCTAssertNil(RelativeNotificationTiming(value: Int.max, unit: .weeks).custom(hasTime: true))
    }

    func test200WeeksRoundTripsAndComputesForBothPrecisionsAcrossTimeZones() throws {
        for zone in ["UTC", "Asia/Tokyo", "America/New_York"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: zone)!
            let anchor = calendar.date(from: DateComponents(year: 2035, month: 3, day: 12, hour: 12))!
            let value = RelativeNotificationTiming(value: 200, unit: .weeks)
            for timed in [true, false] {
                let wire = try XCTUnwrap(value.custom(hasTime: timed))
                XCTAssertEqual(wire, timed ? .elapsed(33_600, unit: .hours) : .calendar(daysBefore: 1_400))
                let decoded = try JSONDecoder().decode(CustomNotificationTiming.self, from: JSONEncoder().encode(wire))
                XCTAssertEqual(decoded, wire)
                XCTAssertEqual(RelativeNotificationTiming(custom: decoded, hasTime: timed), value)
                let fire = try XCTUnwrap(NotificationScheduleCalculator.reminderDate(
                    anchor: anchor, hasTime: timed, kind: .taskDue,
                    timedPreset: nil, datePreset: nil,
                    timedCustom: timed ? wire : nil, dateCustom: timed ? nil : wire,
                    calendar: calendar
                ))
                if timed {
                    XCTAssertEqual(anchor.timeIntervalSince(fire), 120_960_000)
                } else {
                    let expectedDay = calendar.date(byAdding: .day, value: -1_400, to: calendar.startOfDay(for: anchor))!
                    XCTAssertTrue(calendar.isDate(fire, inSameDayAs: expectedDay))
                    XCTAssertEqual(calendar.component(.hour, from: fire), 9)
                    XCTAssertEqual(calendar.component(.minute, from: fire), 0)
                }
                XCTAssertLessThan(fire, anchor)
            }
        }
    }

    func test200WeeksDraftChangeAndOuterCancelPreserveOriginalValue() {
        for timed in [true, false] {
            var initial = RecruitTaskDraft()
            initial.notificationTimedCustom = .elapsed(12_347)
            initial.notificationDateCustom = .calendar(daysBefore: 201)
            var draft = initial
            var choices = AbsoluteNotificationSelection()
            choices.selectRelative(.init(value: 200, unit: .weeks), hasTime: timed, kind: .taskDue,
                                   enabled: &draft.notificationEnabled, absoluteAt: &draft.notificationAbsoluteAt,
                                   timedPreset: &draft.notificationTimedPreset, datePreset: &draft.notificationDatePreset,
                                   timedCustom: &draft.notificationTimedCustom, dateCustom: &draft.notificationDateCustom)
            XCTAssertEqual(timed ? draft.notificationTimedCustom : draft.notificationDateCustom,
                           timed ? .elapsed(33_600, unit: .hours) : .calendar(daysBefore: 1_400))
            draft = initial
            XCTAssertEqual(draft.notificationTimedCustom, .elapsed(12_347))
            XCTAssertEqual(draft.notificationDateCustom, .calendar(daysBefore: 201))
            XCTAssertFalse(draft.hasTaskEditorChanges(comparedTo: initial))
        }
    }
}
