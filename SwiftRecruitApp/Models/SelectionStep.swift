import Foundation

struct SelectionStep: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let companyID: UUID
    var type: SelectionType
    var customTitle: String?
    var startsAt: Date?
    var startsOn: LocalDate? = nil
    var endsAt: Date? = nil
    var endsOn: LocalDate? = nil
    var startsHasTime: Bool
    var deadlineAt: Date?
    var deadlineOn: LocalDate? = nil
    var deadlineHasTime: Bool
    var status: SelectionStepStatus
    var memo: String?
    var notificationTimedPreset: TimedNotificationPreset? = nil
    var notificationDatePreset: DateNotificationPreset? = nil
    var notificationTimedCustom: CustomNotificationTiming? = nil
    var notificationDateCustom: CustomNotificationTiming? = nil
    var notificationAbsoluteAt: Date? = nil
    var notificationEnabled: Bool
    let createdAt: Date
    var updatedAt: Date
    var version: Int = 1

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case companyID = "company_id"
        case type
        case customTitle = "custom_title"
        case startsAt = "starts_at"
        case startsOn = "starts_on"
        case endsAt = "ends_at"
        case endsOn = "ends_on"
        case startsHasTime = "starts_has_time"
        case deadlineAt = "deadline_at"
        case deadlineOn = "deadline_on"
        case deadlineHasTime = "deadline_has_time"
        case status
        case memo
        case notificationTimedPreset = "notification_timed_preset"
        case notificationDatePreset = "notification_date_preset"
        case notificationTimedCustom = "notification_timed_custom"
        case notificationDateCustom = "notification_date_custom"
        case notificationAbsoluteAt = "notification_absolute_at"
        case notificationEnabled = "notification_enabled"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case version
    }

    var displayTitle: String {
        guard let customTitle,
              !customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return type.title
        }
        // Preserve stored titles, including legacy titles such as “一次面接”.
        if type == .other || customTitle.contains(type.title) {
            return customTitle
        }
        return "\(type.title)／\(customTitle)"
    }

    func nextDate(relativeTo referenceDate: Date = Date()) -> Date? {
        nextMilestone(relativeTo: referenceDate)?.date
    }

    func nextMilestone(relativeTo referenceDate: Date = Date()) -> SelectionMilestone? {
        var milestones: [SelectionMilestone] = []
        if let date = startDate(),
           isUpcoming(date, hasTime: startsHasTime, relativeTo: referenceDate) {
            milestones.append(SelectionMilestone(kind: .start, date: date, hasTime: startsHasTime))
        }
        if let date = deadlineDate(),
           isUpcoming(date, hasTime: deadlineHasTime, relativeTo: referenceDate) {
            milestones.append(SelectionMilestone(kind: .deadline, date: date, hasTime: deadlineHasTime))
        }
        if let upcoming = milestones.min(by: { $0.date < $1.date }) { return upcoming }
        guard isOngoing(relativeTo: referenceDate), let start = startDate() else { return nil }
        return SelectionMilestone(kind: .start, date: start, hasTime: startsHasTime)
    }

    var earliestDate: Date? {
        [startDate(), deadlineDate()].compactMap { $0 }.min()
    }

    func startDate(calendar: Calendar = .current) -> Date? {
        startsOn?.date(calendar: calendar) ?? startsAt
    }

    func endDate(calendar: Calendar = .current) -> Date? {
        endsOn?.date(calendar: calendar) ?? endsAt
    }

    /// Timed ranges are half-open; date-only ranges include their last calendar day.
    func isOngoing(relativeTo now: Date, calendar: Calendar = .current) -> Bool {
        guard let start = startDate(calendar: calendar), let end = endDate(calendar: calendar) else { return false }
        if startsHasTime { return start <= now && now < end }
        let day = calendar.startOfDay(for: now)
        return calendar.startOfDay(for: start) <= day && day <= calendar.startOfDay(for: end)
    }

    func coveredDays(calendar: Calendar = .current) -> ClosedRange<Date>? {
        guard let start = startDate(calendar: calendar) else { return nil }
        let first = calendar.startOfDay(for: start)
        guard let end = endDate(calendar: calendar), end > start else { return first...first }
        let last = calendar.startOfDay(for: end)
        // A timed end at the start of a day belongs exclusively to the previous day.
        if startsHasTime && end == last {
            return first...calendar.startOfDay(for: end.addingTimeInterval(-1))
        }
        return first...last
    }

    func covers(day: Date, calendar: Calendar = .current) -> Bool {
        coveredDays(calendar: calendar)?.contains(calendar.startOfDay(for: day)) == true
    }

    func deadlineDate(calendar: Calendar = .current) -> Date? {
        deadlineOn?.date(calendar: calendar) ?? deadlineAt
    }

    private func isUpcoming(_ date: Date, hasTime: Bool, relativeTo referenceDate: Date) -> Bool {
        if hasTime { return date >= referenceDate }
        return Calendar.current.startOfDay(for: date) >= Calendar.current.startOfDay(for: referenceDate)
    }
}

struct SelectionMilestone: Equatable, Sendable {
    let kind: SelectionMilestoneKind
    let date: Date
    let hasTime: Bool
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

enum SelectionDateKind: String, CaseIterable, Identifiable, Sendable {
    case schedule
    case deadline

    var id: Self { self }

    var title: String {
        switch self {
        case .schedule: "予定"
        case .deadline: "締切"
        }
    }
}

enum SelectionType: String, Codable, CaseIterable, Identifiable, Sendable {
    case briefing
    case internship
    case document
    case aptitude
    case interview
    case offer
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .briefing: "説明会"
        case .internship: "インターンシップ"
        case .document: "書類選考"
        case .aptitude: "適性検査"
        case .interview: "面接"
        case .offer: "内定・オファー"
        case .other: "その他"
        }
    }

    var systemImage: String {
        switch self {
        case .briefing: "megaphone"
        case .internship: "briefcase"
        case .document: "doc.text"
        case .aptitude: "checklist"
        case .interview: "person.crop.rectangle.stack"
        case .offer: "checkmark.seal"
        case .other: "square.grid.2x2"
        }
    }

    var defaultDateKind: SelectionDateKind {
        switch self {
        case .document, .aptitude: .deadline
        case .briefing, .internship, .interview, .offer, .other: .schedule
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
