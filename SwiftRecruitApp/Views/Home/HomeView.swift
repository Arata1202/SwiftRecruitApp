import SwiftUI

struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    @State private var isAddingCompany = false
    @State private var isAddingTask = false
    @State private var showsAllSelections = false
    @State private var showsAllOverdueTasks = false
    @State private var showsAllUpcomingTasks = false
    @State private var editingStep: SelectionStep?
    @State private var editingTask: RecruitTask?
    @State private var referenceDate = Date()
    @State private var completedTaskForUndo: RecruitTask?
    @State private var isUndoingTask = false
    @State private var completedSelectionForUndo: SelectionStep?
    @State private var isUndoingSelection = false
    @State private var undoDismissal: Task<Void, Never>?
    @State private var undoGeneration = UUID()
    @State private var isHomeVisible = false

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.companies.isEmpty && store.tasks.isEmpty {
                    ProgressView("予定を読み込み中")
                } else if let message = store.loadErrorMessage {
                    DataLoadFailureView(message: message) {
                        Task { await reload() }
                    }
                } else if hasItems == false {
                    emptyState
                } else {
                    List {
                        selectionSection
                        taskSection
                    }
                    .listStyle(.insetGrouped)
                    .animation(.snappy, value: upcomingSteps)
                    .animation(.snappy, value: taskBuckets.overdue)
                    .animation(.snappy, value: taskBuckets.upcoming)
                    .refreshable {
                        if let userID = session.userID { await store.reload(userID: userID, force: true) }
                    }
                }
            }
            .animation(.snappy, value: hasItems)
            .safeAreaInset(edge: .bottom) {
                if let step = completedSelectionForUndo {
                    selectionUndoBar(for: step)
                } else if let task = completedTaskForUndo {
                    undoBar(for: task)
                }
            }
            .onAppear { isHomeVisible = true }
            .onDisappear { isHomeVisible = false; clearUndo() }
            .onChange(of: store.isSaving) { _, saving in
                if saving { cancelUndoTimer() } else { scheduleUndoDismissal() }
            }
            .onChange(of: voiceOverEnabled) { _, _ in scheduleUndoDismissal() }
            .onChange(of: session.userID) { _, _ in
                clearUndo()
            }
            .onChange(of: store.selectionSteps) { _, steps in
                guard let completed = completedSelectionForUndo else { return }
                if !steps.contains(where: { $0.id == completed.id && $0.status == .completed && $0.version == completed.version }) {
                    completedSelectionForUndo = nil
                }
            }
            .onChange(of: store.tasks) { _, tasks in
                guard let completed = completedTaskForUndo else { return }
                if !tasks.contains(where: { $0.id == completed.id && $0.isCompleted && $0.version == completed.version }) {
                    completedTaskForUndo = nil
                }
            }
            .navigationTitle("ホーム")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { SettingsView() } label: {
                        Label("設定", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $isAddingCompany) {
                CompanyEditorView { company in
                    router.openCompany(id: company.id)
                }
            }
            .sheet(isPresented: $isAddingTask) { TaskEditorView() }
            .sheet(item: $editingStep) { SelectionStepEditorView(step: $0) }
            .sheet(item: $editingTask) { TaskEditorView(task: $0) }
            .recruitErrorAlert(store: store)
        }
        .task { await refreshReferenceDate() }
    }

    private var isFirstUse: Bool {
        store.companies.isEmpty && store.tasks.isEmpty
    }

    private var emptyState: some View {
        ContentUnavailableView {
            if isFirstUse {
                Label("就活管理を始めましょう", systemImage: "briefcase")
            } else {
                Label("直近の予定はありません", systemImage: "calendar.badge.checkmark")
            }
        } description: {
            if isFirstUse {
                Text("企業の選考や期限付きのToDoをまとめて確認できます。")
            } else {
                Text("7日以内の選考・締切と、期限切れや7日以内のToDoを表示します。")
            }
        } actions: {
            if store.companies.isEmpty {
                Button("企業を追加") { isAddingCompany = true }.buttonStyle(.borderedProminent)
                Button("ToDoを追加") { isAddingTask = true }.buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var selectionSection: some View {
        if upcomingSteps.isEmpty == false {
            Section("7日以内の選考・締切") {
                ForEach(showsAllSelections ? upcomingSteps : Array(upcomingSteps.prefix(8))) { step in
                    HStack(alignment: .top, spacing: 0) {
                        Button { Task { await completeSelection(step) } } label: {
                            Group {
                                if store.savingSelectionStepID == step.id {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "circle")
                                        .font(.title3)
                                        .foregroundStyle(Color.secondary)
                                }
                            }
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isSaving)
                        .accessibilityLabel(store.savingSelectionStepID == step.id
                            ? "「\(step.displayTitle)」を更新中"
                            : "「\(step.displayTitle)」を完了にする")
                        Button { editingStep = step } label: {
                            SelectionStepRow(
                                step: step,
                                companyName: store.company(id: step.companyID)?.name ?? "企業",
                                showsMilestoneKind: true,
                                showsMemo: true,
                                showsTypeIcon: false,
                                referenceDate: referenceDate,
                                homeLineLimits: true
                            )
                        }
                        .buttonStyle(.plain)
                        .contentShape(.rect)
                        .accessibilityHint("選考を編集")
                    }
                }
                if !showsAllSelections && upcomingSteps.count > 8 {
                    Button("残り\(upcomingSteps.count - 8)件を表示") { showsAllSelections = true }
                }
            }
        }
    }

    @ViewBuilder
    private var taskSection: some View {
        if taskBuckets.overdue.isEmpty == false {
            taskRows(title: "期限切れのToDo", tasks: taskBuckets.overdue, limit: 4, showsAll: $showsAllOverdueTasks)
        }
        if taskBuckets.upcoming.isEmpty == false {
            taskRows(title: "7日以内のToDo", tasks: taskBuckets.upcoming, limit: 8, showsAll: $showsAllUpcomingTasks)
        }
    }

    private func taskRows(title: String, tasks: [RecruitTask], limit: Int, showsAll: Binding<Bool>) -> some View {
            Section(title) {
                ForEach(showsAll.wrappedValue ? tasks : Array(tasks.prefix(limit))) { task in
                    HStack(alignment: .top, spacing: 0) {
                        TaskCompletionButton(
                            task: task,
                            isDisabled: store.isSaving,
                            isWorking: store.savingTaskID == task.id
                        ) {
                            Task { await completeTask(task) }
                        }
                        Button { editingTask = task } label: {
                            TaskRow(
                                task: task,
                                companyName: task.companyID.flatMap { store.company(id: $0)?.name },
                                showsDueLabel: true,
                                homeLineLimits: true
                            )
                        }
                        .buttonStyle(.plain)
                        .contentShape(.rect)
                        .accessibilityHint("ToDoを編集")
                    }
                }
                if !showsAll.wrappedValue && tasks.count > limit {
                    Button("残り\(tasks.count - limit)件を表示") { showsAll.wrappedValue = true }
                }
            }
    }

    private func undoBar(for task: RecruitTask) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("完了しました")
                Text(task.title).foregroundStyle(.secondary).lineLimit(1)
            }
            .font(.subheadline)
            Spacer(minLength: 0)
            Button("元に戻す") {
                cancelUndoTimer()
                Task { await undoTaskCompletion(task) }
            }
                .disabled(store.isSaving || isUndoingTask)
            Button("閉じる", systemImage: "xmark") { clearUndo() }
                .labelStyle(.iconOnly)
                .disabled(isUndoingTask)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @MainActor
    private func completeTask(_ task: RecruitTask) async {
        guard let userID = session.userID, store.loadedUserID == userID else {
            store.errorMessage = "ログイン状態または読み込み中のデータが変わりました。ログイン状態を確認し、データを再読み込みしてください。"
            return
        }
        let success = await store.setTaskCompleted(task, completed: true)
        guard success, isHomeVisible, session.userID == userID, store.loadedUserID == userID,
              let updated = store.tasks.first(where: { $0.id == task.id && $0.isCompleted })
        else { return }
        completedSelectionForUndo = nil
        completedTaskForUndo = updated
        scheduleUndoDismissal()
    }

    @MainActor
    private func undoTaskCompletion(_ task: RecruitTask) async {
        guard !isUndoingTask, !store.isSaving,
              let userID = session.userID, store.loadedUserID == userID,
              completedTaskForUndo?.id == task.id,
              let current = store.tasks.first(where: {
                  $0.id == task.id && $0.isCompleted && $0.version == task.version
              }) else {
            scheduleUndoDismissal()
            return
        }
        isUndoingTask = true
        defer { isUndoingTask = false; scheduleUndoDismissal() }
        let success = await store.setTaskCompleted(current, completed: false)
        if success, session.userID == userID, completedTaskForUndo?.id == task.id, completedTaskForUndo?.version == task.version {
            completedTaskForUndo = nil
        }
    }

    private func selectionUndoBar(for step: SelectionStep) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("完了しました")
                Text(step.displayTitle).foregroundStyle(.secondary).lineLimit(1)
            }
            .font(.subheadline)
            Spacer(minLength: 0)
            Button("元に戻す") {
                cancelUndoTimer()
                Task { await undoSelectionCompletion(step) }
            }
                .disabled(store.isSaving || isUndoingSelection)
            Button("閉じる", systemImage: "xmark") { clearUndo() }
                .labelStyle(.iconOnly).disabled(isUndoingSelection)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal).padding(.bottom, 8)
    }

    @MainActor
    private func completeSelection(_ step: SelectionStep) async {
        guard let userID = session.userID, store.loadedUserID == userID else {
            store.errorMessage = "ログイン状態または読み込み中のデータが変わりました。ログイン状態を確認し、データを再読み込みしてください。"
            return
        }
        guard let updated = await store.setSelectionStepStatus(step, status: .completed),
              isHomeVisible, session.userID == userID, store.loadedUserID == userID,
              store.selectionSteps.contains(where: { $0.id == updated.id && $0.version == updated.version && $0.status == .completed }) else { return }
        completedTaskForUndo = nil
        completedSelectionForUndo = updated
        scheduleUndoDismissal()
    }

    @MainActor
    private func undoSelectionCompletion(_ step: SelectionStep) async {
        guard !isUndoingSelection, !store.isSaving,
              let userID = session.userID, store.loadedUserID == userID,
              completedSelectionForUndo?.id == step.id,
              let current = store.selectionSteps.first(where: {
                  $0.id == step.id && $0.status == .completed && $0.version == step.version
              }) else { scheduleUndoDismissal(); return }
        isUndoingSelection = true
        defer { isUndoingSelection = false; scheduleUndoDismissal() }
        let updated = await store.setSelectionStepStatus(current, status: .scheduled)
        if updated != nil, session.userID == userID, completedSelectionForUndo?.id == step.id, completedSelectionForUndo?.version == step.version {
            completedSelectionForUndo = nil
        }
    }

    @MainActor
    private func cancelUndoTimer() {
        undoDismissal?.cancel()
        undoDismissal = nil
        undoGeneration = UUID()
    }

    @MainActor
    private func clearUndo() {
        cancelUndoTimer()
        completedTaskForUndo = nil
        completedSelectionForUndo = nil
    }

    @MainActor
    private func scheduleUndoDismissal() {
        cancelUndoTimer()
        // VoiceOver users can dismiss the bar manually without a time limit.
        guard isHomeVisible, !voiceOverEnabled, !store.isSaving, !isUndoingTask, !isUndoingSelection,
              completedTaskForUndo != nil || completedSelectionForUndo != nil else { return }
        let generation = undoGeneration
        undoDismissal = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            guard !Task.isCancelled, generation == undoGeneration,
                  !store.isSaving, !isUndoingTask, !isUndoingSelection else { return }
            clearUndo()
        }
    }

    private var hasItems: Bool {
        upcomingSteps.isEmpty == false
            || taskBuckets.overdue.isEmpty == false
            || taskBuckets.upcoming.isEmpty == false
    }

    private var upcomingSteps: [SelectionStep] {
        let now = referenceDate
        let end = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        let filtered = store.selectionSteps
            .filter { step in
                guard step.status == .scheduled else { return false }
                guard let milestone = step.nextMilestone(relativeTo: now) else { return false }
                let isCurrentOrFuture = milestone.hasTime
                    ? milestone.date >= now
                    : Calendar.current.startOfDay(for: milestone.date)
                        >= Calendar.current.startOfDay(for: now)
                let isInsideWindow = milestone.hasTime
                    ? milestone.date <= end
                    : Calendar.current.startOfDay(for: milestone.date)
                        <= Calendar.current.startOfDay(for: end)
                return isCurrentOrFuture && isInsideWindow
            }
        return HomeOrdering.steps(filtered, relativeTo: now)
    }

    private var taskBuckets: HomeTaskBuckets {
        HomeTaskBuckets.make(tasks: store.tasks, relativeTo: referenceDate)
    }

    private func reload() async {
        if let userID = session.userID { await store.reload(userID: userID, force: true) }
    }

    private func refreshReferenceDate() async {
        while Task.isCancelled == false {
            referenceDate = Date()
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                return
            }
        }
    }

}
