import Foundation
import Observation

@MainActor
@Observable
final class RecruitStore {
    private let repository: RecruitRepository?
    private let notifications: LocalNotificationService
    private let appleCalendar: AppleCalendarService

    var companies: [Company] = []
    var companyInformationItems: [CompanyInformationItem] = []
    var selectionSteps: [SelectionStep] = []
    var tasks: [RecruitTask] = []
    var esTemplates: [ESTemplate] = []
    var isLoading = false
    var isSaving = false
    private(set) var savingTaskID: UUID?
    var errorMessage: String?
    private(set) var loadErrorMessage: String?
    private(set) var loadedUserID: UUID?
    private(set) var lastSuccessfulReloadAt: Date?
    private var reloadGeneration = 0
    private var sessionGeneration = 0

    init(
        repository: RecruitRepository?,
        notifications: LocalNotificationService,
        appleCalendar: AppleCalendarService
    ) {
        self.repository = repository
        self.notifications = notifications
        self.appleCalendar = appleCalendar
    }

#if DEBUG
    func loadScreenshotData(userID: UUID) {
        let data = ScreenshotData.make()
        companies = data.companies
        companyInformationItems = []
        selectionSteps = data.selectionSteps
        tasks = data.tasks
        esTemplates = []
        loadedUserID = userID
    }
#endif

    func reload(userID: UUID, force: Bool = false) async {
        appleCalendar.activate(userID: userID)
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
            async let esTemplates = repository.fetchESTemplates(userID: userID)
            let values = try await (companies, informationItems, steps, tasks, esTemplates)
            guard reloadGeneration == generation else { return }
            self.companies = values.0
            companyInformationItems = values.1
            selectionSteps = values.2
            self.tasks = values.3
            self.esTemplates = values.4
            loadedUserID = userID
            lastSuccessfulReloadAt = Date()
            await reconcileNotifications(
                generation: sessionGeneration,
                promptIfNeeded: false,
                reportDenied: false
            )
            await reconcileAppleCalendarExports()
        } catch {
            guard reloadGeneration == generation else { return }
            let message = UserFacingError.message(
                for: error,
                fallback: "データを読み込めませんでした。少し待ってから、もう一度お試しください。"
            )
            if loadedUserID == nil
                && companies.isEmpty
                && companyInformationItems.isEmpty
                && selectionSteps.isEmpty
                && tasks.isEmpty
                && esTemplates.isEmpty {
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
        companies = []
        companyInformationItems = []
        selectionSteps = []
        tasks = []
        esTemplates = []
        loadedUserID = nil
        lastSuccessfulReloadAt = nil
        errorMessage = nil
        loadErrorMessage = nil
        PendingNotificationStore.clear()
        await notifications.invalidateAndCancelAll()
        appleCalendar.activate(userID: nil)
    }

    @discardableResult
    func reloadIfStale(userID: UUID, now: Date = Date()) async -> Bool {
        guard isLoading == false, isSaving == false else { return false }
        guard loadedUserID != userID
                || ReloadPolicy.shouldReload(lastSuccessfulReloadAt: lastSuccessfulReloadAt, now: now)
        else { return false }
        await reload(userID: userID, force: true)
        return true
    }

    @discardableResult
    func createCompany(userID: UUID, draft: CompanyDraft) async -> Company? {
        await performSave { generation in
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
            guard let repository else { throw RepositoryError.notConfigured }
            let updated = try await repository.updateCompany(company, draft: draft)
            try ensureCurrentSession(generation)
            Self.replace(updated, in: &companies)
            await syncExportedEvents(for: updated.id)
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
            for id in stepIDs { await removeExportedSelection(id: id) }
            for id in taskIDs { await removeExportedTask(id: id) }
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
            await syncExportedSelection(step)
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
            await syncExportedSelection(updated)
            let shouldNotify = updated.notificationEnabled && updated.status == .scheduled
            await reconcileNotifications(
                generation: generation,
                promptIfNeeded: shouldNotify,
                reportDenied: shouldNotify
            )
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
            await removeExportedSelection(id: step.id)
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
            await syncExportedTask(task)
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
            await syncExportedTask(updated)
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
        savingTaskID = task.id
        defer { savingTaskID = nil }
        let result: Bool? = await performSave { generation in
            guard let repository else { throw RepositoryError.notConfigured }
            let updated = try await repository.setTaskCompleted(task, completed: completed)
            try ensureCurrentSession(generation)
            Self.replace(updated, in: &tasks)
            sortTasks()
            await syncExportedTask(updated)
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
            await removeExportedTask(id: task.id)
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
    func createESTemplate(userID: UUID, draft: ESTemplateDraft) async -> ESTemplate? {
        await performSave { generation in
            guard let repository else { throw RepositoryError.notConfigured }
            let template = try await repository.createESTemplate(userID: userID, draft: draft)
            try ensureCurrentSession(generation)
            esTemplates.append(template)
            sortESTemplates()
            return template
        }
    }

    @discardableResult
    func updateESTemplate(_ template: ESTemplate, draft: ESTemplateDraft) async -> ESTemplate? {
        await performSave { generation in
            guard let repository else { throw RepositoryError.notConfigured }
            let updated = try await repository.updateESTemplate(template, draft: draft)
            try ensureCurrentSession(generation)
            Self.replace(updated, in: &esTemplates)
            sortESTemplates()
            return updated
        }
    }

    func deleteESTemplate(_ template: ESTemplate) async -> Bool {
        let result: Bool? = await performSave { generation in
            guard let repository else { throw RepositoryError.notConfigured }
            try await repository.deleteESTemplate(template)
            try ensureCurrentSession(generation)
            esTemplates.removeAll { $0.id == template.id }
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

    func isSelectionExported(id: UUID, kind: SelectionMilestoneKind) -> Bool {
        appleCalendar.isExported(key: AppleCalendarService.selectionKey(id: id, kind: kind))
    }

    func isTaskExported(id: UUID) -> Bool {
        appleCalendar.isExported(key: AppleCalendarService.taskKey(id: id))
    }

    var isAppleCalendarAutoSyncEnabled: Bool {
        appleCalendar.isAutoSyncEnabled
    }

    func isAppleCalendarCategoryEnabled(_ category: AppleCalendarSyncCategory) -> Bool {
        appleCalendar.isCategoryEnabled(category)
    }

    var appleCalendarAutoSyncItemCount: Int {
        var count = 0
        if appleCalendar.isCategoryEnabled(.selection) {
            count += selectionSteps.filter {
                isAutoSyncEligible($0, kind: .start)
                    && appleCalendar.isAutoSyncSuppressed(
                        key: AppleCalendarService.selectionKey(id: $0.id, kind: .start)
                    ) == false
            }.count
        }
        if appleCalendar.isCategoryEnabled(.deadline) {
            count += selectionSteps.filter {
                isAutoSyncEligible($0, kind: .deadline)
                    && appleCalendar.isAutoSyncSuppressed(
                        key: AppleCalendarService.selectionKey(id: $0.id, kind: .deadline)
                    ) == false
            }.count
        }
        if appleCalendar.isCategoryEnabled(.task) {
            count += tasks.filter {
                isAutoSyncEligible($0)
                    && appleCalendar.isAutoSyncSuppressed(
                        key: AppleCalendarService.taskKey(id: $0.id)
                    ) == false
            }.count
        }
        return count
    }

    func setAppleCalendarCategory(_ category: AppleCalendarSyncCategory, enabled: Bool) async {
        appleCalendar.setCategory(category, enabled: enabled)
        guard appleCalendar.isAutoSyncEnabled else { return }
        if enabled {
            await reconcileAppleCalendarExports()
        } else {
            await removeAutomaticallyManagedEvents(for: category)
        }
    }

    func setAppleCalendarAutoSyncEnabled(_ enabled: Bool) async -> Bool {
        do {
            try await appleCalendar.setAutoSyncEnabled(enabled)
            if enabled { await reconcileAppleCalendarExports() }
            return true
        } catch {
            errorMessage = UserFacingError.message(
                for: error,
                fallback: "Appleカレンダーの自動連携を設定できませんでした。"
            )
            return false
        }
    }

    func exportSelection(_ step: SelectionStep, kind: SelectionMilestoneKind) async -> Bool {
        guard let descriptor = selectionDescriptor(step, kind: kind) else { return false }
        do {
            _ = try await appleCalendar.export(descriptor)
            return true
        } catch {
            errorMessage = UserFacingError.message(
                for: error,
                fallback: "Appleカレンダーへ追加できませんでした。設定を確認してください。"
            )
            return false
        }
    }

    func exportTask(_ task: RecruitTask) async -> Bool {
        guard let descriptor = taskDescriptor(task) else { return false }
        do {
            _ = try await appleCalendar.export(descriptor)
            return true
        } catch {
            errorMessage = UserFacingError.message(
                for: error,
                fallback: "Appleカレンダーへ追加できませんでした。設定を確認してください。"
            )
            return false
        }
    }

    func removeSelectionFromAppleCalendar(
        id: UUID,
        kind: SelectionMilestoneKind
    ) async -> Bool {
        await removeFromAppleCalendar(
            key: AppleCalendarService.selectionKey(id: id, kind: kind)
        )
    }

    func removeTaskFromAppleCalendar(id: UUID) async -> Bool {
        await removeFromAppleCalendar(key: AppleCalendarService.taskKey(id: id))
    }

    func rescheduleAllNotificationsIfAuthorized() async {
        let generation = sessionGeneration
        await reconcileNotifications(
            generation: generation,
            promptIfNeeded: false,
            reportDenied: false
        )
    }

    func resyncAppleCalendarIfNeeded() async {
        guard appleCalendar.isAutoSyncEnabled || appleCalendar.hasManagedEvents else { return }
        await reconcileAppleCalendarExports()
    }

    func removeAppleCalendarEventsForAccountDeletion() async throws {
        var descriptors: [AppleCalendarEventDescriptor] = []
        for step in selectionSteps {
            descriptors += [SelectionMilestoneKind.start, .deadline].compactMap {
                selectionDescriptor(step, kind: $0)
            }
        }
        descriptors += tasks.compactMap(taskDescriptor)

        do {
            try await appleCalendar.removeAllManagedEvents(matching: descriptors)
        } catch {
            throw AccountDeletionPreparationError.calendarCleanupFailed
        }
    }

    func purgeAppleCalendarPreferences(userID: UUID) {
        appleCalendar.purgePreferences(userID: userID)
    }

    private func performSave<T>(_ operation: (Int) async throws -> T) async -> T? {
        guard isSaving == false else { return nil }
        reloadGeneration += 1
        isLoading = false
        let generation = sessionGeneration
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            return try await operation(generation)
        } catch is CancellationError {
            return nil
        } catch {
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

    private func sortESTemplates() {
        esTemplates = ESTemplateSorting.sorted(esTemplates)
    }

    private func syncExportedEvents(for companyID: UUID) async {
        for step in selectionSteps where step.companyID == companyID {
            await syncExportedSelection(step)
        }
        for task in tasks where task.companyID == companyID {
            await syncExportedTask(task)
        }
    }

    private func reconcileAppleCalendarExports() async {
        try? await appleCalendar.retryPendingRemovals()
        await removeOrphanedCalendarEvents()
        for step in selectionSteps {
            await syncExportedSelection(step)
        }
        for task in tasks {
            await syncExportedTask(task)
        }
    }

    private func syncExportedSelection(_ step: SelectionStep) async {
        if step.status == .cancelled {
            await removeExportedSelection(id: step.id)
            return
        }
        for kind in [SelectionMilestoneKind.start, .deadline] {
            let key = AppleCalendarService.selectionKey(id: step.id, kind: kind)
            let category: AppleCalendarSyncCategory = kind == .start ? .selection : .deadline
            let shouldAutoExport = appleCalendar.isAutoSyncEnabled
                && appleCalendar.isCategoryEnabled(category)
                && appleCalendar.isAutoSyncSuppressed(key: key) == false
                && isAutoSyncEligible(step, kind: kind)
            guard appleCalendar.isExported(key: key) || shouldAutoExport else { continue }
            guard let descriptor = selectionDescriptor(step, kind: kind) else {
                try? await appleCalendar.remove(key: key)
                continue
            }
            do {
                if appleCalendar.isExported(key: key) {
                    try await appleCalendar.sync(descriptor)
                } else {
                    _ = try await appleCalendar.export(descriptor, automatically: true)
                }
            } catch {
                errorMessage = "Appleカレンダーへ変更を反映できませんでした。iOSの設定を確認してください。"
            }
        }
    }

    private func syncExportedTask(_ task: RecruitTask) async {
        let key = AppleCalendarService.taskKey(id: task.id)
        let shouldAutoExport = appleCalendar.isAutoSyncEnabled
            && appleCalendar.isCategoryEnabled(.task)
            && appleCalendar.isAutoSyncSuppressed(key: key) == false
            && isAutoSyncEligible(task)
        guard appleCalendar.isExported(key: key) || shouldAutoExport else { return }
        guard let descriptor = taskDescriptor(task) else {
            try? await appleCalendar.remove(key: key)
            return
        }
        do {
            if appleCalendar.isExported(key: key) {
                try await appleCalendar.sync(descriptor)
            } else {
                _ = try await appleCalendar.export(descriptor, automatically: true)
            }
        } catch {
            errorMessage = "Appleカレンダーへ変更を反映できませんでした。iOSの設定を確認してください。"
        }
    }

    private func removeExportedSelection(id: UUID) async {
        do {
            try await appleCalendar.removeSelection(id: id)
        } catch {
            errorMessage = "リクビジョンのデータは削除されましたが、Appleカレンダーの予定を削除できませんでした。"
        }
    }

    private func removeExportedTask(id: UUID) async {
        do {
            try await appleCalendar.remove(key: AppleCalendarService.taskKey(id: id))
        } catch {
            errorMessage = "リクビジョンのデータは削除されましたが、Appleカレンダーの予定を削除できませんでした。"
        }
    }

    private func removeFromAppleCalendar(key: String) async -> Bool {
        do {
            try await appleCalendar.remove(key: key, suppressAutoSync: true)
            return true
        } catch {
            errorMessage = UserFacingError.message(
                for: error,
                fallback: "Appleカレンダーから予定を削除できませんでした。"
            )
            return false
        }
    }

    private func removeAutomaticallyManagedEvents(for category: AppleCalendarSyncCategory) async {
        do {
            try await appleCalendar.removeManagedEvents(category: category)
        } catch {
            errorMessage = "自動追加したAppleカレンダーの予定を削除できませんでした。権限の設定を確認してください。"
        }
    }

    private func removeOrphanedCalendarEvents() async {
        var desiredKeys = Set<String>()
        for step in selectionSteps where step.status != .cancelled {
            if step.startDate() != nil {
                desiredKeys.insert(AppleCalendarService.selectionKey(id: step.id, kind: .start))
            }
            if step.deadlineDate() != nil {
                desiredKeys.insert(AppleCalendarService.selectionKey(id: step.id, kind: .deadline))
            }
        }
        for task in tasks where task.dueDate() != nil {
            desiredKeys.insert(AppleCalendarService.taskKey(id: task.id))
        }
        for key in appleCalendar.managedKeys.subtracting(desiredKeys) {
            try? await appleCalendar.remove(key: key)
        }
    }

    private func isAutoSyncEligible(
        _ step: SelectionStep,
        kind: SelectionMilestoneKind
    ) -> Bool {
        guard step.status == .scheduled else { return false }
        switch kind {
        case .start:
            guard let date = step.startDate() else { return false }
            return AppleCalendarSyncPolicy.isUpcoming(date: date, hasTime: step.startsHasTime)
        case .deadline:
            guard let date = step.deadlineDate() else { return false }
            return AppleCalendarSyncPolicy.isUpcoming(date: date, hasTime: step.deadlineHasTime)
        }
    }

    private func isAutoSyncEligible(_ task: RecruitTask) -> Bool {
        guard task.isCompleted == false, let date = task.dueDate() else { return false }
        return AppleCalendarSyncPolicy.isUpcoming(date: date, hasTime: task.dueHasTime)
    }

    private func selectionDescriptor(
        _ step: SelectionStep,
        kind: SelectionMilestoneKind
    ) -> AppleCalendarEventDescriptor? {
        let date: Date?
        let hasTime: Bool
        switch kind {
        case .start:
            date = step.startDate()
            hasTime = step.startsHasTime
        case .deadline:
            date = step.deadlineDate()
            hasTime = step.deadlineHasTime
        }
        guard let date else { return nil }
        let companyName = company(id: step.companyID)?.name
        let baseTitle = [companyName, step.displayTitle].compactMap { $0 }.joined(separator: " · ")
        let kindTitle = kind == .deadline ? "【締切】\(baseTitle)" : baseTitle
        let title = step.status == .completed ? "【完了】\(kindTitle)" : kindTitle
        return AppleCalendarEventDescriptor(
            key: AppleCalendarService.selectionKey(id: step.id, kind: kind),
            title: title,
            notes: step.memo,
            startDate: date,
            hasTime: hasTime,
            duration: kind == .start ? 3_600 : 1_800
        )
    }

    private func taskDescriptor(_ task: RecruitTask) -> AppleCalendarEventDescriptor? {
        guard let date = task.dueDate() else { return nil }
        let companyName = task.companyID.flatMap { company(id: $0)?.name }
        let baseTitle = [companyName, task.title].compactMap { $0 }.joined(separator: " · ")
        return AppleCalendarEventDescriptor(
            key: AppleCalendarService.taskKey(id: task.id),
            title: task.isCompleted ? "【完了】\(baseTitle)" : baseTitle,
            notes: task.memo,
            startDate: date,
            hasTime: task.dueHasTime,
            duration: 1_800
        )
    }

    private func reconcileNotifications(
        generation: Int,
        promptIfNeeded: Bool,
        reportDenied: Bool
    ) async {
        guard sessionGeneration == generation else { return }

        do {
            let isAuthorized: Bool
            if promptIfNeeded {
                isAuthorized = try await notifications.requestAuthorizationIfNeeded()
            } else {
                isAuthorized = await notifications.canScheduleWithoutPrompt()
            }

            guard sessionGeneration == generation else { return }
            guard isAuthorized else {
                if reportDenied {
                    errorMessage = "データは保存されましたが、通知は許可されていません。設定画面からiOSの通知を有効にしてください。"
                }
                return
            }

            let companyNames = Dictionary(
                uniqueKeysWithValues: companies.map { ($0.id, $0.name) }
            )
            try await notifications.reconcile(
                steps: selectionSteps,
                tasks: tasks,
                companyNames: companyNames
            )
        } catch {
            guard sessionGeneration == generation else { return }
            errorMessage = "データは保存されましたが、通知を設定できませんでした。iOSの通知設定を確認してください。"
        }
    }
}

enum AccountDeletionPreparationError: LocalizedError {
    case calendarCleanupFailed

    var errorDescription: String? {
        switch self {
        case .calendarCleanupFailed:
            "Appleカレンダーの予定を削除できませんでした。iOSの設定でカレンダーへのフルアクセスを許可して、もう一度お試しください。"
        }
    }
}
