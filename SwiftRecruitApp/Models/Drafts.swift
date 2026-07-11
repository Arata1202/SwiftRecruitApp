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
    var hasStartsAt = true
    var startsAt = Date().addingTimeInterval(86_400)
    var startsHasTime = false
    var hasDeadline = false
    var deadlineAt = Date().addingTimeInterval(86_400)
    var deadlineHasTime = false
    var status: SelectionStepStatus = .scheduled
    var memo = ""
    var notificationEnabled = true

    init() {}

    init(step: SelectionStep) {
        type = step.type
        customTitle = step.customTitle ?? ""
        hasStartsAt = step.startsAt != nil
        startsAt = step.startsAt ?? Date()
        startsHasTime = step.startsHasTime
        hasDeadline = step.deadlineAt != nil
        deadlineAt = step.deadlineAt ?? Date()
        deadlineHasTime = step.deadlineHasTime
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
