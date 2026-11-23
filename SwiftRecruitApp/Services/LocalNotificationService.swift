import Foundation
import UserNotifications

struct NotificationPlanItem: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let fireDate: Date
    let userInfo: [String: String]
}

/// A computed plan, not confirmation of OS acceptance or delivery.
struct NotificationPlan: Equatable, Sendable {
    let admitted: [NotificationPlanItem]
    let overflow: [NotificationPlanItem]
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
        assessment(steps: steps, tasks: tasks, companyNames: companyNames, calendar: calendar, now: now).admitted
    }

    static func assessment(
        steps: [SelectionStep],
        tasks: [RecruitTask],
        companyNames: [UUID: String],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> NotificationPlan {
        var items: [NotificationPlanItem] = []

        for step in steps where step.notificationEnabled && step.status == .scheduled {
            let companyName = companyNames[step.companyID] ?? "企業"

            if let startsAt = step.startDate(calendar: calendar),
               let fireDate = NotificationScheduleCalculator.reminderDate(
                   anchor: startsAt,
                   hasTime: step.startsHasTime, kind: .selectionStart,
                   timedPreset: step.notificationTimedPreset, datePreset: step.notificationDatePreset,
                   timedCustom: step.notificationTimedCustom, dateCustom: step.notificationDateCustom,
                   absoluteAt: step.notificationAbsoluteAt,
                   calendar: calendar
               ), fireDate > now {
                items.append(
                    NotificationPlanItem(
                        identifier: selectionStartIdentifier(step.id),
                        title: "\(step.displayTitle)の予定",
                        body: "\(companyName)｜開始：\(anchorDescription(startsAt, hasTime: step.startsHasTime, calendar: calendar))",
                        fireDate: fireDate,
                        userInfo: [
                            "kind": "selection",
                            "item_id": step.id.uuidString,
                            "user_id": step.userID.uuidString,
                            "company_id": step.companyID.uuidString,
                        ]
                    )
                )
            }

            if step.notificationAbsoluteAt == nil || step.startDate(calendar: calendar) == nil,
               let deadlineAt = step.deadlineDate(calendar: calendar),
               let fireDate = NotificationScheduleCalculator.reminderDate(
                   anchor: deadlineAt, hasTime: step.deadlineHasTime, kind: .selectionDeadline,
                   timedPreset: step.notificationTimedPreset, datePreset: step.notificationDatePreset,
                   timedCustom: step.notificationTimedCustom, dateCustom: step.notificationDateCustom,
                   absoluteAt: step.notificationAbsoluteAt,
                   calendar: calendar
               ), fireDate > now {
                items.append(
                    NotificationPlanItem(
                        identifier: selectionDeadlineIdentifier(step.id),
                        title: "\(step.displayTitle)の締切",
                        body: "\(companyName)｜期限：\(anchorDescription(deadlineAt, hasTime: step.deadlineHasTime, calendar: calendar))",
                        fireDate: fireDate,
                        userInfo: [
                            "kind": "selection",
                            "item_id": step.id.uuidString,
                            "user_id": step.userID.uuidString,
                            "company_id": step.companyID.uuidString,
                        ]
                    )
                )
            }
        }

        for task in tasks
        where task.notificationEnabled && task.isCompleted == false {
            guard let dueAt = task.dueDate(calendar: calendar),
                  let fireDate = NotificationScheduleCalculator.reminderDate(
                      anchor: dueAt,
                      hasTime: task.dueHasTime, kind: .taskDue,
                      timedPreset: task.notificationTimedPreset, datePreset: task.notificationDatePreset,
                      timedCustom: task.notificationTimedCustom, dateCustom: task.notificationDateCustom,
                   absoluteAt: task.notificationAbsoluteAt,
                      calendar: calendar
                  ), fireDate > now
            else { continue }

            let companyName = task.companyID.flatMap { companyNames[$0] }
            items.append(
                NotificationPlanItem(
                    identifier: taskIdentifier(task.id),
                    title: task.title,
                    body: (companyName.map { "\($0)｜" } ?? "")
                        + "期限：\(anchorDescription(dueAt, hasTime: task.dueHasTime, calendar: calendar))",
                    fireDate: fireDate,
                    userInfo: [
                        "kind": "task",
                        "item_id": task.id.uuidString,
                        "user_id": task.userID.uuidString,
                    ]
                )
            )
        }

        let ordered = items.sorted {
            $0.fireDate == $1.fireDate
                ? $0.identifier < $1.identifier
                : $0.fireDate < $1.fireDate
        }
        return NotificationPlan(
            admitted: Array(ordered.prefix(maximumPendingCount)),
            overflow: Array(ordered.dropFirst(maximumPendingCount))
        )
    }

    static func anchorDescription(_ date: Date, hasTime: Bool, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = hasTime ? "yyyy年M月d日 H:mm" : "yyyy年M月d日"
        return formatter.string(from: date)
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

    func authorizationStatus(requestIfNeeded: Bool) async throws -> UNAuthorizationStatus {
        let status = await authorizationStatus()
        guard requestIfNeeded, status == .notDetermined else { return status }
        _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        return await authorizationStatus()
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

    // Pending-plan omissions (past dates, disabled reminders, or the cap) are not deletion evidence.
    func removeDeliveredNotifications(
        selectionIDs: Set<UUID>,
        taskIDs: Set<UUID>,
        isCurrent: @escaping @MainActor @Sendable () -> Bool
    ) async {
        let identifiers = selectionIDs.flatMap(NotificationPlanBuilder.selectionIdentifiers)
            + taskIDs.flatMap(NotificationPlanBuilder.taskIdentifiers)
        guard identifiers.isEmpty == false else { return }
        await performSerially {
            guard Task.isCancelled == false, await isCurrent() else { return }
            await center.removeDeliveredNotifications(withIdentifiers: identifiers)
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

        for item in plan {
            try await add(item)
        }
    }

    private func remove(identifiers: [String]) async {
        await center.removePendingNotificationRequests(withIdentifiers: identifiers)
        await center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func add(_ item: NotificationPlanItem) async throws {
        guard item.fireDate > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = .default
        content.userInfo = item.userInfo

        // Encode the calculated instant in UTC so a repeated local hour cannot
        // shift an elapsed reminder to the other occurrence. Recalculate local
        // calendar preferences on foreground/time-zone changes.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: item.fireDate
        )
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        guard let triggerDate = trigger.nextTriggerDate(), triggerDate > Date() else { return }
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

extension UNAuthorizationStatus {
    var allowsScheduling: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral: true
        case .denied, .notDetermined: false
        @unknown default: false
        }
    }
}
