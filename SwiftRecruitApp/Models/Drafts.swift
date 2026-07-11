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

    init(step: SelectionStep) {
        type = step.type
        customTitle = step.customTitle ?? ""
        if step.startsAt != nil && step.deadlineAt == nil {
            dateKind = .schedule
        } else if step.deadlineAt != nil && step.startsAt == nil {
            dateKind = .deadline
        } else {
            dateKind = step.type.defaultDateKind
        }
        if dateKind == .deadline {
            date = step.deadlineAt ?? step.startsAt ?? Date()
            hasTime = step.deadlineAt != nil ? step.deadlineHasTime : step.startsHasTime
        } else {
            date = step.startsAt ?? step.deadlineAt ?? Date()
            hasTime = step.startsAt != nil ? step.startsHasTime : step.deadlineHasTime
        }
        status = step.status
        memo = step.memo ?? ""
        notificationEnabled = step.notificationEnabled
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

    init(task: RecruitTask) {
        title = task.title
        memo = task.memo ?? ""
        companyID = task.companyID
        hasDueDate = task.dueAt != nil
        dueAt = task.dueAt ?? Date()
        dueHasTime = task.dueHasTime
        notificationEnabled = task.notificationEnabled
    }
}
