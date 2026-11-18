import Foundation
import UserNotifications
import XCTest
@testable import SwiftRecruitApp

@MainActor
final class RecruitStoreSelfAnalysisLoadingTests: XCTestCase {
    func testMainReloadDoesNotFetchOptionalSelfAnalysisData() async {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let userID = UUID()

        await context.store.reload(userID: userID)

        let counts = await context.repository.selfAnalysisFetchCounts()
        XCTAssertEqual(counts.answers, 0)
        XCTAssertEqual(counts.motivationPoints, 0)
        XCTAssertEqual(context.store.loadedUserID, userID)
        XCTAssertNil(context.store.loadErrorMessage)
    }

    func testSelfAnalysisLoadsOnDemand() async {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let userID = UUID()

        await context.store.loadSelfAnalysis(userID: userID)

        let counts = await context.repository.selfAnalysisFetchCounts()
        XCTAssertEqual(counts.answers, 1)
        XCTAssertEqual(counts.motivationPoints, 1)
        XCTAssertEqual(context.store.selfAnalysisAnswers.count, 1)
        XCTAssertEqual(context.store.motivationPoints.count, 1)
        XCTAssertTrue(context.store.hasLoadedSelfAnalysis(for: userID))
        XCTAssertNil(context.store.selfAnalysisLoadErrorMessage)
    }

    func testSelfAnalysisFailureDoesNotInvalidateCoreDataLoad() async {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let userID = UUID()
        await context.repository.setSelfAnalysisFailureEnabled(true)

        await context.store.reload(userID: userID)
        await context.store.loadSelfAnalysis(userID: userID)

        XCTAssertEqual(context.store.loadedUserID, userID)
        XCTAssertNil(context.store.loadErrorMessage)
        XCTAssertNotNil(context.store.selfAnalysisLoadErrorMessage)
        XCTAssertFalse(context.store.hasLoadedSelfAnalysis(for: userID))
    }

    func testFailedSelfAnalysisRefreshPreservesPreviouslyLoadedData() async {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let userID = UUID()
        await context.store.loadSelfAnalysis(userID: userID)
        await context.repository.setSelfAnalysisFailureEnabled(true)

        await context.store.loadSelfAnalysis(userID: userID, force: true)

        XCTAssertEqual(context.store.selfAnalysisAnswers.count, 1)
        XCTAssertEqual(context.store.motivationPoints.count, 1)
        XCTAssertTrue(context.store.hasLoadedSelfAnalysis(for: userID))
        XCTAssertNil(context.store.selfAnalysisLoadErrorMessage)
        XCTAssertNotNil(context.store.errorMessage)
    }

    func testResetClearsSelfAnalysisState() async {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let userID = UUID()
        await context.store.loadSelfAnalysis(userID: userID)

        await context.store.reset()

        XCTAssertTrue(context.store.selfAnalysisAnswers.isEmpty)
        XCTAssertTrue(context.store.motivationPoints.isEmpty)
        XCTAssertFalse(context.store.hasLoadedSelfAnalysis(for: userID))
        XCTAssertNil(context.store.selfAnalysisLoadErrorMessage)
    }

    func testSelfAnalysisReloadsOnlyAfterTheStaleInterval() async throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let userID = UUID()
        await context.store.loadSelfAnalysis(userID: userID)
        let lastReloadAt = try XCTUnwrap(context.store.lastSuccessfulSelfAnalysisReloadAt)

        let reloadedWhileFresh = await context.store.loadSelfAnalysisIfStale(
            userID: userID,
            now: lastReloadAt.addingTimeInterval(60)
        )
        let reloadedWhenStale = await context.store.loadSelfAnalysisIfStale(
            userID: userID,
            now: lastReloadAt.addingTimeInterval(ReloadPolicy.defaultMinimumInterval + 1)
        )

        let counts = await context.repository.selfAnalysisFetchCounts()
        XCTAssertFalse(reloadedWhileFresh)
        XCTAssertTrue(reloadedWhenStale)
        XCTAssertEqual(counts.answers, 2)
        XCTAssertEqual(counts.motivationPoints, 2)
    }

    private func makeContext() -> (
        store: RecruitStore,
        repository: SelfAnalysisRepositorySpy,
        defaults: UserDefaults,
        suiteName: String
    ) {
        let suiteName = "RecruitStoreSelfAnalysisLoadingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let repository = SelfAnalysisRepositorySpy()
        let store = RecruitStore(
            repository: repository,
            notifications: LocalNotificationService(client: SilentNotificationCenterClient())
        )
        return (store, repository, defaults, suiteName)
    }
}

@MainActor
final class RecruitStoreSaveSessionTests: XCTestCase {
    func testOldSaveSuccessDoesNotClearNewSessionsSavingState() async {
        await checkOldSaveCompletingDuringNewSave(fails: false)
    }

    func testOldSaveFailureDoesNotClearNewSessionsSavingStateOrShowError() async {
        await checkOldSaveCompletingDuringNewSave(fails: true)
    }

    func testCurrentSessionSaveFailureStillShowsErrorAndClearsSavingState() async {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let save = Task { await context.store.createSelfAnalysisAnswer(userID: UUID(), draft: SelfAnalysisAnswerDraft()) }
        await context.repository.waitForAnswerSaveCount(1)
        await context.repository.finishAnswerSave(1, fails: true)
        let result = await save.value

        XCTAssertNil(result)
        XCTAssertFalse(context.store.isSaving)
        XCTAssertEqual(context.store.errorMessage, RepositoryError.conflict.localizedDescription)
    }

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

    private func checkOldSaveCompletingDuringNewSave(fails: Bool) async {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let oldUserID = UUID()
        let oldSave = Task {
            await context.store.createSelfAnalysisAnswer(userID: oldUserID, draft: SelfAnalysisAnswerDraft())
        }
        await context.repository.waitForAnswerSaveCount(1)
        await context.store.reset()

        let newUserID = UUID()
        let newSave = Task {
            await context.store.createSelfAnalysisAnswer(userID: newUserID, draft: SelfAnalysisAnswerDraft())
        }
        await context.repository.waitForAnswerSaveCount(2)
        await context.repository.finishAnswerSave(1, fails: fails)
        let oldResult = await oldSave.value

        XCTAssertNil(oldResult)
        XCTAssertTrue(context.store.isSaving)
        XCTAssertNil(context.store.errorMessage)
        XCTAssertTrue(context.store.selfAnalysisAnswers.isEmpty)

        await context.repository.finishAnswerSave(2, fails: false)
        let newResult = await newSave.value
        XCTAssertEqual(newResult?.userID, newUserID)
        XCTAssertEqual(context.store.selfAnalysisAnswers.map { $0.userID }, [newUserID])
        XCTAssertFalse(context.store.isSaving)
        XCTAssertNil(context.store.errorMessage)
    }

    private func makeContext() -> (
        store: RecruitStore,
        repository: SelfAnalysisRepositorySpy,
        defaults: UserDefaults,
        suiteName: String
    ) {
        let suiteName = "RecruitStoreSaveSessionTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        let repository = SelfAnalysisRepositorySpy()
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

private enum SelfAnalysisLoadingTestError: Error {
    case unavailable
}

private actor SelfAnalysisRepositorySpy: RecruitRepository {
    private var answerFetchCount = 0
    private var motivationPointFetchCount = 0
    private var selfAnalysisFailureEnabled = false
    private var answerSaveCount = 0
    private var pendingAnswerSaves: [Int: (UUID, CheckedContinuation<SelfAnalysisAnswer, Error>)] = [:]
    private var answerSaveWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var taskSaveCount = 0
    private var pendingTaskSaves: [Int: (RecruitTask, CheckedContinuation<RecruitTask, Error>)] = [:]
    private var taskSaveWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func createSelfAnalysisAnswer(userID: UUID, draft: SelfAnalysisAnswerDraft) async throws -> SelfAnalysisAnswer {
        try await withCheckedThrowingContinuation { continuation in
            answerSaveCount += 1
            pendingAnswerSaves[answerSaveCount] = (userID, continuation)
            let ready = answerSaveWaiters.filter { $0.0 <= answerSaveCount }
            answerSaveWaiters.removeAll { $0.0 <= answerSaveCount }
            for (_, waiter) in ready { waiter.resume() }
        }
    }

    func waitForAnswerSaveCount(_ count: Int) async {
        guard answerSaveCount < count else { return }
        await withCheckedContinuation { answerSaveWaiters.append((count, $0)) }
    }

    func finishAnswerSave(_ number: Int, fails: Bool) {
        guard let (userID, continuation) = pendingAnswerSaves.removeValue(forKey: number) else {
            preconditionFailure("No pending answer save")
        }
        if fails {
            continuation.resume(throwing: RepositoryError.conflict)
        } else {
            continuation.resume(returning: SelfAnalysisAnswer(
                id: UUID(), userID: userID, category: .values,
                question: SelfAnalysisCategory.values.defaultQuestion, answer: "成長できる環境",
                createdAt: Date(), updatedAt: Date()
            ))
        }
    }

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

    func setSelfAnalysisFailureEnabled(_ enabled: Bool) {
        selfAnalysisFailureEnabled = enabled
    }

    func selfAnalysisFetchCounts() -> (answers: Int, motivationPoints: Int) {
        (answerFetchCount, motivationPointFetchCount)
    }

    func fetchCompanies(userID: UUID) async throws -> [Company] { [] }
    func fetchCompanyInformationItems(userID: UUID) async throws -> [CompanyInformationItem] { [] }
    func fetchSelectionSteps(userID: UUID) async throws -> [SelectionStep] { [] }
    func fetchTasks(userID: UUID) async throws -> [RecruitTask] { [] }
    func fetchSelfAnalysisAnswers(userID: UUID) async throws -> [SelfAnalysisAnswer] {
        answerFetchCount += 1
        if selfAnalysisFailureEnabled { throw SelfAnalysisLoadingTestError.unavailable }
        return [
            SelfAnalysisAnswer(
                id: UUID(),
                userID: userID,
                category: .values,
                question: SelfAnalysisCategory.values.defaultQuestion,
                answer: "成長できる環境",
                createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
            ),
        ]
    }

    func fetchMotivationPoints(userID: UUID) async throws -> [MotivationPoint] {
        motivationPointFetchCount += 1
        if selfAnalysisFailureEnabled { throw SelfAnalysisLoadingTestError.unavailable }
        return [
            MotivationPoint(
                id: UUID(),
                userID: userID,
                age: 20,
                happiness: 8,
                reason: "開発に熱中した",
                createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
            ),
        ]
    }
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
    func createSelfAnalysisAnswer(
        userID: UUID,
        draft: SelfAnalysisAnswerDraft
    ) async throws -> SelfAnalysisAnswer { fatalError() }

    func updateSelfAnalysisAnswer(
        _ answer: SelfAnalysisAnswer,
        draft: SelfAnalysisAnswerDraft
    ) async throws -> SelfAnalysisAnswer { fatalError() }

    func deleteSelfAnalysisAnswer(_ answer: SelfAnalysisAnswer) async throws { fatalError() }
    func createMotivationPoint(
        userID: UUID,
        draft: MotivationPointDraft
    ) async throws -> MotivationPoint { fatalError() }

    func updateMotivationPoint(
        _ point: MotivationPoint,
        draft: MotivationPointDraft
    ) async throws -> MotivationPoint { fatalError() }

    func deleteMotivationPoint(_ point: MotivationPoint) async throws { fatalError() }
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
