import XCTest
@testable import SwiftRecruitApp

final class ListDateFormattingTests: XCTestCase {
    private func calendar(_ zone: String = "Asia/Tokyo") -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: zone)!
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testCurrentYearKeepsShortDateWithOptionalTime() {
        let cal = calendar()
        let now = date(2026, 11, 19, calendar: cal)
        let target = date(2026, 12, 1, calendar: cal)
        XCTAssertEqual(DateFormatting.listDate(target, hasTime: false, calendar: cal, referenceDate: now), "12月1日(火)")
        XCTAssertEqual(DateFormatting.listDate(target, hasTime: true, calendar: cal, referenceDate: now), "12月1日(火) 9:00")
    }

    func testPastAndFutureYearsAreExplicitForBothPrecisions() {
        let cal = calendar()
        let now = date(2026, 11, 19, calendar: cal)
        for (year, weekday) in [(2025, "水"), (2027, "金")] {
            let target = date(year, 1, 1, calendar: cal)
            let day = "\(year)年1月1日(\(weekday))"
            XCTAssertEqual(DateFormatting.listDate(target, hasTime: false, calendar: cal, referenceDate: now), day)
            XCTAssertEqual(DateFormatting.listDate(target, hasTime: true, calendar: cal, referenceDate: now), day + " 9:00")
        }
    }

    func testJapaneseCalendarIncludesEraWheneverYearIsShown() {
        let gregorian = calendar()
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = gregorian.timeZone
        let target = date(2027, 1, 15, calendar: gregorian)
        let previousEra = date(1997, 1, 15, calendar: gregorian) // Heisei 9
        XCTAssertEqual(DateFormatting.listDate(target, hasTime: false, calendar: japanese, referenceDate: previousEra),
                       "令和9年1月15日(金)")
        XCTAssertTrue(NotificationScheduleCalculator.reminderDescription(target, now: target, calendar: japanese)
            .contains("令和9年1月15日"))
    }

    func testYearRolloverUsesSuppliedReferenceDateAndTimeZone() {
        let tokyo = calendar()
        let losAngeles = calendar("America/Los_Angeles")
        let before = date(2026, 12, 31, 23, calendar: tokyo)
        let after = date(2027, 1, 1, 0, calendar: tokyo)
        XCTAssertEqual(DateFormatting.listDate(after, hasTime: true, calendar: tokyo, referenceDate: before), "2027年1月1日(金) 0:00")
        XCTAssertEqual(DateFormatting.listDate(after, hasTime: true, calendar: tokyo, referenceDate: after), "1月1日(金) 0:00")
        XCTAssertEqual(DateFormatting.listDate(after, hasTime: true, calendar: losAngeles, referenceDate: before), "12月31日(木) 7:00")
    }

    func testNormalReminderCopyIsOnlyPlannedDateButPastAndMissingRemainExplicit() {
        let cal = calendar()
        let now = date(2026, 11, 19, calendar: cal)
        let target = date(2026, 12, 1, calendar: cal)
        XCTAssertEqual(NotificationScheduleCalculator.reminderDescription(target, now: now, calendar: cal), "通知予定：2026年12月1日 9:00")
        XCTAssertTrue(NotificationScheduleCalculator.reminderDescription(now, now: now, calendar: cal).contains("過ぎているため、通知されません"))
        XCTAssertEqual(NotificationScheduleCalculator.reminderDescription(nil, now: now, calendar: cal), "日程が未設定のため、通知されません。")
    }
}
