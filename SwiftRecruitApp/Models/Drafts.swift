import Foundation

struct CompanyDraft: Sendable {
    var name = ""
    var priority = 3
    var status: CompanyStatus = .considering
    var url = ""
    var memo = ""

    init() {}

    init(company: Company) {
        name = company.name
        // Preserve the hidden compatibility field when editing an existing company.
        priority = company.priority
        status = company.status
        url = company.url ?? ""
        memo = company.memo ?? ""
    }
}

struct SelectionStepDraft: Sendable {
    var type: SelectionType = .interview
    var customTitle = ""
    var dateKind: SelectionDateKind = .schedule
    var date = Date()
    var hasTime = false
    var status: SelectionStepStatus = .scheduled
    var memo = ""
    var notificationEnabled = true

    init() {}

    init(date: Date) {
        self.date = date
    }

    init(step: SelectionStep) {
        type = step.type
        customTitle = step.customTitle ?? ""
        if step.startDate() != nil && step.deadlineDate() == nil {
            dateKind = .schedule
        } else if step.deadlineDate() != nil && step.startDate() == nil {
            dateKind = .deadline
        } else {
            dateKind = step.type.defaultDateKind
        }
        if dateKind == .deadline {
            date = step.deadlineDate() ?? step.startDate() ?? Date()
            hasTime = step.deadlineDate() != nil ? step.deadlineHasTime : step.startsHasTime
        } else {
            date = step.startDate() ?? step.deadlineDate() ?? Date()
            hasTime = step.startDate() != nil ? step.startsHasTime : step.deadlineHasTime
        }
        status = step.status
        memo = step.memo ?? ""
        notificationEnabled = step.notificationEnabled
    }

    func notificationDescription(calendar: Calendar = .current, now: Date = Date()) -> String? {
        guard status == .scheduled, notificationEnabled else { return nil }
        let notificationDate: Date?
        let timing: String
        switch dateKind {
        case .schedule:
            notificationDate = NotificationScheduleCalculator.selectionStartDate(
                startsAt: date, hasTime: hasTime, calendar: calendar, now: now
            )
            timing = hasTime ? "予定時刻の1時間前" : "予定日の9時"
        case .deadline:
            notificationDate = NotificationScheduleCalculator.selectionDeadlineDate(
                deadlineAt: date, calendar: calendar, now: now
            )
            timing = "締切前日の20時"
        }
        guard notificationDate != nil else {
            return "通知時刻（\(timing)）を過ぎているため、この日程では通知されません。"
        }
        return "\(timing)に通知予定です。端末の通知設定によっては届かない場合があります。"
    }
}

struct RecruitTaskDraft: Sendable {
    var title = ""
    var memo = ""
    var companyID: UUID?
    var hasDueDate = true
    var dueAt = Date()
    var dueHasTime = false
    var notificationEnabled = true

    init() {}

    init(dueDate: Date) {
        dueAt = dueDate
    }

    init(task: RecruitTask) {
        title = task.title
        memo = task.memo ?? ""
        companyID = task.companyID
        hasDueDate = task.dueDate() != nil
        dueAt = task.dueDate() ?? Date()
        dueHasTime = task.dueHasTime
        notificationEnabled = task.notificationEnabled
    }
}
