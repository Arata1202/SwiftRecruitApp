import Foundation
import UserNotifications

enum NotificationReconciliationTrigger {
    case refresh
    case saved(requestPermission: Bool)

    var requestsPermission: Bool {
        if case .saved(let requestPermission) = self { return requestPermission }
        return false
    }

    var failureMessage: String {
        switch self {
        case .refresh: "通知予定を更新できませんでした。iOSの通知設定を確認してください。"
        case .saved: "データは保存されましたが、通知を設定できませんでした。iOSの通知設定を確認してください。"
        }
    }
}

/// Owns notification authorization/reconciliation policy, never the session generation itself.
@MainActor
final class RecruitNotificationCoordinator {
    private let notifications: LocalNotificationService
    private let isCurrentSession: (Int) -> Bool
    private let currentCompanies: () -> [Company]
    private let currentSelectionSteps: () -> [SelectionStep]
    private let currentTasks: () -> [RecruitTask]
    private let updateAuthorization: (UNAuthorizationStatus) -> Void
    private let reportError: (String) -> Void

    private var companies: [Company] { currentCompanies() }
    private var selectionSteps: [SelectionStep] { currentSelectionSteps() }
    private var tasks: [RecruitTask] { currentTasks() }

    init(
        notifications: LocalNotificationService,
        isCurrentSession: @escaping (Int) -> Bool,
        companies: @escaping () -> [Company],
        selectionSteps: @escaping () -> [SelectionStep],
        tasks: @escaping () -> [RecruitTask],
        updateAuthorization: @escaping (UNAuthorizationStatus) -> Void,
        reportError: @escaping (String) -> Void
    ) {
        self.notifications = notifications
        self.isCurrentSession = isCurrentSession
        currentCompanies = companies
        currentSelectionSteps = selectionSteps
        currentTasks = tasks
        self.updateAuthorization = updateAuthorization
        self.reportError = reportError
    }

    func removeDeliveredAfterReload(
        generation: Int,
        userID: UUID,
        previousSteps: [SelectionStep],
        previousTasks: [RecruitTask],
        isCurrentReload: @escaping @MainActor @Sendable () -> Bool
    ) async {
        guard isCurrentSession(generation), isCurrentReload() else { return }
        await notifications.removeDeliveredNotifications(for: userID) { [weak self] delivered in
            guard let self, self.isCurrentSession(generation), isCurrentReload() else { return [] }
            let steps = self.selectionSteps.filter { $0.userID == userID }
            let tasks = self.tasks.filter { $0.userID == userID }
            var stepIDs = Set(previousSteps.filter { $0.userID == userID }.map(\.id))
            var taskIDs = Set(previousTasks.filter { $0.userID == userID }.map(\.id))
            for target in delivered {
                switch target.kind {
                case .task: taskIDs.insert(target.itemID)
                case .selection: stepIDs.insert(target.itemID)
                }
            }
            stepIDs.formUnion(steps.map(\.id))
            taskIDs.formUnion(tasks.map(\.id))
            stepIDs.subtract(steps.filter { $0.status == .scheduled }.map(\.id))
            taskIDs.subtract(tasks.filter { !$0.isCompleted }.map(\.id))
            return stepIDs.flatMap(NotificationPlanBuilder.selectionIdentifiers)
                + taskIDs.flatMap(NotificationPlanBuilder.taskIdentifiers)
        }
    }

    private var authorizationTask: Task<UNAuthorizationStatus, Error>?
    private var authorizationRevision = 0

    func authorization(generation: Int, requestPermission: Bool) async throws -> UNAuthorizationStatus {
        // Read settings after any earlier permission dialog has returned its decision.
        let previous = authorizationTask
        authorizationRevision &+= 1
        let revision = authorizationRevision
        let task = Task {
            _ = await previous?.result
            guard isCurrentSession(generation) else { throw CancellationError() }
            let status = try await notifications.authorizationStatus(requestIfNeeded: requestPermission) { [weak self] in
                self?.isCurrentSession(generation) == true
            }
            guard isCurrentSession(generation) else { throw CancellationError() }
            updateAuthorization(status)
            return status
        }
        authorizationTask = task
        defer { if authorizationRevision == revision { authorizationTask = nil } }
        return try await task.value
    }

    /// Returns true only when the notification center accepted the plan.
    func reconcile(
        generation: Int,
        trigger: NotificationReconciliationTrigger,
        isLatest: @escaping @MainActor @Sendable () -> Bool = { true }
    ) async throws -> Bool {
        guard isCurrentSession(generation) else { return false }
        let status: UNAuthorizationStatus
        do {
            status = try await authorization(generation: generation, requestPermission: trigger.requestsPermission)
        } catch is CancellationError {
            return false
        }
        guard isCurrentSession(generation), isLatest() else { return false }
        guard status.allowsScheduling else {
            if trigger.requestsPermission && status == .denied {
                reportError("データは保存されましたが、通知は許可されていません。設定画面からiOSの通知を有効にしてください。")
            }
            return false
        }

        let companyNames = Dictionary(
            uniqueKeysWithValues: companies.map { ($0.id, $0.name) }
        )
        try await notifications.reconcile(
            steps: selectionSteps,
            tasks: tasks,
            companyNames: companyNames
        )
        return true
    }
}
