import Foundation
import Observation

@MainActor
@Observable
final class RecruitStore {
    private let repository: RecruitRepository?
    private let notifications: LocalNotificationService

    var companies: [Company] = []
    var selectionSteps: [SelectionStep] = []
    var tasks: [RecruitTask] = []
    var isLoading = false
    var isSaving = false
    private(set) var savingTaskID: UUID?
    var errorMessage: String?
    private(set) var loadedUserID: UUID?
    private var reloadGeneration = 0

    init(repository: RecruitRepository?, notifications: LocalNotificationService) {
        self.repository = repository
        self.notifications = notifications
    }

    func reload(userID: UUID, force: Bool = false) async {
        if loadedUserID == userID, force == false { return }
        guard let repository else {
            errorMessage = RepositoryError.notConfigured.localizedDescription
            return
        }

        reloadGeneration += 1
        let generation = reloadGeneration
        isLoading = true
        errorMessage = nil
        defer {
            if reloadGeneration == generation { isLoading = false }
        }

        do {
            async let companies = repository.fetchCompanies(userID: userID)
            async let steps = repository.fetchSelectionSteps(userID: userID)
            async let tasks = repository.fetchTasks(userID: userID)
            let values = try await (companies, steps, tasks)
            guard reloadGeneration == generation else { return }
            self.companies = values.0
            selectionSteps = values.1
            self.tasks = values.2
            loadedUserID = userID
            await rescheduleNotificationsIfAuthorized()
        } catch {
            guard reloadGeneration == generation else { return }
            errorMessage = UserFacingError.message(
                for: error,
                fallback: "データを読み込めませんでした。通信状態を確認して、もう一度お試しください。"
            )
        }
    }

    func reset() async {
        reloadGeneration += 1
        isLoading = false
        isSaving = false
        savingTaskID = nil
        companies = []
        selectionSteps = []
        tasks = []
        loadedUserID = nil
        errorMessage = nil
        PendingNotificationStore.clear()
        await notifications.cancelAll()
    }

    @discardableResult
    func createCompany(userID: UUID, draft: CompanyDraft) async -> Company? {
        await performSave {
            guard let repository else { throw RepositoryError.notConfigured }
            let company = try await repository.createCompany(userID: userID, draft: draft)
            companies.insert(company, at: 0)
            return company
        }
    }

    @discardableResult
    func updateCompany(_ company: Company, draft: CompanyDraft) async -> Company? {
        await performSave {
            guard let repository else { throw RepositoryError.notConfigured }
            let updated = try await repository.updateCompany(company, draft: draft)
            Self.replace(updated, in: &companies)
            await rescheduleNotifications(for: updated)
            return updated
        }
    }

    func deleteCompany(_ company: Company) async -> Bool {
        let result: Bool? = await performSave {
            guard let repository else { throw RepositoryError.notConfigured }
            try await repository.deleteCompany(id: company.id)
            let stepIDs = selectionSteps.filter { $0.companyID == company.id }.map(\.id)
            let taskIDs = tasks.filter { $0.companyID == company.id }.map(\.id)
            companies.removeAll { $0.id == company.id }
            selectionSteps.removeAll { $0.companyID == company.id }
            tasks.removeAll { $0.companyID == company.id }
            for id in stepIDs { await notifications.cancelSelection(id: id) }
            for id in taskIDs { await notifications.cancelTask(id: id) }
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
        await performSave {
            guard let repository else { throw RepositoryError.notConfigured }
            let step = try await repository.createSelectionStep(
                userID: userID,
                companyID: companyID,
                draft: draft
            )
            selectionSteps.append(step)
            sortSelectionSteps()
            await scheduleNotification(
                step: step,
                companyName: company(id: companyID)?.name ?? "企業"
            )
            return step
        }
    }

    @discardableResult
    func updateSelectionStep(_ step: SelectionStep, draft: SelectionStepDraft) async -> SelectionStep? {
        await performSave {
            guard let repository else { throw RepositoryError.notConfigured }
            let updated = try await repository.updateSelectionStep(step, draft: draft)
            Self.replace(updated, in: &selectionSteps)
            sortSelectionSteps()
            await scheduleNotification(
                step: updated,
                companyName: company(id: updated.companyID)?.name ?? "企業"
            )
            return updated
        }
    }

    func deleteSelectionStep(_ step: SelectionStep) async -> Bool {
        let result: Bool? = await performSave {
            guard let repository else { throw RepositoryError.notConfigured }
            try await repository.deleteSelectionStep(id: step.id)
            selectionSteps.removeAll { $0.id == step.id }
            await notifications.cancelSelection(id: step.id)
            return true
        }
        return result ?? false
    }

    @discardableResult
    func createTask(userID: UUID, draft: RecruitTaskDraft) async -> RecruitTask? {
        await performSave {
            guard let repository else { throw RepositoryError.notConfigured }
            let task = try await repository.createTask(userID: userID, draft: draft)
            tasks.append(task)
            sortTasks()
            await scheduleNotification(
                task: task,
                companyName: task.companyID.flatMap { company(id: $0)?.name }
            )
            return task
        }
    }

    @discardableResult
    func updateTask(_ task: RecruitTask, draft: RecruitTaskDraft) async -> RecruitTask? {
        await performSave {
            guard let repository else { throw RepositoryError.notConfigured }
            let updated = try await repository.updateTask(task, draft: draft)
            Self.replace(updated, in: &tasks)
            sortTasks()
            await scheduleNotification(
                task: updated,
                companyName: updated.companyID.flatMap { company(id: $0)?.name }
            )
            return updated
        }
    }

    func setTaskCompleted(_ task: RecruitTask, completed: Bool) async -> Bool {
        guard isSaving == false else { return false }
        savingTaskID = task.id
        defer { savingTaskID = nil }
        let result: Bool? = await performSave {
            guard let repository else { throw RepositoryError.notConfigured }
            let updated = try await repository.setTaskCompleted(task, completed: completed)
            Self.replace(updated, in: &tasks)
            sortTasks()
            if completed {
                await notifications.cancelTask(id: task.id)
            } else {
                await scheduleNotification(
                    task: updated,
                    companyName: updated.companyID.flatMap { company(id: $0)?.name }
                )
            }
            return true
        }
        return result ?? false
    }

    func deleteTask(_ task: RecruitTask) async -> Bool {
        let result: Bool? = await performSave {
            guard let repository else { throw RepositoryError.notConfigured }
            try await repository.deleteTask(id: task.id)
            tasks.removeAll { $0.id == task.id }
            await notifications.cancelTask(id: task.id)
            return true
        }
        return result ?? false
    }

    func company(id: UUID) -> Company? {
        companies.first { $0.id == id }
    }

    func steps(for companyID: UUID) -> [SelectionStep] {
        selectionSteps
            .filter { $0.companyID == companyID }
            .sorted { ($0.earliestDate ?? .distantFuture) < ($1.earliestDate ?? .distantFuture) }
    }

    func tasks(for companyID: UUID) -> [RecruitTask] {
        tasks.filter { $0.companyID == companyID }
    }

    private func performSave<T>(_ operation: () async throws -> T) async -> T? {
        guard isSaving == false else { return nil }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            return try await operation()
        } catch {
            errorMessage = UserFacingError.message(
                for: error,
                fallback: "操作を完了できませんでした。通信状態を確認して、もう一度お試しください。"
            )
            return nil
        }
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
        tasks.sort { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }

    private func rescheduleNotifications(for company: Company) async {
        guard await notifications.canScheduleWithoutPrompt() else { return }
        for step in steps(for: company.id) {
            await scheduleNotification(step: step, companyName: company.name)
        }
        for task in tasks(for: company.id) {
            await scheduleNotification(task: task, companyName: company.name)
        }
    }

    private func rescheduleNotificationsIfAuthorized() async {
        guard await notifications.canScheduleWithoutPrompt() else { return }
        for step in selectionSteps {
            await scheduleNotification(
                step: step,
                companyName: company(id: step.companyID)?.name ?? "企業"
            )
        }
        for task in tasks {
            await scheduleNotification(
                task: task,
                companyName: task.companyID.flatMap { company(id: $0)?.name }
            )
        }
    }

    private func scheduleNotification(step: SelectionStep, companyName: String) async {
        do {
            try await notifications.schedule(step: step, companyName: companyName)
        } catch {
            errorMessage = "データは保存されましたが、通知を設定できませんでした。iOSの通知設定を確認してください。"
        }
    }

    private func scheduleNotification(task: RecruitTask, companyName: String?) async {
        do {
            try await notifications.schedule(task: task, companyName: companyName)
        } catch {
            errorMessage = "データは保存されましたが、通知を設定できませんでした。iOSの通知設定を確認してください。"
        }
    }
}
