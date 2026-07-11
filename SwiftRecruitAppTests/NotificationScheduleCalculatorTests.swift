import XCTest
@testable import SwiftRecruitApp

final class NotificationScheduleCalculatorTests: XCTestCase {
    func testSelectionStartNotificationIsOneHourBefore() throws {
        let startsAt = Date(timeIntervalSince1970: 2_000_000_000)
        let now = startsAt.addingTimeInterval(-10_000)

        let result = try XCTUnwrap(
            NotificationScheduleCalculator.selectionStartDate(startsAt: startsAt, now: now)
        )

        XCTAssertEqual(result, startsAt.addingTimeInterval(-3_600))
    }

    func testPastSelectionNotificationIsNotScheduled() {
        let startsAt = Date(timeIntervalSince1970: 2_000_000_000)
        let now = startsAt
        XCTAssertNil(NotificationScheduleCalculator.selectionStartDate(startsAt: startsAt, now: now))
    }

    func testSelectionDeadlineNotificationIsEightPMOnPreviousDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 9 * 3_600))
        let deadline = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2030, month: 1, day: 3, hour: 12))
        )
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2030, month: 1, day: 1))
        )

        let result = try XCTUnwrap(
            NotificationScheduleCalculator.selectionDeadlineDate(
                deadlineAt: deadline,
                calendar: calendar,
                now: now
            )
        )

        XCTAssertEqual(calendar.component(.day, from: result), 2)
        XCTAssertEqual(calendar.component(.hour, from: result), 20)
        XCTAssertEqual(calendar.component(.minute, from: result), 0)
    }

    func testDateOnlyTaskUsesNineAM() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3_600)!
        let dueAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2030, month: 1, day: 2, hour: 18)))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2030, month: 1, day: 1)))

        let result = try XCTUnwrap(
            NotificationScheduleCalculator.taskDate(
                dueAt: dueAt,
                hasTime: false,
                calendar: calendar,
                now: now
            )
        )

        XCTAssertEqual(calendar.component(.hour, from: result), 9)
        XCTAssertEqual(calendar.component(.day, from: result), 2)
    }

    func testPastTaskNotificationIsNotScheduled() {
        let dueAt = Date(timeIntervalSince1970: 2_000_000_000)
        let now = dueAt.addingTimeInterval(1)

        XCTAssertNil(
            NotificationScheduleCalculator.taskDate(
                dueAt: dueAt,
                hasTime: true,
                now: now
            )
        )
    }
}
