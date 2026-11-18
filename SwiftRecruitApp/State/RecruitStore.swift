import Foundation
import Observation

@MainActor
@Observable
final class RecruitStore {
    private let repository: RecruitRepository?
    private let notifications: LocalNotificationService
    @ObservationIgnored private lazy var notificationCoordinator = RecruitNotificationCoordinator(
        notifications: notifications,
        isCurrentSession: { [weak self] in self?.sessionGeneration == $0 },
        companies: { [weak self] in self?.companies ?? [] },
        selectionSteps: { [weak self] in self?.selectionSteps ?? [] },
        tasks: { [weak self] in self?.tasks ?? [] },
        reportError: { [weak self] in self?.errorMessage = $0 }
    )

    var companies: [Company] = []
    var companyInformationItems: [CompanyInformationItem] = []
    var selectionSteps: [SelectionStep] = []
    var tasks: [RecruitTask] = []
    var isLoading = false
    var isSaving = false
    private(set) var savingTaskID: UUID?
    private(set) var savingSelectionStepID: UUID?
    var errorMessage: String?
    private(set) var loadErrorMessage: String?
    private(set) var loadedUserID: UUID?
    private(set) var lastSuccessfulReloadAt: Date?
    private var reloadGeneration = 0
    private var sessionGeneration = 0

    init(
        repository: RecruitRepository?,
        notifications: LocalNotificationService
    ) {
        self.repository = repository
        self.notifications = notifications
    }

#if DEBUG
    func loadScreenshotData(userID: UUID) {
        let data = ScreenshotData.make()
        companies = data.companies
        companyInformationItems = []
        selectionSteps = data.selectionSteps
        tasks = data.tasks
        loadedUserID = userID
    }
#endif

    func reload(userID: UUID, force: Bool = false) async {
        guard isSaving == false else { return }
        guard isLoading == false else { return }
        if loadedUserID == userID, force == false { return }
        guard let repository else {
            errorMessage = RepositoryError.notConfigured.localizedDescription
            return
        }

        reloadGeneration += 1
        let generation = reloadGeneration
        isLoading = true
        errorMessage = nil
        loadErrorMessage = nil
        defer {
            if reloadGeneration == generation { isLoading = false }
        }

        do {
            async let companies = repository.fetchCompanies(userID: userID)
            async let informationItems = repository.fetchCompanyInformationItems(userID: userID)
            async let steps = repository.fetchSelectionSteps(userID: userID)
            async let tasks = repository.fetchTasks(userID: userID)
            let values = try await (companies, informationItems, steps, tasks)
            try Task.checkCancellation()
            guard reloadGeneration == generation else { return }
            self.companies = values.0
            companyInformationItems = values.1
            selectionSteps = values.2
            self.tasks = values.3
            loadedUserID = userID
            lastSuccessfulReloadAt = Date()
            await reconcileNotifications(
                generation: sessionGeneration,
                promptIfNeeded: false,
                reportDenied: false
            )
        } catch {
            guard reloadGeneration == generation else { return }
            // A cancelled refresh is not a failed server operation. Keep retained data.
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            let message = UserFacingError.message(
                for: error,
                fallback: "データを読み込めませんでした。少し待ってから、もう一度お試しください。"
            )
            if loadedUserID == nil
                && companies.isEmpty
                && companyInformationItems.isEmpty
                && selectionSteps.isEmpty
                && tasks.isEmpty {
                loadErrorMessage = message
            } else {
                errorMessage = message
            }
        }
    }

    func reset() async {
        reloadGeneration += 1
        sessionGeneration += 1
        isLoading = false
        isSaving = false
        savingTaskID = nil
        savingSelectionStepID = nil
        companies = []
        companyInformationItems = []
        selectionSteps = []
        tasks = []
        loadedUserID = nil
        lastSuccessfulReloadAt = nil
        errorMessage = nil
        loadErrorMessage = nil
        PendingNotificationStore.clear()
        await notifications.invalidateAndCancelAll()
    }

    @discardableResult
    func reloadIfStale(userID: UUID, now: Date = Date()) async -> Bool {
        guard isLoading == false, isSaving == false else { return false }
        guard loadedUserID != userID
                || ReloadPolicy.shouldReload(lastSuccessfulReloadAt: lastSuccessfulReloadAt, now: now)
        else { return false }
        let previousReload = lastSuccessfulReloadAt
        let expectedSession = sessionGeneration
        await reload(userID: userID, force: true)
        // Failed reloads need notification reconciliation using retained data.
        return sessionGeneration == expectedSession
            && loadedUserID == userID
            && lastSuccessfulReloadAt != previousReload
    }

    @discardableResult
    func createCompany(userID: UUID, draft: CompanyDraft) async -> Company? {
        await performSave { generation in
            _ = try WebURLNormalizer.validatedString(from: draft.url)
            guard let repository else { throw RepositoryError.notConfigured }
            let company = try await repository.createCompany(userID: userID, draft: draft)
            try ensureCurrentSession(generation)
            companies.insert(company, at: 0)
            return company
        }
    }

    @discardableResult
    func updateCompany(_ company: Company, draft: CompanyDraft) async -> Company? {
        await performSave { generation in
            _ = try WebURLNormalizer.validatedString(from: draft.url, preservingUnchanged: company.url)
            guard let repository else { throw RepositoryError.notConfigured }
            let updated = try await repository.updateCompany(company, draft: draft)
            try ensureCurrentSession(generation)
            Self.replace(updated, in: &companies)
            await reconcileNotifications(
                generation: generation,
                promptIfNeeded: false,
                reportDenied: false
            )
            return updated
        }
    }

    func deleteCompany(_ company: Company) async -> Bool {
        let result: Bool? = await performSave { generation in
            guard let repository else { throw RepositoryError.notConfigured }
            try await repository.deleteCompany(company)
            try ensureCurrentSession(generation)
            let stepIDs = selectionSteps.filter { $0.companyID == company.id }.map(\.id)
            let taskIDs = tasks.filter { $0.companyID == company.id }.map(\.id)
            companies.removeAll { $0.id == company.id }
            companyInformationItems.removeAll { $0.companyID == company.id }
            selectionSteps.removeAll { $0.companyID == company.id }
            tasks.removeAll { $0.companyID == company.id }
            for id in stepIDs { await notifications.cancelSelection(id: id) }
            for id in taskIDs { await notifications.cancelTask(id: id) }
            await reconcileNotifications(
                generation: generation,
                promptIfNeeded: false,
                reportDenied: false
            )
            return true
        }
        return result ?? false
    }

    @discardableResult
    func createCompanyInformationItem(
        userID: UUID,
        companyID: UUID,
        draft: CompanyInformationDraft
    ) async -> CompanyInformationItem? {
        await performSave { generation in
            guard let repository else { throw RepositoryError.notConfigured }
            let item = try await repository.createCompanyInformationItem(
                userID: userID,
                companyID: companyID,
                draft: draft
            )
            try ensureCurrentSession(generation)
            companyInformationItems.append(item)
            sortCompanyInformationItems()
            return item
        }
    }

    @discardableResult
    func updateCompanyInformationItem(
        _ item: CompanyInformationItem,
        draft: CompanyInformationDraft
    ) async -> CompanyInformationItem? {
        await performSave { generation in
            guard let repository else { throw RepositoryError.notConfigured }
            let updated = try await repository.updateCompanyInformationItem(item, draft: draft)
            try ensureCurrentSession(generation)
            Self.replace(updated, in: &companyInformationItems)
            sortCompanyInformationItems()
            return updated
        }
    }

    func deleteCompanyInformationItem(_ item: CompanyInformationItem) async -> Bool {
        let result: Bool? = await performSave { generation in
            guard let repository else { throw RepositoryError.notConfigured }
            try await repository.deleteCompanyInformationItem(item)
            try ensureCurrentSession(generation)
            companyInformationItems.removeAll { $0.id == item.id }
            return true
        }
        return result ?? false
    }

    @discardableResult
    func createSelectionStep(
        userID: UUID,
        companyID: UUID,
        draft: SelectionStepDraft
    ) async -> SelectionStep? {
        await performSave { generation in
            guard let repository else { throw RepositoryError.notConfigured }
            let step = try await repository.createSelectionStep(
                userID: userID,
                companyID: companyID,
                draft: draft
            )
            try ensureCurrentSession(generation)
            selectionSteps.append(step)
            sortSelectionSteps()
            let shouldNotify = step.notificationEnabled && step.status == .scheduled
            await reconcileNotifications(
                generation: generation,
                promptIfNeeded: shouldNotify,
                reportDenied: shouldNotify
            )
            return step
        }
    }

    @discardableResult
    func updateSelectionStep(_ step: SelectionStep, draft: SelectionStepDraft) async -> SelectionStep? {
        await performSave { generation in
            guard let repository else { throw RepositoryError.notConfigured }
            let updated = try await repository.updateSelectionStep(step, draft: draft)
            try ensureCurrentSession(generation)
            Self.replace(updated, in: &selectionSteps)
            sortSelectionSteps()
            if updated.status != .scheduled { await notifications.cancelSelection(id: updated.id) }
            let shouldNotify = updated.notificationEnabled && updated.status == .scheduled
            await reconcileNotifications(
                generation: generation,
                promptIfNeeded: shouldNotify,
                reportDenied: shouldNotify
            )
            return updated
        }
    }

    func setSelectionStepStatus(_ step: SelectionStep, status: SelectionStepStatus) async -> SelectionStep? {
        guard isSaving == false else { return nil }
        let generation = sessionGeneration
        savingSelectionStepID = step.id
        defer {
            if sessionGeneration == generation { savingSelectionStepID = nil }
        }
        return await performSave { generation in
            guard let repository else { throw RepositoryError.notConfigured }
            let updated = try await repository.setSelectionStepStatus(step, status: status, notificationEnabled: step.notificationEnabled)
            try ensureCurrentSession(generation)
            Self.replace(updated, in: &selectionSteps)
            sortSelectionSteps()
            if updated.status != .scheduled {
                await notifications.cancelSelection(id: step.id)
            }
            let shouldNotify = updated.notificationEnabled && updated.status == .scheduled
            await reconcileNotifications(generation: generation, promptIfNeeded: shouldNotify, reportDenied: shouldNotify)
            return updated
        }
    }

    func deleteSelectionStep(_ step: SelectionStep) async -> Bool {
        let result: Bool? = await performSave { generation in
            guard let repository else { throw RepositoryError.notConfigured }
            try await repository.deleteSelectionStep(step)
            try ensureCurrentSession(generation)
            selectionSteps.removeAll { $0.id == step.id }
            await notifications.cancelSelection(id: step.id)
            await reconcileNotifications(
                generation: generation,
                promptIfNeeded: false,
                reportDenied: false
            )
            return true
        }
        return result ?? false
    }

    @discardableResult
    func createTask(userID: UUID, draft: RecruitTaskDraft) async -> RecruitTask? {
        await performSave { generation in
            guard let repository else { throw RepositoryError.notConfigured }
            let task = try await repository.createTask(userID: userID, draft: draft)
            try ensureCurrentSession(generation)
            tasks.append(task)
            sortTasks()
            let shouldNotify = task.notificationEnabled
                && task.isCompleted == false
                && task.dueDate() != nil
            await reconcileNotifications(
                generation: generation,
                promptIfNeeded: shouldNotify,
                reportDenied: shouldNotify
            )
            return task
        }
    }

    @discardableResult
    func updateTask(_ task: RecruitTask, draft: RecruitTaskDraft) async -> RecruitTask? {
        await performSave { generation in
            guard let repository else { throw RepositoryError.notConfigured }
            let updated = try await repository.updateTask(task, draft: draft)
            try ensureCurrentSession(generation)
            Self.replace(updated, in: &tasks)
            sortTasks()
            let shouldNotify = updated.notificationEnabled
                && updated.isCompleted == false
                && updated.dueDate() != nil
            await reconcileNotifications(
                generation: generation,
                promptIfNeeded: shouldNotify,
                reportDenied: shouldNotify
            )
            return updated
        }
    }

    func setTaskCompleted(_ task: RecruitTask, completed: Bool) async -> Bool {
        guard isSaving == false else { return false }
        let generation = sessionGeneration
        savingTaskID = task.id
        defer {
            if sessionGeneration == generation { savingTaskID = nil }
        }
        let result: Bool? = await performSave { generation in
            guard let repository else { throw RepositoryError.notConfigured }
            let updated = try await repository.setTaskCompleted(task, completed: completed)
            try ensureCurrentSession(generation)
            Self.replace(updated, in: &tasks)
            sortTasks()
            if completed {
                await notifications.cancelTask(id: task.id)
            }
            let shouldNotify = completed == false
                && updated.notificationEnabled
                && updated.dueDate() != nil
            await reconcileNotifications(
                generation: generation,
                promptIfNeeded: shouldNotify,
                reportDenied: shouldNotify
            )
            return true
        }
        return result ?? false
    }

    func deleteTask(_ task: RecruitTask) async -> Bool {
        let result: Bool? = await performSave { generation in
            guard let repository else { throw RepositoryError.notConfigured }
            try await repository.deleteTask(task)
            try ensureCurrentSession(generation)
            tasks.removeAll { $0.id == task.id }
            await notifications.cancelTask(id: task.id)
            await reconcileNotifications(
                generation: generation,
                promptIfNeeded: false,
                reportDenied: false
            )
            return true
        }
        return result ?? false
    }

    func company(id: UUID) -> Company? {
        companies.first { $0.id == id }
    }

    func informationItems(for companyID: UUID) -> [CompanyInformationItem] {
        companyInformationItems.filter { $0.companyID == companyID }
    }

    func steps(for companyID: UUID) -> [SelectionStep] {
        selectionSteps
            .filter { $0.companyID == companyID }
            .sorted { ($0.earliestDate ?? .distantFuture) < ($1.earliestDate ?? .distantFuture) }
    }

    func tasks(for companyID: UUID) -> [RecruitTask] {
        tasks.filter { $0.companyID == companyID }
    }

    func rescheduleAllNotificationsIfAuthorized() async {
        let generation = sessionGeneration
        await reconcileNotifications(
            generation: generation,
            promptIfNeeded: false,
            reportDenied: false
        )
    }

    private func performSave<T>(_ operation: (Int) async throws -> T) async -> T? {
        guard isSaving == false else { return nil }
        reloadGeneration += 1
        isLoading = false
        let generation = sessionGeneration
        isSaving = true
        errorMessage = nil
        defer {
            if sessionGeneration == generation { isSaving = false }
        }
        do {
            let result = try await operation(generation)
            try ensureCurrentSession(generation)
            return result
        } catch is CancellationError {
            return nil
        } catch {
            guard sessionGeneration == generation else { return nil }
            errorMessage = UserFacingError.message(
                for: error,
                fallback: "操作を完了できませんでした。通信状態を確認して、もう一度お試しください。"
            )
            return nil
        }
    }

    private func ensureCurrentSession(_ generation: Int) throws {
        guard sessionGeneration == generation else { throw CancellationError() }
    }

    private static func replace<T: Identifiable>(_ value: T, in values: inout [T]) where T.ID == UUID {
        guard let index = values.firstIndex(where: { $0.id == value.id }) else { return }
        values[index] = value
    }

    private func sortSelectionSteps() {
        selectionSteps.sort {
            ($0.earliestDate ?? .distantFuture) < ($1.earliestDate ?? .distantFuture)
        }
    }

    private func sortTasks() {
        tasks.sort { ($0.dueDate() ?? .distantFuture) < ($1.dueDate() ?? .distantFuture) }
    }

    private func sortCompanyInformationItems() {
        companyInformationItems = CompanyInformationSorting.sorted(companyInformationItems)
    }

    private func reconcileNotifications(
        generation: Int,
        promptIfNeeded: Bool,
        reportDenied: Bool
    ) async {
        await notificationCoordinator.reconcile(
            generation: generation,
            promptIfNeeded: promptIfNeeded,
            reportDenied: reportDenied
        )
    }
}
