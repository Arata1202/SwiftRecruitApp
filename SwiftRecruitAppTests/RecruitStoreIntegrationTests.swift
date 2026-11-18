import Foundation
import UserNotifications
import XCTest
@testable import SwiftRecruitApp

@MainActor
final class RecruitStoreIntegrationTests: XCTestCase {
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
        XCTAssertEqual(requests.first?.content.body, "変更後の企業｜期限を確認しましょう。")
    }

    func testStaleNotificationGenerationDoesNotEvenCheckAuthorization() async {
        let client = IntegrationNotificationClient()
        let coordinator = RecruitNotificationCoordinator(
            notifications: LocalNotificationService(client: client),
            isCurrentSession: { _ in false },
            companies: { [] },
            selectionSteps: { [] },
            tasks: { [] },
            reportError: { _ in XCTFail("古いセッションのエラーを表示しない") }
        )

        await coordinator.reconcile(generation: 1, promptIfNeeded: true, reportDenied: true)

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

    private func makeStep(companyID: UUID) -> SelectionStep {
        let now = Date()
        return SelectionStep(
            id: UUID(), userID: UUID(), companyID: companyID, type: .interview,
            customTitle: nil, startsAt: now.addingTimeInterval(172_800), startsHasTime: true,
            deadlineAt: now.addingTimeInterval(86_400), deadlineHasTime: true,
            status: .scheduled, memo: "メモ", notificationEnabled: false,
            createdAt: now, updatedAt: now
        )
    }

    private func makeTask() -> RecruitTask {
        let now = Date()
        return RecruitTask(
            id: UUID(), userID: UUID(), companyID: nil, title: "タスク", memo: nil,
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

    func finishAuthorizationCheck() {
        authorizationChecked = false
        authorizationRelease?.resume(returning: .authorized)
        authorizationRelease = nil
    }

    func didCheckAuthorization() -> Bool { authorizationChecked }
    func scheduledRequests() -> [UNNotificationRequest] { requests }
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
    func pendingNotificationRequests() async -> [UNNotificationRequest] { requests }
    func deliveredNotifications() async -> [UNNotification] { [] }
    func add(_ request: UNNotificationRequest) async throws { requests.append(request) }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        requests.removeAll { identifiers.contains($0.identifier) }
    }
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {}
    func removeAllPendingNotificationRequests() async { requests.removeAll() }
    func removeAllDeliveredNotifications() async {}
}

private actor TaskRestoreRepository: RecruitRepository {
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
    func fetchCompanies(userID: UUID) async throws -> [Company] { fatalError() }
    func fetchCompanyInformationItems(userID: UUID) async throws -> [CompanyInformationItem] { fatalError() }
    func fetchSelectionSteps(userID: UUID) async throws -> [SelectionStep] { fatalError() }
    func fetchTasks(userID: UUID) async throws -> [RecruitTask] { fatalError() }
}

private extension TaskRestoreRepository {
    func createCompany(userID: UUID, draft: CompanyDraft) async throws -> Company { fatalError() }
    func updateCompany(_ company: Company, draft: CompanyDraft) async throws -> Company { fatalError() }
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
