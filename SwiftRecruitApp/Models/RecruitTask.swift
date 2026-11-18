import Foundation

struct RecruitTask: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    var companyID: UUID?
    var title: String
    var memo: String?
    var dueAt: Date?
    var dueOn: LocalDate? = nil
    var dueHasTime: Bool
    var completedAt: Date?
    var notificationTimedPreset: TimedNotificationPreset? = nil
    var notificationDatePreset: DateNotificationPreset? = nil
    var notificationEnabled: Bool
    let createdAt: Date
    var updatedAt: Date
    var version: Int = 1

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case companyID = "company_id"
        case title
        case memo
        case dueAt = "due_at"
        case dueOn = "due_on"
        case dueHasTime = "due_has_time"
        case completedAt = "completed_at"
        case notificationTimedPreset = "notification_timed_preset"
        case notificationDatePreset = "notification_date_preset"
        case notificationEnabled = "notification_enabled"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case version
    }

    var isCompleted: Bool { completedAt != nil }

    func isOverdue(relativeTo referenceDate: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard isCompleted == false, let dueDate = dueDate(calendar: calendar) else { return false }
        if dueHasTime { return dueDate < referenceDate }
        return calendar.startOfDay(for: dueDate) < calendar.startOfDay(for: referenceDate)
    }

    func dueDate(calendar: Calendar = .current) -> Date? {
        dueOn?.date(calendar: calendar) ?? dueAt
    }
}
