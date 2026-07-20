import XCTest
@testable import SwiftRecruitApp

final class CalendarMonthTests: XCTestCase {
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
}
