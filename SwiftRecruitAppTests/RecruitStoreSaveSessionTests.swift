import Foundation
import UserNotifications
import XCTest
@testable import SwiftRecruitApp

@MainActor
final class RecruitStoreSaveSessionTests: XCTestCase {
    func testOldTaskCompletionDoesNotClearNewSessionsTaskIndicator() async {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let oldTask = makeTask()
        let oldSave = Task { await context.store.setTaskCompleted(oldTask, completed: true) }
        await context.repository.waitForTaskSaveCount(1)
        await context.store.reset()

        let newTask = makeTask()
        let newSave = Task { await context.store.setTaskCompleted(newTask, completed: true) }
        await context.repository.waitForTaskSaveCount(2)
        await context.repository.finishTaskSave(1)
        let oldResult = await oldSave.value

        XCTAssertFalse(oldResult)
        XCTAssertTrue(context.store.isSaving)
        XCTAssertEqual(context.store.savingTaskID, newTask.id)

        await context.repository.finishTaskSave(2)
        let newResult = await newSave.value
        XCTAssertTrue(newResult)
        XCTAssertFalse(context.store.isSaving)
        XCTAssertNil(context.store.savingTaskID)
    }

    private func makeContext() -> (
        store: RecruitStore,
        repository: CoreSessionRepositorySpy,
        defaults: UserDefaults,
        suiteName: String
    ) {
        let suiteName = "RecruitStoreSaveSessionTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        let repository = CoreSessionRepositorySpy()
        return (
            RecruitStore(
                repository: repository,
                notifications: LocalNotificationService(client: SilentNotificationCenterClient())
            ),
            repository, defaults, suiteName
        )
    }

    private func makeTask() -> RecruitTask {
        RecruitTask(
            id: UUID(), userID: UUID(), companyID: nil, title: "書類提出", memo: nil,
            dueAt: nil, dueHasTime: false, completedAt: nil, notificationEnabled: false,
            createdAt: Date(), updatedAt: Date()
        )
    }
}

private actor CoreSessionRepositorySpy: RecruitRepository {
    private var taskSaveCount = 0
    private var pendingTaskSaves: [Int: (RecruitTask, CheckedContinuation<RecruitTask, Error>)] = [:]
    private var taskSaveWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func setTaskCompleted(_ task: RecruitTask, completed: Bool) async throws -> RecruitTask {
        var updated = task
        updated.completedAt = completed ? Date() : nil
        return try await withCheckedThrowingContinuation { continuation in
            taskSaveCount += 1
            pendingTaskSaves[taskSaveCount] = (updated, continuation)
            let ready = taskSaveWaiters.filter { $0.0 <= taskSaveCount }
            taskSaveWaiters.removeAll { $0.0 <= taskSaveCount }
            for (_, waiter) in ready { waiter.resume() }
        }
    }

    func waitForTaskSaveCount(_ count: Int) async {
        guard taskSaveCount < count else { return }
        await withCheckedContinuation { taskSaveWaiters.append((count, $0)) }
    }

    func finishTaskSave(_ number: Int) {
        guard let (task, continuation) = pendingTaskSaves.removeValue(forKey: number) else {
            preconditionFailure("No pending task save")
        }
        continuation.resume(returning: task)
    }

    func fetchCompanies(userID: UUID) async throws -> [Company] { [] }
    func fetchCompanyInformationItems(userID: UUID) async throws -> [CompanyInformationItem] { [] }
    func fetchSelectionSteps(userID: UUID) async throws -> [SelectionStep] { [] }
    func fetchTasks(userID: UUID) async throws -> [RecruitTask] { [] }
}

private extension RecruitRepository {
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

    func setSelectionStepStatus(_ step: SelectionStep, status: SelectionStepStatus, notificationEnabled: Bool) async throws -> SelectionStep { fatalError() }
    func deleteSelectionStep(_ step: SelectionStep) async throws { fatalError() }
    func createTask(userID: UUID, draft: RecruitTaskDraft) async throws -> RecruitTask { fatalError() }
    func updateTask(_ task: RecruitTask, draft: RecruitTaskDraft) async throws -> RecruitTask { fatalError() }
    func setTaskCompleted(_ task: RecruitTask, completed: Bool) async throws -> RecruitTask { fatalError() }
    func deleteTask(_ task: RecruitTask) async throws { fatalError() }
}

private actor SilentNotificationCenterClient: UserNotificationCenterClient {
    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
    func pendingNotificationRequests() async -> [UNNotificationRequest] { [] }
    func deliveredNotifications() async -> [UNNotification] { [] }
    func add(_ request: UNNotificationRequest) async throws {}
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {}
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {}
    func removeAllPendingNotificationRequests() async {}
    func removeAllDeliveredNotifications() async {}
}
