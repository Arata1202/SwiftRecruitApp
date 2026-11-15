import SwiftUI

struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    @State private var isAddingCompany = false
    @State private var isAddingTask = false
    @State private var showsAllSelections = false
    @State private var showsAllOverdueTasks = false
    @State private var showsAllUpcomingTasks = false
    @State private var editingStep: SelectionStep?
    @State private var editingTask: RecruitTask?
    @State private var referenceDate = Date()

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
                    .animation(.snappy, value: taskBuckets.overdue)
                    .animation(.snappy, value: taskBuckets.upcoming)
                    .refreshable {
                        if let userID = session.userID { await store.reload(userID: userID, force: true) }
                    }
                }
            }
            .animation(.snappy, value: hasItems)
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

    private var emptyState: some View {
        ContentUnavailableView {
            if store.companies.isEmpty {
                Label("就活管理を始めましょう", systemImage: "briefcase")
            } else {
                Label("直近の予定はありません", systemImage: "calendar.badge.checkmark")
            }
        } description: {
            if store.companies.isEmpty {
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
                    Button { editingStep = step } label: {
                        SelectionStepRow(
                            step: step,
                            companyName: store.company(id: step.companyID)?.name ?? "企業",
                            showsMilestoneKind: true,
                            referenceDate: referenceDate
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(.rect)
                    .accessibilityHint("選考を編集")
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
                            Task { _ = await store.setTaskCompleted(task, completed: !task.isCompleted) }
                        }
                        Button { editingTask = task } label: {
                            TaskRow(
                                task: task,
                                companyName: task.companyID.flatMap { store.company(id: $0)?.name },
                                showsDueLabel: true
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

    private var hasItems: Bool {
        upcomingSteps.isEmpty == false
            || taskBuckets.overdue.isEmpty == false
            || taskBuckets.upcoming.isEmpty == false
    }

    private var upcomingSteps: [SelectionStep] {
        let now = referenceDate
        let end = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        return store.selectionSteps
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
            .sorted {
                ($0.nextDate(relativeTo: now) ?? .distantFuture)
                    < ($1.nextDate(relativeTo: now) ?? .distantFuture)
            }
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
