import SwiftUI

struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    @State private var quickAddPresented = false
    @State private var isAddingCompany = false
    @State private var isAddingSelection = false
    @State private var isAddingTask = false

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.companies.isEmpty && store.tasks.isEmpty {
                    ProgressView("予定を読み込み中")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            welcomeHeader
                            if hasItems == false {
                                emptyState
                            } else {
                                selectionSection
                                taskSection
                            }
                        }
                        .padding()
                    }
                    .refreshable {
                        if let userID = session.userID { await store.reload(userID: userID, force: true) }
                    }
                }
            }
            .navigationTitle("ホーム")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { SettingsView() } label: {
                        Label("設定", systemImage: "person.crop.circle")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("追加", systemImage: "plus") { quickAddPresented = true }
                }
            }
            .confirmationDialog("追加するもの", isPresented: $quickAddPresented) {
                Button("企業") { isAddingCompany = true }
                Button("選考") { isAddingSelection = true }
                    .disabled(store.companies.filter { $0.status == .active }.isEmpty)
                Button("ToDo") { isAddingTask = true }
            } message: {
                if store.companies.filter({ $0.status == .active }).isEmpty {
                    Text("選考を追加するには、先に企業を登録してください。")
                }
            }
            .sheet(isPresented: $isAddingCompany) { CompanyEditorView() }
            .sheet(isPresented: $isAddingSelection) { SelectionStepEditorView() }
            .sheet(isPresented: $isAddingTask) { TaskEditorView() }
            .recruitErrorAlert(store: store)
        }
    }

    private var welcomeHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(greeting)
                .font(.title2.bold())
            Text("次の予定と締切を確認しましょう。")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("就活管理を始めましょう", systemImage: "briefcase")
        } description: {
            Text("企業を登録すると、選考予定とToDoをまとめて確認できます。")
        } actions: {
            Button("企業を追加") { isAddingCompany = true }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }

    @ViewBuilder
    private var selectionSection: some View {
        if upcomingSteps.isEmpty == false {
            HomeSection(title: "直近の選考", systemImage: "calendar") {
                ForEach(upcomingSteps) { step in
                    Button { router.openCompany(id: step.companyID) } label: {
                        HomeSelectionRow(
                            step: step,
                            companyName: store.company(id: step.companyID)?.name ?? "企業"
                        )
                    }
                    .buttonStyle(.plain)
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
                    Button { router.openTask(id: task.id) } label: {
                        TaskRowForHome(
                            task: task,
                            companyName: task.companyID.flatMap { store.company(id: $0)?.name }
                        )
                    }
                    .buttonStyle(.plain)
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
                let date = step.startsAt ?? step.deadlineAt
                return date.map { $0 >= now && $0 <= end } ?? false
            }
            .sorted { ($0.startsAt ?? $0.deadlineAt ?? .distantFuture) < ($1.startsAt ?? $1.deadlineAt ?? .distantFuture) }
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

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: "おはようございます"
        case 11..<17: "こんにちは"
        default: "お疲れさまです"
        }
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
                .background(.background, in: .rect(cornerRadius: 14))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
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
                if let date = step.startsAt ?? step.deadlineAt {
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
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title).font(.headline)
                if let companyName { Text(companyName).font(.subheadline).foregroundStyle(.secondary) }
                if let dueAt = task.dueAt {
                    Text(task.dueHasTime ? DateFormatting.dateTime.string(from: dueAt) : DateFormatting.day.string(from: dueAt))
                        .font(.caption)
                        .foregroundStyle(dueAt < Date() ? .red : .secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
    }
}
