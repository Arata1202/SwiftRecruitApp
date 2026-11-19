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
    var hasEnd = false
    var endDate = Date()
    private var hasExplicitEnd = false
    private var hasExplicitTime = false
    var status: SelectionStepStatus = .scheduled
    var memo = ""
    // Nil in a new draft means the user has not selected a timing yet.
    var notificationTimedPreset: TimedNotificationPreset? = nil
    var notificationDatePreset: DateNotificationPreset? = nil
    var notificationTimedCustom: CustomNotificationTiming? = nil
    var notificationDateCustom: CustomNotificationTiming? = nil
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
        hasEnd = step.endDate() != nil
        endDate = step.endDate() ?? date
        hasExplicitEnd = hasEnd
        hasExplicitTime = hasTime
        status = step.status
        memo = step.memo ?? ""
        // Existing records keep their effective preference even if the date kind changes.
        notificationTimedPreset = step.notificationTimedPreset ?? notificationAnchor.defaultTimedPreset
        notificationDatePreset = step.notificationDatePreset ?? notificationAnchor.defaultDatePreset
        notificationTimedCustom = step.notificationTimedCustom
        notificationDateCustom = step.notificationDateCustom
        notificationEnabled = step.notificationEnabled
    }

    var isCustomTitleTooLong: Bool {
        InputLimits.length(of: customTitle.trimmingCharacters(in: .whitespacesAndNewlines)) > InputLimits.selectionTitle
    }

    var notificationAnchor: NotificationAnchor {
        dateKind == .schedule ? .selectionStart : .selectionDeadline
    }

    var resolvedNotificationTimedPreset: TimedNotificationPreset {
        notificationTimedPreset ?? notificationAnchor.defaultTimedPreset
    }

    var resolvedNotificationDatePreset: DateNotificationPreset {
        notificationDatePreset ?? notificationAnchor.defaultDatePreset
    }

    /// Only the first explicit time in this editor is initialized from the clock.
    mutating func setHasTime(_ enabled: Bool, now: Date = Date(), calendar: Calendar = .current) {
        if enabled && !hasTime && !hasExplicitTime {
            date = initialExplicitTime(on: date, now: now, calendar: calendar)
        }
        hasExplicitTime = hasExplicitTime || hasTime || enabled
        hasTime = enabled
    }

    mutating func setHasEnd(_ enabled: Bool) {
        if enabled && !hasExplicitEnd { endDate = date }
        hasExplicitEnd = hasExplicitEnd || enabled
        hasEnd = enabled
    }

    func isValidRange(calendar: Calendar = .current) -> Bool {
        guard dateKind == .schedule, hasEnd else { return true }
        return hasTime ? endDate >= date : LocalDate(date: endDate, calendar: calendar) >= LocalDate(date: date, calendar: calendar)
    }

    func notificationDescription(calendar: Calendar = .current, now: Date = Date()) -> String? {
        guard status == .scheduled, notificationEnabled else { return nil }
        if let error = notificationValidationMessage(calendar: calendar) { return error }
        return NotificationScheduleCalculator.reminderDescription(
            NotificationScheduleCalculator.reminderDate(
                anchor: date, hasTime: hasTime,
                kind: dateKind == .schedule ? .selectionStart : .selectionDeadline,
                timedPreset: notificationTimedPreset, datePreset: notificationDatePreset,
                timedCustom: notificationTimedCustom, dateCustom: notificationDateCustom, calendar: calendar
            ), now: now, calendar: calendar
        )
    }
}

struct RecruitTaskDraft: Sendable {
    var title = ""
    var memo = ""
    var companyID: UUID?
    var hasDueDate = true
    var dueAt = Date()
    var dueHasTime = false
    private var hasExplicitTime = false
    var notificationTimedPreset: TimedNotificationPreset? = .atTime
    var notificationDatePreset: DateNotificationPreset? = .sameDay
    var notificationTimedCustom: CustomNotificationTiming? = nil
    var notificationDateCustom: CustomNotificationTiming? = nil
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
        hasExplicitTime = hasDueDate && dueHasTime
        notificationTimedPreset = task.notificationTimedPreset ?? NotificationAnchor.taskDue.defaultTimedPreset
        notificationDatePreset = task.notificationDatePreset ?? NotificationAnchor.taskDue.defaultDatePreset
        notificationTimedCustom = task.notificationTimedCustom
        notificationDateCustom = task.notificationDateCustom
        notificationEnabled = task.notificationEnabled
    }

    mutating func setDueHasTime(_ enabled: Bool, now: Date = Date(), calendar: Calendar = .current) {
        if enabled && !dueHasTime && !hasExplicitTime {
            dueAt = initialExplicitTime(on: dueAt, now: now, calendar: calendar)
        }
        hasExplicitTime = hasExplicitTime || dueHasTime || enabled
        dueHasTime = enabled
    }
}

// Shared by both editors. Never move the selected day, including at DST boundaries.
private func initialExplicitTime(on date: Date, now: Date, calendar: Calendar) -> Date {
    let time = calendar.dateComponents([.hour, .minute], from: now)
    if let result = calendar.date(
        bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: date,
        matchingPolicy: .nextTime, repeatedTimePolicy: .first
    ), calendar.isDate(result, inSameDayAs: date) {
        return result
    }
    return calendar.startOfDay(for: date)
}

extension SelectionStepDraft {
    func notificationValidationMessage(calendar: Calendar = .current) -> String? {
        if let error = NotificationScheduleCalculator.preferenceValidationMessage(
            timedCustom: notificationTimedCustom, dateCustom: notificationDateCustom
        ) { return error }
        guard notificationEnabled, status == .scheduled else { return nil }
        return NotificationScheduleCalculator.validationMessage(
            anchor: date, hasTime: hasTime, kind: notificationAnchor,
            timedCustom: notificationTimedCustom, dateCustom: notificationDateCustom, calendar: calendar
        )
    }
}

extension RecruitTaskDraft {
    func notificationValidationMessage(isCompleted: Bool = false, calendar: Calendar = .current) -> String? {
        if let error = NotificationScheduleCalculator.preferenceValidationMessage(
            timedCustom: notificationTimedCustom, dateCustom: notificationDateCustom
        ) { return error }
        guard notificationEnabled, hasDueDate, !isCompleted else { return nil }
        return NotificationScheduleCalculator.validationMessage(
            anchor: dueAt, hasTime: dueHasTime, kind: .taskDue,
            timedCustom: notificationTimedCustom, dateCustom: notificationDateCustom, calendar: calendar
        )
    }
}
