import SwiftUI

struct TasksView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    @State private var isAddingTask = false
    @State private var editingTask: RecruitTask?
    @State private var deletingTask: RecruitTask?
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.tasks.isEmpty {
                    ProgressView("ToDoを読み込み中")
                } else if filteredTasks.isEmpty {
                    ContentUnavailableView {
                        Label(searchText.isEmpty ? "ToDoはありません" : "見つかりません", systemImage: "checklist")
                    } description: {
                        Text(searchText.isEmpty ? "次にすることを追加しましょう。" : "検索条件を変更してください。")
                    } actions: {
                        if searchText.isEmpty {
                            Button("ToDoを追加") { isAddingTask = true }.buttonStyle(.borderedProminent)
                        } else {
                            Button("検索をクリア") { searchText = "" }.buttonStyle(.bordered)
                        }
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
            .sheet(item: $editingTask) { TaskEditorView(task: $0) }
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
            .onAppear { openPendingTaskIfNeeded() }
            .onChange(of: router.pendingTaskID) { _, _ in openPendingTaskIfNeeded() }
            .onChange(of: store.tasks) { _, _ in openPendingTaskIfNeeded() }
            .recruitErrorAlert(store: store)
        }
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
                            Task { _ = await store.setTaskCompleted(task, completed: !task.isCompleted) }
                        }
                        Button { editingTask = task } label: {
                            TaskRow(
                                task: task,
                                companyName: task.companyID.flatMap { store.company(id: $0)?.name }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button(task.isCompleted ? "未完了" : "完了") {
                            Task { _ = await store.setTaskCompleted(task, completed: !task.isCompleted) }
                        }
                        .disabled(store.isSaving)
                        .tint(task.isCompleted ? .orange : .green)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("削除", role: .destructive) { deletingTask = task }
                            .tint(.red)
                            .disabled(store.isSaving)
                    }
                }
            }
        }
    }

    private var filteredTasks: [RecruitTask] {
        guard searchText.isEmpty == false else { return store.tasks }
        return store.tasks.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || ($0.memo?.localizedCaseInsensitiveContains(searchText) ?? false)
                || ($0.companyID.flatMap { store.company(id: $0)?.name.localizedCaseInsensitiveContains(searchText) } ?? false)
        }
    }

    private var todayTasks: [RecruitTask] {
        filteredTasks.filter { task in
            task.isCompleted == false && task.dueAt.map(Calendar.current.isDateInToday) == true
        }
    }

    private var upcomingTasks: [RecruitTask] {
        filteredTasks.filter { task in
            guard task.isCompleted == false, let dueAt = task.dueAt else { return false }
            let startOfTomorrow = Calendar.current.date(
                byAdding: .day,
                value: 1,
                to: Calendar.current.startOfDay(for: Date())
            ) ?? Date()
            return dueAt >= startOfTomorrow
        }.sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }

    private var overdueTasks: [RecruitTask] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return filteredTasks.filter { task in
            task.isCompleted == false && task.dueAt.map { $0 < startOfToday } == true
        }.sorted { ($0.dueAt ?? .distantPast) < ($1.dueAt ?? .distantPast) }
    }

    private var noDueTasks: [RecruitTask] {
        filteredTasks.filter { $0.isCompleted == false && $0.dueAt == nil }
    }

    private var completedTasks: [RecruitTask] {
        filteredTasks.filter(\.isCompleted).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    private func openPendingTaskIfNeeded() {
        guard let pendingID = router.pendingTaskID,
              let task = store.tasks.first(where: { $0.id == pendingID })
        else { return }
        editingTask = task
        router.pendingTaskID = nil
    }
}
