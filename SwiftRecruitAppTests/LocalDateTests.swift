import XCTest
@testable import SwiftRecruitApp

final class LocalDateTests: XCTestCase {
    func testCompatibilityMirrorPreservesDayInAucklandAndDatabaseTimeZone() throws {
        var origin = Calendar(identifier: .gregorian)
        origin.timeZone = try XCTUnwrap(TimeZone(identifier: "Pacific/Auckland"))
        var database = Calendar(identifier: .gregorian)
        database.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let day = LocalDate(year: 2027, month: 1, day: 2)
        let mirror = try XCTUnwrap(day.compatibilityTimestamp(in: origin))
        XCTAssertEqual(LocalDate(date: mirror, calendar: origin), day)
        XCTAssertEqual(LocalDate(date: mirror, calendar: database), day)
    }

    func testCodableUsesPostgresDateFormat() throws {
        let value = LocalDate(year: 2030, month: 2, day: 3)

        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "\"2030-02-03\"")
        XCTAssertEqual(try JSONDecoder().decode(LocalDate.self, from: data), value)
    }

    func testCalendarDateDoesNotShiftAcrossTimeZones() throws {
        let value = LocalDate(year: 2030, month: 1, day: 2)
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))

        let tokyoDate = try XCTUnwrap(value.date(calendar: tokyo))
        let losAngelesDate = try XCTUnwrap(value.date(calendar: losAngeles))

        XCTAssertEqual(tokyo.dateComponents([.year, .month, .day], from: tokyoDate).day, 2)
        XCTAssertEqual(
            losAngeles.dateComponents([.year, .month, .day], from: losAngelesDate).day,
            2
        )
    }

    func testTaskPrefersDateOnlyValueOverCompatibilityTimestamp() throws {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let compatibilityTimestamp = Date(timeIntervalSince1970: 1_893_499_200)
        let task = RecruitTask(
            id: UUID(),
            userID: UUID(),
            companyID: nil,
            title: "提出",
            memo: nil,
            dueAt: compatibilityTimestamp,
            dueOn: LocalDate(year: 2030, month: 1, day: 2),
            dueHasTime: false,
            completedAt: nil,
            notificationEnabled: true,
            createdAt: compatibilityTimestamp,
            updatedAt: compatibilityTimestamp
        )

        let resolved = try XCTUnwrap(task.dueDate(calendar: losAngeles))
        let components = losAngeles.dateComponents([.year, .month, .day], from: resolved)
        XCTAssertEqual(components.year, 2030)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 2)
    }
}
