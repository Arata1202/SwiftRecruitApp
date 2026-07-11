import SwiftUI

struct CompanyDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(RecruitStore.self) private var store

    let companyID: UUID
    @State private var isEditingCompany = false
    @State private var isAddingSelection = false
    @State private var isAddingTask = false
    @State private var editingStep: SelectionStep?
    @State private var editingTask: RecruitTask?
    @State private var deletingStep: SelectionStep?
    @State private var deletingTask: RecruitTask?
    @State private var confirmsCompanyDeletion = false

    var body: some View {
        Group {
            if let company = store.company(id: companyID) {
                List {
                    companySection(company)
                    selectionSection
                    taskSection
                    deleteSection(company)
                }
                .navigationTitle(company.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("企業を編集", systemImage: "pencil") { isEditingCompany = true }
                    }
                }
                .sheet(isPresented: $isEditingCompany) { CompanyEditorView(company: company) }
                .sheet(isPresented: $isAddingSelection) { SelectionStepEditorView(companyID: companyID) }
                .sheet(isPresented: $isAddingTask) { TaskEditorView(companyID: companyID) }
                .sheet(item: $editingStep) { SelectionStepEditorView(step: $0) }
                .sheet(item: $editingTask) { TaskEditorView(task: $0) }
                .alert(
                    "企業を削除しますか？",
                    isPresented: $confirmsCompanyDeletion
                ) {
                    Button("企業と関連データを削除", role: .destructive) {
                        Task { if await store.deleteCompany(company) { dismiss() } }
                    }
                    Button("キャンセル", role: .cancel) {}
                } message: {
                    Text("選考と関連ToDoも削除されます。この操作は取り消せません。")
                }
            } else {
                ContentUnavailableView("企業が見つかりません", systemImage: "building.2.crop.circle")
            }
        }
        .alert(
            "選考を削除しますか？",
            isPresented: Binding(
                get: { deletingStep != nil },
                set: { if $0 == false { deletingStep = nil } }
            )
        ) {
            Button("削除", role: .destructive) {
                guard let deletingStep else { return }
                Task { _ = await store.deleteSelectionStep(deletingStep) }
            }
            Button("キャンセル", role: .cancel) { deletingStep = nil }
        } message: {
            Text("この操作は取り消せません。")
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
        .onAppear { openPendingSelectionIfNeeded() }
        .onChange(of: router.pendingSelectionID) { _, _ in openPendingSelectionIfNeeded() }
        .onChange(of: store.selectionSteps) { _, _ in openPendingSelectionIfNeeded() }
        .recruitErrorAlert(store: store)
    }

    private func companySection(_ company: Company) -> some View {
        Section {
            NavigationLink {
                CompanyStatusSelectionView(companyID: company.id)
            } label: {
                LabeledContent("ステータス") {
                    CompanyStatusBadge(status: company.status)
                }
                .fullWidthTappableArea()
            }
            if let urlValue = company.url, let url = URL(string: urlValue) {
                Link(destination: url) {
                    LabeledContent("採用ページ") { Image(systemName: "arrow.up.right.square") }
                        .fullWidthTappableArea()
                }
            }
            if let memo = company.memo, memo.isEmpty == false {
                Text(memo)
                    .textSelection(.enabled)
            }
        } header: {
            Text("企業情報")
        }
    }

    private var selectionSection: some View {
        Section {
            let steps = store.steps(for: companyID)
            if steps.isEmpty {
                Button("最初の選考を追加", systemImage: "calendar.badge.plus") { isAddingSelection = true }
            } else {
                ForEach(steps) { step in
                    Button { editingStep = step } label: {
                        SelectionStepRow(step: step)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("削除", role: .destructive) { deletingStep = step }
                            .tint(.red)
                    }
                }
            }
        } header: {
            HStack {
                Text("選考タイムライン")
                Spacer()
                Button { isAddingSelection = true } label: { Image(systemName: "plus.circle") }
                    .accessibilityLabel("選考を追加")
            }
        }
    }

    private var taskSection: some View {
        Section {
            let relatedTasks = store.tasks(for: companyID)
            if relatedTasks.isEmpty {
                Button("ToDoを追加", systemImage: "plus") { isAddingTask = true }
            } else {
                ForEach(relatedTasks) { task in
                    HStack(spacing: 0) {
                        TaskCompletionButton(
                            task: task,
                            isDisabled: store.isSaving,
                            isWorking: store.savingTaskID == task.id
                        ) {
                            Task { _ = await store.setTaskCompleted(task, completed: !task.isCompleted) }
                        }
                        Button { editingTask = task } label: {
                            VStack(alignment: .leading) {
                                Text(task.title)
                                    .strikethrough(task.isCompleted)
                                    .foregroundStyle(task.isCompleted ? Color.secondary : Color.primary)
                                if let dueAt = task.dueAt {
                                    Text(task.dueHasTime ? DateFormatting.dateTime.string(from: dueAt) : DateFormatting.day.string(from: dueAt))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .fullWidthTappableArea()
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
        } header: {
            HStack {
                Text("関連ToDo")
                Spacer()
                Button { isAddingTask = true } label: { Image(systemName: "plus.circle") }
                    .accessibilityLabel("ToDoを追加")
            }
        }
    }

    private func deleteSection(_ company: Company) -> some View {
        Section {
            Button("企業を削除", role: .destructive) { confirmsCompanyDeletion = true }
        }
    }

    private func openPendingSelectionIfNeeded() {
        guard let pendingID = router.pendingSelectionID,
              let step = store.selectionSteps.first(where: {
                  $0.id == pendingID && $0.companyID == companyID
              })
        else { return }

        editingStep = step
        router.pendingSelectionID = nil
    }
}

private struct SelectionStepRow: View {
    let step: SelectionStep

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: step.type.systemImage)
                .foregroundStyle(statusColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(step.displayTitle).font(.headline)
                    Spacer()
                    Text(step.status.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let startsAt = step.startsAt {
                    Label(DateFormatting.dateTime.string(from: startsAt), systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let deadlineAt = step.deadlineAt {
                    Label("締切 \(DateFormatting.dateTime.string(from: deadlineAt))", systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
                if let memo = step.memo, memo.isEmpty == false {
                    Text(memo).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 3)
        .fullWidthTappableArea()
    }

    private var statusColor: Color {
        switch step.status {
        case .scheduled: .accentColor
        case .completed: .green
        case .cancelled: .secondary
        }
    }
}

private struct CompanyStatusSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RecruitStore.self) private var store

    let companyID: UUID

    var body: some View {
        List(CompanyStatus.allCases) { status in
            Button {
                Task { await updateStatus(status) }
            } label: {
                HStack {
                    CompanyStatusBadge(status: status)
                    Spacer()
                    if status == company?.status {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .fullWidthTappableArea()
            }
            .buttonStyle(.plain)
            .disabled(store.isSaving)
        }
        .navigationTitle("ステータス")
        .navigationBarTitleDisplayMode(.inline)
        .recruitErrorAlert(store: store)
    }

    private var company: Company? {
        store.company(id: companyID)
    }

    private func updateStatus(_ status: CompanyStatus) async {
        guard let company, status != company.status else {
            dismiss()
            return
        }

        var draft = CompanyDraft(company: company)
        draft.status = status
        if await store.updateCompany(company, draft: draft) != nil {
            dismiss()
        }
    }
}
