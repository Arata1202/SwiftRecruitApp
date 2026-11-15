import Foundation

/// Translates recruit state into calendar exports; persistence/session ownership stays in RecruitStore.
@MainActor
final class RecruitCalendarCoordinator {
    private let appleCalendar: AppleCalendarService
    private let currentCompanies: () -> [Company]
    private let currentSelectionSteps: () -> [SelectionStep]
    private let currentTasks: () -> [RecruitTask]
    private let reportError: (String) -> Void

    // Read live state at the same points as the Store did, including after suspension.
    private var companies: [Company] { currentCompanies() }
    private var selectionSteps: [SelectionStep] { currentSelectionSteps() }
    private var tasks: [RecruitTask] { currentTasks() }

    init(
        appleCalendar: AppleCalendarService,
        companies: @escaping () -> [Company],
        selectionSteps: @escaping () -> [SelectionStep],
        tasks: @escaping () -> [RecruitTask],
        reportError: @escaping (String) -> Void
    ) {
        self.appleCalendar = appleCalendar
        currentCompanies = companies
        currentSelectionSteps = selectionSteps
        currentTasks = tasks
        self.reportError = reportError
    }

    func activate(userID: UUID?) {
        appleCalendar.activate(userID: userID)
    }

    private func company(id: UUID) -> Company? {
        companies.first { $0.id == id }
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
            reportError(UserFacingError.message(
                for: error,
                fallback: "Appleカレンダーの自動連携を設定できませんでした。"
            ))
            return false
        }
    }

    func exportSelection(_ step: SelectionStep, kind: SelectionMilestoneKind) async -> Bool {
        guard let descriptor = selectionDescriptor(step, kind: kind) else { return false }
        do {
            _ = try await appleCalendar.export(descriptor)
            return true
        } catch {
            reportError(UserFacingError.message(
                for: error,
                fallback: "Appleカレンダーへ追加できませんでした。設定を確認してください。"
            ))
            return false
        }
    }

    func exportTask(_ task: RecruitTask) async -> Bool {
        guard let descriptor = taskDescriptor(task) else { return false }
        do {
            _ = try await appleCalendar.export(descriptor)
            return true
        } catch {
            reportError(UserFacingError.message(
                for: error,
                fallback: "Appleカレンダーへ追加できませんでした。設定を確認してください。"
            ))
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

    func syncExportedEvents(for companyID: UUID) async {
        for step in selectionSteps where step.companyID == companyID {
            await syncExportedSelection(step)
        }
        for task in tasks where task.companyID == companyID {
            await syncExportedTask(task)
        }
    }

    func reconcileAppleCalendarExports() async {
        try? await appleCalendar.retryPendingRemovals()
        await removeOrphanedCalendarEvents()
        for step in selectionSteps {
            await syncExportedSelection(step)
        }
        for task in tasks {
            await syncExportedTask(task)
        }
    }

    func syncExportedSelection(_ step: SelectionStep) async {
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
                reportError("Appleカレンダーへ変更を反映できませんでした。iOSの設定を確認してください。")
            }
        }
    }

    func syncExportedTask(_ task: RecruitTask) async {
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
            reportError("Appleカレンダーへ変更を反映できませんでした。iOSの設定を確認してください。")
        }
    }

    func removeExportedSelection(id: UUID) async {
        do {
            try await appleCalendar.removeSelection(id: id)
        } catch {
            reportError("リクビジョンのデータは削除されましたが、Appleカレンダーの予定を削除できませんでした。")
        }
    }

    func removeExportedTask(id: UUID) async {
        do {
            try await appleCalendar.remove(key: AppleCalendarService.taskKey(id: id))
        } catch {
            reportError("リクビジョンのデータは削除されましたが、Appleカレンダーの予定を削除できませんでした。")
        }
    }

    private func removeFromAppleCalendar(key: String) async -> Bool {
        do {
            try await appleCalendar.remove(key: key, suppressAutoSync: true)
            return true
        } catch {
            reportError(UserFacingError.message(
                for: error,
                fallback: "Appleカレンダーから予定を削除できませんでした。"
            ))
            return false
        }
    }

    private func removeAutomaticallyManagedEvents(for category: AppleCalendarSyncCategory) async {
        do {
            try await appleCalendar.removeManagedEvents(category: category)
        } catch {
            reportError("自動追加したAppleカレンダーの予定を削除できませんでした。権限の設定を確認してください。")
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
}
