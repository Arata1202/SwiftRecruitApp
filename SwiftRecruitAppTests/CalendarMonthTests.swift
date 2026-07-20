import XCTest
@testable import SwiftRecruitApp

final class CalendarMonthTests: XCTestCase {
    func testOrderedWeekdaysStartsOnConfiguredWeekday() {
        var sundayCalendar = Calendar(identifier: .gregorian)
        sundayCalendar.firstWeekday = 1
        XCTAssertEqual(sundayCalendar.orderedWeekdays, [1, 2, 3, 4, 5, 6, 7])

        var mondayCalendar = Calendar(identifier: .gregorian)
        mondayCalendar.firstWeekday = 2
        XCTAssertEqual(mondayCalendar.orderedWeekdays, [2, 3, 4, 5, 6, 7, 1])
    }

    func testDatesCoveringFiveWeekMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        calendar.firstWeekday = 1
        let month = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)))

        let dates = calendar.datesCoveringMonth(containing: month)

        XCTAssertEqual(dates.count, 35)
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(dates.first)), 28)
        XCTAssertEqual(calendar.component(.month, from: try XCTUnwrap(dates.first)), 6)
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(dates.last)), 1)
        XCTAssertEqual(calendar.component(.month, from: try XCTUnwrap(dates.last)), 8)
    }

    func testDatesCoveringSixWeekMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        calendar.firstWeekday = 1
        let month = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))

        let dates = calendar.datesCoveringMonth(containing: month)

        XCTAssertEqual(dates.count, 42)
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(dates.first)), 26)
        XCTAssertEqual(calendar.component(.month, from: try XCTUnwrap(dates.first)), 7)
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(dates.last)), 5)
        XCTAssertEqual(calendar.component(.month, from: try XCTUnwrap(dates.last)), 9)
    }

    func testDatesCoveringMonthWithMondayFirst() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        calendar.firstWeekday = 2
        let month = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))

        let dates = calendar.datesCoveringMonth(containing: month)

        XCTAssertEqual(dates.count, 42)
        XCTAssertEqual(calendar.component(.weekday, from: try XCTUnwrap(dates.first)), 2)
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(dates.first)), 27)
        XCTAssertEqual(calendar.component(.month, from: try XCTUnwrap(dates.first)), 7)
    }

    func testDatesCoveringMonthAcrossYearBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        calendar.firstWeekday = 1
        let month = try XCTUnwrap(calendar.date(from: DateComponents(year: 2027, month: 1, day: 1)))

        let dates = calendar.datesCoveringMonth(containing: month)

        XCTAssertEqual(calendar.component(.year, from: try XCTUnwrap(dates.first)), 2026)
        XCTAssertEqual(calendar.component(.month, from: try XCTUnwrap(dates.first)), 12)
        XCTAssertEqual(calendar.component(.year, from: try XCTUnwrap(dates.last)), 2027)
        XCTAssertEqual(calendar.component(.month, from: try XCTUnwrap(dates.last)), 2)
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(dates.last)), 6)
    }
}
