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
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            selectionSection
                            taskSection
                        }
                        .padding()
                        .animation(.snappy, value: urgentTasks)
                    }
                    .background(Color(uiColor: .systemGroupedBackground))
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
            if store.companies.isEmpty {
                Button("企業を追加") { isAddingCompany = true }.buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private var selectionSection: some View {
        if upcomingSteps.isEmpty == false {
            HomeSection(title: "直近の選考", systemImage: "calendar") {
                ForEach(upcomingSteps) { step in
                    Button { editingStep = step } label: {
                        HomeSelectionRow(
                            step: step,
                            companyName: store.company(id: step.companyID)?.name ?? "企業"
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(.rect)
                    if step.id != upcomingSteps.last?.id { Divider() }
                }
            }
        }
    }

    @ViewBuilder
    private var taskSection: some View {
        if urgentTasks.isEmpty == false {
            HomeSection(title: "期限が近いToDo", systemImage: "checklist") {
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
                            TaskRowForHome(
                                task: task,
                                companyName: task.companyID.flatMap { store.company(id: $0)?.name }
                            )
                        }
                        .buttonStyle(.plain)
                        .contentShape(.rect)
                    }
                    if task.id != urgentTasks.last?.id { Divider() }
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
                let date = step.nextDate(relativeTo: now)
                return date.map { $0 >= now && $0 <= end } ?? false
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

}

private struct HomeSection<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage).font(.headline)
            VStack(spacing: 12) { content }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        }
    }
}

private struct HomeSelectionRow: View {
    let step: SelectionStep
    let companyName: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: step.type.systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(step.displayTitle).font(.headline)
                Text(companyName).font(.subheadline).foregroundStyle(.secondary)
                if let milestone = step.nextMilestone() {
                    Label(
                        "\(milestone.kind.title) \(DateFormatting.dateTime.string(from: milestone.date))",
                        systemImage: milestone.kind.systemImage
                    )
                        .font(.caption)
                        .foregroundStyle(
                            milestone.kind == .deadline ? Color.orange : Color.secondary
                        )
                } else if let date = step.earliestDate {
                    Text(DateFormatting.dateTime.string(from: date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
    }
}

private struct TaskRowForHome: View {
    let task: RecruitTask
    let companyName: String?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title).font(.headline)
                if let companyName { Text(companyName).font(.subheadline).foregroundStyle(.secondary) }
                if let dueAt = task.dueAt {
                    Text(task.dueHasTime ? DateFormatting.dateTime.string(from: dueAt) : DateFormatting.day.string(from: dueAt))
                        .font(.caption)
                        .foregroundStyle(dueAt < Date() ? Color.red : Color.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
