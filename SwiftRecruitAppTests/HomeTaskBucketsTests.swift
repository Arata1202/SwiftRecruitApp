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

        XCTAssertEqual(buckets.overdue.map(\.title), ["古い期限切れ", "直近の期限切れ"])
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

    func testDateAndTimeBoundariesAndCompletedTasks() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3_600)!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2030, month: 1, day: 10, hour: 12)))
        var yesterday = makeTask(title: "昨日", dueAt: now.addingTimeInterval(-86_400))
        yesterday.dueHasTime = false
        var today = makeTask(title: "今日", dueAt: now.addingTimeInterval(-3_600))
        today.dueHasTime = false
        let before = makeTask(title: "直前", dueAt: now.addingTimeInterval(-1))
        let boundary = makeTask(title: "ちょうど", dueAt: now)
        let future = makeTask(title: "未来", dueAt: now.addingTimeInterval(1))
        var completed = makeTask(title: "完了済み期限切れ", dueAt: now.addingTimeInterval(-2 * 86_400))
        completed.completedAt = now

        let buckets = HomeTaskBuckets.make(tasks: [future, before, today, completed, boundary, yesterday], relativeTo: now, calendar: calendar)

        XCTAssertEqual(buckets.overdue.map(\.title), ["昨日", "直前"])
        XCTAssertEqual(buckets.upcoming.map(\.title), ["今日", "ちょうど", "未来"])
    }

    func testSevenDayBoundaryForTimedAndDateOnlyTasks() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3_600)!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2030, month: 1, day: 10, hour: 12)))
        let end = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: now))
        let exact = makeTask(title: "時刻境界", dueAt: end)
        let after = makeTask(title: "境界の後", dueAt: end.addingTimeInterval(1))
        var dateOnly = makeTask(title: "7日後の日付", dueAt: end.addingTimeInterval(3_600))
        dateOnly.dueHasTime = false
        var nextDay = makeTask(title: "8日後の日付", dueAt: end.addingTimeInterval(86_400))
        nextDay.dueHasTime = false

        let buckets = HomeTaskBuckets.make(tasks: [nextDay, after, dateOnly, exact], relativeTo: now, calendar: calendar)

        XCTAssertEqual(buckets.upcoming.map(\.title), ["時刻境界", "7日後の日付"])
        XCTAssertTrue(buckets.overdue.isEmpty)
    }

    func testTieOrderingIsIndependentOfInputOrder() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let low = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let high = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let later = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        func task(_ id: UUID, _ created: Date, _ due: Date) -> RecruitTask {
            RecruitTask(id: id, userID: UUID(), companyID: nil, title: "", memo: nil,
                        dueAt: due, dueHasTime: true, completedAt: nil,
                        notificationEnabled: false, createdAt: created, updatedAt: created)
        }
        for due in [now.addingTimeInterval(-10), now.addingTimeInterval(10)] {
            let items = [task(later, now, due), task(high, now.addingTimeInterval(-1), due),
                         task(low, now.addingTimeInterval(-1), due)]
            for input in [items, Array(items.reversed())] {
                let buckets = HomeTaskBuckets.make(tasks: input, relativeTo: now)
                XCTAssertEqual((due < now ? buckets.overdue : buckets.upcoming).map(\.id), [low, high, later])
            }
        }
        func step(_ id: UUID, _ created: Date) -> SelectionStep {
            SelectionStep(id: id, userID: UUID(), companyID: UUID(), type: .interview,
                          customTitle: nil, startsAt: now.addingTimeInterval(10), startsHasTime: true,
                          deadlineAt: nil, deadlineHasTime: false, status: .scheduled, memo: nil,
                          notificationEnabled: false, createdAt: created, updatedAt: created)
        }
        let steps = [step(later, now), step(high, now.addingTimeInterval(-1)), step(low, now.addingTimeInterval(-1))]
        for input in [steps, Array(steps.reversed())] {
            XCTAssertEqual(HomeOrdering.steps(input, relativeTo: now).map(\.id), [low, high, later])
        }
    }

    private func makeTask(title: String, dueAt: Date) -> RecruitTask {
        RecruitTask(
            id: UUID(), userID: UUID(), companyID: nil, title: title, memo: nil,
            dueAt: dueAt, dueHasTime: true, completedAt: nil,
            notificationEnabled: false, createdAt: dueAt, updatedAt: dueAt
        )
    }
}
