import Foundation
import XCTest
@testable import SwiftRecruitApp

final class RecruitTaskDeadlineTests: XCTestCase {
    func testTimedTaskBecomesOverdueAfterItsTime() {
        let dueAt = Date(timeIntervalSince1970: 2_000_000_000)
        let task = makeTask(dueAt: dueAt, hasTime: true)

        XCTAssertTrue(task.isOverdue(relativeTo: dueAt.addingTimeInterval(1)))
    }

    func testDateOnlyTaskIsNotOverdueUntilNextDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3_600)!
        let dueAt = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2030, month: 1, day: 2, hour: 9))
        )
        let evening = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2030, month: 1, day: 2, hour: 20))
        )
        let task = makeTask(dueAt: dueAt, hasTime: false)

        XCTAssertFalse(task.isOverdue(relativeTo: evening, calendar: calendar))
    }

    private func makeTask(dueAt: Date, hasTime: Bool) -> RecruitTask {
        RecruitTask(
            id: UUID(),
            userID: UUID(),
            companyID: nil,
            title: "テスト",
            memo: nil,
            dueAt: dueAt,
            dueHasTime: hasTime,
            completedAt: nil,
            notificationEnabled: true,
            createdAt: Date(timeIntervalSince1970: 1_900_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_900_000_000)
        )
    }
}
