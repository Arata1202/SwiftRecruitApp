import Foundation
import XCTest
@testable import SwiftRecruitApp

final class HomeTaskBucketsTests: XCTestCase {
    func testSeparatesOverdueAndUpcomingWithoutOldItemsHidingUpcoming() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3_600)!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2030, month: 1, day: 10, hour: 12)))
        let old = makeTask(title: "古い期限切れ", dueAt: now.addingTimeInterval(-10 * 86_400))
        let recent = makeTask(title: "直近の期限切れ", dueAt: now.addingTimeInterval(-3_600))
        let tomorrow = makeTask(title: "明日", dueAt: now.addingTimeInterval(86_400))

        let buckets = HomeTaskBuckets.make(tasks: [old, tomorrow, recent], relativeTo: now, calendar: calendar)

        XCTAssertEqual(buckets.overdue.map(\.title), ["直近の期限切れ", "古い期限切れ"])
        XCTAssertEqual(buckets.upcoming.map(\.title), ["明日"])
    }

    func testExcludesCompletedAndItemsOutsideSevenDays() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var completed = makeTask(title: "完了", dueAt: now.addingTimeInterval(3_600))
        completed.completedAt = now
        let later = makeTask(title: "8日後", dueAt: now.addingTimeInterval(8 * 86_400))

        let buckets = HomeTaskBuckets.make(tasks: [completed, later], relativeTo: now)

        XCTAssertTrue(buckets.overdue.isEmpty)
        XCTAssertTrue(buckets.upcoming.isEmpty)
    }

    private func makeTask(title: String, dueAt: Date) -> RecruitTask {
        RecruitTask(
            id: UUID(), userID: UUID(), companyID: nil, title: title, memo: nil,
            dueAt: dueAt, dueHasTime: true, completedAt: nil,
            notificationEnabled: false, createdAt: dueAt, updatedAt: dueAt
        )
    }
}
