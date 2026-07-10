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

    private func makeStep(startsAt: Date?, deadlineAt: Date?) -> SelectionStep {
        SelectionStep(
            id: UUID(),
            userID: UUID(),
            companyID: UUID(),
            type: .interview,
            customTitle: nil,
            startsAt: startsAt,
            deadlineAt: deadlineAt,
            status: .scheduled,
            memo: nil,
            notificationEnabled: true,
            createdAt: Date(timeIntervalSince1970: 1_900_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_900_000_000)
        )
    }
}
