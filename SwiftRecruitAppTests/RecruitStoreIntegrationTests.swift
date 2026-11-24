import Foundation
import UserNotifications
import XCTest
@testable import SwiftRecruitApp

@MainActor
final class RecruitStoreIntegrationTests: XCTestCase {
    func testScreenshotDataSurvivesForcedAndForegroundRefresh() async {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let userID = ScreenshotData.userID
        context.store.loadScreenshotData(userID: userID)
        let companies = context.store.companies.map(\.id)

        await context.store.reload(userID: userID, force: true)
        _ = await context.store.reloadIfStale(userID: userID)

        XCTAssertFalse(companies.isEmpty)
        XCTAssertEqual(context.store.companies.map(\.id), companies)
        XCTAssertNil(context.store.errorMessage)
    }

    func testInitialOfflineRetryKeepsAuthenticatedPresentationHostAvailable() async {
        let repository = TaskRestoreRepository()
        let context = makeContext(repository: repository)
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let userID = UUID()
        await repository.setFetchError(URLError(.notConnectedToInternet))
        await context.store.reload(userID: userID, force: true)
        XCTAssertNil(context.store.loadedUserID)
        XCTAssertNotNil(context.store.loadErrorMessage)
        let failure = context.store.notificationPlanDescription(identifiers: [], userID: userID, fallback: "fallback")
        XCTAssertTrue(failure.text.contains(context.store.loadErrorMessage!))
        XCTAssertTrue(failure.text.contains("もう一度お試しください"))
        XCTAssertNotEqual(failure, .loading)
        await repository.suspendNextFetch()
        let retry = Task { await context.store.reload(userID: userID, force: true) }
        await repository.waitForFetch()
        XCTAssertTrue(context.store.isLoading)
        XCTAssertEqual(context.store.notificationPlanDescription(identifiers: [], userID: userID, fallback: "fallback"), .loading)
        // RootView must keep MainTabView and its route sheet during the retry.
        XCTAssertFalse(context.store.loadedUserID != userID && context.store.loadErrorMessage == nil)
        await repository.finishFetch()
        await retry.value
        XCTAssertNotNil(context.store.loadErrorMessage)
        await repository.setFetchError(nil)
        let success = Task { await context.store.reload(userID: userID, force: true) }
        await context.notifications.waitForAuthorizationCheck()
        XCTAssertEqual(context.store.loadedUserID, userID)
        XCTAssertNil(context.store.loadErrorMessage)
        await context.notifications.finishAuthorizationCheck()
        await success.value
    }

    func testNotificationPlanKeepsRefreshFailureUntilDataReloads() async throws {
        let repository = TaskRestoreRepository()
        let context = makeContext(repository: repository)
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let task = makeTask()
        await repository.setFetchedItems(steps: [], tasks: [task])
        func reload() async {
            let reload = Task { await context.store.reload(userID: task.userID, force: true) }
            await context.notifications.waitForAuthorizationCheck()
            await context.notifications.finishAuthorizationCheck()
            await reload.value
        }
        func description() -> String {
            context.store.notificationPlanDescription(
                identifiers: NotificationPlanBuilder.taskIdentifiers(task.id), userID: task.userID, fallback: ""
            ).text
        }

        await reload()
        let original = description()
        XCTAssertTrue(original.contains("通知予定："))
        await repository.setFetchError(URLError(.notConnectedToInternet))
        await context.store.reload(userID: task.userID, force: true)
        let reloadError = try XCTUnwrap(context.store.errorMessage)
        context.store.errorMessage = nil
        XCTAssertTrue(description().contains(reloadError))
        XCTAssertTrue(description().contains("一覧を更新"))
        await repository.setFetchError(nil)
        await reload()
        XCTAssertEqual(description(), original)
    }

    func testNotificationRouteReloadAuthorityDoesNotAdvanceOnFailureOrSkippedLoad() async {
        let repository = TaskRestoreRepository()
        let context = makeContext(repository: repository)
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let userID = UUID()
        let initial = context.store.successfulReloadRevision
        await repository.setFetchError(URLError(.notConnectedToInternet))
        await context.store.reload(userID: userID, force: true)
        XCTAssertEqual(context.store.successfulReloadRevision, initial)
        await repository.setFetchError(nil)
        let reload = Task { await context.store.reload(userID: userID, force: true) }
        await context.notifications.waitForAuthorizationCheck()
        XCTAssertEqual(context.store.successfulReloadRevision, initial + 1)
        await context.notifications.finishAuthorizationCheck()
        await reload.value
        await context.store.reload(userID: userID)
        XCTAssertEqual(context.store.successfulReloadRevision, initial + 1)
        await repository.setFetchError(URLError(.notConnectedToInternet))
        await context.store.reload(userID: userID, force: true)
        XCTAssertEqual(context.store.successfulReloadRevision, initial + 1)
        XCTAssertEqual(context.store.loadedUserID, userID)
    }

    func testNotificationRouteReloadAuthorityIgnoresOldSessionCompletion() async {
        let repository = TaskRestoreRepository()
        let context = makeContext(repository: repository)
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        await repository.suspendNextFetch()
        let reload = Task { await context.store.reload(userID: UUID(), force: true) }
        await repository.waitForFetch()
        await context.store.reset()
        await repository.finishFetch()
        await reload.value
        XCTAssertEqual(context.store.successfulReloadRevision, 0)
        XCTAssertNil(context.store.loadedUserID)
    }

    func testAuthoritativeReloadRemovesOnlyDeletedAndTerminalAccountItems() async {
        let repository = TaskRestoreRepository()
        let context = makeContext(repository: repository)
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let userID = UUID()
        let deleted = makeTask(userID: userID)
        var completed = makeTask(userID: userID)
        completed.completedAt = Date()
        var overdue = makeTask(userID: userID)
        overdue.dueAt = Date().addingTimeInterval(-3600)
        var disabled = makeTask(userID: userID)
        disabled.notificationEnabled = false
        let otherAccount = makeTask()
        let deletedStep = makeStep(companyID: UUID(), userID: userID)
        var cancelled = makeStep(companyID: UUID(), userID: userID)
        cancelled.status = .cancelled
        var finished = makeStep(companyID: UUID(), userID: userID)
        finished.status = .completed
        let scheduled = makeStep(companyID: UUID(), userID: userID)
        context.store.tasks = [deleted, completed, overdue, disabled, otherAccount]
        context.store.selectionSteps = [deletedStep, cancelled, finished, scheduled]
        await repository.setFetchedItems(steps: [cancelled, finished, scheduled], tasks: [completed, overdue, disabled])
        let reload = Task { await context.store.reload(userID: userID) }
        await context.notifications.waitForAuthorizationCheck()
        let removed = await context.notifications.removedDeliveredIdentifiers()
        let expected = [deleted, completed].flatMap { NotificationPlanBuilder.taskIdentifiers($0.id) }
            + [deletedStep, cancelled, finished].flatMap { NotificationPlanBuilder.selectionIdentifiers($0.id) }
        XCTAssertEqual(Set(removed), Set(expected))
        await context.notifications.finishAuthorizationCheck()
        await reload.value
    }

    func testColdReloadRemovesDeliveredRemindersOnlyForMissingItemsOfCurrentUser() async {
        let repository = TaskRestoreRepository()
        let context = makeContext(repository: repository)
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let deleted = makeTask()
        let kept = makeTask(userID: deleted.userID)
        let other = makeTask()
        let delivered = [deleted, kept, other].map { task in
            let content = UNMutableNotificationContent()
            content.userInfo = ["kind": "task", "item_id": task.id.uuidString, "user_id": task.userID.uuidString]
            return UNNotificationRequest(identifier: "task-" + task.id.uuidString, content: content, trigger: nil)
        }
        await context.notifications.setDelivered(delivered)
        await repository.setFetchedItems(steps: [], tasks: [kept])
        let reload = Task { await context.store.reload(userID: deleted.userID) }
        await context.notifications.waitForAuthorizationCheck()
        let removed = await context.notifications.removedDeliveredIdentifiers()
        XCTAssertEqual(removed, NotificationPlanBuilder.taskIdentifiers(deleted.id))
        await context.notifications.finishAuthorizationCheck()
        await reload.value
    }

    func testPartialReloadFailureDoesNotCleanDeliveredNotifications() async {
        let repository = TaskRestoreRepository()
        let context = makeContext(repository: repository)
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let task = makeTask()
        context.store.tasks = [task]
        await repository.setFetchError(URLError(.notConnectedToInternet))
        await context.store.reload(userID: task.userID)
        let removed = await context.notifications.removedDeliveredIdentifiers()
        XCTAssertTrue(removed.isEmpty)
        XCTAssertEqual(context.store.tasks.map(\.id), [task.id])
    }

    func testStaleReloadAndSessionDoNotCleanDeliveredNotifications() async {
        for staleSession in [true, false] {
            let client = IntegrationNotificationClient()
            let task = makeTask()
            let coordinator = RecruitNotificationCoordinator(
                notifications: LocalNotificationService(client: client),
                isCurrentSession: { _ in !staleSession },
                companies: { [] }, selectionSteps: { [] }, tasks: { [] },
                updateAuthorization: { _ in },
                reportError: { _ in XCTFail("Unexpected error") }
            )
            await coordinator.removeDeliveredAfterReload(
                generation: 1, userID: task.userID, previousSteps: [], previousTasks: [task],
                isCurrentReload: { staleSession }
            )
            let removed = await client.removedDeliveredIdentifiers()
            XCTAssertTrue(removed.isEmpty)
        }
    }

    func testNotificationAuthorizationFinishingAfterResetDoesNotScheduleOldSession() async {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        context.store.tasks = [makeTask()]
        let reconciliation = Task { await context.store.rescheduleAllNotificationsIfAuthorized() }
        await context.notifications.waitForAuthorizationCheck()

        await context.store.reset()
        await context.notifications.finishAuthorizationCheck()
        await reconciliation.value

        let requests = await context.notifications.scheduledRequests()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertNil(context.store.errorMessage)
    }

    func testNotificationPlanTracksPermissionChangesOnReturnToApp() async {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let task = makeTask()
        context.store.loadScreenshotData(userID: task.userID)
        context.store.tasks = [task]
        for permission in [UNAuthorizationStatus.notDetermined, .denied, .authorized] {
            let refresh = Task { await context.store.rescheduleAllNotificationsIfAuthorized() }
            await context.notifications.waitForAuthorizationCheck()
            await context.notifications.finishAuthorizationCheck(permission)
            await refresh.value
            let status = context.store.notificationPlanDescription(
                identifiers: NotificationPlanBuilder.taskIdentifiers(task.id), userID: task.userID, fallback: "期限なし"
            )
            if permission == .notDetermined {
                XCTAssertEqual(status, .message("通知を受け取るには、アプリの設定画面で通知を許可してください。"))
                let preview = context.store.taskNotificationPreview(
                    draft: RecruitTaskDraft(task: task), task: task, previewID: UUID(),
                    userID: task.userID, fallback: "", now: Date()
                )
                XCTAssertTrue(preview.text.contains("保存後の通知予定："))
                XCTAssertTrue(preview.text.contains("許可してください"))
            } else if permission == .denied {
                XCTAssertEqual(status, .message("iOSの設定で通知がオフになっています。"))
            } else {
                XCTAssertTrue(status.text.contains("通知予定："))
            }
        }
    }

    func testNotificationReconciliationReadsStateAfterAuthorizationSuspends() async {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let company = makeCompany()
        context.store.companies = [company]
        context.store.tasks = [makeTask()]
        let reconciliation = Task { await context.store.rescheduleAllNotificationsIfAuthorized() }
        await context.notifications.waitForAuthorizationCheck()

        var renamed = company
        renamed.name = "変更後の企業"
        var replacement = makeTask()
        replacement.companyID = company.id
        replacement.title = "変更後のタスク"
        context.store.companies = [renamed]
        context.store.tasks = [replacement]
        await context.notifications.finishAuthorizationCheck()
        await reconciliation.value

        let requests = await context.notifications.scheduledRequests()
        XCTAssertEqual(requests.map(\.identifier), NotificationPlanBuilder.taskIdentifiers(replacement.id))
        XCTAssertEqual(requests.first?.content.title, "変更後のタスク")
        let due = NotificationPlanBuilder.anchorDescription(replacement.dueAt!, hasTime: replacement.dueHasTime, calendar: .current)
        XCTAssertEqual(requests.first?.content.body, "変更後の企業｜期限：\(due)")
    }

    func testNotificationFailurePersistsAfterAlertUntilSuccessfulRetry() async {
        let context = makeContext(repository: TaskRestoreRepository())
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let task = makeTask()
        context.store.loadScreenshotData(userID: task.userID)
        context.store.tasks = [task]
        func description() -> NotificationPlanStatus {
            context.store.notificationPlanDescription(
                identifiers: NotificationPlanBuilder.taskIdentifiers(task.id), userID: task.userID, fallback: ""
            )
        }
        func refresh() async {
            let refresh = Task { await context.store.rescheduleAllNotificationsIfAuthorized() }
            await context.notifications.waitForAuthorizationCheck()
            await context.notifications.finishAuthorizationCheck()
            await refresh.value
        }

        await context.notifications.setSchedulingFails(true)
        let save = Task { await context.store.setTaskCompleted(task, completed: false) }
        await context.notifications.waitForAuthorizationCheck()
        await context.notifications.finishAuthorizationCheck()
        let saved = await save.value
        XCTAssertTrue(saved)
        XCTAssertEqual(context.store.errorMessage, "データは保存されましたが、通知を設定できませんでした。iOSの通知設定を確認してください。")
        context.store.errorMessage = nil
        XCTAssertEqual(description(), .message("通知予定を更新できませんでした。一覧を更新して、もう一度お試しください。"))

        // Leave the next failure alert open while the app retries.
        await refresh()
        XCTAssertEqual(context.store.errorMessage, "通知予定を更新できませんでした。iOSの通知設定を確認してください。")
        await context.notifications.setSchedulingFails(false)
        await refresh()
        XCTAssertNil(context.store.errorMessage)
        XCTAssertTrue(description().text.contains("通知予定："))
        XCTAssertFalse(description().text.contains("更新できませんでした"))

        // Even an identical message from another operation belongs to that operation.
        await context.notifications.setSchedulingFails(true)
        await refresh()
        let otherError = NotificationReconciliationTrigger.refresh.failureMessage
        context.store.errorMessage = otherError
        await context.notifications.setSchedulingFails(false)
        await refresh()
        XCTAssertEqual(context.store.errorMessage, otherError)
        XCTAssertFalse(description().text.contains(otherError))
    }

    func testStaleNotificationGenerationDoesNotEvenCheckAuthorization() async throws {
        let client = IntegrationNotificationClient()
        let coordinator = RecruitNotificationCoordinator(
            notifications: LocalNotificationService(client: client),
            isCurrentSession: { _ in false },
            companies: { [] },
            selectionSteps: { [] },
            tasks: { [] },
            updateAuthorization: { _ in },
            reportError: { _ in XCTFail("古いセッションのエラーを表示しない") }
        )

        let applied = try await coordinator.reconcile(generation: 1, trigger: .saved(requestPermission: true))
        XCTAssertFalse(applied)

        let didCheck = await client.didCheckAuthorization()
        XCTAssertFalse(didCheck)
    }

    func testCompleteThenRestoreUsesSavedVersionAndReschedulesNotification() async throws {
        let repository = TaskRestoreRepository()
        let context = makeContext(repository: repository)
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let task = makeTask()
        context.store.tasks = [task]
        let completion = Task { await context.store.setTaskCompleted(task, completed: true) }
        await context.notifications.waitForAuthorizationCheck()
        await context.notifications.finishAuthorizationCheck()
        let completed = await completion.value
        XCTAssertTrue(completed)
        let saved = try XCTUnwrap(context.store.tasks.first)
        XCTAssertTrue(saved.isCompleted)
        XCTAssertEqual(saved.version, task.version + 1)
        let restore = Task { await context.store.setTaskCompleted(saved, completed: false) }
        await context.notifications.waitForNextAuthorizationCheck()
        await context.notifications.finishAuthorizationCheck()
        let restored = await restore.value
        XCTAssertTrue(restored)
        XCTAssertFalse(try XCTUnwrap(context.store.tasks.first).isCompleted)
        let versions = await repository.inputVersions()
        XCTAssertEqual(versions, [task.version, saved.version])
        let requests = await context.notifications.scheduledRequests()
        XCTAssertEqual(requests.map(\.identifier), NotificationPlanBuilder.taskIdentifiers(task.id))
    }

    func testRestoreSaveFailureLeavesCompletedTaskAndReportsError() async {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        var task = makeTask()
        task.completedAt = Date()
        context.store.tasks = [task]
        let restored = await context.store.setTaskCompleted(task, completed: false)
        XCTAssertFalse(restored)
        XCTAssertTrue(context.store.tasks[0].isCompleted)
        XCTAssertNotNil(context.store.errorMessage)
        let requests = await context.notifications.scheduledRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testSelectionConflictPreservesLocalStateAndReportsError() async {
        let repository = TaskRestoreRepository()
        await repository.failSelectionWithConflict()
        let context = makeContext(repository: repository)
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let step = makeStep(companyID: UUID())
        context.store.selectionSteps = [step]

        let result = await context.store.setSelectionStepStatus(step, status: .completed)

        XCTAssertNil(result)
        XCTAssertNil(context.store.savingSelectionStepID)
        XCTAssertEqual(context.store.selectionSteps.first?.status, .scheduled)
        XCTAssertEqual(context.store.selectionSteps.first?.version, step.version)
        XCTAssertEqual(context.store.errorMessage, RepositoryError.conflict.localizedDescription)
        let requests = await context.notifications.scheduledRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testSelectionCompletionAndUndoRestoreNotifications() async throws {
        let repository = TaskRestoreRepository()
        let context = makeContext(repository: repository)
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let company = makeCompany()
        var step = makeStep(companyID: company.id)
        step.notificationEnabled = true
        step.startsAt = Date().addingTimeInterval(5 * 86_400)
        step.deadlineAt = Date().addingTimeInterval(4 * 86_400)
        context.store.companies = [company]
        context.store.selectionSteps = [step]

        let initialSync = Task { await context.store.rescheduleAllNotificationsIfAuthorized() }
        await context.notifications.waitForAuthorizationCheck()
        await context.notifications.finishAuthorizationCheck()
        await initialSync.value
        let initialRequests = await context.notifications.scheduledRequests()
        XCTAssertEqual(Set(initialRequests.map(\.identifier)), Set(NotificationPlanBuilder.selectionIdentifiers(step.id)))

        let complete = Task { await context.store.setSelectionStepStatus(step, status: .completed) }
        await context.notifications.waitForNextAuthorizationCheck()
        XCTAssertEqual(context.store.savingSelectionStepID, step.id)
        await context.notifications.finishAuthorizationCheck()
        let completionResult = await complete.value
        XCTAssertNil(context.store.savingSelectionStepID)
        let completed = try XCTUnwrap(completionResult)
        XCTAssertEqual(completed.status, .completed)
        XCTAssertTrue(completed.notificationEnabled)
        XCTAssertEqual(completed.version, step.version + 1)
        let completedRequests = await context.notifications.scheduledRequests()
        XCTAssertTrue(completedRequests.isEmpty)

        let undo = Task { await context.store.setSelectionStepStatus(completed, status: .scheduled) }
        await context.notifications.waitForNextAuthorizationCheck()
        await context.notifications.finishAuthorizationCheck()
        let undoResult = await undo.value
        let restored = try XCTUnwrap(undoResult)
        XCTAssertEqual(restored.status, .scheduled)
        XCTAssertTrue(restored.notificationEnabled)
        XCTAssertEqual(restored.version, completed.version + 1)
        let versions = await repository.selectionInputVersions()
        XCTAssertEqual(versions, [step.version, completed.version])
        let restoredRequests = await context.notifications.scheduledRequests()
        XCTAssertEqual(Set(restoredRequests.map(\.identifier)), Set(NotificationPlanBuilder.selectionIdentifiers(step.id)))


    }

    func testSelectionStatusRoundTripsKeepNotificationPreference() async throws {
        for enabled in [false, true] {
            for inactiveStatus: SelectionStepStatus in [.completed, .cancelled] {
                let repository = TaskRestoreRepository()
                let context = makeContext(repository: repository)
                defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
                let company = makeCompany()
                var step = makeStep(companyID: company.id)
                step.notificationEnabled = enabled
                step.startsAt = Date().addingTimeInterval(5 * 86_400)
                step.deadlineAt = Date().addingTimeInterval(4 * 86_400)
                context.store.companies = [company]
                context.store.selectionSteps = [step]

                let sync = Task { await context.store.rescheduleAllNotificationsIfAuthorized() }
                await context.notifications.waitForAuthorizationCheck()
                await context.notifications.finishAuthorizationCheck()
                await sync.value
                let initial = await context.notifications.scheduledRequests()
                XCTAssertEqual(Set(initial.map(\.identifier)), enabled ? Set(NotificationPlanBuilder.selectionIdentifiers(step.id)) : [])

                let deactivate = Task { await context.store.setSelectionStepStatus(step, status: inactiveStatus) }
                await context.notifications.waitForNextAuthorizationCheck()
                await context.notifications.finishAuthorizationCheck()
                let inactiveResult = await deactivate.value
                let inactive = try XCTUnwrap(inactiveResult)
                XCTAssertEqual(inactive.status, inactiveStatus)
                XCTAssertEqual(inactive.notificationEnabled, enabled)
                let inactiveRequests = await context.notifications.scheduledRequests()
                XCTAssertTrue(inactiveRequests.isEmpty)

                let reactivate = Task { await context.store.setSelectionStepStatus(inactive, status: .scheduled) }
                await context.notifications.waitForNextAuthorizationCheck()
                await context.notifications.finishAuthorizationCheck()
                let restoredResult = await reactivate.value
                let restored = try XCTUnwrap(restoredResult)
                XCTAssertEqual(restored.notificationEnabled, enabled)
                XCTAssertEqual(restored.version, inactive.version + 1)
                let versions = await repository.selectionInputVersions()
                XCTAssertEqual(versions, [step.version, inactive.version])
                let requests = await context.notifications.scheduledRequests()
                XCTAssertEqual(Set(requests.map(\.identifier)), enabled ? Set(NotificationPlanBuilder.selectionIdentifiers(step.id)) : [])
            }
        }
    }

    func testInvalidCompanyURLNeverReachesRepositoryOrClearsStoredURL() async {
        // The fixture traps if a company mutation reaches the repository.
        let context = makeContext(repository: TaskRestoreRepository())
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        var company = makeCompany()
        company.url = "https://realunivlog.com"
        context.store.companies = [company]
        var draft = CompanyDraft(company: company)
        draft.url = "realunivlog"
        let updated = await context.store.updateCompany(company, draft: draft)
        XCTAssertNil(updated)
        XCTAssertEqual(context.store.companies.first?.url, company.url)
        XCTAssertNotNil(context.store.errorMessage)
        let created = await context.store.createCompany(userID: company.userID, draft: draft)
        XCTAssertNil(created)
        XCTAssertEqual(context.store.companies.count, 1)
        XCTAssertFalse(context.store.isSaving)
    }

    func testDeletionSuccessAndFailureAcknowledgementForBothRecordKinds() async {
        for isTask in [true, false] {
            for shouldFail in [true, false] {
                let repository = TaskRestoreRepository()
                await repository.setDeletionFailure(shouldFail)
                let context = makeContext(repository: repository)
                defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
                let task = makeTask()
                let step = makeStep(companyID: UUID())
                context.store.tasks = [task]
                context.store.selectionSteps = [step]
                let deletion = Task {
                    if isTask { return await context.store.deleteTask(task) }
                    return await context.store.deleteSelectionStep(step)
                }
                if !shouldFail {
                    await context.notifications.waitForAuthorizationCheck()
                    await context.notifications.finishAuthorizationCheck()
                }
                let success = await deletion.value
                XCTAssertEqual(success, !shouldFail)
                XCTAssertEqual(context.store.tasks.contains { $0.id == task.id }, !isTask || shouldFail)
                XCTAssertEqual(context.store.selectionSteps.contains { $0.id == step.id }, isTask || shouldFail)
                XCTAssertEqual(context.store.errorMessage != nil, shouldFail)
            }
        }
    }

    func testSessionResetDuringDeletionNotificationsNeverAcknowledgesOldSuccess() async {
        for isTask in [true, false] {
            let context = makeContext(repository: TaskRestoreRepository())
            defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
            let task = makeTask()
            let step = makeStep(companyID: UUID())
            context.store.tasks = [task]
            context.store.selectionSteps = [step]
            let deletion = Task {
                if isTask { return await context.store.deleteTask(task) }
                return await context.store.deleteSelectionStep(step)
            }
            await context.notifications.waitForAuthorizationCheck()
            await context.store.reset()
            await context.notifications.finishAuthorizationCheck()
            let success = await deletion.value
            XCTAssertFalse(success)
            XCTAssertNil(context.store.errorMessage)
        }
    }

    func testEmptyReloadRetainsLoadedStateWhileRefreshing() async {
        let repository = TaskRestoreRepository()
        let context = makeContext(repository: repository)
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let userID = UUID()
        let initial = Task { await context.store.reload(userID: userID) }
        await context.notifications.waitForAuthorizationCheck()
        await context.notifications.finishAuthorizationCheck()
        await initial.value
        await repository.suspendNextFetch()
        let refresh = Task { await context.store.reload(userID: userID, force: true) }
        await repository.waitForFetch()
        XCTAssertTrue(context.store.isLoading)
        XCTAssertEqual(context.store.loadedUserID, userID)
        XCTAssertTrue(context.store.companies.isEmpty)
        await repository.finishFetch()
        await context.notifications.waitForAuthorizationCheck()
        await context.notifications.finishAuthorizationCheck()
        await refresh.value
        XCTAssertFalse(context.store.isLoading)
        XCTAssertNil(context.store.errorMessage)
    }

    func testCancelledReloadsDoNotShowErrorsOrReplaceRetainedData() async {
        for error: Error in [CancellationError(), URLError(.cancelled)] {
            let repository = TaskRestoreRepository()
            let context = makeContext(repository: repository)
            defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
            let task = makeTask()
            context.store.tasks = [task]
            await repository.setFetchError(error)
            await context.store.reload(userID: UUID(), force: true)
            XCTAssertEqual(context.store.tasks.map(\.id), [task.id])
            XCTAssertNil(context.store.errorMessage)
            XCTAssertNil(context.store.loadErrorMessage)
            XCTAssertNil(context.store.lastSuccessfulReloadAt)
            XCTAssertFalse(context.store.isLoading)
            let removed = await context.notifications.removedDeliveredIdentifiers()
            XCTAssertTrue(removed.isEmpty)
        }
    }

    func testRealReloadFailuresStillReportInitialAndRefreshErrors() async {
        for retainsData in [false, true] {
            let repository = TaskRestoreRepository()
            let context = makeContext(repository: repository)
            defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
            if retainsData { context.store.tasks = [makeTask()] }
            await repository.setFetchError(URLError(.notConnectedToInternet))
            await context.store.reload(userID: UUID(), force: true)
            XCTAssertNotNil(retainsData ? context.store.errorMessage : context.store.loadErrorMessage)
            XCTAssertEqual(context.store.tasks.count, retainsData ? 1 : 0)
            XCTAssertFalse(context.store.isLoading)
        }
    }

    func testResetDuringReloadRejectsOldSessionResult() async {
        let repository = TaskRestoreRepository()
        let context = makeContext(repository: repository)
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        await repository.suspendNextFetch()
        let reload = Task { await context.store.reload(userID: UUID()) }
        await repository.waitForFetch()
        XCTAssertTrue(context.store.isLoading)
        XCTAssertNil(context.store.loadedUserID)
        await context.store.reset()
        await repository.finishFetch()
        await reload.value
        let removed = await context.notifications.removedDeliveredIdentifiers()
        XCTAssertTrue(removed.isEmpty)
        XCTAssertNil(context.store.loadedUserID)
        XCTAssertNil(context.store.lastSuccessfulReloadAt)
        XCTAssertNil(context.store.errorMessage)
        XCTAssertFalse(context.store.isLoading)
    }

    func testCancellationBeforeSuccessfulResponseDoesNotCommitReload() async {
        let repository = TaskRestoreRepository()
        let context = makeContext(repository: repository)
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        await repository.suspendNextFetch()
        let reload = Task { await context.store.reload(userID: UUID()) }
        await repository.waitForFetch()
        reload.cancel()
        await repository.finishFetch()
        await reload.value
        XCTAssertNil(context.store.loadedUserID)
        XCTAssertNil(context.store.lastSuccessfulReloadAt)
        XCTAssertNil(context.store.loadErrorMessage)
        XCTAssertNil(context.store.errorMessage)
        XCTAssertFalse(context.store.isLoading)
    }

    func testInitialCancellationCanRetryWithoutReportingNetworkFailure() async {
        for error: Error in [CancellationError(), URLError(.cancelled)] {
            let repository = TaskRestoreRepository()
            let context = makeContext(repository: repository)
            defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
            let userID = UUID()
            await repository.setFetchError(error)
            await context.store.reload(userID: userID)
            XCTAssertNil(context.store.loadedUserID)
            XCTAssertFalse(context.store.isLoading)
            XCTAssertNil(context.store.loadErrorMessage)
            XCTAssertNil(context.store.errorMessage)

            await repository.setFetchError(nil)
            let retry = Task { await context.store.reload(userID: userID, force: true) }
            await context.notifications.waitForAuthorizationCheck()
            await context.notifications.finishAuthorizationCheck()
            await retry.value
            XCTAssertEqual(context.store.loadedUserID, userID)
            XCTAssertNotNil(context.store.lastSuccessfulReloadAt)
            XCTAssertFalse(context.store.isLoading)
        }
    }

    func testCompanyUpdateUsesEditingVersionAfterStoreRefresh() async {
        let repository = TaskRestoreRepository()
        let context = makeContext(repository: repository)
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let original = makeCompany()
        var refreshed = original
        refreshed.version += 1
        refreshed.name = "別端末の変更"
        context.store.companies = [refreshed]
        var draft = CompanyDraft(company: original)
        draft.name = "編集中の変更"
        let result = await context.store.updateCompany(original, draft: draft)
        let versions = await repository.companyInputVersions()
        XCTAssertEqual(versions, [original.version])
        XCTAssertNil(result)
        XCTAssertEqual(context.store.companies, [refreshed])
        XCTAssertNotNil(context.store.errorMessage)
        XCTAssertFalse(context.store.isSaving)
    }

    private func makeContext(repository: (any RecruitRepository)? = nil) -> (
        store: RecruitStore,
        notifications: IntegrationNotificationClient,
        defaults: UserDefaults,
        suiteName: String
    ) {
        let suiteName = "RecruitStoreIntegrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let notifications = IntegrationNotificationClient()
        let store = RecruitStore(
            repository: repository,
            notifications: LocalNotificationService(client: notifications)
        )
        return (store, notifications, defaults, suiteName)
    }

    private func makeCompany() -> Company {
        Company(
            id: UUID(), userID: UUID(), name: "企業", priority: 0, status: .active,
            url: nil, memo: nil, createdAt: Date(), updatedAt: Date()
        )
    }

    private func makeStep(companyID: UUID, userID: UUID = UUID()) -> SelectionStep {
        let now = Date()
        return SelectionStep(
            id: UUID(), userID: userID, companyID: companyID, type: .interview,
            customTitle: nil, startsAt: now.addingTimeInterval(172_800), startsHasTime: true,
            deadlineAt: now.addingTimeInterval(86_400), deadlineHasTime: true,
            status: .scheduled, memo: "メモ", notificationEnabled: false,
            createdAt: now, updatedAt: now
        )
    }

    private func makeTask(userID: UUID = UUID()) -> RecruitTask {
        let now = Date()
        return RecruitTask(
            id: UUID(), userID: userID, companyID: nil, title: "タスク", memo: nil,
            dueAt: now.addingTimeInterval(172_800), dueHasTime: true, completedAt: nil,
            notificationEnabled: true, createdAt: now, updatedAt: now
        )
    }
}

private actor IntegrationNotificationClient: UserNotificationCenterClient {
    private var authorizationChecked = false
    private var checkWaiters: [CheckedContinuation<Void, Never>] = []
    private var authorizationRelease: CheckedContinuation<UNAuthorizationStatus, Never>?
    private var requests: [UNNotificationRequest] = []
    private var removedDelivered: [String] = []
    func removedDeliveredIdentifiers() -> [String] { removedDelivered }

    func authorizationStatus() async -> UNAuthorizationStatus {
        authorizationChecked = true
        return await withCheckedContinuation { continuation in
            authorizationRelease = continuation
            checkWaiters.forEach { $0.resume() }
            checkWaiters.removeAll()
        }
    }

    func waitForAuthorizationCheck() async {
        guard authorizationChecked == false else { return }
        await withCheckedContinuation { checkWaiters.append($0) }
    }

    func waitForNextAuthorizationCheck() async {
        await waitForAuthorizationCheck()
    }

    func finishAuthorizationCheck(_ status: UNAuthorizationStatus = .authorized) {
        authorizationChecked = false
        authorizationRelease?.resume(returning: status)
        authorizationRelease = nil
    }

    func didCheckAuthorization() -> Bool { authorizationChecked }
    func scheduledRequests() -> [UNNotificationRequest] { requests }
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
    func pendingNotificationRequests() async -> [UNNotificationRequest] { requests }
    private var delivered: [UNNotificationRequest] = []
    func setDelivered(_ requests: [UNNotificationRequest]) { delivered = requests }
    func deliveredRequests() async -> [UNNotificationRequest] { delivered }
    private var schedulingFails = false
    func setSchedulingFails(_ value: Bool) { schedulingFails = value }
    func add(_ request: UNNotificationRequest) async throws {
        if schedulingFails { throw URLError(.unknown) }
        requests.append(request)
    }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        requests.removeAll { identifiers.contains($0.identifier) }
    }
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async { removedDelivered += identifiers }
    func removeAllPendingNotificationRequests() async { requests.removeAll() }
    func removeAllDeliveredNotifications() async {}
}

private actor TaskRestoreRepository: RecruitRepository {
    private var fetchedSteps: [SelectionStep] = []
    private var fetchedTasks: [RecruitTask] = []
    func setFetchedItems(steps: [SelectionStep], tasks: [RecruitTask]) {
        fetchedSteps = steps
        fetchedTasks = tasks
    }
    private var fetchError: Error?
    private var suspendsFetch = false
    private var pendingFetch: CheckedContinuation<Void, Never>?
    private var fetchWaiters: [CheckedContinuation<Void, Never>] = []
    func setFetchError(_ error: Error?) { fetchError = error }
    func suspendNextFetch() { suspendsFetch = true }
    func waitForFetch() async {
        if pendingFetch != nil { return }
        await withCheckedContinuation { fetchWaiters.append($0) }
    }
    func finishFetch() {
        pendingFetch?.resume()
        pendingFetch = nil
    }

    private var companyVersions: [Int] = []
    func companyInputVersions() -> [Int] { companyVersions }
    func updateCompany(_ company: Company, draft: CompanyDraft) async throws -> Company {
        companyVersions.append(company.version)
        throw RepositoryError.conflict
    }

    private var versions: [Int] = []
    private var selectionVersions: [Int] = []
    private var selectionConflict = false
    private var deletionFails = false
    func setDeletionFailure(_ value: Bool) { deletionFails = value }
    func failSelectionWithConflict() { selectionConflict = true }
    func selectionInputVersions() -> [Int] { selectionVersions }
    func inputVersions() -> [Int] { versions }
    func setTaskCompleted(_ task: RecruitTask, completed: Bool) async throws -> RecruitTask {
        versions.append(task.version)
        var updated = task
        updated.version += 1
        updated.completedAt = completed ? Date() : nil
        return updated
    }
    func fetchCompanies(userID: UUID) async throws -> [Company] {
        if suspendsFetch {
            suspendsFetch = false
            await withCheckedContinuation { continuation in
                pendingFetch = continuation
                fetchWaiters.forEach { $0.resume() }
                fetchWaiters.removeAll()
            }
        }
        if let fetchError { throw fetchError }
        return []
    }
    func fetchCompanyInformationItems(userID: UUID) async throws -> [CompanyInformationItem] { [] }
    func fetchSelectionSteps(userID: UUID) async throws -> [SelectionStep] { fetchedSteps }
    func fetchTasks(userID: UUID) async throws -> [RecruitTask] { fetchedTasks }

}

private extension TaskRestoreRepository {
    func createCompany(userID: UUID, draft: CompanyDraft) async throws -> Company { fatalError() }
    func deleteCompany(_ company: Company) async throws { fatalError() }

    func createCompanyInformationItem(
        userID: UUID,
        companyID: UUID,
        draft: CompanyInformationDraft
    ) async throws -> CompanyInformationItem { fatalError() }

    func updateCompanyInformationItem(
        _ item: CompanyInformationItem,
        draft: CompanyInformationDraft
    ) async throws -> CompanyInformationItem { fatalError() }

    func deleteCompanyInformationItem(_ item: CompanyInformationItem) async throws { fatalError() }
    func createSelectionStep(
        userID: UUID,
        companyID: UUID,
        draft: SelectionStepDraft
    ) async throws -> SelectionStep { fatalError() }

    func updateSelectionStep(
        _ step: SelectionStep,
        draft: SelectionStepDraft
    ) async throws -> SelectionStep { fatalError() }

    func setSelectionStepStatus(_ step: SelectionStep, status: SelectionStepStatus, notificationEnabled: Bool) async throws -> SelectionStep {
        selectionVersions.append(step.version)
        if selectionConflict { throw RepositoryError.conflict }
        var updated = step
        updated.status = status
        updated.notificationEnabled = notificationEnabled
        updated.version += 1
        return updated
    }
    func deleteSelectionStep(_ step: SelectionStep) async throws {
        if deletionFails { throw URLError(.notConnectedToInternet) }
    }
    func createTask(userID: UUID, draft: RecruitTaskDraft) async throws -> RecruitTask { fatalError() }
    func updateTask(_ task: RecruitTask, draft: RecruitTaskDraft) async throws -> RecruitTask { fatalError() }
    func deleteTask(_ task: RecruitTask) async throws {
        if deletionFails { throw URLError(.notConnectedToInternet) }
    }
}
