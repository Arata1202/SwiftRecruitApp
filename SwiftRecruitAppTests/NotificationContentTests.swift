import XCTest
@testable import SwiftRecruitApp

final class NotificationContentTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    func testFullDateUsesCalculationTimeZoneAcrossYearAndOmitsTimeForDateOnly() {
        let instant = ISO8601DateFormatter().date(from: "2026-12-31T16:05:00Z")!
        XCTAssertEqual(NotificationPlanBuilder.anchorDescription(instant, hasTime: true, calendar: calendar),
                       "2027年1月1日 1:05")
        XCTAssertEqual(NotificationPlanBuilder.anchorDescription(instant, hasTime: false, calendar: calendar),
                       "2027年1月1日")
        var western = calendar
        western.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(NotificationPlanBuilder.anchorDescription(instant, hasTime: true, calendar: western),
                       "2026年12月31日 8:05")
    }

    func testTaskContentIdentifiesCompanyDeadlineAndOwnerWithoutMemo() {
        let now = ISO8601DateFormatter().date(from: "2026-12-30T00:00:00Z")!
        let due = ISO8601DateFormatter().date(from: "2026-12-31T16:05:00Z")!
        let owner = UUID(), company = UUID()
        var task = RecruitTask(id: UUID(), userID: owner, companyID: company, title: "書類を送る",
                               memo: "private memo", dueAt: due, dueHasTime: true, completedAt: nil,
                               notificationEnabled: true, createdAt: now, updatedAt: now)
        var plan = NotificationPlanBuilder.make(steps: [], tasks: [task], companyNames: [company: "テスト企業"],
                                                calendar: calendar, now: now)
        XCTAssertEqual(plan.first?.title, task.title)
        XCTAssertEqual(plan.first?.body, "テスト企業｜期限：2027年1月1日 1:05")
        XCTAssertEqual(plan.first?.userInfo["user_id"], owner.uuidString)
        XCTAssertEqual(plan.first?.identifier, NotificationPlanBuilder.taskIdentifiers(task.id).first)
        XCTAssertFalse(plan.first!.body.contains("private memo"))
        task.companyID = nil
        task.dueAt = nil
        task.dueOn = LocalDate(year: 2027, month: 1, day: 1)
        task.dueHasTime = false
        plan = NotificationPlanBuilder.make(steps: [], tasks: [task], companyNames: [:], calendar: calendar, now: now)
        XCTAssertEqual(plan.first?.body, "期限：2027年1月1日")
    }

    func testSelectionStartAndDeadlineUseTheirOwnAnchorsNotReminderOrEnd() {
        let now = ISO8601DateFormatter().date(from: "2026-12-20T00:00:00Z")!
        let start = ISO8601DateFormatter().date(from: "2027-01-02T01:00:00Z")!
        let deadline = ISO8601DateFormatter().date(from: "2027-01-01T03:30:00Z")!
        let owner = UUID(), company = UUID()
        var step = SelectionStep(id: UUID(), userID: owner, companyID: company, type: .other,
                                 customTitle: "最終確認", startsAt: start, endsAt: start.addingTimeInterval(3600),
                                 startsHasTime: true, deadlineAt: deadline, deadlineHasTime: true,
                                 status: .scheduled, memo: "private memo", notificationEnabled: true,
                                 createdAt: now, updatedAt: now)
        var plan = NotificationPlanBuilder.make(steps: [step], tasks: [], companyNames: [company: "テスト企業"],
                                                calendar: calendar, now: now)
        XCTAssertEqual(Set(plan.map(\.body)), ["テスト企業｜開始：2027年1月2日 10:00", "テスト企業｜期限：2027年1月1日 12:30"])
        XCTAssertEqual(Set(plan.map(\.title)), ["最終確認の予定", "最終確認の締切"])
        XCTAssertTrue(plan.allSatisfy { $0.userInfo["user_id"] == owner.uuidString && !$0.body.contains("private memo") })
        step.startsHasTime = false
        step.startsAt = nil
        step.startsOn = LocalDate(year: 2027, month: 1, day: 2)
        step.deadlineHasTime = false
        step.deadlineAt = nil
        step.deadlineOn = LocalDate(year: 2027, month: 1, day: 1)
        plan = NotificationPlanBuilder.make(steps: [step], tasks: [], companyNames: [company: "テスト企業"],
                                            calendar: calendar, now: now)
        XCTAssertEqual(Set(plan.map(\.body)), ["テスト企業｜開始：2027年1月2日", "テスト企業｜期限：2027年1月1日"])
    }
}
