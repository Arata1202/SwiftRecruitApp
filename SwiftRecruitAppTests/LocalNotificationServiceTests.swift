import Foundation
import UserNotifications
import XCTest
@testable import SwiftRecruitApp

final class LocalNotificationServiceTests: XCTestCase {
    func testSchedulerUsesSharedAdmissionAndNeverClearsDeliveredForOverflow() async throws {
        let center = BlockingNotificationCenterClient()
        await center.releaseFirstAdd()
        let service = LocalNotificationService(client: center)
        let tasks = (1...70).map { index in
            makeTask(id: UUID(uuidString: String(format: "30000000-0000-0000-0000-%012d", index))!, title: "task")
        }
        let plan = NotificationPlanBuilder.assessment(steps: [], tasks: tasks, companyNames: [:])
        try await service.reconcile(steps: [], tasks: tasks, companyNames: [:])
        let added = await center.addedIdentifiers()
        let removed = await center.removedDeliveredIdentifiers()
        XCTAssertEqual(added, plan.admitted.map(\.identifier))
        XCTAssertEqual(added.count, 64)
        XCTAssertEqual(plan.overflow.count, 6)
        XCTAssertTrue(removed.isEmpty)
    }

    func testReconciliationsDoNotOverlap() async throws {
        let center = BlockingNotificationCenterClient()
        let service = LocalNotificationService(client: center)
        let firstTask = makeTask(id: UUID(), title: "first")
        let secondTask = makeTask(id: UUID(), title: "second")

        let firstReconciliation = Task {
            try await service.reconcile(steps: [], tasks: [firstTask], companyNames: [:])
        }
        await center.waitUntilFirstAddStarts()

        let secondReconciliation = Task {
            try await service.reconcile(steps: [], tasks: [secondTask], companyNames: [:])
        }
        try await Task.sleep(for: .milliseconds(50))

        let identifiersBeforeRelease = await center.addedIdentifiers()
        XCTAssertEqual(
            identifiersBeforeRelease,
            [NotificationPlanBuilder.taskIdentifiers(firstTask.id)[0]]
        )

        await center.releaseFirstAdd()
        try await firstReconciliation.value
        try await secondReconciliation.value

        let finalIdentifiers = await center.addedIdentifiers()
        XCTAssertEqual(
            finalIdentifiers,
            [
                NotificationPlanBuilder.taskIdentifiers(firstTask.id)[0],
                NotificationPlanBuilder.taskIdentifiers(secondTask.id)[0],
            ]
        )
    }

    func testCancelAllWaitsForAnInFlightReconciliation() async throws {
        let center = BlockingNotificationCenterClient()
        let service = LocalNotificationService(client: center)
        let task = makeTask(id: UUID(), title: "task")

        let reconciliation = Task {
            try await service.reconcile(steps: [], tasks: [task], companyNames: [:])
        }
        await center.waitUntilFirstAddStarts()

        let cancellation = Task {
            await service.invalidateAndCancelAll()
        }
        try await Task.sleep(for: .milliseconds(50))
        let callsBeforeRelease = await center.removeAllCallCount()
        XCTAssertEqual(callsBeforeRelease, 0)

        await center.releaseFirstAdd()
        try await reconciliation.value
        await cancellation.value
        let finalCallCount = await center.removeAllCallCount()
        XCTAssertEqual(finalCallCount, 2)
    }

    func testNormalReconciliationDoesNotClearDeliveredNotifications() async throws {
        let center = BlockingNotificationCenterClient()
        let service = LocalNotificationService(client: center)
        await center.releaseFirstAdd()
        try await service.reconcile(steps: [], tasks: [makeTask(id: UUID(), title: "edited")], companyNames: [:])
        let removed = await center.removedDeliveredIdentifiers()
        let allCalls = await center.removeAllCallCount()
        XCTAssertTrue(removed.isEmpty)
        XCTAssertEqual(allCalls, 0)
    }

    func testCompletionOrDeletionCancellationOnlyRemovesTargetNotifications() async {
        let center = BlockingNotificationCenterClient()
        let service = LocalNotificationService(client: center)
        let taskID = UUID()
        let selectionID = UUID()
        await service.cancelTask(id: taskID)
        let taskRemoved = await center.removedDeliveredIdentifiers()
        XCTAssertEqual(taskRemoved, NotificationPlanBuilder.taskIdentifiers(taskID))
        await service.cancelSelection(id: selectionID)
        let allRemoved = await center.removedDeliveredIdentifiers()
        XCTAssertEqual(allRemoved, NotificationPlanBuilder.taskIdentifiers(taskID) + NotificationPlanBuilder.selectionIdentifiers(selectionID))
        let allCalls = await center.removeAllCallCount()
        XCTAssertEqual(allCalls, 0)
    }

    @MainActor
    func testQueuedCleanupRechecksReloadValidityBeforeRemovingDelivered() async throws {
        let center = BlockingNotificationCenterClient()
        let service = LocalNotificationService(client: center)
        let task = makeTask(id: UUID(), title: "blocking")
        let reconciliation = Task {
            try await service.reconcile(steps: [], tasks: [task], companyNames: [:])
        }
        await center.waitUntilFirstAddStarts()
        let validity = CleanupValidity()
        let cleanup = Task {
            await service.removeDeliveredNotifications(
                selectionIDs: [], taskIDs: [task.id], isCurrent: { validity.isCurrent }
            )
        }
        await Task.yield()
        validity.isCurrent = false
        await center.releaseFirstAdd()
        try await reconciliation.value
        await cleanup.value
        let removed = await center.removedDeliveredIdentifiers()
        XCTAssertTrue(removed.isEmpty)
    }

    func testReloadCleanupRemovesOnlyExplicitDeliveredIDsWithoutTouchingPending() async throws {
        let center = BlockingNotificationCenterClient()
        let service = LocalNotificationService(client: center)
        await center.releaseFirstAdd()
        let pendingTask = makeTask(id: UUID(), title: "pending")
        try await service.reconcile(steps: [], tasks: [pendingTask], companyNames: [:])
        let selectionID = UUID()
        let taskID = UUID()
        await service.removeDeliveredNotifications(
            selectionIDs: [selectionID], taskIDs: [taskID], isCurrent: { true }
        )
        let removed = await center.removedDeliveredIdentifiers()
        XCTAssertEqual(Set(removed), Set(NotificationPlanBuilder.selectionIdentifiers(selectionID)
            + NotificationPlanBuilder.taskIdentifiers(taskID)))
        let pending = await center.pendingNotificationRequests()
        XCTAssertEqual(pending.map { $0.identifier }, NotificationPlanBuilder.taskIdentifiers(pendingTask.id))
        let allCalls = await center.removeAllCallCount()
        XCTAssertEqual(allCalls, 0)
    }

    func testTriggerRetainsSecondsRatherThanMovingToPastMinute() async throws {
        let center = BlockingNotificationCenterClient()
        let service = LocalNotificationService(client: center)
        await center.releaseFirstAdd()
        var task = makeTask(id: UUID(), title: "seconds")
        let minute = Calendar.current.dateInterval(of: .minute, for: Date().addingTimeInterval(3_600))!.start
        task.dueAt = minute.addingTimeInterval(45)
        task.notificationTimedPreset = .atTime
        try await service.reconcile(steps: [], tasks: [task], companyNames: [:])
        let requests = await center.pendingNotificationRequests()
        let trigger = try XCTUnwrap(requests.first?.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.calendar?.identifier, .gregorian)
        XCTAssertEqual(trigger.dateComponents.second, 45)
        XCTAssertEqual(try XCTUnwrap(trigger.nextTriggerDate()), task.dueAt)
    }

    func testElapsedReminderRetainsSecondOccurrenceOfRepeatedHour() async throws {
        let center = BlockingNotificationCenterClient()
        let service = LocalNotificationService(client: center)
        await center.releaseFirstAdd()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let day = cal.date(from: DateComponents(year: 2030, month: 11, day: 3))!
        let secondOccurrence = try XCTUnwrap(cal.nextDate(after: day,
            matching: DateComponents(hour: 1, minute: 30), matchingPolicy: .nextTime, repeatedTimePolicy: .last))
        var task = makeTask(id: UUID(), title: "Repeated hour")
        task.dueAt = secondOccurrence.addingTimeInterval(3_600)
        task.notificationTimedCustom = .elapsed(1, unit: .hours)
        try await service.reconcile(steps: [], tasks: [task], companyNames: [:])
        let requests = await center.pendingNotificationRequests()
        let trigger = try XCTUnwrap(requests.first?.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.nextTriggerDate(), secondOccurrence)
        XCTAssertEqual(trigger.dateComponents.timeZone?.secondsFromGMT(), 0)
    }

    private func makeTask(id: UUID, title: String) -> RecruitTask {
        let now = Date()
        return RecruitTask(
            id: id,
            userID: UUID(),
            companyID: nil,
            title: title,
            memo: nil,
            dueAt: now.addingTimeInterval(24 * 60 * 60),
            dueHasTime: true,
            completedAt: nil,
            notificationEnabled: true,
            createdAt: now,
            updatedAt: now
        )
    }
}

private actor BlockingNotificationCenterClient: UserNotificationCenterClient {
    private var requests: [String: UNNotificationRequest] = [:]
    private var addOrder: [String] = []
    private var firstAddWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstAddRelease: CheckedContinuation<Void, Never>?
    private var shouldBlockFirstAdd = true
    private var removeAllCalls = 0
    private var removedDelivered: [String] = []

    func authorizationStatus() async -> UNAuthorizationStatus {
        .authorized
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        true
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        Array(requests.values)
    }

    func deliveredNotifications() async -> [UNNotification] {
        []
    }

    func add(_ request: UNNotificationRequest) async throws {
        requests[request.identifier] = request
        addOrder.append(request.identifier)

        guard shouldBlockFirstAdd else { return }
        shouldBlockFirstAdd = false
        firstAddWaiters.forEach { $0.resume() }
        firstAddWaiters.removeAll()
        await withCheckedContinuation { continuation in
            firstAddRelease = continuation
        }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        for identifier in identifiers {
            requests.removeValue(forKey: identifier)
        }
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async { removedDelivered += identifiers }

    func removedDeliveredIdentifiers() -> [String] { removedDelivered }

    func removeAllPendingNotificationRequests() async {
        requests.removeAll()
        removeAllCalls += 1
    }

    func removeAllDeliveredNotifications() async {
        removeAllCalls += 1
    }

    func waitUntilFirstAddStarts() async {
        guard addOrder.isEmpty else { return }
        await withCheckedContinuation { continuation in
            firstAddWaiters.append(continuation)
        }
    }

    func releaseFirstAdd() {
        shouldBlockFirstAdd = false
        firstAddRelease?.resume()
        firstAddRelease = nil
    }

    func addedIdentifiers() -> [String] {
        addOrder
    }

    func removeAllCallCount() -> Int {
        removeAllCalls
    }
}

@MainActor
private final class CleanupValidity {
    var isCurrent = true
}
