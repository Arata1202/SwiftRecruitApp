import Foundation

struct SelectionStep: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let companyID: UUID
    var type: SelectionType
    var customTitle: String?
    var startsAt: Date?
    var deadlineAt: Date?
    var status: SelectionStepStatus
    var memo: String?
    var notificationEnabled: Bool
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case companyID = "company_id"
        case type
        case customTitle = "custom_title"
        case startsAt = "starts_at"
        case deadlineAt = "deadline_at"
        case status
        case memo
        case notificationEnabled = "notification_enabled"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var displayTitle: String {
        if type == .other, let customTitle, customTitle.isEmpty == false {
            return customTitle
        }
        return type.title
    }

    func nextDate(relativeTo referenceDate: Date = Date()) -> Date? {
        nextMilestone(relativeTo: referenceDate)?.date
    }

    func nextMilestone(relativeTo referenceDate: Date = Date()) -> SelectionMilestone? {
        var milestones: [SelectionMilestone] = []
        if let startsAt, startsAt >= referenceDate {
            milestones.append(SelectionMilestone(kind: .start, date: startsAt))
        }
        if let deadlineAt, deadlineAt >= referenceDate {
            milestones.append(SelectionMilestone(kind: .deadline, date: deadlineAt))
        }
        return milestones.min { $0.date < $1.date }
    }

    var earliestDate: Date? {
        [startsAt, deadlineAt].compactMap { $0 }.min()
    }
}

struct SelectionMilestone: Equatable, Sendable {
    let kind: SelectionMilestoneKind
    let date: Date
}

enum SelectionMilestoneKind: Equatable, Sendable {
    case start
    case deadline

    var title: String {
        switch self {
        case .start: "予定"
        case .deadline: "締切"
        }
    }

    var systemImage: String {
        switch self {
        case .start: "clock"
        case .deadline: "exclamationmark.circle"
        }
    }
}

enum SelectionType: String, Codable, CaseIterable, Identifiable, Sendable {
    case briefing
    case document
    case aptitude
    case interview
    case offer
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .briefing: "説明会"
        case .document: "書類選考"
        case .aptitude: "適性検査"
        case .interview: "面接"
        case .offer: "内定・オファー"
        case .other: "その他"
        }
    }

    var systemImage: String {
        switch self {
        case .briefing: "person.3"
        case .document: "doc.text"
        case .aptitude: "checklist"
        case .interview: "person.crop.rectangle.stack"
        case .offer: "checkmark.seal"
        case .other: "square.grid.2x2"
        }
    }
}

enum SelectionStepStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case scheduled
    case completed
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scheduled: "予定"
        case .completed: "完了"
        case .cancelled: "中止"
        }
    }
}
