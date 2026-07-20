import Foundation

protocol RecruitRepository: Sendable {
    func fetchCompanies(userID: UUID) async throws -> [Company]
    func createCompany(userID: UUID, draft: CompanyDraft) async throws -> Company
    func updateCompany(_ company: Company, draft: CompanyDraft) async throws -> Company
    func deleteCompany(_ company: Company) async throws

    func fetchCompanyInformationItems(userID: UUID) async throws -> [CompanyInformationItem]
    func createCompanyInformationItem(
        userID: UUID,
        companyID: UUID,
        draft: CompanyInformationDraft
    ) async throws -> CompanyInformationItem
    func updateCompanyInformationItem(
        _ item: CompanyInformationItem,
        draft: CompanyInformationDraft
    ) async throws -> CompanyInformationItem
    func deleteCompanyInformationItem(_ item: CompanyInformationItem) async throws

    func fetchSelectionSteps(userID: UUID) async throws -> [SelectionStep]
    func createSelectionStep(userID: UUID, companyID: UUID, draft: SelectionStepDraft) async throws -> SelectionStep
    func updateSelectionStep(_ step: SelectionStep, draft: SelectionStepDraft) async throws -> SelectionStep
    func deleteSelectionStep(_ step: SelectionStep) async throws

    func fetchTasks(userID: UUID) async throws -> [RecruitTask]
    func createTask(userID: UUID, draft: RecruitTaskDraft) async throws -> RecruitTask
    func updateTask(_ task: RecruitTask, draft: RecruitTaskDraft) async throws -> RecruitTask
    func setTaskCompleted(_ task: RecruitTask, completed: Bool) async throws -> RecruitTask
    func deleteTask(_ task: RecruitTask) async throws

    func fetchESTemplates(userID: UUID) async throws -> [ESTemplate]
    func createESTemplate(userID: UUID, draft: ESTemplateDraft) async throws -> ESTemplate
    func updateESTemplate(_ template: ESTemplate, draft: ESTemplateDraft) async throws -> ESTemplate
    func deleteESTemplate(_ template: ESTemplate) async throws

    func fetchSelfAnalysisAnswers(userID: UUID) async throws -> [SelfAnalysisAnswer]
    func createSelfAnalysisAnswer(userID: UUID, draft: SelfAnalysisAnswerDraft) async throws -> SelfAnalysisAnswer
    func updateSelfAnalysisAnswer(_ answer: SelfAnalysisAnswer, draft: SelfAnalysisAnswerDraft) async throws -> SelfAnalysisAnswer
    func deleteSelfAnalysisAnswer(_ answer: SelfAnalysisAnswer) async throws

    func fetchMotivationPoints(userID: UUID) async throws -> [MotivationPoint]
    func createMotivationPoint(userID: UUID, draft: MotivationPointDraft) async throws -> MotivationPoint
    func updateMotivationPoint(_ point: MotivationPoint, draft: MotivationPointDraft) async throws -> MotivationPoint
    func deleteMotivationPoint(_ point: MotivationPoint) async throws
}

enum RepositoryError: LocalizedError {
    case notConfigured
    case unauthenticated
    case missingCompany
    case conflict
    case duplicateMotivationAge
    case invalidPaginationResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "アプリの接続設定を確認できませんでした。"
        case .unauthenticated:
            "ログイン状態を確認できませんでした。もう一度ログインしてください。"
        case .missingCompany:
            "対象の企業が見つかりませんでした。"
        case .conflict:
            "別の端末でデータが更新されました。再読み込みしてから、もう一度お試しください。"
        case .duplicateMotivationAge:
            "同じ年齢の記録がすでにあります。既存の記録を編集してください。"
        case .invalidPaginationResponse:
            "データを最後まで読み込めませんでした。もう一度お試しください。"
        }
    }
}
