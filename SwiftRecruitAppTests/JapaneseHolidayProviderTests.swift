import Foundation
import XCTest
@testable import SwiftRecruitApp

final class JapaneseHolidayProviderTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ja_JP")
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    func testFixedAndHappyMondayHolidays() throws {
        XCTAssertEqual(holiday(2026, 2, 11), "建国記念の日")
        XCTAssertEqual(holiday(2026, 7, 20), "海の日")
        XCTAssertEqual(holiday(2026, 10, 12), "スポーツの日")
    }

    func testEquinoxAndCitizenHoliday() throws {
        XCTAssertEqual(holiday(2026, 9, 22), "国民の休日")
        XCTAssertEqual(holiday(2026, 9, 23), "秋分の日")
    }

    func testGoldenWeekSubstituteHoliday() throws {
        XCTAssertEqual(holiday(2026, 5, 6), "振替休日")
    }

    func testSubstituteHolidaySkipsExistingHoliday() throws {
        XCTAssertEqual(holiday(2021, 8, 9), "振替休日")
    }

    func testNonHolidayReturnsNil() throws {
        XCTAssertNil(holiday(2026, 7, 21))
    }

    private func holiday(_ year: Int, _ month: Int, _ day: Int) -> String? {
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day))!
        return JapaneseHolidayProvider().holidayName(on: date, calendar: calendar)
    }
}
