import Foundation
import Supabase

struct SupabaseRecruitRepository: RecruitRepository {
    let client: SupabaseClient

    func fetchCompanies(userID: UUID) async throws -> [Company] {
        let companies: [Company] = try await AuthenticatedReadRecovery.run(
            operationName: "companies"
        ) {
            try await KeysetPaginatedFetch.all { afterID, limit in
                let query = client
                    .from("companies")
                    .select()
                    .eq("user_id", value: userID)
                if let afterID {
                    _ = query.gt("id", value: afterID)
                }
                return try await query
                    .order("id")
                    .limit(limit)
                    .execute()
                    .value
            }
        } recoverSession: {
            _ = try await client.auth.refreshSession()
        }
        return companies.sorted { $0.updatedAt > $1.updatedAt }
    }

    func createCompany(userID: UUID, draft: CompanyDraft) async throws -> Company {
        try await client
            .from("companies")
            .insert(CompanyWrite(userID: userID, draft: draft))
            .select()
            .single()
            .execute()
            .value
    }

    func updateCompany(_ company: Company, draft: CompanyDraft) async throws -> Company {
        do {
            return try await client
                .from("companies")
                .update(CompanyUpdate(draft: draft, existingURL: company.url))
                .eq("id", value: company.id)
                .eq("version", value: company.version)
                .select()
                .single()
                .execute()
                .value
        } catch {
            throw Self.mapMutationError(error)
        }
    }

    func deleteCompany(_ company: Company) async throws {
        let deleted: [DeletedRecord] = try await client
            .from("companies")
            .delete()
            .eq("id", value: company.id)
            .eq("version", value: company.version)
            .select("id")
            .execute()
            .value
        guard deleted.isEmpty == false else { throw RepositoryError.conflict }
    }

    func fetchCompanyInformationItems(userID: UUID) async throws -> [CompanyInformationItem] {
        let items: [CompanyInformationItem] = try await AuthenticatedReadRecovery.run(
            operationName: "company_information_items"
        ) {
            try await KeysetPaginatedFetch.all { afterID, limit in
                let query = client
                    .from("company_information_items")
                    .select()
                    .eq("user_id", value: userID)
                if let afterID { _ = query.gt("id", value: afterID) }
                return try await query.order("id").limit(limit).execute().value
            }
        } recoverSession: {
            _ = try await client.auth.refreshSession()
        }
        return CompanyInformationSorting.sorted(items)
    }

    func createCompanyInformationItem(
        userID: UUID,
        companyID: UUID,
        draft: CompanyInformationDraft
    ) async throws -> CompanyInformationItem {
        try await client
            .from("company_information_items")
            .insert(CompanyInformationWrite(userID: userID, companyID: companyID, draft: draft))
            .select()
            .single()
            .execute()
            .value
    }

    func updateCompanyInformationItem(
        _ item: CompanyInformationItem,
        draft: CompanyInformationDraft
    ) async throws -> CompanyInformationItem {
        do {
            return try await client
                .from("company_information_items")
                .update(CompanyInformationUpdate(draft: draft))
                .eq("id", value: item.id)
                .eq("version", value: item.version)
                .select()
                .single()
                .execute()
                .value
        } catch {
            throw Self.mapMutationError(error)
        }
    }

    func deleteCompanyInformationItem(_ item: CompanyInformationItem) async throws {
        let deleted: [DeletedRecord] = try await client
            .from("company_information_items")
            .delete()
            .eq("id", value: item.id)
            .eq("version", value: item.version)
            .select("id")
            .execute()
            .value
        guard deleted.isEmpty == false else { throw RepositoryError.conflict }
    }

    func fetchSelectionSteps(userID: UUID) async throws -> [SelectionStep] {
        let steps: [SelectionStep] = try await AuthenticatedReadRecovery.run(
            operationName: "selection_steps"
        ) {
            try await KeysetPaginatedFetch.all { afterID, limit in
                let query = client
                    .from("selection_steps")
                    .select()
                    .eq("user_id", value: userID)
                if let afterID {
                    _ = query.gt("id", value: afterID)
                }
                return try await query
                    .order("id")
                    .limit(limit)
                    .execute()
                    .value
            }
        } recoverSession: {
            _ = try await client.auth.refreshSession()
        }
        return steps.sorted {
            ($0.earliestDate ?? .distantFuture) < ($1.earliestDate ?? .distantFuture)
        }
    }

    func createSelectionStep(
        userID: UUID,
        companyID: UUID,
        draft: SelectionStepDraft
    ) async throws -> SelectionStep {
        if draft.notificationEnabled && draft.status == .scheduled, let date = draft.notificationAbsoluteAt,
           AbsoluteNotificationTiming.validationMessage(date, original: nil) != nil {
            throw NotificationTimingError.invalidAbsolute
        }
        guard draft.notificationValidationMessage() == nil else { throw NotificationTimingError.invalid }
        guard draft.isValidRange() else { throw RepositoryError.invalidScheduleRange }
        return try await client
            .from("selection_steps")
            .insert(SelectionStepWrite(userID: userID, companyID: companyID, draft: draft))
            .select()
            .single()
            .execute()
            .value
    }

    func updateSelectionStep(_ step: SelectionStep, draft: SelectionStepDraft) async throws -> SelectionStep {
        if draft.notificationEnabled && draft.status == .scheduled, let date = draft.notificationAbsoluteAt,
           AbsoluteNotificationTiming.validationMessage(date, original: step.notificationAbsoluteAt) != nil {
            throw NotificationTimingError.invalidAbsolute
        }
        guard draft.notificationValidationMessage() == nil else { throw NotificationTimingError.invalid }
        guard draft.isValidRange() else { throw RepositoryError.invalidScheduleRange }
        do {
            return try await client
                .from("selection_steps")
                .update(SelectionStepUpdate(draft: draft))
                .eq("id", value: step.id)
                .eq("version", value: step.version)
                .select()
                .single()
                .execute()
                .value
        } catch {
            throw Self.mapMutationError(error)
        }
    }

    func setSelectionStepStatus(_ step: SelectionStep, status: SelectionStepStatus, notificationEnabled: Bool) async throws -> SelectionStep {
        do {
            return try await client
                .from("selection_steps")
                .update(SelectionStatusUpdate(status: status, notificationEnabled: notificationEnabled))
                .eq("id", value: step.id)
                .eq("version", value: step.version)
                .select()
                .single()
                .execute()
                .value
        } catch {
            throw Self.mapMutationError(error)
        }
    }

    func deleteSelectionStep(_ step: SelectionStep) async throws {
        let deleted: [DeletedRecord] = try await client
            .from("selection_steps")
            .delete()
            .eq("id", value: step.id)
            .eq("version", value: step.version)
            .select("id")
            .execute()
            .value
        guard deleted.isEmpty == false else { throw RepositoryError.conflict }
    }

    func fetchTasks(userID: UUID) async throws -> [RecruitTask] {
        let tasks: [RecruitTask] = try await AuthenticatedReadRecovery.run(
            operationName: "tasks"
        ) {
            try await KeysetPaginatedFetch.all { afterID, limit in
                let query = client
                    .from("tasks")
                    .select()
                    .eq("user_id", value: userID)
                if let afterID {
                    _ = query.gt("id", value: afterID)
                }
                return try await query
                    .order("id")
                    .limit(limit)
                    .execute()
                    .value
            }
        } recoverSession: {
            _ = try await client.auth.refreshSession()
        }
        return tasks.sorted {
            ($0.dueDate() ?? .distantFuture) < ($1.dueDate() ?? .distantFuture)
        }
    }

    func createTask(userID: UUID, draft: RecruitTaskDraft) async throws -> RecruitTask {
        if draft.notificationEnabled && draft.hasDueDate, let date = draft.notificationAbsoluteAt,
           AbsoluteNotificationTiming.validationMessage(date, original: nil) != nil {
            throw NotificationTimingError.invalidAbsolute
        }
        guard draft.notificationValidationMessage() == nil else { throw NotificationTimingError.invalid }
        return try await client
            .from("tasks")
            .insert(RecruitTaskWrite(userID: userID, draft: draft))
            .select()
            .single()
            .execute()
            .value
    }

    func updateTask(_ task: RecruitTask, draft: RecruitTaskDraft) async throws -> RecruitTask {
        if draft.notificationEnabled && draft.hasDueDate && !task.isCompleted, let date = draft.notificationAbsoluteAt,
           AbsoluteNotificationTiming.validationMessage(date, original: task.notificationAbsoluteAt) != nil {
            throw NotificationTimingError.invalidAbsolute
        }
        guard draft.notificationValidationMessage(isCompleted: task.isCompleted) == nil else { throw NotificationTimingError.invalid }
        do {
            return try await client
                .from("tasks")
                .update(RecruitTaskUpdate(draft: draft))
                .eq("id", value: task.id)
                .eq("version", value: task.version)
                .select()
                .single()
                .execute()
                .value
        } catch {
            throw Self.mapMutationError(error)
        }
    }

    func setTaskCompleted(_ task: RecruitTask, completed: Bool) async throws -> RecruitTask {
        do {
            return try await client
                .from("tasks")
                .update(TaskCompletionUpdate(completedAt: completed ? Date() : nil))
                .eq("id", value: task.id)
                .eq("version", value: task.version)
                .select()
                .single()
                .execute()
                .value
        } catch {
            throw Self.mapMutationError(error)
        }
    }

    func deleteTask(_ task: RecruitTask) async throws {
        let deleted: [DeletedRecord] = try await client
            .from("tasks")
            .delete()
            .eq("id", value: task.id)
            .eq("version", value: task.version)
            .select("id")
            .execute()
            .value
        guard deleted.isEmpty == false else { throw RepositoryError.conflict }
    }

    private static func mapMutationError(_ error: Error) -> Error {
        if let error = error as? PostgrestError, error.code == "PGRST116" {
            return RepositoryError.conflict
        }
        return error
    }

}

private struct DeletedRecord: Decodable {
    let id: UUID
}

struct CompanyInformationWrite: Encodable {
    let userID: UUID
    let companyID: UUID
    let category: CompanyInformationCategory
    let title: String
    let body: String
    let occurredOn: LocalDate?

    init(userID: UUID, companyID: UUID, draft: CompanyInformationDraft) {
        self.userID = userID
        self.companyID = companyID
        category = draft.category
        title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        occurredOn = draft.hasDate ? LocalDate(date: draft.date) : nil
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case companyID = "company_id"
        case category, title, body
        case occurredOn = "occurred_on"
    }
}

struct CompanyInformationUpdate: Encodable {
    let category: CompanyInformationCategory
    let title: String
    let body: String
    let occurredOn: LocalDate?

    init(draft: CompanyInformationDraft) {
        category = draft.category
        title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        occurredOn = draft.hasDate ? LocalDate(date: draft.date) : nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(category, forKey: .category)
        try container.encode(title, forKey: .title)
        try container.encode(body, forKey: .body)
        if let occurredOn {
            try container.encode(occurredOn, forKey: .occurredOn)
        } else {
            try container.encodeNil(forKey: .occurredOn)
        }
    }

    enum CodingKeys: String, CodingKey {
        case category, title, body
        case occurredOn = "occurred_on"
    }
}

struct CompanyWrite: Encodable {
    let userID: UUID
    let name: String
    let priority: Int
    let status: CompanyStatus
    let url: String?
    let memo: String?

    init(userID: UUID, draft: CompanyDraft) throws {
        self.userID = userID
        name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        priority = draft.priority
        status = draft.status
        url = try WebURLNormalizer.validatedString(from: draft.url)
        memo = draft.memo.nilIfBlank
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case name, priority, status, url, memo
    }
}

struct CompanyUpdate: Encodable {
    let name: String
    let priority: Int
    let status: CompanyStatus
    let url: String?
    let memo: String?

    init(draft: CompanyDraft, existingURL: String? = nil) throws {
        name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        priority = draft.priority
        status = draft.status
        url = try WebURLNormalizer.validatedString(from: draft.url, preservingUnchanged: existingURL)
        memo = draft.memo.nilIfBlank
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(priority, forKey: .priority)
        try container.encode(status, forKey: .status)
        if let url { try container.encode(url, forKey: .url) } else { try container.encodeNil(forKey: .url) }
        if let memo { try container.encode(memo, forKey: .memo) } else { try container.encodeNil(forKey: .memo) }
    }

    enum CodingKeys: String, CodingKey { case name, priority, status, url, memo }
}

struct SelectionStepWrite: Encodable {
    let userID: UUID
    let companyID: UUID
    let type: SelectionType
    let customTitle: String?
    let startsAt: Date?
    let startsOn: LocalDate?
    let endsAt: Date?
    let endsOn: LocalDate?
    let startsHasTime: Bool
    let deadlineAt: Date?
    let deadlineOn: LocalDate?
    let deadlineHasTime: Bool
    let status: SelectionStepStatus
    let memo: String?
    let notificationTimedPreset: TimedNotificationPreset?
    let notificationDatePreset: DateNotificationPreset?
    let notificationTimedCustom: CustomNotificationTiming?
    let notificationDateCustom: CustomNotificationTiming?
    let notificationAbsoluteAt: Date?
    let notificationEnabled: Bool

    init(userID: UUID, companyID: UUID, draft: SelectionStepDraft) {
        self.userID = userID
        self.companyID = companyID
        type = draft.type
        customTitle = draft.customTitle.nilIfBlank
        let localDate = LocalDate(date: draft.date)
        startsAt = draft.dateKind == .schedule
            ? (draft.hasTime ? draft.date : localDate.compatibilityTimestamp)
            : nil
        startsOn = draft.dateKind == .schedule && draft.hasTime == false ? localDate : nil
        endsAt = draft.dateKind == .schedule && draft.hasEnd && draft.hasTime ? draft.endDate : nil
        endsOn = draft.dateKind == .schedule && draft.hasEnd && !draft.hasTime ? LocalDate(date: draft.endDate) : nil
        startsHasTime = draft.dateKind == .schedule && draft.hasTime
        deadlineAt = draft.dateKind == .deadline
            ? (draft.hasTime ? draft.date : localDate.compatibilityTimestamp)
            : nil
        deadlineOn = draft.dateKind == .deadline && draft.hasTime == false ? localDate : nil
        deadlineHasTime = draft.dateKind == .deadline && draft.hasTime
        status = draft.status
        memo = draft.memo.nilIfBlank
        notificationTimedPreset = draft.resolvedNotificationTimedPreset
        notificationDatePreset = draft.resolvedNotificationDatePreset
        notificationTimedCustom = draft.notificationTimedCustom
        notificationDateCustom = draft.notificationDateCustom
        notificationAbsoluteAt = draft.notificationAbsoluteAt
        notificationEnabled = draft.notificationEnabled
    }

    enum CodingKeys: String, CodingKey {
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
        case status, memo
        case notificationTimedPreset = "notification_timed_preset"
        case notificationDatePreset = "notification_date_preset"
        case notificationTimedCustom = "notification_timed_custom"
        case notificationDateCustom = "notification_date_custom"
        case notificationAbsoluteAt = "notification_absolute_at"
        case notificationEnabled = "notification_enabled"
    }
}

struct SelectionStepUpdate: Encodable {
    let type: SelectionType
    let customTitle: String?
    let startsAt: Date?
    let startsOn: LocalDate?
    let endsAt: Date?
    let endsOn: LocalDate?
    let startsHasTime: Bool
    let deadlineAt: Date?
    let deadlineOn: LocalDate?
    let deadlineHasTime: Bool
    let status: SelectionStepStatus
    let memo: String?
    let notificationTimedPreset: TimedNotificationPreset?
    let notificationDatePreset: DateNotificationPreset?
    let notificationTimedCustom: CustomNotificationTiming?
    let notificationDateCustom: CustomNotificationTiming?
    let notificationAbsoluteAt: Date?
    let notificationEnabled: Bool

    init(draft: SelectionStepDraft) {
        type = draft.type
        customTitle = draft.customTitle.nilIfBlank
        let localDate = LocalDate(date: draft.date)
        startsAt = draft.dateKind == .schedule
            ? (draft.hasTime ? draft.date : localDate.compatibilityTimestamp)
            : nil
        startsOn = draft.dateKind == .schedule && draft.hasTime == false ? localDate : nil
        endsAt = draft.dateKind == .schedule && draft.hasEnd && draft.hasTime ? draft.endDate : nil
        endsOn = draft.dateKind == .schedule && draft.hasEnd && !draft.hasTime ? LocalDate(date: draft.endDate) : nil
        startsHasTime = draft.dateKind == .schedule && draft.hasTime
        deadlineAt = draft.dateKind == .deadline
            ? (draft.hasTime ? draft.date : localDate.compatibilityTimestamp)
            : nil
        deadlineOn = draft.dateKind == .deadline && draft.hasTime == false ? localDate : nil
        deadlineHasTime = draft.dateKind == .deadline && draft.hasTime
        status = draft.status
        memo = draft.memo.nilIfBlank
        notificationTimedPreset = draft.resolvedNotificationTimedPreset
        notificationDatePreset = draft.resolvedNotificationDatePreset
        notificationTimedCustom = draft.notificationTimedCustom
        notificationDateCustom = draft.notificationDateCustom
        notificationAbsoluteAt = draft.notificationAbsoluteAt
        notificationEnabled = draft.notificationEnabled
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        if let customTitle { try container.encode(customTitle, forKey: .customTitle) } else { try container.encodeNil(forKey: .customTitle) }
        if let startsAt { try container.encode(startsAt, forKey: .startsAt) } else { try container.encodeNil(forKey: .startsAt) }
        if let startsOn { try container.encode(startsOn, forKey: .startsOn) } else { try container.encodeNil(forKey: .startsOn) }
        if let endsAt { try container.encode(endsAt, forKey: .endsAt) } else { try container.encodeNil(forKey: .endsAt) }
        if let endsOn { try container.encode(endsOn, forKey: .endsOn) } else { try container.encodeNil(forKey: .endsOn) }
        try container.encode(startsHasTime, forKey: .startsHasTime)
        if let deadlineAt { try container.encode(deadlineAt, forKey: .deadlineAt) } else { try container.encodeNil(forKey: .deadlineAt) }
        if let deadlineOn { try container.encode(deadlineOn, forKey: .deadlineOn) } else { try container.encodeNil(forKey: .deadlineOn) }
        try container.encode(deadlineHasTime, forKey: .deadlineHasTime)
        try container.encode(status, forKey: .status)
        if let memo { try container.encode(memo, forKey: .memo) } else { try container.encodeNil(forKey: .memo) }
        try container.encode(notificationTimedPreset, forKey: .notificationTimedPreset)
        try container.encode(notificationDatePreset, forKey: .notificationDatePreset)
        try container.encode(notificationTimedCustom, forKey: .notificationTimedCustom)
        try container.encode(notificationDateCustom, forKey: .notificationDateCustom)
        try container.encode(notificationAbsoluteAt, forKey: .notificationAbsoluteAt)
        try container.encode(notificationEnabled, forKey: .notificationEnabled)
    }

    enum CodingKeys: String, CodingKey {
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
        case status, memo
        case notificationTimedPreset = "notification_timed_preset"
        case notificationDatePreset = "notification_date_preset"
        case notificationTimedCustom = "notification_timed_custom"
        case notificationDateCustom = "notification_date_custom"
        case notificationAbsoluteAt = "notification_absolute_at"
        case notificationEnabled = "notification_enabled"
    }
}

struct RecruitTaskWrite: Encodable {
    let userID: UUID
    let companyID: UUID?
    let title: String
    let memo: String?
    let dueAt: Date?
    let dueOn: LocalDate?
    let dueHasTime: Bool
    let notificationTimedPreset: TimedNotificationPreset?
    let notificationDatePreset: DateNotificationPreset?
    let notificationTimedCustom: CustomNotificationTiming?
    let notificationDateCustom: CustomNotificationTiming?
    let notificationAbsoluteAt: Date?
    let notificationEnabled: Bool

    init(userID: UUID, draft: RecruitTaskDraft) {
        self.userID = userID
        companyID = draft.companyID
        title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        memo = draft.memo.nilIfBlank
        let localDate = LocalDate(date: draft.dueAt)
        dueAt = draft.hasDueDate
            ? (draft.dueHasTime ? draft.dueAt : localDate.compatibilityTimestamp)
            : nil
        dueOn = draft.hasDueDate && draft.dueHasTime == false ? localDate : nil
        dueHasTime = draft.hasDueDate && draft.dueHasTime
        notificationTimedPreset = draft.notificationTimedPreset
        notificationDatePreset = draft.notificationDatePreset
        notificationTimedCustom = draft.notificationTimedCustom
        notificationDateCustom = draft.notificationDateCustom
        notificationAbsoluteAt = draft.notificationAbsoluteAt
        notificationEnabled = draft.hasDueDate && draft.notificationEnabled
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case companyID = "company_id"
        case title, memo
        case dueAt = "due_at"
        case dueOn = "due_on"
        case dueHasTime = "due_has_time"
        case notificationTimedPreset = "notification_timed_preset"
        case notificationDatePreset = "notification_date_preset"
        case notificationTimedCustom = "notification_timed_custom"
        case notificationDateCustom = "notification_date_custom"
        case notificationAbsoluteAt = "notification_absolute_at"
        case notificationEnabled = "notification_enabled"
    }
}

struct RecruitTaskUpdate: Encodable {
    let companyID: UUID?
    let title: String
    let memo: String?
    let dueAt: Date?
    let dueOn: LocalDate?
    let dueHasTime: Bool
    let notificationTimedPreset: TimedNotificationPreset?
    let notificationDatePreset: DateNotificationPreset?
    let notificationTimedCustom: CustomNotificationTiming?
    let notificationDateCustom: CustomNotificationTiming?
    let notificationAbsoluteAt: Date?
    let notificationEnabled: Bool

    init(draft: RecruitTaskDraft) {
        companyID = draft.companyID
        title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        memo = draft.memo.nilIfBlank
        let localDate = LocalDate(date: draft.dueAt)
        dueAt = draft.hasDueDate
            ? (draft.dueHasTime ? draft.dueAt : localDate.compatibilityTimestamp)
            : nil
        dueOn = draft.hasDueDate && draft.dueHasTime == false ? localDate : nil
        dueHasTime = draft.hasDueDate && draft.dueHasTime
        notificationTimedPreset = draft.notificationTimedPreset
        notificationDatePreset = draft.notificationDatePreset
        notificationTimedCustom = draft.notificationTimedCustom
        notificationDateCustom = draft.notificationDateCustom
        notificationAbsoluteAt = draft.notificationAbsoluteAt
        notificationEnabled = draft.hasDueDate && draft.notificationEnabled
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let companyID { try container.encode(companyID, forKey: .companyID) } else { try container.encodeNil(forKey: .companyID) }
        try container.encode(title, forKey: .title)
        if let memo { try container.encode(memo, forKey: .memo) } else { try container.encodeNil(forKey: .memo) }
        if let dueAt { try container.encode(dueAt, forKey: .dueAt) } else { try container.encodeNil(forKey: .dueAt) }
        if let dueOn { try container.encode(dueOn, forKey: .dueOn) } else { try container.encodeNil(forKey: .dueOn) }
        try container.encode(dueHasTime, forKey: .dueHasTime)
        try container.encode(notificationTimedPreset, forKey: .notificationTimedPreset)
        try container.encode(notificationDatePreset, forKey: .notificationDatePreset)
        try container.encode(notificationTimedCustom, forKey: .notificationTimedCustom)
        try container.encode(notificationDateCustom, forKey: .notificationDateCustom)
        try container.encode(notificationAbsoluteAt, forKey: .notificationAbsoluteAt)
        try container.encode(notificationEnabled, forKey: .notificationEnabled)
    }

    enum CodingKeys: String, CodingKey {
        case companyID = "company_id"
        case title, memo
        case dueAt = "due_at"
        case dueOn = "due_on"
        case dueHasTime = "due_has_time"
        case notificationTimedPreset = "notification_timed_preset"
        case notificationDatePreset = "notification_date_preset"
        case notificationTimedCustom = "notification_timed_custom"
        case notificationDateCustom = "notification_date_custom"
        case notificationAbsoluteAt = "notification_absolute_at"
        case notificationEnabled = "notification_enabled"
    }
}

private struct TaskCompletionUpdate: Encodable {
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case completedAt = "completed_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let completedAt {
            try container.encode(completedAt, forKey: .completedAt)
        } else {
            try container.encodeNil(forKey: .completedAt)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

struct SelectionStatusUpdate: Encodable {
    let status: SelectionStepStatus
    let notificationEnabled: Bool
    enum CodingKeys: String, CodingKey {
        case status
        case notificationEnabled = "notification_enabled"
    }
}
