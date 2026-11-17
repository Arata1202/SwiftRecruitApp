import XCTest
@testable import SwiftRecruitApp

final class HomeSelectionBucketsTests: XCTestCase {
    func testBoundariesStatusesAndNoDuplicates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_049_600) // UTC noon
        let today = calendar.startOfDay(for: now)
        func step(_ date: Date, timed: Bool = true, status: SelectionStepStatus = .scheduled, deadline: Date? = nil) -> SelectionStep {
            SelectionStep(id: UUID(), userID: UUID(), companyID: UUID(), type: .interview,
                          customTitle: nil, startsAt: date, startsHasTime: timed,
                          deadlineAt: deadline, deadlineHasTime: true, status: status, memo: nil,
                          notificationEnabled: false, createdAt: now, updatedAt: now)
        }
        let past = step(now.addingTimeInterval(-1), deadline: now.addingTimeInterval(60))
        let yesterday = step(today.addingTimeInterval(-1), timed: false)
        let allDayToday = step(today, timed: false)
        let exact = step(now)
        let end = step(now.addingTimeInterval(7 * 86400))
        let beyond = step(now.addingTimeInterval(7 * 86400 + 1))
        let completed = step(now.addingTimeInterval(-1), status: .completed)
        let cancelled = step(now.addingTimeInterval(-1), status: .cancelled)
        let result = HomeSelectionBuckets.make(steps: [past, yesterday, allDayToday, exact, end, beyond, completed, cancelled], relativeTo: now, calendar: calendar)
        XCTAssertEqual(Set(result.past.map(\.id)), Set([yesterday.id]))
        XCTAssertEqual(Set(result.upcoming.map(\.id)), Set([past.id, allDayToday.id, exact.id, end.id]))
        XCTAssertTrue(Set(result.past.map(\.id)).isDisjoint(with: Set(result.upcoming.map(\.id))))
    }
    func testLegacyTodayAllDayAndPastTimedUseSameMilestoneForDisplayAndSorting() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_049_600)
        let today = calendar.startOfDay(for: now)
        func step(start: Date, timed: Bool, deadline: Date) -> SelectionStep {
            SelectionStep(id: UUID(), userID: UUID(), companyID: UUID(), type: .interview,
                          customTitle: nil, startsAt: start, startsHasTime: timed,
                          deadlineAt: deadline, deadlineHasTime: true, status: .scheduled, memo: nil,
                          notificationEnabled: false, createdAt: now, updatedAt: now)
        }
        let legacy = step(start: today, timed: false, deadline: now.addingTimeInterval(-60))
        let earlierPast = step(start: now.addingTimeInterval(-120), timed: true, deadline: now.addingTimeInterval(60))
        let result = HomeSelectionBuckets.make(steps: [legacy, earlierPast], relativeTo: now, calendar: calendar)
        XCTAssertTrue(result.past.isEmpty)
        let displayed = HomeSelectionMilestones.earliestPast(for: legacy, relativeTo: now, calendar: calendar)
        XCTAssertEqual(displayed?.date, now.addingTimeInterval(-60))
        XCTAssertEqual(displayed?.kind, .deadline)
        XCTAssertEqual(result.upcoming.map(\.id), [legacy.id, earlierPast.id])
    }

    func testInjectedCalendarControlsEligibleOrderingAndMixedBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!
        func step(start: Date?, day: Int?, deadline: Date?) -> SelectionStep {
            SelectionStep(id: UUID(), userID: UUID(), companyID: UUID(), type: .interview,
                          customTitle: nil, startsAt: start,
                          startsOn: day.map { LocalDate(year: 2026, month: 1, day: $0) },
                          startsHasTime: day == nil, deadlineAt: deadline, deadlineHasTime: true,
                          status: .scheduled, memo: nil, notificationEnabled: false, createdAt: now, updatedAt: now)
        }
        let localTomorrow = step(start: nil, day: 2, deadline: nil)
        let timedBefore = step(start: now.addingTimeInterval(11 * 3600), day: nil, deadline: nil)
        let atBoundary = step(start: now.addingTimeInterval(-1), day: nil, deadline: now.addingTimeInterval(7 * 86400))
        let beyondBoundary = step(start: now.addingTimeInterval(-2), day: nil, deadline: now.addingTimeInterval(7 * 86400 + 1))
        let result = HomeSelectionBuckets.make(steps: [localTomorrow, timedBefore, atBoundary, beyondBoundary], relativeTo: now, calendar: calendar)
        XCTAssertEqual(result.upcoming.map(\.id), [timedBefore.id, localTomorrow.id, atBoundary.id])
        XCTAssertEqual(result.past.map(\.id), [beyondBoundary.id])
    }

}
