import Foundation

/// Owns notification authorization/reconciliation policy, never the session generation itself.
@MainActor
final class RecruitNotificationCoordinator {
    private let notifications: LocalNotificationService
    private let isCurrentSession: (Int) -> Bool
    private let currentCompanies: () -> [Company]
    private let currentSelectionSteps: () -> [SelectionStep]
    private let currentTasks: () -> [RecruitTask]
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
        reportError: @escaping (String) -> Void
    ) {
        self.notifications = notifications
        self.isCurrentSession = isCurrentSession
        currentCompanies = companies
        currentSelectionSteps = selectionSteps
        currentTasks = tasks
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
        let steps = selectionSteps.filter { $0.userID == userID }
        let accountTasks = tasks.filter { $0.userID == userID }
        let stepIDs = Set(steps.map(\.id))
        let taskIDs = Set(accountTasks.map(\.id))
        let removedSteps = Set(previousSteps.filter { $0.userID == userID }.map(\.id))
            .subtracting(stepIDs)
            .union(steps.filter { $0.status != .scheduled }.map(\.id))
        let removedTasks = Set(previousTasks.filter { $0.userID == userID }.map(\.id))
            .subtracting(taskIDs)
            .union(accountTasks.filter(\.isCompleted).map(\.id))
        await notifications.removeDeliveredNotifications(
            selectionIDs: removedSteps,
            taskIDs: removedTasks,
            isCurrent: { [weak self] in
                self?.isCurrentSession(generation) == true && isCurrentReload()
            }
        )
    }

    func reconcile(
        generation: Int,
        promptIfNeeded: Bool,
        reportDenied: Bool
    ) async {
        guard isCurrentSession(generation) else { return }

        do {
            let isAuthorized: Bool
            if promptIfNeeded {
                isAuthorized = try await notifications.requestAuthorizationIfNeeded()
            } else {
                isAuthorized = await notifications.canScheduleWithoutPrompt()
            }

            guard isCurrentSession(generation) else { return }
            guard isAuthorized else {
                if reportDenied {
                    reportError("データは保存されましたが、通知は許可されていません。設定画面からiOSの通知を有効にしてください。")
                }
                return
            }

            let companyNames = Dictionary(
                uniqueKeysWithValues: companies.map { ($0.id, $0.name) }
            )
            try await notifications.reconcile(
                steps: selectionSteps,
                tasks: tasks,
                companyNames: companyNames
            )
        } catch {
            guard isCurrentSession(generation) else { return }
            reportError("データは保存されましたが、通知を設定できませんでした。iOSの通知設定を確認してください。")
        }
    }
}
