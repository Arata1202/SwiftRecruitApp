import EventKit
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
            notifications: LocalNotificationService(client: SilentNotificationCenterClient()),
            appleCalendar: AppleCalendarService(
                defaults: defaults,
                client: SilentAppleCalendarEventClient()
            )
        )
        return (store, repository, defaults, suiteName)
    }
}

private enum SelfAnalysisLoadingTestError: Error {
    case unavailable
}

private actor SelfAnalysisRepositorySpy: RecruitRepository {
    private var answerFetchCount = 0
    private var motivationPointFetchCount = 0
    private var selfAnalysisFailureEnabled = false

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
    func fetchESTemplates(userID: UUID) async throws -> [ESTemplate] { [] }

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

    func deleteSelectionStep(_ step: SelectionStep) async throws { fatalError() }
    func createTask(userID: UUID, draft: RecruitTaskDraft) async throws -> RecruitTask { fatalError() }
    func updateTask(_ task: RecruitTask, draft: RecruitTaskDraft) async throws -> RecruitTask { fatalError() }
    func setTaskCompleted(_ task: RecruitTask, completed: Bool) async throws -> RecruitTask { fatalError() }
    func deleteTask(_ task: RecruitTask) async throws { fatalError() }
    func createESTemplate(userID: UUID, draft: ESTemplateDraft) async throws -> ESTemplate { fatalError() }
    func updateESTemplate(_ template: ESTemplate, draft: ESTemplateDraft) async throws -> ESTemplate { fatalError() }
    func deleteESTemplate(_ template: ESTemplate) async throws { fatalError() }
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

@MainActor
private final class SilentAppleCalendarEventClient: AppleCalendarEventClient {
    var hasFullAccess = true

    func requestFullAccess() async throws -> Bool { true }

    func contains(identifier: String, lastStartDate: Date, key: String) -> Bool { false }

    func save(
        _ descriptor: AppleCalendarEventDescriptor,
        existingIdentifier: String?,
        lastStartDate: Date?
    ) throws -> AppleCalendarSavedEvent {
        AppleCalendarSavedEvent(identifier: "unused", startDate: descriptor.startDate)
    }

    func remove(identifier: String?, lastStartDate: Date, key: String) throws {}
}
