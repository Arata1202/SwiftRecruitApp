import Foundation
import XCTest
@testable import SwiftRecruitApp

final class JapaneseHolidayProviderTests: XCTestCase {
    private let provider = JapaneseHolidayProvider()

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ja_JP")
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    @MainActor
    func testVisibleCalendarRefreshesWhenYearOrTimeZoneChanges() throws {
        let visible = VisibleHolidayCalendar()
        let january = try XCTUnwrap(calendar.date(from: DateComponents(year: 2027, month: 1, day: 1)))
        let december = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: january))
        let tokyo = calendar.timeZone
        let utc = TimeZone.gmt
        for (days, zone) in [([december], tokyo), ([december, january], tokyo), ([january], tokyo), ([january], utc)] {
            XCTAssertEqual(visible.holidays(containing: days, timeZone: zone),
                           provider.holidays(containing: days, timeZone: zone))
        }
    }

    func testAllOfficialHolidaysIn2026() {
        XCTAssertEqual(
            holidays(in: 2026),
            [
                "2026-01-01": "元日",
                "2026-01-12": "成人の日",
                "2026-02-11": "建国記念の日",
                "2026-02-23": "天皇誕生日",
                "2026-03-20": "春分の日",
                "2026-04-29": "昭和の日",
                "2026-05-03": "憲法記念日",
                "2026-05-04": "みどりの日",
                "2026-05-05": "こどもの日",
                "2026-05-06": "振替休日",
                "2026-07-20": "海の日",
                "2026-08-11": "山の日",
                "2026-09-21": "敬老の日",
                "2026-09-22": "国民の休日",
                "2026-09-23": "秋分の日",
                "2026-10-12": "スポーツの日",
                "2026-11-03": "文化の日",
                "2026-11-23": "勤労感謝の日"
            ]
        )
    }

    func testAllOfficialHolidaysIn2027() {
        XCTAssertEqual(
            holidays(in: 2027),
            [
                "2027-01-01": "元日",
                "2027-01-11": "成人の日",
                "2027-02-11": "建国記念の日",
                "2027-02-23": "天皇誕生日",
                "2027-03-21": "春分の日",
                "2027-03-22": "振替休日",
                "2027-04-29": "昭和の日",
                "2027-05-03": "憲法記念日",
                "2027-05-04": "みどりの日",
                "2027-05-05": "こどもの日",
                "2027-07-19": "海の日",
                "2027-08-11": "山の日",
                "2027-09-20": "敬老の日",
                "2027-09-23": "秋分の日",
                "2027-10-11": "スポーツの日",
                "2027-11-03": "文化の日",
                "2027-11-23": "勤労感謝の日"
            ]
        )
    }

    func testRulesBefore2003UseFixedSeaAndRespectForTheAgedDays() {
        XCTAssertEqual(holiday(2000, 4, 29), "みどりの日")
        XCTAssertEqual(holiday(2000, 5, 4), "国民の休日")
        XCTAssertEqual(holiday(2000, 7, 20), "海の日")
        XCTAssertEqual(holiday(2000, 9, 15), "敬老の日")
        XCTAssertEqual(holiday(2000, 10, 9), "体育の日")
        XCTAssertEqual(holiday(2000, 12, 23), "天皇誕生日")
        XCTAssertNil(holiday(2000, 7, 17))
        XCTAssertNil(holiday(2000, 8, 11))
        XCTAssertNil(holiday(2003, 5, 4))
    }

    func test2007HolidayChangesAreAppliedAtTheCorrectBoundary() {
        XCTAssertEqual(holiday(2006, 4, 29), "みどりの日")
        XCTAssertEqual(holiday(2006, 5, 4), "国民の休日")
        XCTAssertEqual(holiday(2007, 4, 29), "昭和の日")
        XCTAssertEqual(holiday(2007, 4, 30), "振替休日")
        XCTAssertEqual(holiday(2007, 5, 4), "みどりの日")
    }

    func test2019ImperialSuccessionHolidays() {
        XCTAssertEqual(holiday(2019, 4, 30), "国民の休日")
        XCTAssertEqual(holiday(2019, 5, 1), "天皇の即位の日")
        XCTAssertEqual(holiday(2019, 5, 2), "国民の休日")
        XCTAssertEqual(holiday(2019, 10, 14), "体育の日")
        XCTAssertEqual(holiday(2019, 10, 22), "即位礼正殿の儀の行われる日")
        XCTAssertNil(holiday(2019, 12, 23))
    }

    func testOlympicExceptionsAndSubstituteHoliday() {
        XCTAssertEqual(holiday(2021, 8, 9), "振替休日")
        XCTAssertEqual(holiday(2021, 7, 22), "海の日")
        XCTAssertEqual(holiday(2021, 7, 23), "スポーツの日")
        XCTAssertNil(holiday(2021, 10, 11))
    }

    func testContainingDateUsesGregorianYearRegardlessOfDisplayCalendar() {
        var japaneseCalendar = Calendar(identifier: .japanese)
        japaneseCalendar.timeZone = calendar.timeZone
        let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        let values = provider.holidays(containing: [date], timeZone: japaneseCalendar.timeZone)

        XCTAssertNotEqual(japaneseCalendar.component(.year, from: date), 2026)
        XCTAssertEqual(values[calendar.date(from: DateComponents(year: 2026, month: 7, day: 20))!], "海の日")
    }

    func testDisplayMonthSpanningGregorianYearsIncludesHolidaysFromBothYears() {
        var islamicCalendar = Calendar(identifier: .islamicCivil)
        islamicCalendar.timeZone = calendar.timeZone
        let gregorianNewYear = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let dates = islamicCalendar.datesCoveringMonth(containing: gregorianNewYear)
        let values = provider.holidays(containing: dates, timeZone: islamicCalendar.timeZone)

        XCTAssertEqual(values[holidayDate(2025, 11, 23)], "勤労感謝の日")
        XCTAssertEqual(values[holidayDate(2026, 1, 1)], "元日")
    }

    func testDatesOutsideSupportedRangeReturnNoHoliday() {
        XCTAssertNil(holiday(1999, 1, 1))
        XCTAssertEqual(holiday(2050, 1, 1), "元日")
        XCTAssertNil(holiday(2051, 1, 1))
    }

    private func holiday(_ year: Int, _ month: Int, _ day: Int) -> String? {
        let date = holidayDate(year, month, day)
        return provider.holidayName(on: date, calendar: calendar)
    }

    private func holidayDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func holidays(in year: Int) -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: provider.holidays(in: year, timeZone: calendar.timeZone).map {
                let components = calendar.dateComponents([.year, .month, .day], from: $0.key)
                let key = String(
                    format: "%04d-%02d-%02d",
                    components.year!,
                    components.month!,
                    components.day!
                )
                return (key, $0.value)
            }
        )
    }
}
