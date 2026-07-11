import Foundation

protocol RecruitRepository: Sendable {
    func fetchCompanies(userID: UUID) async throws -> [Company]
    func createCompany(userID: UUID, draft: CompanyDraft) async throws -> Company
    func updateCompany(_ company: Company, draft: CompanyDraft) async throws -> Company
    func deleteCompany(id: UUID) async throws

    func fetchSelectionSteps(userID: UUID) async throws -> [SelectionStep]
    func createSelectionStep(userID: UUID, companyID: UUID, draft: SelectionStepDraft) async throws -> SelectionStep
    func updateSelectionStep(_ step: SelectionStep, draft: SelectionStepDraft) async throws -> SelectionStep
    func deleteSelectionStep(id: UUID) async throws

    func fetchTasks(userID: UUID) async throws -> [RecruitTask]
    func createTask(userID: UUID, draft: RecruitTaskDraft) async throws -> RecruitTask
    func updateTask(_ task: RecruitTask, draft: RecruitTaskDraft) async throws -> RecruitTask
    func setTaskCompleted(_ task: RecruitTask, completed: Bool) async throws -> RecruitTask
    func deleteTask(id: UUID) async throws
}

enum RepositoryError: LocalizedError {
    case notConfigured
    case unauthenticated
    case missingCompany

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "アプリの接続設定を確認できませんでした。"
        case .unauthenticated:
            "ログイン状態を確認できませんでした。もう一度ログインしてください。"
        case .missingCompany:
            "対象の企業が見つかりませんでした。"
        }
    }
}
