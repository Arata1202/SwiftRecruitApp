import XCTest
@testable import SwiftRecruitApp

final class NotificationCopyTests: XCTestCase {
    func testPastTimeCopyDistinguishesEditingFromDeliveryHistory() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        for fireDate in [now.addingTimeInterval(-1), now] {
            XCTAssertEqual(NotificationScheduleCalculator.reminderDescription(fireDate, now: now), "通知時刻を過ぎています")
            XCTAssertEqual(NotificationScheduleCalculator.reminderDescription(fireDate, now: now, isPreview: true), "通知時刻を過ぎているため、この設定では通知されません。")
            XCTAssertEqual(TaskNotificationDescription.text(enabled: true, isCompleted: false, dueAt: fireDate, hasTime: true, now: now), "通知時刻を過ぎています")
            XCTAssertEqual(TaskNotificationDescription.text(enabled: true, isCompleted: false, dueAt: fireDate, hasTime: true, now: now, isPreview: true), "通知時刻を過ぎているため、この設定では通知されません。")
            var draft = SelectionStepDraft()
            draft.notificationEnabled = true
            draft.hasTime = true
            draft.date = fireDate
            draft.notificationTimedPreset = .atTime
            XCTAssertEqual(draft.notificationDescription(now: now, isPreview: false), "通知時刻を過ぎています")
            XCTAssertEqual(draft.notificationDescription(now: now), "通知時刻を過ぎているため、この設定では通知されません。")
        }
        XCTAssertTrue(NotificationScheduleCalculator.reminderDescription(now.addingTimeInterval(1), now: now, isPreview: true).hasPrefix("保存後の通知予定："))
        XCTAssertTrue(NotificationScheduleCalculator.reminderDescription(now.addingTimeInterval(1), now: now).hasPrefix("通知予定："))
    }

    @MainActor
    func testUnloadedLoadingAndWrongOwnerRemainDistinct() {
        let store = RecruitStore(repository: nil, notifications: LocalNotificationService())
        let userID = UUID()
        func message(_ owner: UUID?) -> String {
            store.notificationPlanDescription(identifiers: [], userID: owner, fallback: "fallback")
        }
        XCTAssertTrue(message(userID).contains("まだ読み込まれていません"))
        XCTAssertTrue(message(userID).contains("一覧を更新"))
        store.isLoading = true
        XCTAssertEqual(message(userID), "通知予定を確認中…")
        XCTAssertTrue(message(nil).contains("ログイン"))
        store.loadScreenshotData(userID: UUID())
        XCTAssertTrue(message(userID).contains("ログイン状態"))
        XCTAssertFalse(message(userID).contains("確認中"))
    }

    @MainActor
    func testErrorReasonAndRecoverySurviveFallbackAndPreview() {
        let store = RecruitStore(repository: nil, notifications: LocalNotificationService())
        let userID = UUID()
        store.errorMessage = "通知が許可されていません。iOSの設定を確認してください。"
        let unloaded = store.notificationPlanDescription(identifiers: [], userID: userID, fallback: "fallback")
        XCTAssertTrue(unloaded.contains(store.errorMessage!))
        store.loadScreenshotData(userID: userID)
        store.selectionSteps = []
        store.tasks = []
        for preview in [false, true] {
            let text = store.notificationPlanDescription(identifiers: [], userID: userID, fallback: "通知時刻を過ぎています", isPreview: preview)
            XCTAssertTrue(text.contains("通知時刻を過ぎています"))
            XCTAssertTrue(text.contains(store.errorMessage!))
            XCTAssertTrue(text.contains("一覧を更新し、もう一度"))
            XCTAssertFalse(text.contains("確認中"))
        }
    }

    @MainActor
    func testNewPreviewsUseSaveAfterCopyWithoutChangingStoredRecords() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let store = RecruitStore(repository: nil, notifications: LocalNotificationService())
        let userID = UUID()
        store.loadScreenshotData(userID: userID)
        store.selectionSteps = []
        store.tasks = []
        var task = RecruitTaskDraft()
        task.notificationEnabled = true
        task.dueHasTime = true
        task.dueAt = now.addingTimeInterval(86_400)
        var step = SelectionStepDraft()
        step.notificationEnabled = true
        step.hasTime = true
        step.date = task.dueAt
        let previews = [
            store.taskNotificationPreview(draft: task, task: nil, previewID: UUID(), userID: userID, fallback: "fallback", now: now),
            store.selectionNotificationPreview(draft: step, step: nil, previewID: UUID(), companyID: UUID(), userID: userID, fallback: "fallback", now: now)
        ]
        for text in previews {
            XCTAssertTrue(text.hasPrefix("保存後の通知予定："))
            XCTAssertFalse(text.contains("保存前"))
            XCTAssertEqual(text.components(separatedBy: "\n").count, 1)
        }
        XCTAssertTrue(store.tasks.isEmpty)
        XCTAssertTrue(store.selectionSteps.isEmpty)
        store.isLoading = true
        XCTAssertEqual(store.taskNotificationPreview(draft: task, task: nil, previewID: UUID(), userID: userID, fallback: "fallback", now: now), "通知予定を確認中…")
        XCTAssertTrue(store.selectionNotificationPreview(draft: step, step: nil, previewID: UUID(), companyID: nil, userID: userID, fallback: "fallback", now: now).contains("企業を選ぶ"))
    }
}
