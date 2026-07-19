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
                .update(CompanyUpdate(draft: draft))
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
        try await client
            .from("selection_steps")
            .insert(SelectionStepWrite(userID: userID, companyID: companyID, draft: draft))
            .select()
            .single()
            .execute()
            .value
    }

    func updateSelectionStep(_ step: SelectionStep, draft: SelectionStepDraft) async throws -> SelectionStep {
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
        try await client
            .from("tasks")
            .insert(RecruitTaskWrite(userID: userID, draft: draft))
            .select()
            .single()
            .execute()
            .value
    }

    func updateTask(_ task: RecruitTask, draft: RecruitTaskDraft) async throws -> RecruitTask {
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

private struct CompanyWrite: Encodable {
    let userID: UUID
    let name: String
    let priority: Int
    let status: CompanyStatus
    let url: String?
    let memo: String?

    init(userID: UUID, draft: CompanyDraft) {
        self.userID = userID
        name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        priority = draft.priority
        status = draft.status
        url = WebURLNormalizer.normalizedString(from: draft.url)
        memo = draft.memo.nilIfBlank
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case name, priority, status, url, memo
    }
}

private struct CompanyUpdate: Encodable {
    let name: String
    let priority: Int
    let status: CompanyStatus
    let url: String?
    let memo: String?

    init(draft: CompanyDraft) {
        name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        priority = draft.priority
        status = draft.status
        url = WebURLNormalizer.normalizedString(from: draft.url)
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

private struct SelectionStepWrite: Encodable {
    let userID: UUID
    let companyID: UUID
    let type: SelectionType
    let customTitle: String?
    let startsAt: Date?
    let startsOn: LocalDate?
    let startsHasTime: Bool
    let deadlineAt: Date?
    let deadlineOn: LocalDate?
    let deadlineHasTime: Bool
    let status: SelectionStepStatus
    let memo: String?
    let notificationEnabled: Bool

    init(userID: UUID, companyID: UUID, draft: SelectionStepDraft) {
        self.userID = userID
        self.companyID = companyID
        type = draft.type
        customTitle = draft.type == .other ? draft.customTitle.nilIfBlank : nil
        let localDate = LocalDate(date: draft.date)
        startsAt = draft.dateKind == .schedule
            ? (draft.hasTime ? draft.date : localDate.compatibilityTimestamp)
            : nil
        startsOn = draft.dateKind == .schedule && draft.hasTime == false ? localDate : nil
        startsHasTime = draft.dateKind == .schedule && draft.hasTime
        deadlineAt = draft.dateKind == .deadline
            ? (draft.hasTime ? draft.date : localDate.compatibilityTimestamp)
            : nil
        deadlineOn = draft.dateKind == .deadline && draft.hasTime == false ? localDate : nil
        deadlineHasTime = draft.dateKind == .deadline && draft.hasTime
        status = draft.status
        memo = draft.memo.nilIfBlank
        notificationEnabled = draft.status == .scheduled && draft.notificationEnabled
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case companyID = "company_id"
        case type
        case customTitle = "custom_title"
        case startsAt = "starts_at"
        case startsOn = "starts_on"
        case startsHasTime = "starts_has_time"
        case deadlineAt = "deadline_at"
        case deadlineOn = "deadline_on"
        case deadlineHasTime = "deadline_has_time"
        case status, memo
        case notificationEnabled = "notification_enabled"
    }
}

private struct SelectionStepUpdate: Encodable {
    let type: SelectionType
    let customTitle: String?
    let startsAt: Date?
    let startsOn: LocalDate?
    let startsHasTime: Bool
    let deadlineAt: Date?
    let deadlineOn: LocalDate?
    let deadlineHasTime: Bool
    let status: SelectionStepStatus
    let memo: String?
    let notificationEnabled: Bool

    init(draft: SelectionStepDraft) {
        type = draft.type
        customTitle = draft.type == .other ? draft.customTitle.nilIfBlank : nil
        let localDate = LocalDate(date: draft.date)
        startsAt = draft.dateKind == .schedule
            ? (draft.hasTime ? draft.date : localDate.compatibilityTimestamp)
            : nil
        startsOn = draft.dateKind == .schedule && draft.hasTime == false ? localDate : nil
        startsHasTime = draft.dateKind == .schedule && draft.hasTime
        deadlineAt = draft.dateKind == .deadline
            ? (draft.hasTime ? draft.date : localDate.compatibilityTimestamp)
            : nil
        deadlineOn = draft.dateKind == .deadline && draft.hasTime == false ? localDate : nil
        deadlineHasTime = draft.dateKind == .deadline && draft.hasTime
        status = draft.status
        memo = draft.memo.nilIfBlank
        notificationEnabled = draft.status == .scheduled && draft.notificationEnabled
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        if let customTitle { try container.encode(customTitle, forKey: .customTitle) } else { try container.encodeNil(forKey: .customTitle) }
        if let startsAt { try container.encode(startsAt, forKey: .startsAt) } else { try container.encodeNil(forKey: .startsAt) }
        if let startsOn { try container.encode(startsOn, forKey: .startsOn) } else { try container.encodeNil(forKey: .startsOn) }
        try container.encode(startsHasTime, forKey: .startsHasTime)
        if let deadlineAt { try container.encode(deadlineAt, forKey: .deadlineAt) } else { try container.encodeNil(forKey: .deadlineAt) }
        if let deadlineOn { try container.encode(deadlineOn, forKey: .deadlineOn) } else { try container.encodeNil(forKey: .deadlineOn) }
        try container.encode(deadlineHasTime, forKey: .deadlineHasTime)
        try container.encode(status, forKey: .status)
        if let memo { try container.encode(memo, forKey: .memo) } else { try container.encodeNil(forKey: .memo) }
        try container.encode(notificationEnabled, forKey: .notificationEnabled)
    }

    enum CodingKeys: String, CodingKey {
        case type
        case customTitle = "custom_title"
        case startsAt = "starts_at"
        case startsOn = "starts_on"
        case startsHasTime = "starts_has_time"
        case deadlineAt = "deadline_at"
        case deadlineOn = "deadline_on"
        case deadlineHasTime = "deadline_has_time"
        case status, memo
        case notificationEnabled = "notification_enabled"
    }
}

private struct RecruitTaskWrite: Encodable {
    let userID: UUID
    let companyID: UUID?
    let title: String
    let memo: String?
    let dueAt: Date?
    let dueOn: LocalDate?
    let dueHasTime: Bool
    let notificationEnabled: Bool

    init(userID: UUID, draft: RecruitTaskDraft) {
        self.userID = userID
        companyID = draft.companyID
        title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        memo = nil
        let localDate = LocalDate(date: draft.dueAt)
        dueAt = draft.hasDueDate
            ? (draft.dueHasTime ? draft.dueAt : localDate.compatibilityTimestamp)
            : nil
        dueOn = draft.hasDueDate && draft.dueHasTime == false ? localDate : nil
        dueHasTime = draft.hasDueDate && draft.dueHasTime
        notificationEnabled = draft.hasDueDate && draft.notificationEnabled
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case companyID = "company_id"
        case title, memo
        case dueAt = "due_at"
        case dueOn = "due_on"
        case dueHasTime = "due_has_time"
        case notificationEnabled = "notification_enabled"
    }
}

private struct RecruitTaskUpdate: Encodable {
    let companyID: UUID?
    let title: String
    let memo: String?
    let dueAt: Date?
    let dueOn: LocalDate?
    let dueHasTime: Bool
    let notificationEnabled: Bool

    init(draft: RecruitTaskDraft) {
        companyID = draft.companyID
        title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        memo = nil
        let localDate = LocalDate(date: draft.dueAt)
        dueAt = draft.hasDueDate
            ? (draft.dueHasTime ? draft.dueAt : localDate.compatibilityTimestamp)
            : nil
        dueOn = draft.hasDueDate && draft.dueHasTime == false ? localDate : nil
        dueHasTime = draft.hasDueDate && draft.dueHasTime
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
        try container.encode(notificationEnabled, forKey: .notificationEnabled)
    }

    enum CodingKeys: String, CodingKey {
        case companyID = "company_id"
        case title, memo
        case dueAt = "due_at"
        case dueOn = "due_on"
        case dueHasTime = "due_has_time"
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
