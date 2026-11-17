import SwiftUI

struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    @State private var isAddingCompany = false
    @State private var isAddingTask = false
    @State private var showsAllSelections = false
    @State private var showsAllPastSelections = false
    @State private var showsAllOverdueTasks = false
    @State private var showsAllUpcomingTasks = false
    @State private var editingStep: SelectionStep?
    @State private var editingTask: RecruitTask?
    @State private var referenceDate = Date()
    @State private var completedTaskForUndo: RecruitTask?
    @State private var isUndoingTask = false
    @State private var completedSelectionForUndo: SelectionStep?
    @State private var selectionUndoNotificationEnabled = false
    @State private var isUndoingSelection = false

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
                        selectionRows(title: "未完了の選考・締切", steps: selectionBuckets.past, limit: 4, showsAll: $showsAllPastSelections)
                        taskRowsIfPresent(title: "未完了のToDo", tasks: taskBuckets.overdue, limit: 4, showsAll: $showsAllOverdueTasks)
                        selectionRows(title: "7日以内の選考・締切", steps: selectionBuckets.upcoming, limit: 8, showsAll: $showsAllSelections)
                        taskRowsIfPresent(title: "7日以内のToDo", tasks: taskBuckets.upcoming, limit: 8, showsAll: $showsAllUpcomingTasks)
                    }
                    .listStyle(.insetGrouped)
                    .animation(.snappy, value: selectionBuckets.past)
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
            .onChange(of: session.userID) { _, _ in
                completedTaskForUndo = nil
                completedSelectionForUndo = nil
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
                Text("日付を過ぎた未完了と、7日以内の選考・締切やToDoを表示します。")
            }
        } actions: {
            if store.companies.isEmpty {
                Button("企業を追加") { isAddingCompany = true }.buttonStyle(.borderedProminent)
                Button("ToDoを追加") { isAddingTask = true }.buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func selectionRows(title: String, steps: [SelectionStep], limit: Int, showsAll: Binding<Bool>) -> some View {
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
                        Button { editingStep = step } label: {
                            SelectionStepRow(
                                step: step,
                                companyName: store.company(id: step.companyID)?.name ?? "企業",
                                showsMilestoneKind: true,
                                showsMemo: true,
                                showsTypeIcon: false,
                                referenceDate: referenceDate,
                                homeLineLimits: true,
                                preferPastMilestone: title == "未完了の選考・締切"
                            )
                        }
                        .buttonStyle(.plain)
                        .contentShape(.rect)
                        .accessibilityHint("選考を編集")
                    }
                }
                if !showsAll.wrappedValue && steps.count > limit {
                    Button("残り\(steps.count - limit)件を表示") { showsAll.wrappedValue = true }
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
            Text("「\(task.title)」を完了しました")
                .font(.subheadline)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button("元に戻す") { Task { await undoTaskCompletion(task) } }
                .disabled(store.isSaving || isUndoingTask)
            Button("閉じる", systemImage: "xmark") { completedTaskForUndo = nil }
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
        guard let userID = session.userID, store.loadedUserID == userID else { return }
        let success = await store.setTaskCompleted(task, completed: true)
        guard success, session.userID == userID, store.loadedUserID == userID,
              let updated = store.tasks.first(where: { $0.id == task.id && $0.isCompleted })
        else { return }
        completedSelectionForUndo = nil
        completedTaskForUndo = updated
    }

    @MainActor
    private func undoTaskCompletion(_ task: RecruitTask) async {
        guard !isUndoingTask, !store.isSaving,
              let userID = session.userID, store.loadedUserID == userID,
              completedTaskForUndo?.id == task.id,
              let current = store.tasks.first(where: {
                  $0.id == task.id && $0.isCompleted && $0.version == task.version
              }) else {
            return
        }
        isUndoingTask = true
        defer { isUndoingTask = false }
        let success = await store.setTaskCompleted(current, completed: false)
        if success, session.userID == userID, completedTaskForUndo?.id == task.id {
            completedTaskForUndo = nil
        }
    }

    private func selectionUndoBar(for step: SelectionStep) -> some View {
        HStack(spacing: 12) {
            Text("「\(step.displayTitle)」を完了しました")
                .font(.subheadline).lineLimit(2)
            Spacer(minLength: 0)
            Button("元に戻す") { Task { await undoSelectionCompletion(step) } }
                .disabled(store.isSaving || isUndoingSelection)
            Button("閉じる", systemImage: "xmark") { completedSelectionForUndo = nil }
                .labelStyle(.iconOnly).disabled(isUndoingSelection)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal).padding(.bottom, 8)
    }

    @MainActor
    private func completeSelection(_ step: SelectionStep) async {
        guard let userID = session.userID, store.loadedUserID == userID else { return }
        guard let updated = await store.setSelectionStepStatus(step, status: .completed),
              session.userID == userID, store.loadedUserID == userID,
              store.selectionSteps.contains(where: { $0.id == updated.id && $0.version == updated.version && $0.status == .completed }) else { return }
        completedTaskForUndo = nil
        selectionUndoNotificationEnabled = step.notificationEnabled
        completedSelectionForUndo = updated
    }

    @MainActor
    private func undoSelectionCompletion(_ step: SelectionStep) async {
        guard !isUndoingSelection, !store.isSaving,
              let userID = session.userID, store.loadedUserID == userID,
              completedSelectionForUndo?.id == step.id,
              let current = store.selectionSteps.first(where: {
                  $0.id == step.id && $0.status == .completed && $0.version == step.version
              }) else { return }
        isUndoingSelection = true
        defer { isUndoingSelection = false }
        let updated = await store.setSelectionStepStatus(current, status: .scheduled, notificationEnabled: selectionUndoNotificationEnabled)
        if updated != nil, session.userID == userID, completedSelectionForUndo?.id == step.id {
            completedSelectionForUndo = nil
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
