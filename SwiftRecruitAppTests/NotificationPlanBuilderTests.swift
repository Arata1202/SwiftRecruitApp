import XCTest
@testable import SwiftRecruitApp

final class NotificationPlanBuilderTests: XCTestCase {
    func testKeepsOnlyTheNearestSixtyFourNotifications() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let userID = UUID()
        let tasks = (1...70).map { index in
            RecruitTask(
                id: UUID(uuidString: String(format: "30000000-0000-0000-0000-%012d", index))!,
                userID: userID,
                companyID: nil,
                title: "ToDo \(index)",
                memo: nil,
                dueAt: now.addingTimeInterval(TimeInterval(index * 3_600)),
                dueHasTime: true,
                completedAt: nil,
                notificationEnabled: true,
                createdAt: now,
                updatedAt: now
            )
        }

        let result = NotificationPlanBuilder.make(
            steps: [],
            tasks: tasks,
            companyNames: [:],
            now: now
        )

        XCTAssertEqual(result.count, NotificationPlanBuilder.maximumPendingCount)
        XCTAssertEqual(result.first?.title, "ToDo 1")
        XCTAssertEqual(result.last?.title, "ToDo 64")
    }

    func testExcludesCompletedAndDisabledItems() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let completed = makeTask(
            title: "完了",
            dueAt: now.addingTimeInterval(3_600),
            completedAt: now,
            notificationEnabled: true
        )
        let disabled = makeTask(
            title: "通知なし",
            dueAt: now.addingTimeInterval(7_200),
            completedAt: nil,
            notificationEnabled: false
        )

        XCTAssertTrue(
            NotificationPlanBuilder.make(
                steps: [],
                tasks: [completed, disabled],
                companyNames: [:],
                now: now
            ).isEmpty
        )
    }

    private func makeTask(
        title: String,
        dueAt: Date,
        completedAt: Date?,
        notificationEnabled: Bool
    ) -> RecruitTask {
        RecruitTask(
            id: UUID(),
            userID: UUID(),
            companyID: nil,
            title: title,
            memo: nil,
            dueAt: dueAt,
            dueHasTime: true,
            completedAt: completedAt,
            notificationEnabled: notificationEnabled,
            createdAt: dueAt,
            updatedAt: dueAt
        )
    }
}
