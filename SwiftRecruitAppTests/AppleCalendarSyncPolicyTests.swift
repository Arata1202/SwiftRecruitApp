import XCTest
@testable import SwiftRecruitApp

final class AppleCalendarSyncPolicyTests: XCTestCase {
    func testTimedPastEventIsNotUpcoming() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        XCTAssertFalse(
            AppleCalendarSyncPolicy.isUpcoming(
                date: now.addingTimeInterval(-1),
                hasTime: true,
                now: now
            )
        )
    }

    func testTimedFutureEventIsUpcoming() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        XCTAssertTrue(
            AppleCalendarSyncPolicy.isUpcoming(
                date: now.addingTimeInterval(1),
                hasTime: true,
                now: now
            )
        )
    }

    func testDateOnlyEventRemainsUpcomingForWholeDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3_600)!
        let morning = calendar.date(from: DateComponents(year: 2030, month: 1, day: 2, hour: 9))!
        let evening = calendar.date(from: DateComponents(year: 2030, month: 1, day: 2, hour: 20))!

        XCTAssertTrue(
            AppleCalendarSyncPolicy.isUpcoming(
                date: morning,
                hasTime: false,
                now: evening,
                calendar: calendar
            )
        )
    }
}
