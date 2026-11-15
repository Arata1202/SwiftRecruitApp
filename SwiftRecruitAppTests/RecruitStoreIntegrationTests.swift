import Foundation
import UserNotifications
import XCTest
@testable import SwiftRecruitApp

@MainActor
final class RecruitStoreIntegrationTests: XCTestCase {
    func testCalendarExportReportsAccessDenied() async {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        context.calendar.hasFullAccess = false
        context.calendar.accessRequestResult = false

        let exported = await context.store.exportTask(makeTask())

        XCTAssertFalse(exported)
        XCTAssertEqual(context.store.errorMessage, AppleCalendarError.accessDenied.localizedDescription)
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

    func testCalendarExportPreservesMilestoneTitlesDatesAndDurations() async {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let company = makeCompany()
        context.store.companies = [company]
        var step = makeStep(companyID: company.id)
        step.status = .completed

        let startExported = await context.store.exportSelection(step, kind: .start)
        let deadlineExported = await context.store.exportSelection(step, kind: .deadline)

        XCTAssertTrue(startExported)
        XCTAssertTrue(deadlineExported)
        XCTAssertEqual(context.calendar.saved.map(\.title), ["【完了】企業 · 面接", "【完了】【締切】企業 · 面接"])
        XCTAssertEqual(context.calendar.saved.map(\.duration), [3_600, 1_800])
        XCTAssertEqual(context.calendar.saved.map(\.startDate), [step.startDate()!, step.deadlineDate()!])
        XCTAssertEqual(context.calendar.saved.map(\.notes), ["メモ", "メモ"])
    }

    func testCalendarResyncUsesLiveCompanyNameAndRemovesCancelledSelection() async {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let company = makeCompany()
        var step = makeStep(companyID: company.id)
        context.store.companies = [company]
        context.store.selectionSteps = [step]
        let exported = await context.store.exportSelection(step, kind: .start)
        XCTAssertTrue(exported)
        var renamed = company
        renamed.name = "新しい企業名"
        context.store.companies = [renamed]

        await context.store.resyncAppleCalendarIfNeeded()
        XCTAssertEqual(context.calendar.saved.last?.title, "新しい企業名 · 面接")

        step.status = .cancelled
        context.store.selectionSteps = [step]
        await context.store.resyncAppleCalendarIfNeeded()
        XCTAssertFalse(context.store.isSelectionExported(id: step.id, kind: .start))
        XCTAssertEqual(context.calendar.removedKeys, [AppleCalendarService.selectionKey(id: step.id, kind: .start)])
    }

    func testAutomaticCreationDisabledAndManualEventsRemainManaged() async {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let manual = makeTask()
        let newTask = makeTask()
        context.store.tasks = [manual, newTask]
        let exported = await context.store.exportTask(manual)
        XCTAssertTrue(exported)
        await context.store.setAppleCalendarCategory(.task, enabled: true)
        await context.store.resyncAppleCalendarIfNeeded()
        XCTAssertTrue(context.store.isTaskExported(id: manual.id))
        XCTAssertFalse(context.store.isTaskExported(id: newTask.id))
        XCTAssertTrue(context.calendar.removedKeys.isEmpty)
        let removed = await context.store.removeTaskFromAppleCalendar(id: manual.id)
        XCTAssertTrue(removed)
        await context.store.resyncAppleCalendarIfNeeded()
        XCTAssertFalse(context.store.isTaskExported(id: manual.id))
    }

    func testLegacyAutomaticRecordContinuesToUpdateAndDelete() async throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let userID = UUID()
        let task = makeTask()
        let key = AppleCalendarService.taskKey(id: task.id)
        let record: [String: [String: Any]] = [key: [
            "eventIdentifier": "legacy-event",
            "lastStartDate": task.dueDate()!.timeIntervalSinceReferenceDate,
            "automatically": true
        ]]
        context.defaults.set(try JSONSerialization.data(withJSONObject: record), forKey: "appleCalendarExportRecords.v2.\(userID.uuidString)")
        context.calendarService.activate(userID: userID)
        context.store.tasks = [task]
        await context.store.resyncAppleCalendarIfNeeded()
        XCTAssertEqual(context.calendar.saved.last?.key, key)
        context.store.tasks = []
        await context.store.resyncAppleCalendarIfNeeded()
        XCTAssertEqual(context.calendar.removedKeys, [key])
    }

    func testLegacyEnabledPreferencesNeverCreateEvents() async {
        for version in [1, 2] {
            let context = makeContext()
            defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
            let userID = UUID()
            if version == 1 {
                context.defaults.removeObject(forKey: "appleCalendarUserScopeMigration.v2")
                context.defaults.set(true, forKey: "appleCalendarAutoSyncEnabled.v1")
                context.defaults.set(true, forKey: "appleCalendarAutoSyncCategory.v1.task")
            } else {
                context.defaults.set(true, forKey: "appleCalendarAutoSyncEnabled.v2.\(userID.uuidString)")
                context.defaults.set(true, forKey: "appleCalendarAutoSyncCategory.v2.task.\(userID.uuidString)")
            }
            context.calendarService.activate(userID: userID)
            context.store.tasks = [makeTask()]
            await context.store.resyncAppleCalendarIfNeeded()
            XCTAssertTrue(context.calendar.saved.isEmpty, "v\(version)")
        }
    }

    func testCalendarFailureStillReachesStoreErrorState() async {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        context.calendar.saveError = AppleCalendarError.calendarUnavailable

        let exported = await context.store.exportTask(makeTask())

        XCTAssertFalse(exported)
        XCTAssertNotNil(context.store.errorMessage)
    }

    private func makeContext() -> (
        store: RecruitStore,
        notifications: IntegrationNotificationClient,
        calendar: IntegrationCalendarClient,
        calendarService: AppleCalendarService,
        defaults: UserDefaults,
        suiteName: String
    ) {
        let suiteName = "RecruitStoreIntegrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let notifications = IntegrationNotificationClient()
        let calendar = IntegrationCalendarClient()
        let service = AppleCalendarService(defaults: defaults, client: calendar)
        service.activate(userID: UUID())
        let store = RecruitStore(
            repository: nil,
            notifications: LocalNotificationService(client: notifications),
            appleCalendar: service
        )
        return (store, notifications, calendar, service, defaults, suiteName)
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

    func finishAuthorizationCheck() {
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

private enum IntegrationCalendarError: Error {
    case requestFailed
}

@MainActor
private final class IntegrationCalendarClient: AppleCalendarEventClient {
    var hasFullAccess = true
    var accessRequestResult = true
    var accessRequestCount = 0
    var accessRequestError: Error?
    var suspendsAccessRequest = false
    private var accessRequest: CheckedContinuation<Bool, Never>?
    private var accessRequestWaiter: CheckedContinuation<Void, Never>?
    var saved: [AppleCalendarEventDescriptor] = []
    var removedKeys: [String] = []
    var saveError: Error?

    func requestFullAccess() async throws -> Bool {
        accessRequestCount += 1
        if let accessRequestError { throw accessRequestError }
        if suspendsAccessRequest {
            let granted = await withCheckedContinuation { continuation in
                accessRequest = continuation
                accessRequestWaiter?.resume()
                accessRequestWaiter = nil
            }
            hasFullAccess = granted
            return granted
        }
        hasFullAccess = accessRequestResult
        return hasFullAccess
    }
    func waitForAccessRequest() async {
        if accessRequest != nil { return }
        await withCheckedContinuation { accessRequestWaiter = $0 }
    }
    func finishAccessRequest(granted: Bool) {
        accessRequest?.resume(returning: granted)
        accessRequest = nil
    }
    func contains(identifier: String, lastStartDate: Date, key: String) -> Bool { true }
    func save(
        _ descriptor: AppleCalendarEventDescriptor,
        existingIdentifier: String?,
        lastStartDate: Date?
    ) throws -> AppleCalendarSavedEvent {
        if let saveError { throw saveError }
        saved.append(descriptor)
        return AppleCalendarSavedEvent(identifier: descriptor.key, startDate: descriptor.startDate)
    }
    func remove(identifier: String?, lastStartDate: Date, key: String) throws {
        removedKeys.append(key)
    }
}
