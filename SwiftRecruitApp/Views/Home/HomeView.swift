import SwiftUI

struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isAddingCompany = false
    @State private var isAddingTask = false
    @State private var showsAllSelections = false
    @State private var showsAllPastSelections = false
    @State private var showsAllOverdueTasks = false
    @State private var showsAllUpcomingTasks = false
    @State private var selectedStep: SelectionStep?
    @State private var editingTask: RecruitTask?
    @State private var referenceDate = Date()
    @State private var completedTaskForUndo: RecruitTask?
    @State private var isUndoingTask = false
    @State private var completedSelectionForUndo: SelectionStep?
    @State private var isUndoingSelection = false
    @State private var undoDismissal: Task<Void, Never>?
    @State private var undoGeneration = UUID()
    @State private var isHomeVisible = false
    // Independent of timer resets; every leave/return starts a new UI lifetime.
    @State private var visibilityGeneration = UUID()
    @State private var undoBarHeight: CGFloat = 0

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.loadedUserID == nil && store.companies.isEmpty && store.tasks.isEmpty {
                    ProgressView("予定を読み込み中")
                } else if let message = store.loadErrorMessage {
                    DataLoadFailureView(message: message) {
                        Task { await reload() }
                    }
                } else if hasItems == false {
                    GeometryReader { geometry in
                        ScrollView {
                            emptyState
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: max(0, geometry.size.height - undoContentClearance), alignment: .center)
                                .padding(.bottom, undoContentClearance)
                        }
                        .scrollBounceBehavior(.always)
                        .refreshable { await reload() }
                    }
                } else {
                    List {
                        selectionRows(title: "日時を過ぎた選考・締切", steps: selectionBuckets.past, limit: 4, showsAll: $showsAllPastSelections, preferPastMilestone: true)
                        taskRowsIfPresent(title: "期限を過ぎたToDo", tasks: taskBuckets.overdue, limit: 4, showsAll: $showsAllOverdueTasks)
                        selectionRows(title: "7日以内の選考・締切", steps: selectionBuckets.upcoming, limit: 8, showsAll: $showsAllSelections)
                        taskRowsIfPresent(title: "7日以内のToDo", tasks: taskBuckets.upcoming, limit: 8, showsAll: $showsAllUpcomingTasks)
                    }
                    .listStyle(.insetGrouped)
                    .contentMargins(.bottom, undoContentClearance, for: .scrollContent)
                    .animation(reduceMotion ? nil : .snappy, value: selectionBuckets.past)
                    .animation(reduceMotion ? nil : .snappy, value: upcomingSteps)
                    .animation(reduceMotion ? nil : .snappy, value: taskBuckets.overdue)
                    .animation(reduceMotion ? nil : .snappy, value: taskBuckets.upcoming)
                    .refreshable {
                        if let userID = session.userID { await store.reload(userID: userID, force: true) }
                    }
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: hasItems)
            .overlay(alignment: .bottom) { undoOverlay }
            .onAppear {
                visibilityGeneration = UUID()
                isHomeVisible = true
            }
            .onDisappear {
                isHomeVisible = false
                visibilityGeneration = UUID()
                clearUndo()
            }
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
            .sheet(item: $selectedStep) { step in
                SelectionStepDetailView(stepID: step.id, ownerUserID: step.userID, onDeleted: {
                    if selectedStep?.id == step.id { selectedStep = nil }
                })
            }
            .sheet(item: $editingTask) { task in
                TaskDetailView(taskID: task.id, ownerUserID: task.userID, onDeleted: {
                    if editingTask?.id == task.id { editingTask = nil }
                })
            }
            .recruitErrorAlert(store: store)
        }
        .task { await refreshReferenceDate() }
    }

    private var undoContentClearance: CGFloat { undoBarHeight + 8 }

    private var undoOverlay: some View {
        ZStack(alignment: .bottom) {
            // Permanent scroll clearance lets the last row move above the overlay.
            // The body never resizes when the toast appears; tab safe areas are retained.
            undoBarPlaceholder
                .hidden()
                .accessibilityHidden(true)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: HomeUndoBarHeightKey.self, value: geometry.size.height)
                    }
                }
                .allowsHitTesting(false)
            Group {
                if let step = completedSelectionForUndo {
                    selectionUndoBar(for: step)
                } else if let task = completedTaskForUndo {
                    undoBar(for: task)
                }
            }
            .transition(.opacity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: completedSelectionForUndo?.id)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: completedTaskForUndo?.id)
        }
        .onPreferenceChange(HomeUndoBarHeightKey.self) { undoBarHeight = $0 }
    }

    private var undoBarPlaceholder: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("完了しました").lineLimit(1)
                Text("ToDo").lineLimit(1)
                Text("企業").lineLimit(1)
            }
            .font(.subheadline)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("戻しています")
                    .fixedSize(horizontal: true, vertical: false)
            }
            Button("閉じる", systemImage: "xmark") {}.labelStyle(.iconOnly)
        }
        .padding(12)
        .padding(.horizontal)
        .padding(.bottom, 8)
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
                Text("7日以内の予定や、進行中・期限を過ぎた未完了の項目をここで確認できます。")
            }
        } actions: {
            if store.companies.isEmpty {
                Button("企業を追加") { isAddingCompany = true }.buttonStyle(.borderedProminent)
                Button("ToDoを追加") { isAddingTask = true }.buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func selectionRows(title: String, steps: [SelectionStep], limit: Int, showsAll: Binding<Bool>, preferPastMilestone: Bool = false) -> some View {
        if steps.isEmpty == false {
            Section(title) {
                ForEach(showsAll.wrappedValue ? steps : Array(steps.prefix(limit))) { step in
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
                        Button { selectedStep = step } label: {
                            SelectionStepRow(
                                step: step,
                                companyName: store.company(id: step.companyID)?.name ?? "企業",
                                showsMilestoneKind: true,
                                showsMemo: true,
                                showsTypeIcon: false,
                                referenceDate: referenceDate,
                                homeLineLimits: true,
                                preferPastMilestone: preferPastMilestone
                            )
                        }
                        .buttonStyle(.plain)
                        .contentShape(.rect)
                        .accessibilityHint("選考の詳細を表示")
                    }
                }
                if !showsAll.wrappedValue && steps.count > limit {
                    Button("残り\(steps.count - limit)件を表示") {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            showsAll.wrappedValue = true
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func taskRowsIfPresent(title: String, tasks: [RecruitTask], limit: Int, showsAll: Binding<Bool>) -> some View {
        if !tasks.isEmpty { taskRows(title: title, tasks: tasks, limit: limit, showsAll: showsAll) }
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
                        .accessibilityHint("ToDoの詳細を表示")
                    }
                }
                if !showsAll.wrappedValue && tasks.count > limit {
                    Button("残り\(tasks.count - limit)件を表示") {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            showsAll.wrappedValue = true
                        }
                    }
                }
            }
    }

    private func undoBar(for task: RecruitTask) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("完了しました").lineLimit(1)
                Text(task.title).foregroundStyle(.secondary).lineLimit(1)
                if let companyName = task.companyID.flatMap({ store.company(id: $0)?.name }) {
                    Text(companyName).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .font(.subheadline)
            Spacer(minLength: 0)
            Button {
                cancelUndoTimer()
                Task { await undoTaskCompletion(task) }
            } label: {
                HStack(spacing: 6) {
                    if isUndoingTask { ProgressView().controlSize(.small) }
                    Text(isUndoingTask ? "戻しています" : "元に戻す")
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
                .accessibilityLabel(isUndoingTask ? "戻しています" : "元に戻す")
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
            store.errorMessage = "ログイン状態を確認し、一覧を更新してから、もう一度お試しください。"
            return
        }
        let generation = visibilityGeneration
        let success = await store.setTaskCompleted(task, completed: true)
        guard success, isHomeVisible, generation == visibilityGeneration, session.userID == userID, store.loadedUserID == userID,
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
                Text("完了しました").lineLimit(1)
                Text(step.displayTitle).foregroundStyle(.secondary).lineLimit(1)
                Text(store.company(id: step.companyID)?.name ?? "企業")
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            .font(.subheadline)
            Spacer(minLength: 0)
            Button {
                cancelUndoTimer()
                Task { await undoSelectionCompletion(step) }
            } label: {
                HStack(spacing: 6) {
                    if isUndoingSelection { ProgressView().controlSize(.small) }
                    Text(isUndoingSelection ? "戻しています" : "元に戻す")
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
                .accessibilityLabel(isUndoingSelection ? "戻しています" : "元に戻す")
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
            store.errorMessage = "ログイン状態を確認し、一覧を更新してから、もう一度お試しください。"
            return
        }
        let generation = visibilityGeneration
        guard let updated = await store.setSelectionStepStatus(step, status: .completed),
              isHomeVisible, generation == visibilityGeneration, session.userID == userID, store.loadedUserID == userID,
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
        selectionBuckets.past.isEmpty == false
            || upcomingSteps.isEmpty == false
            || taskBuckets.overdue.isEmpty == false
            || taskBuckets.upcoming.isEmpty == false
    }

    private var upcomingSteps: [SelectionStep] { selectionBuckets.upcoming }

    private var selectionBuckets: HomeSelectionBuckets {
        HomeSelectionBuckets.make(steps: store.selectionSteps, relativeTo: referenceDate)
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

private struct HomeUndoBarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
