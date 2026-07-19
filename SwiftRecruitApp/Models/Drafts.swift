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
}

struct RecruitTaskDraft: Sendable {
    var title = ""
    var companyID: UUID?
    var hasDueDate = true
    var dueAt = Date()
    var dueHasTime = false
    var notificationEnabled = true

    init() {}

    init(task: RecruitTask) {
        title = task.title
        companyID = task.companyID
        hasDueDate = task.dueDate() != nil
        dueAt = task.dueDate() ?? Date()
        dueHasTime = task.dueHasTime
        notificationEnabled = task.notificationEnabled
    }
}
