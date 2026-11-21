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

    func testOverflowUsesSameOrderingAsSchedulerIncludingTies() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let tasks = capacityTasks(now: now, tied: true)
        let plan = NotificationPlanBuilder.assessment(steps: [], tasks: Array(tasks.reversed()), companyNames: [:], now: now)
        XCTAssertEqual(plan.admitted.count, 64)
        XCTAssertEqual(plan.overflow.count, 6)
        XCTAssertEqual(plan.admitted, NotificationPlanBuilder.make(steps: [], tasks: tasks, companyNames: [:], now: now))
        XCTAssertEqual(plan.admitted.map(\.identifier), tasks.prefix(64).flatMap { NotificationPlanBuilder.taskIdentifiers($0.id) })
        XCTAssertEqual(plan.overflow.map(\.identifier), tasks.suffix(6).flatMap { NotificationPlanBuilder.taskIdentifiers($0.id) })
    }

    func testCompletionDeletionAndTimePassingPromoteOverflow() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let tasks = capacityTasks(now: now)
        let target = NotificationPlanBuilder.taskIdentifiers(tasks[64].id)[0]
        var completed = tasks
        completed[0].completedAt = now
        for remaining in [completed, Array(tasks.dropFirst())] {
            let plan = NotificationPlanBuilder.assessment(steps: [], tasks: remaining, companyNames: [:], now: now)
            XCTAssertTrue(plan.admitted.contains { $0.identifier == target })
            XCTAssertEqual(plan.admitted.count, 64)
            XCTAssertEqual(plan.overflow.count, 5)
        }
        let reopened = NotificationPlanBuilder.assessment(steps: [], tasks: tasks, companyNames: [:], now: now.addingTimeInterval(3_601))
        XCTAssertTrue(reopened.admitted.contains { $0.identifier == target })
    }

    @MainActor
    func testFreshStoreAssessmentPreviewLoadingFailureAndReset() async {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let tasks = capacityTasks(now: now)
        let userID = tasks[0].userID
        let store = RecruitStore(repository: nil, notifications: LocalNotificationService())
        store.loadScreenshotData(userID: userID)
        store.selectionSteps = []
        store.tasks = tasks
        store.notificationAuthorizationStatus = .authorized
        let target = tasks[64]
        func description() -> NotificationPlanStatus {
            store.notificationPlanDescription(identifiers: NotificationPlanBuilder.taskIdentifiers(target.id), userID: userID, fallback: "fallback", now: now)
        }
        XCTAssertTrue(description().text.contains("まだ予約されていません"))
        XCTAssertTrue(description().text.contains("空きがあれば予約されます"))
        store.tasks.removeFirst()
        XCTAssertTrue(description().text.contains("通知予定："))
        XCTAssertEqual(description().text.components(separatedBy: "\n").count, 1)
        var draft = RecruitTaskDraft(task: target)
        draft.dueAt = now.addingTimeInterval(500_000)
        let preview = store.taskNotificationPreview(draft: draft, task: target, previewID: UUID(), userID: userID, fallback: "fallback", now: now)
        XCTAssertFalse(preview.text.contains("保存前の通知予定"))
        XCTAssertTrue(preview.text.contains("まだ予約されていません"))
        XCTAssertTrue(description().text.contains("通知予定："))
        store.isLoading = true
        XCTAssertEqual(description(), .loading)
        store.isLoading = false
        store.errorMessage = "failed"
        XCTAssertFalse(description().text.contains("failed"))
        XCTAssertFalse(description().text.contains("最新の変更が反映されていない"))
        await store.reset()
        XCTAssertFalse(description().text.contains("通知予定："))
        XCTAssertFalse(description().text.contains("まだ予約されていません"))
    }

    @MainActor
    func testRemoteCompletionInvalidatesOpenTaskPreview() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let original = capacityTasks(now: now)[0]
        let store = RecruitStore(repository: nil, notifications: LocalNotificationService())
        store.loadScreenshotData(userID: original.userID)
        store.selectionSteps = []
        var completed = original
        completed.completedAt = now
        store.tasks = [completed]
        let status = store.taskNotificationPreview(
            draft: RecruitTaskDraft(task: original), task: original, previewID: UUID(),
            userID: original.userID, fallback: "通知予定：古い日時", now: now
        )
        XCTAssertTrue(status.text.contains("データが変わりました"))
        XCTAssertFalse(status.text.contains("通知予定"))
        XCTAssertFalse(status.text.contains("通知予定："))
        store.tasks = [original]
        let restored = store.taskNotificationPreview(
            draft: RecruitTaskDraft(task: completed), task: completed, previewID: UUID(),
            userID: original.userID, fallback: "完了済み", now: now
        )
        XCTAssertTrue(restored.text.contains("データが変わりました"))
    }

    @MainActor
    func testEditingAtCapacityReplacesInsteadOfAddingPersistedCandidate() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let tasks = Array(capacityTasks(now: now).prefix(64))
        let store = RecruitStore(repository: nil, notifications: LocalNotificationService())
        store.loadScreenshotData(userID: tasks[0].userID)
        store.selectionSteps = []
        store.tasks = tasks
        let task = tasks[63]
        let status = store.taskNotificationPreview(draft: RecruitTaskDraft(task: task), task: task, previewID: UUID(), userID: task.userID, fallback: "fallback", now: now)
        XCTAssertTrue(status.text.contains("通知予定："))
        XCTAssertFalse(status.text.contains("まだ予約されていません"))
        XCTAssertEqual(store.tasks.count, 64)
    }

    @MainActor
    func testSelectionPreviewPromptsOnlyForTheMissingStep() {
        let store = RecruitStore(repository: nil, notifications: LocalNotificationService())
        func preview(userID: UUID?) -> NotificationPlanStatus {
            store.selectionNotificationPreview(draft: SelectionStepDraft(), step: nil, previewID: UUID(),
                                               companyID: nil, userID: userID, fallback: "", now: .now)
        }
        store.isLoading = true
        XCTAssertEqual(preview(userID: nil), .message("通知予定を確認するにはログインしてください。"))
        XCTAssertEqual(preview(userID: UUID()), .message("関連企業を選ぶと、通知予定を確認できます。"))
    }

    @MainActor
    func testNewTaskAndSelectionPreviewsShareGlobalCapacityWithoutMutation() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let tasks = Array(capacityTasks(now: now).prefix(64))
        let userID = tasks[0].userID
        let store = RecruitStore(repository: nil, notifications: LocalNotificationService())
        store.loadScreenshotData(userID: userID)
        store.selectionSteps = []
        store.tasks = tasks
        var taskDraft = RecruitTaskDraft()
        taskDraft.dueAt = now.addingTimeInterval(500_000)
        taskDraft.dueHasTime = true
        let taskText = store.taskNotificationPreview(draft: taskDraft, task: nil, previewID: UUID(), userID: userID, fallback: "fallback", now: now)
        XCTAssertTrue(taskText.text.contains("まだ予約されていません"))
        var stepDraft = SelectionStepDraft()
        stepDraft.hasTime = true
        stepDraft.date = taskDraft.dueAt
        let stepText = store.selectionNotificationPreview(draft: stepDraft, step: nil, previewID: UUID(), companyID: UUID(), userID: userID, fallback: "fallback", now: now)
        XCTAssertTrue(stepText.text.contains("まだ予約されていません"))
        XCTAssertFalse(stepText.text.contains("保存前の通知予定"))
        stepDraft.date = now.addingTimeInterval(4_000)
        let promoted = store.selectionNotificationPreview(draft: stepDraft, step: nil, previewID: UUID(), companyID: UUID(), userID: userID, fallback: "fallback", now: now)
        XCTAssertTrue(promoted.text.contains("通知予定："))
        XCTAssertTrue(store.selectionSteps.isEmpty)
        XCTAssertEqual(store.tasks.count, 64)
    }

    private func capacityTasks(now: Date, tied: Bool = false) -> [RecruitTask] {
        let userID = UUID()
        return (1...70).map { index in
            RecruitTask(
                id: UUID(uuidString: String(format: "30000000-0000-0000-0000-%012d", index))!,
                userID: userID, companyID: nil, title: "ToDo", memo: nil,
                dueAt: now.addingTimeInterval(TimeInterval((tied ? 1 : index) * 3_600)),
                dueHasTime: true, completedAt: nil, notificationEnabled: true,
                createdAt: now, updatedAt: now
            )
        }
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
