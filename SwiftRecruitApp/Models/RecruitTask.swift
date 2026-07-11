import Foundation

struct RecruitTask: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    var companyID: UUID?
    var title: String
    var memo: String?
    var dueAt: Date?
    var dueHasTime: Bool
    var completedAt: Date?
    var notificationEnabled: Bool
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case companyID = "company_id"
        case title
        case memo
        case dueAt = "due_at"
        case dueHasTime = "due_has_time"
        case completedAt = "completed_at"
        case notificationEnabled = "notification_enabled"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var isCompleted: Bool { completedAt != nil }

    func isOverdue(relativeTo referenceDate: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard isCompleted == false, let dueAt else { return false }
        if dueHasTime { return dueAt < referenceDate }
        return calendar.startOfDay(for: dueAt) < calendar.startOfDay(for: referenceDate)
    }
}
