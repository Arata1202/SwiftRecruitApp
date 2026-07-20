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

    func fetchESTemplates(userID: UUID) async throws -> [ESTemplate] {
        let templates: [ESTemplate] = try await AuthenticatedReadRecovery.run(
            operationName: "es_templates"
        ) {
            try await KeysetPaginatedFetch.all { afterID, limit in
                let query = client
                    .from("es_templates")
                    .select()
                    .eq("user_id", value: userID)
                if let afterID { _ = query.gt("id", value: afterID) }
                return try await query.order("id").limit(limit).execute().value
            }
        } recoverSession: {
            _ = try await client.auth.refreshSession()
        }
        return ESTemplateSorting.sorted(templates)
    }

    func createESTemplate(userID: UUID, draft: ESTemplateDraft) async throws -> ESTemplate {
        try await client
            .from("es_templates")
            .insert(ESTemplateWrite(userID: userID, draft: draft))
            .select()
            .single()
            .execute()
            .value
    }

    func updateESTemplate(_ template: ESTemplate, draft: ESTemplateDraft) async throws -> ESTemplate {
        do {
            return try await client
                .from("es_templates")
                .update(ESTemplateUpdate(draft: draft))
                .eq("id", value: template.id)
                .eq("version", value: template.version)
                .select()
                .single()
                .execute()
                .value
        } catch {
            throw Self.mapMutationError(error)
        }
    }

    func deleteESTemplate(_ template: ESTemplate) async throws {
        let deleted: [DeletedRecord] = try await client
            .from("es_templates")
            .delete()
            .eq("id", value: template.id)
            .eq("version", value: template.version)
            .select("id")
            .execute()
            .value
        guard deleted.isEmpty == false else { throw RepositoryError.conflict }
    }

    func fetchSelfAnalysisAnswers(userID: UUID) async throws -> [SelfAnalysisAnswer] {
        let answers: [SelfAnalysisAnswer] = try await fetchUserRecords(
            table: "self_analysis_answers",
            userID: userID
        )
        return SelfAnalysisSorting.answers(answers)
    }

    func createSelfAnalysisAnswer(
        userID: UUID,
        draft: SelfAnalysisAnswerDraft
    ) async throws -> SelfAnalysisAnswer {
        try await client.from("self_analysis_answers")
            .insert(SelfAnalysisAnswerWrite(userID: userID, draft: draft))
            .select().single().execute().value
    }

    func updateSelfAnalysisAnswer(
        _ answer: SelfAnalysisAnswer,
        draft: SelfAnalysisAnswerDraft
    ) async throws -> SelfAnalysisAnswer {
        do {
            return try await client.from("self_analysis_answers")
                .update(SelfAnalysisAnswerUpdate(draft: draft))
                .eq("id", value: answer.id)
                .eq("version", value: answer.version)
                .select().single().execute().value
        } catch {
            throw Self.mapMutationError(error)
        }
    }

    func deleteSelfAnalysisAnswer(_ answer: SelfAnalysisAnswer) async throws {
        try await deleteVersionedRecord(
            table: "self_analysis_answers",
            id: answer.id,
            version: answer.version
        )
    }

    func fetchMotivationPoints(userID: UUID) async throws -> [MotivationPoint] {
        let points: [MotivationPoint] = try await fetchUserRecords(
            table: "motivation_points",
            userID: userID
        )
        return SelfAnalysisSorting.motivationPoints(points)
    }

    func createMotivationPoint(
        userID: UUID,
        draft: MotivationPointDraft
    ) async throws -> MotivationPoint {
        try await client.from("motivation_points")
            .insert(MotivationPointWrite(userID: userID, draft: draft))
            .select().single().execute().value
    }

    func updateMotivationPoint(
        _ point: MotivationPoint,
        draft: MotivationPointDraft
    ) async throws -> MotivationPoint {
        do {
            return try await client.from("motivation_points")
                .update(MotivationPointUpdate(draft: draft))
                .eq("id", value: point.id)
                .eq("version", value: point.version)
                .select().single().execute().value
        } catch {
            throw Self.mapMutationError(error)
        }
    }

    func deleteMotivationPoint(_ point: MotivationPoint) async throws {
        try await deleteVersionedRecord(
            table: "motivation_points",
            id: point.id,
            version: point.version
        )
    }

    private func fetchUserRecords<Record: Decodable & Identifiable>(
        table: String,
        userID: UUID
    ) async throws -> [Record] where Record.ID == UUID {
        try await AuthenticatedReadRecovery.run(operationName: table) {
            try await KeysetPaginatedFetch.all { afterID, limit in
                let query = client.from(table).select().eq("user_id", value: userID)
                if let afterID { _ = query.gt("id", value: afterID) }
                return try await query.order("id").limit(limit).execute().value
            }
        } recoverSession: {
            _ = try await client.auth.refreshSession()
        }
    }

    private func deleteVersionedRecord(table: String, id: UUID, version: Int) async throws {
        let deleted: [DeletedRecord] = try await client.from(table)
            .delete()
            .eq("id", value: id)
            .eq("version", value: version)
            .select("id").execute().value
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

struct RecruitTaskWrite: Encodable {
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
        memo = draft.memo.nilIfBlank
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

struct RecruitTaskUpdate: Encodable {
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
        memo = draft.memo.nilIfBlank
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

struct ESTemplateWrite: Encodable {
    let userID: UUID
    let category: ESTemplateCategory
    let title: String
    let body: String

    init(userID: UUID, draft: ESTemplateDraft) {
        self.userID = userID
        category = draft.category
        title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case category, title, body
    }
}

struct ESTemplateUpdate: Encodable {
    let category: ESTemplateCategory
    let title: String
    let body: String

    init(draft: ESTemplateDraft) {
        category = draft.category
        title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct SelfAnalysisAnswerWrite: Encodable {
    let userID: UUID
    let category: SelfAnalysisCategory
    let question: String
    let answer: String

    init(userID: UUID, draft: SelfAnalysisAnswerDraft) {
        self.userID = userID
        category = draft.category
        question = draft.question.trimmingCharacters(in: .whitespacesAndNewlines)
        answer = draft.answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case category, question, answer
    }
}

struct SelfAnalysisAnswerUpdate: Encodable {
    let category: SelfAnalysisCategory
    let question: String
    let answer: String

    init(draft: SelfAnalysisAnswerDraft) {
        category = draft.category
        question = draft.question.trimmingCharacters(in: .whitespacesAndNewlines)
        answer = draft.answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MotivationPointWrite: Encodable {
    let userID: UUID
    let age: Int
    let happiness: Int
    let reason: String

    init(userID: UUID, draft: MotivationPointDraft) {
        self.userID = userID
        age = draft.age
        happiness = draft.happiness
        reason = draft.reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case age, happiness, reason
    }
}

struct MotivationPointUpdate: Encodable {
    let age: Int
    let happiness: Int
    let reason: String

    init(draft: MotivationPointDraft) {
        age = draft.age
        happiness = draft.happiness
        reason = draft.reason.trimmingCharacters(in: .whitespacesAndNewlines)
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
