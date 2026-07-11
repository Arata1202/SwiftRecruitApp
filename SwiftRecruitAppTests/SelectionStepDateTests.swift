import Foundation
import XCTest
@testable import SwiftRecruitApp

final class SelectionStepDateTests: XCTestCase {
    func testNextDateUsesEarlierUpcomingDeadline() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let step = makeStep(
            startsAt: now.addingTimeInterval(7_200),
            deadlineAt: now.addingTimeInterval(3_600)
        )

        XCTAssertEqual(step.nextDate(relativeTo: now), now.addingTimeInterval(3_600))
        XCTAssertEqual(step.nextMilestone(relativeTo: now)?.kind, .deadline)
    }

    func testNextDateSkipsPastDate() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let step = makeStep(
            startsAt: now.addingTimeInterval(3_600),
            deadlineAt: now.addingTimeInterval(-3_600)
        )

        XCTAssertEqual(step.nextDate(relativeTo: now), now.addingTimeInterval(3_600))
    }

    func testNextDateIsNilWhenAllDatesArePast() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let step = makeStep(
            startsAt: now.addingTimeInterval(-3_600),
            deadlineAt: now.addingTimeInterval(-7_200)
        )

        XCTAssertNil(step.nextDate(relativeTo: now))
    }

    func testDateOnlyMilestoneRemainsUpcomingForTheWholeDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3_600)!
        let morning = calendar.date(from: DateComponents(year: 2030, month: 1, day: 2, hour: 9))!
        let evening = calendar.date(from: DateComponents(year: 2030, month: 1, day: 2, hour: 18))!
        var step = makeStep(startsAt: morning, deadlineAt: nil)
        step.startsHasTime = false

        XCTAssertEqual(step.nextDate(relativeTo: evening), morning)
    }

    private func makeStep(startsAt: Date?, deadlineAt: Date?) -> SelectionStep {
        SelectionStep(
            id: UUID(),
            userID: UUID(),
            companyID: UUID(),
            type: .interview,
            customTitle: nil,
            startsAt: startsAt,
            startsHasTime: true,
            deadlineAt: deadlineAt,
            deadlineHasTime: true,
            status: .scheduled,
            memo: nil,
            notificationEnabled: true,
            createdAt: Date(timeIntervalSince1970: 1_900_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_900_000_000)
        )
    }
}
