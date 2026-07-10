import Foundation
import UserNotifications

struct NotificationRoute: Sendable {
    let kind: String
    let itemID: UUID
    let companyID: UUID?
}

actor LocalNotificationService {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
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

    func schedule(step: SelectionStep, companyName: String) async throws {
        await cancelSelection(id: step.id)
        guard step.notificationEnabled, step.status == .scheduled else { return }
        guard try await requestAuthorizationIfNeeded() else { return }

        if let startsAt = step.startsAt,
           let fireDate = NotificationScheduleCalculator.selectionStartDate(startsAt: startsAt) {
            try await add(
                identifier: selectionStartIdentifier(step.id),
                title: "まもなく\(step.displayTitle)です",
                body: "\(companyName)の予定は\(DateFormatting.time.string(from: startsAt))からです。",
                fireDate: fireDate,
                userInfo: [
                    "kind": "selection",
                    "item_id": step.id.uuidString,
                    "company_id": step.companyID.uuidString,
                ]
            )
        }

        if let deadlineAt = step.deadlineAt,
           let fireDate = NotificationScheduleCalculator.selectionDeadlineDate(deadlineAt: deadlineAt) {
            try await add(
                identifier: selectionDeadlineIdentifier(step.id),
                title: "明日が締切です",
                body: "\(companyName)の\(step.displayTitle)を確認しましょう。",
                fireDate: fireDate,
                userInfo: [
                    "kind": "selection",
                    "item_id": step.id.uuidString,
                    "company_id": step.companyID.uuidString,
                ]
            )
        }
    }

    func schedule(task: RecruitTask, companyName: String?) async throws {
        await cancelTask(id: task.id)
        guard task.notificationEnabled, task.isCompleted == false, let dueAt = task.dueAt else { return }
        guard try await requestAuthorizationIfNeeded() else { return }
        guard let fireDate = NotificationScheduleCalculator.taskDate(
            dueAt: dueAt,
            hasTime: task.dueHasTime
        ) else { return }

        let companyText = companyName.map { "（\($0)）" } ?? ""
        try await add(
            identifier: taskIdentifier(task.id),
            title: task.title,
            body: "期限を確認しましょう\(companyText)。",
            fireDate: fireDate,
            userInfo: [
                "kind": "task",
                "item_id": task.id.uuidString,
            ]
        )
    }

    func cancelSelection(id: UUID) async {
        center.removePendingNotificationRequests(withIdentifiers: [
            selectionStartIdentifier(id),
            selectionDeadlineIdentifier(id),
        ])
    }

    func cancelTask(id: UUID) async {
        center.removePendingNotificationRequests(withIdentifiers: [taskIdentifier(id)])
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    private func add(
        identifier: String,
        title: String,
        body: String,
        fireDate: Date,
        userInfo: [String: String]
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo

        var calendar = Calendar.current
        calendar.timeZone = .current
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    private func selectionStartIdentifier(_ id: UUID) -> String { "selection-start-\(id.uuidString)" }
    private func selectionDeadlineIdentifier(_ id: UUID) -> String { "selection-deadline-\(id.uuidString)" }
    private func taskIdentifier(_ id: UUID) -> String { "task-\(id.uuidString)" }
}
