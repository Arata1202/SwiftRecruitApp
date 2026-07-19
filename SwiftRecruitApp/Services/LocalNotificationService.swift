import Foundation
import UserNotifications

struct NotificationPlanItem: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let fireDate: Date
    let userInfo: [String: String]
}

enum NotificationPlanBuilder {
    static let maximumPendingCount = 64

    static func make(
        steps: [SelectionStep],
        tasks: [RecruitTask],
        companyNames: [UUID: String],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [NotificationPlanItem] {
        var items: [NotificationPlanItem] = []

        for step in steps where step.notificationEnabled && step.status == .scheduled {
            let companyName = companyNames[step.companyID] ?? "企業"

            if let startsAt = step.startDate(calendar: calendar),
               let fireDate = NotificationScheduleCalculator.selectionStartDate(
                   startsAt: startsAt,
                   hasTime: step.startsHasTime,
                   calendar: calendar,
                   now: now
               ) {
                items.append(
                    NotificationPlanItem(
                        identifier: selectionStartIdentifier(step.id),
                        title: step.startsHasTime
                            ? "1時間後に\(step.displayTitle)です"
                            : "今日は\(step.displayTitle)の予定があります",
                        body: step.startsHasTime
                            ? "\(companyName)｜\(DateFormatting.time.string(from: startsAt))開始"
                            : companyName,
                        fireDate: fireDate,
                        userInfo: [
                            "kind": "selection",
                            "item_id": step.id.uuidString,
                            "company_id": step.companyID.uuidString,
                        ]
                    )
                )
            }

            if let deadlineAt = step.deadlineDate(calendar: calendar),
               let fireDate = NotificationScheduleCalculator.selectionDeadlineDate(
                   deadlineAt: deadlineAt,
                   calendar: calendar,
                   now: now
               ) {
                items.append(
                    NotificationPlanItem(
                        identifier: selectionDeadlineIdentifier(step.id),
                        title: "明日が\(step.displayTitle)の締切です",
                        body: companyName,
                        fireDate: fireDate,
                        userInfo: [
                            "kind": "selection",
                            "item_id": step.id.uuidString,
                            "company_id": step.companyID.uuidString,
                        ]
                    )
                )
            }
        }

        for task in tasks
        where task.notificationEnabled && task.isCompleted == false {
            guard let dueAt = task.dueDate(calendar: calendar),
                  let fireDate = NotificationScheduleCalculator.taskDate(
                      dueAt: dueAt,
                      hasTime: task.dueHasTime,
                      calendar: calendar,
                      now: now
                  )
            else { continue }

            let companyName = task.companyID.flatMap { companyNames[$0] }
            items.append(
                NotificationPlanItem(
                    identifier: taskIdentifier(task.id),
                    title: task.title,
                    body: companyName.map { "\($0)｜期限を確認しましょう。" }
                        ?? "期限を確認しましょう。",
                    fireDate: fireDate,
                    userInfo: [
                        "kind": "task",
                        "item_id": task.id.uuidString,
                    ]
                )
            )
        }

        return Array(
            items
                .sorted {
                    $0.fireDate == $1.fireDate
                        ? $0.identifier < $1.identifier
                        : $0.fireDate < $1.fireDate
                }
                .prefix(maximumPendingCount)
        )
    }

    static func isRecruitIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix("selection-start-")
            || identifier.hasPrefix("selection-deadline-")
            || identifier.hasPrefix("task-")
    }

    static func selectionIdentifiers(_ id: UUID) -> [String] {
        [selectionStartIdentifier(id), selectionDeadlineIdentifier(id)]
    }

    static func taskIdentifiers(_ id: UUID) -> [String] {
        [taskIdentifier(id)]
    }

    private static func selectionStartIdentifier(_ id: UUID) -> String {
        "selection-start-\(id.uuidString)"
    }

    private static func selectionDeadlineIdentifier(_ id: UUID) -> String {
        "selection-deadline-\(id.uuidString)"
    }

    private static func taskIdentifier(_ id: UUID) -> String {
        "task-\(id.uuidString)"
    }
}

protocol UserNotificationCenterClient: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func deliveredNotifications() async -> [UNNotification]
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async
    func removeAllPendingNotificationRequests() async
    func removeAllDeliveredNotifications() async
}

private struct SystemUserNotificationCenterClient: UserNotificationCenterClient, @unchecked Sendable {
    let center: UNUserNotificationCenter

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }

    func deliveredNotifications() async -> [UNNotification] {
        await center.deliveredNotifications()
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func removeAllPendingNotificationRequests() async {
        center.removeAllPendingNotificationRequests()
    }

    func removeAllDeliveredNotifications() async {
        center.removeAllDeliveredNotifications()
    }
}

actor LocalNotificationService {
    private let center: any UserNotificationCenterClient
    private var operationTail: Task<Void, Never>?

    init(center: UNUserNotificationCenter = .current()) {
        self.center = SystemUserNotificationCenterClient(center: center)
    }

    init(client: any UserNotificationCenterClient) {
        center = client
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.authorizationStatus()
    }

    func canScheduleWithoutPrompt() async -> Bool {
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            true
        case .denied, .notDetermined:
            false
        @unknown default:
            false
        }
    }

    func requestAuthorizationIfNeeded() async throws -> Bool {
        let status = await authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        @unknown default:
            return false
        }
    }

    func reconcile(
        steps: [SelectionStep],
        tasks: [RecruitTask],
        companyNames: [UUID: String]
    ) async throws {
        let plan = NotificationPlanBuilder.make(
            steps: steps,
            tasks: tasks,
            companyNames: companyNames
        )

        try await performSerially {
            try await apply(plan)
        }
    }

    func cancelSelection(id: UUID) async {
        await performSerially {
            await remove(identifiers: NotificationPlanBuilder.selectionIdentifiers(id))
        }
    }

    func cancelTask(id: UUID) async {
        await performSerially {
            await remove(identifiers: NotificationPlanBuilder.taskIdentifiers(id))
        }
    }

    func invalidateAndCancelAll() async {
        await performSerially {
            await center.removeAllPendingNotificationRequests()
            await center.removeAllDeliveredNotifications()
        }
    }

    private func apply(_ plan: [NotificationPlanItem]) async throws {
        let desiredIdentifiers = Set(plan.map(\.identifier))

        let pending = await center.pendingNotificationRequests()
        let stalePending = pending
            .map(\.identifier)
            .filter {
                NotificationPlanBuilder.isRecruitIdentifier($0)
                    && desiredIdentifiers.contains($0) == false
            }
        if stalePending.isEmpty == false {
            await center.removePendingNotificationRequests(withIdentifiers: stalePending)
        }

        let delivered = await center.deliveredNotifications()
        let deliveredIdentifiers = delivered
            .map { $0.request.identifier }
            .filter(NotificationPlanBuilder.isRecruitIdentifier)
        if deliveredIdentifiers.isEmpty == false {
            await center.removeDeliveredNotifications(withIdentifiers: deliveredIdentifiers)
        }

        for item in plan {
            try await add(item)
        }
    }

    private func remove(identifiers: [String]) async {
        await center.removePendingNotificationRequests(withIdentifiers: identifiers)
        await center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func add(_ item: NotificationPlanItem) async throws {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = .default
        content.userInfo = item.userInfo

        var calendar = Calendar.current
        calendar.timeZone = .current
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: item.fireDate
        )
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(
            UNNotificationRequest(
                identifier: item.identifier,
                content: content,
                trigger: trigger
            )
        )
    }

    private func performSerially(
        _ operation: () async throws -> Void
    ) async rethrows {
        // Actor methods are reentrant at each await. Chaining completion tasks
        // keeps every notification-center mutation in deterministic FIFO order.
        let previousOperation = operationTail
        let (completionStream, completion) = AsyncStream<Void>.makeStream()
        let currentOperation = Task {
            for await _ in completionStream {}
        }
        operationTail = currentOperation

        await previousOperation?.value
        defer { completion.finish() }
        try await operation()
    }
}
