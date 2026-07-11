import SwiftUI

struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    @State private var isAddingCompany = false
    @State private var editingStep: SelectionStep?
    @State private var editingTask: RecruitTask?

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.companies.isEmpty && store.tasks.isEmpty {
                    ProgressView("予定を読み込み中")
                } else if hasItems == false {
                    emptyState
                } else {
                    List {
                        selectionSection
                        taskSection
                    }
                    .listStyle(.insetGrouped)
                    .animation(.snappy, value: urgentTasks)
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
            .sheet(item: $editingStep) { SelectionStepEditorView(step: $0) }
            .sheet(item: $editingTask) { TaskEditorView(task: $0) }
            .recruitErrorAlert(store: store)
        }
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
                Text("企業を登録すると、選考予定とToDoをまとめて確認できます。")
            } else {
                Text("7日以内の選考や期限の近いToDoは、ここに表示されます。")
            }
        } actions: {
            if store.loadedUserID == nil {
                Button("再読み込み") { Task { await reload() } }
                    .buttonStyle(.borderedProminent)
            } else if store.companies.isEmpty {
                Button("企業を追加") { isAddingCompany = true }.buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private var selectionSection: some View {
        if upcomingSteps.isEmpty == false {
            Section("直近の選考") {
                ForEach(upcomingSteps) { step in
                    Button { editingStep = step } label: {
                        SelectionStepRow(
                            step: step,
                            companyName: store.company(id: step.companyID)?.name ?? "企業"
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(.rect)
                }
            }
        }
    }

    @ViewBuilder
    private var taskSection: some View {
        if urgentTasks.isEmpty == false {
            Section("期限が近いToDo") {
                ForEach(urgentTasks) { task in
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
                        .contentShape(.rect)
                    }
                }
            }
        }
    }

    private var hasItems: Bool { upcomingSteps.isEmpty == false || urgentTasks.isEmpty == false }

    private var upcomingSteps: [SelectionStep] {
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        return store.selectionSteps
            .filter { step in
                guard step.status == .scheduled else { return false }
                guard let milestone = step.nextMilestone(relativeTo: now) else { return false }
                let isCurrentOrFuture = milestone.hasTime
                    ? milestone.date >= now
                    : Calendar.current.startOfDay(for: milestone.date)
                        >= Calendar.current.startOfDay(for: now)
                return isCurrentOrFuture && milestone.date <= end
            }
            .sorted {
                ($0.nextDate(relativeTo: now) ?? .distantFuture)
                    < ($1.nextDate(relativeTo: now) ?? .distantFuture)
            }
            .prefix(8)
            .map { $0 }
    }

    private var urgentTasks: [RecruitTask] {
        let end = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        return store.tasks
            .filter { $0.isCompleted == false && ($0.dueAt.map { $0 <= end } ?? false) }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
            .prefix(8)
            .map { $0 }
    }

    private func reload() async {
        if let userID = session.userID { await store.reload(userID: userID, force: true) }
    }

}
