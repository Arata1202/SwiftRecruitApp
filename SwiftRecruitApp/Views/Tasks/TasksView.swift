import SwiftUI

struct TasksView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    @State private var isAddingTask = false
    @State private var selectedTask: RecruitTask?
    @State private var completionTaskID: UUID?
    @State private var searchText = ""
    @State private var referenceDate = Date()

    var body: some View {
        let matches = filteredTasks
        NavigationStack {
            Group {
                if store.isLoading && store.loadedUserID == nil && store.tasks.isEmpty {
                    ProgressView("ToDoを読み込み中")
                } else if let message = store.loadErrorMessage {
                    DataLoadFailureView(message: message) {
                        Task { await reload() }
                    }
                } else if matches.isEmpty {
                    GeometryReader { geometry in
                        ScrollView {
                            ContentUnavailableView {
                                Label(store.tasks.isEmpty ? "ToDoはありません" : "該当するToDoがありません", systemImage: "checklist")
                            } description: {
                                Text(store.tasks.isEmpty ? "やることを追加しましょう。" : "検索条件を変更してください。")
                                    .foregroundStyle(RecruitTextColor.supporting)
                            } actions: {
                                if store.tasks.isEmpty {
                                    Button("ToDoを追加") { isAddingTask = true }.prominentAction()
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
                        taskSection(title: "期限切れ", tasks: overdueTasks(matches))
                        taskSection(title: "今日", tasks: todayTasks(matches))
                        taskSection(title: "今後", tasks: upcomingTasks(matches))
                        taskSection(title: "期限なし", tasks: noDueTasks(matches))
                        taskSection(title: "完了済み", tasks: completedTasks(matches))
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
            .recruitErrorAlert(store: store)
        }
        .task { await refreshReferenceDate() }
    }

    @ViewBuilder
    private func taskSection(title: String, tasks: [RecruitTask]) -> some View {
        if tasks.isEmpty == false {
            Section {
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
                }
            } header: {
                Text(title).foregroundStyle(Color.primary)
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
        let query = normalizedSearchText
        guard !query.isEmpty else { return store.tasks }
        let names = Dictionary(uniqueKeysWithValues: store.companies.map { ($0.id, $0.name) })
        return store.tasks.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || ($0.companyID.flatMap { names[$0]?.localizedCaseInsensitiveContains(query) } ?? false)
        }
    }

    private func todayTasks(_ filteredTasks: [RecruitTask]) -> [RecruitTask] {
        filteredTasks.filter { task in
            task.isCompleted == false
                && task.isOverdue(relativeTo: referenceDate) == false
                && task.dueDate().map {
                    Calendar.current.isDate($0, inSameDayAs: referenceDate)
                } == true
        }
    }

    private func upcomingTasks(_ filteredTasks: [RecruitTask]) -> [RecruitTask] {
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

    private func overdueTasks(_ filteredTasks: [RecruitTask]) -> [RecruitTask] {
        filteredTasks
            .filter { $0.isOverdue(relativeTo: referenceDate) }
            .sorted { ($0.dueDate() ?? .distantPast) < ($1.dueDate() ?? .distantPast) }
    }

    private func noDueTasks(_ filteredTasks: [RecruitTask]) -> [RecruitTask] {
        filteredTasks.filter { $0.isCompleted == false && $0.dueDate() == nil }
    }

    private func completedTasks(_ filteredTasks: [RecruitTask]) -> [RecruitTask] {
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
