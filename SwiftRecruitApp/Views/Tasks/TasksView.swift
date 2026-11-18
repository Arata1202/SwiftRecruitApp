import SwiftUI

struct TasksView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    @State private var isAddingTask = false
    @State private var selectedTask: RecruitTask?
    @State private var completionTaskID: UUID?
    @State private var deletingTask: RecruitTask?
    @State private var searchText = ""
    @State private var referenceDate = Date()

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.loadedUserID == nil && store.tasks.isEmpty {
                    ProgressView("ToDoを読み込み中")
                } else if let message = store.loadErrorMessage {
                    DataLoadFailureView(message: message) {
                        Task { await reload() }
                    }
                } else if filteredTasks.isEmpty {
                    GeometryReader { geometry in
                        ScrollView {
                            ContentUnavailableView {
                                Label(normalizedSearchText.isEmpty ? "ToDoはありません" : "見つかりません", systemImage: "checklist")
                            } description: {
                                Text(normalizedSearchText.isEmpty ? "次にすることを追加しましょう。" : "検索条件を変更してください。")
                            } actions: {
                                if normalizedSearchText.isEmpty {
                                    Button("ToDoを追加") { isAddingTask = true }.buttonStyle(.borderedProminent)
                                } else {
                                    Button("検索をクリア") { searchText = "" }.buttonStyle(.bordered)
                                }
                            }
                            .frame(maxWidth: .infinity)
                                .frame(minHeight: geometry.size.height, alignment: .center)
                        }
                        .scrollBounceBehavior(.always)
                    }
                } else {
                    List {
                        taskSection(title: "期限切れ", tasks: overdueTasks)
                        taskSection(title: "今日", tasks: todayTasks)
                        taskSection(title: "今後", tasks: upcomingTasks)
                        taskSection(title: "期限なし", tasks: noDueTasks)
                        taskSection(title: "完了済み", tasks: completedTasks)
                    }
                    .listStyle(.insetGrouped)
                    // Only the locally requested completion transition animates, not searches or reloads.
                    .animation(
                        reduceMotion || completionTaskID == nil ? nil : .easeInOut(duration: 0.2),
                        value: requestedCompletionState
                    )
                }
            }
            .navigationTitle("ToDo")
            .searchableWhen(
                store.tasks.isEmpty == false,
                text: $searchText,
                prompt: "ToDoを検索"
            )
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("ToDoを追加", systemImage: "plus") { isAddingTask = true }
                }
            }
            .refreshable {
                if let userID = session.userID { await store.reload(userID: userID, force: true) }
            }
            .sheet(isPresented: $isAddingTask) { TaskEditorView() }
            .sheet(item: $selectedTask) { task in
                TaskDetailView(taskID: task.id, ownerUserID: task.userID, onDeleted: {
                    if selectedTask?.id == task.id { selectedTask = nil }
                })
            }
            .alert(
                "ToDoを削除しますか？",
                isPresented: Binding(
                    get: { deletingTask != nil },
                    set: { if $0 == false { deletingTask = nil } }
                )
            ) {
                Button("削除", role: .destructive) {
                    guard let deletingTask else { return }
                    Task { _ = await store.deleteTask(deletingTask) }
                }
                Button("キャンセル", role: .cancel) { deletingTask = nil }
            } message: {
                Text("この操作は取り消せません。")
            }
            .recruitErrorAlert(store: store)
        }
        .task { await refreshReferenceDate() }
    }

    @ViewBuilder
    private func taskSection(title: String, tasks: [RecruitTask]) -> some View {
        if tasks.isEmpty == false {
            Section(title) {
                ForEach(tasks) { task in
                    HStack(alignment: .top, spacing: 0) {
                        TaskCompletionButton(
                            task: task,
                            isDisabled: store.isSaving,
                            isWorking: store.savingTaskID == task.id
                        ) {
                            Task { await toggleCompletion(task) }
                        }
                        Button { selectedTask = task } label: {
                            TaskRow(
                                task: task,
                                companyName: task.companyID.flatMap { store.company(id: $0)?.name },
                                referenceDate: referenceDate
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("削除") { deletingTask = task }
                            .tint(.red)
                            .disabled(store.isSaving)
                    }
                }
            }
        }
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var requestedCompletionState: Bool? {
        guard let completionTaskID else { return nil }
        return store.tasks.first { $0.id == completionTaskID }?.isCompleted
    }

    @MainActor
    private func toggleCompletion(_ task: RecruitTask) async {
        guard store.isSaving == false, completionTaskID == nil else { return }
        completionTaskID = task.id
        defer { completionTaskID = nil }
        _ = await store.setTaskCompleted(task, completed: !task.isCompleted)
    }

    private var filteredTasks: [RecruitTask] {
        guard normalizedSearchText.isEmpty == false else { return store.tasks }
        return store.tasks.filter {
            $0.title.localizedCaseInsensitiveContains(normalizedSearchText)
                || ($0.companyID.flatMap { store.company(id: $0)?.name.localizedCaseInsensitiveContains(normalizedSearchText) } ?? false)
        }
    }

    private var todayTasks: [RecruitTask] {
        filteredTasks.filter { task in
            task.isCompleted == false
                && task.isOverdue(relativeTo: referenceDate) == false
                && task.dueDate().map {
                    Calendar.current.isDate($0, inSameDayAs: referenceDate)
                } == true
        }
    }

    private var upcomingTasks: [RecruitTask] {
        filteredTasks.filter { task in
            guard task.isCompleted == false, let dueAt = task.dueDate() else { return false }
            let startOfTomorrow = Calendar.current.date(
                byAdding: .day,
                value: 1,
                to: Calendar.current.startOfDay(for: referenceDate)
            ) ?? referenceDate
            return dueAt >= startOfTomorrow
        }.sorted { ($0.dueDate() ?? .distantFuture) < ($1.dueDate() ?? .distantFuture) }
    }

    private var overdueTasks: [RecruitTask] {
        filteredTasks
            .filter { $0.isOverdue(relativeTo: referenceDate) }
            .sorted { ($0.dueDate() ?? .distantPast) < ($1.dueDate() ?? .distantPast) }
    }

    private var noDueTasks: [RecruitTask] {
        filteredTasks.filter { $0.isCompleted == false && $0.dueDate() == nil }
    }

    private var completedTasks: [RecruitTask] {
        filteredTasks.filter(\.isCompleted).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
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
