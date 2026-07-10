import Foundation
import Supabase

struct SupabaseRecruitRepository: RecruitRepository {
    let client: SupabaseClient

    func fetchCompanies(userID: UUID) async throws -> [Company] {
        try await client
            .from("companies")
            .select()
            .eq("user_id", value: userID.uuidString)
            .order("updated_at", ascending: false)
            .execute()
            .value
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
        try await client
            .from("companies")
            .update(CompanyUpdate(draft: draft))
            .eq("id", value: company.id.uuidString)
            .select()
            .single()
            .execute()
            .value
    }

    func deleteCompany(id: UUID) async throws {
        try await client.from("companies").delete().eq("id", value: id.uuidString).execute()
    }

    func fetchSelectionSteps(userID: UUID) async throws -> [SelectionStep] {
        try await client
            .from("selection_steps")
            .select()
            .eq("user_id", value: userID.uuidString)
            .order("starts_at", ascending: true, nullsFirst: false)
            .execute()
            .value
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
        try await client
            .from("selection_steps")
            .update(SelectionStepUpdate(draft: draft))
            .eq("id", value: step.id.uuidString)
            .select()
            .single()
            .execute()
            .value
    }

    func deleteSelectionStep(id: UUID) async throws {
        try await client.from("selection_steps").delete().eq("id", value: id.uuidString).execute()
    }

    func fetchTasks(userID: UUID) async throws -> [RecruitTask] {
        try await client
            .from("tasks")
            .select()
            .eq("user_id", value: userID.uuidString)
            .order("due_at", ascending: true, nullsFirst: false)
            .execute()
            .value
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
        try await client
            .from("tasks")
            .update(RecruitTaskUpdate(draft: draft))
            .eq("id", value: task.id.uuidString)
            .select()
            .single()
            .execute()
            .value
    }

    func setTaskCompleted(_ task: RecruitTask, completed: Bool) async throws -> RecruitTask {
        try await client
            .from("tasks")
            .update(TaskCompletionUpdate(completedAt: completed ? Date() : nil))
            .eq("id", value: task.id.uuidString)
            .select()
            .single()
            .execute()
            .value
    }

    func deleteTask(id: UUID) async throws {
        try await client.from("tasks").delete().eq("id", value: id.uuidString).execute()
    }
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
    let deadlineAt: Date?
    let status: SelectionStepStatus
    let memo: String?
    let notificationEnabled: Bool

    init(userID: UUID, companyID: UUID, draft: SelectionStepDraft) {
        self.userID = userID
        self.companyID = companyID
        type = draft.type
        customTitle = draft.type == .other ? draft.customTitle.nilIfBlank : nil
        startsAt = draft.hasStartsAt ? draft.startsAt : nil
        deadlineAt = draft.hasDeadline ? draft.deadlineAt : nil
        status = draft.status
        memo = draft.memo.nilIfBlank
        notificationEnabled = draft.notificationEnabled
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case companyID = "company_id"
        case type
        case customTitle = "custom_title"
        case startsAt = "starts_at"
        case deadlineAt = "deadline_at"
        case status, memo
        case notificationEnabled = "notification_enabled"
    }
}

private struct SelectionStepUpdate: Encodable {
    let type: SelectionType
    let customTitle: String?
    let startsAt: Date?
    let deadlineAt: Date?
    let status: SelectionStepStatus
    let memo: String?
    let notificationEnabled: Bool

    init(draft: SelectionStepDraft) {
        type = draft.type
        customTitle = draft.type == .other ? draft.customTitle.nilIfBlank : nil
        startsAt = draft.hasStartsAt ? draft.startsAt : nil
        deadlineAt = draft.hasDeadline ? draft.deadlineAt : nil
        status = draft.status
        memo = draft.memo.nilIfBlank
        notificationEnabled = draft.notificationEnabled
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        if let customTitle { try container.encode(customTitle, forKey: .customTitle) } else { try container.encodeNil(forKey: .customTitle) }
        if let startsAt { try container.encode(startsAt, forKey: .startsAt) } else { try container.encodeNil(forKey: .startsAt) }
        if let deadlineAt { try container.encode(deadlineAt, forKey: .deadlineAt) } else { try container.encodeNil(forKey: .deadlineAt) }
        try container.encode(status, forKey: .status)
        if let memo { try container.encode(memo, forKey: .memo) } else { try container.encodeNil(forKey: .memo) }
        try container.encode(notificationEnabled, forKey: .notificationEnabled)
    }

    enum CodingKeys: String, CodingKey {
        case type
        case customTitle = "custom_title"
        case startsAt = "starts_at"
        case deadlineAt = "deadline_at"
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
    let dueHasTime: Bool
    let notificationEnabled: Bool

    init(userID: UUID, draft: RecruitTaskDraft) {
        self.userID = userID
        companyID = draft.companyID
        title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        memo = draft.memo.nilIfBlank
        dueAt = draft.hasDueDate ? draft.dueAt : nil
        dueHasTime = draft.hasDueDate && draft.dueHasTime
        notificationEnabled = draft.hasDueDate && draft.notificationEnabled
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case companyID = "company_id"
        case title, memo
        case dueAt = "due_at"
        case dueHasTime = "due_has_time"
        case notificationEnabled = "notification_enabled"
    }
}

private struct RecruitTaskUpdate: Encodable {
    let companyID: UUID?
    let title: String
    let memo: String?
    let dueAt: Date?
    let dueHasTime: Bool
    let notificationEnabled: Bool

    init(draft: RecruitTaskDraft) {
        companyID = draft.companyID
        title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        memo = draft.memo.nilIfBlank
        dueAt = draft.hasDueDate ? draft.dueAt : nil
        dueHasTime = draft.hasDueDate && draft.dueHasTime
        notificationEnabled = draft.hasDueDate && draft.notificationEnabled
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let companyID { try container.encode(companyID, forKey: .companyID) } else { try container.encodeNil(forKey: .companyID) }
        try container.encode(title, forKey: .title)
        if let memo { try container.encode(memo, forKey: .memo) } else { try container.encodeNil(forKey: .memo) }
        if let dueAt { try container.encode(dueAt, forKey: .dueAt) } else { try container.encodeNil(forKey: .dueAt) }
        try container.encode(dueHasTime, forKey: .dueHasTime)
        try container.encode(notificationEnabled, forKey: .notificationEnabled)
    }

    enum CodingKeys: String, CodingKey {
        case companyID = "company_id"
        case title, memo
        case dueAt = "due_at"
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
