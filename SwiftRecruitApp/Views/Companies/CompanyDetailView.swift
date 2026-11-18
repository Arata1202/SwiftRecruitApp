import SwiftUI

struct CompanyDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RecruitStore.self) private var store
    @Environment(AppSession.self) private var session

    let companyID: UUID
    @State private var isAddingSelection = false
    @State private var isAddingTask = false
    @State private var editingCompanyField: CompanyEditableField?
    @State private var selectedStep: SelectionStep?
    @State private var selectedTask: RecruitTask?
    @State private var deletingStep: SelectionStep?
    @State private var deletingTask: RecruitTask?
    @State private var confirmsCompanyDeletion = false

    var body: some View {
        Group {
            if let company = store.company(id: companyID) {
                List {
                    companySection(company)
                    informationSection
                    selectionSection
                    taskSection
                    deleteSection(company)
                }
                .refreshable {
                    if let userID = session.userID { await store.reload(userID: userID, force: true) }
                }
                .navigationTitle(company.name)
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $isAddingSelection) { SelectionStepEditorView(companyID: companyID) }
                .sheet(isPresented: $isAddingTask) { TaskEditorView(companyID: companyID, fixesCompany: true) }
                .sheet(item: $editingCompanyField) { field in
                    NavigationStack {
                        CompanyFieldEditorView(company: company, field: field)
                    }
                }
                .sheet(item: $selectedStep) { step in
                    SelectionStepDetailView(stepID: step.id, ownerUserID: step.userID, onDeleted: {
                        if selectedStep?.id == step.id { selectedStep = nil }
                    })
                }
                .sheet(item: $selectedTask) { task in
                    TaskDetailView(taskID: task.id, ownerUserID: task.userID, onDeleted: {
                        if selectedTask?.id == task.id { selectedTask = nil }
                    })
                }
                .alert(
                    "企業を削除しますか？",
                    isPresented: $confirmsCompanyDeletion
                ) {
                    Button("企業と関連データを削除", role: .destructive) {
                        Task {
                            guard !store.isSaving else { return }
                            if await store.deleteCompany(company) { dismiss() }
                        }
                    }
                    .disabled(store.isSaving)
                    Button("キャンセル", role: .cancel) {}
                } message: {
                    Text("企業研究・記録、選考、関連ToDoも削除されます。この操作は取り消せません。")
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
                guard !store.isSaving, let deletingStep else { return }
                Task {
                    guard !store.isSaving else { return }
                    _ = await store.deleteSelectionStep(deletingStep)
                }
            }
            .disabled(store.isSaving)
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
                guard !store.isSaving, let deletingTask else { return }
                Task {
                    guard !store.isSaving else { return }
                    _ = await store.deleteTask(deletingTask)
                }
            }
            .disabled(store.isSaving)
            Button("キャンセル", role: .cancel) { deletingTask = nil }
        } message: {
            Text("この操作は取り消せません。")
        }
        .recruitErrorAlert(store: store)
    }

    private func companySection(_ company: Company) -> some View {
        Section {
            Button { editingCompanyField = .name } label: {
                HStack(spacing: 12) {
                    LabeledContent("企業名") {
                        Text(company.name)
                            .foregroundStyle(.secondary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    editDisclosureIndicator
                }
                .fullWidthTappableArea()
            }
            .buttonStyle(.plain)
            NavigationLink {
                CompanyStatusSelectionView(companyID: company.id)
            } label: {
                HStack {
                    Text("ステータス")
                    Spacer(minLength: 12)
                    CompanyStatusBadge(status: company.status)
                }
                .fullWidthTappableArea()
            }
            Button { editingCompanyField = .url } label: {
                HStack(spacing: 12) {
                    LabeledContent("企業サイトURL") {
                        Text(company.url == nil ? "未設定" : "設定済み")
                            .foregroundStyle(.secondary)
                    }
                    editDisclosureIndicator
                }
                .fullWidthTappableArea()
            }
            .buttonStyle(.plain)
            if let urlValue = company.url, let url = URL(string: urlValue) {
                Link("企業サイトを開く", destination: url)
            }
            Button { editingCompanyField = .memo } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("メモ")
                        Text(company.memo ?? "未設定")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    editDisclosureIndicator
                }
                .fullWidthTappableArea()
            }
            .buttonStyle(.plain)
        } header: {
            Text("企業情報")
        }
    }

    private var editDisclosureIndicator: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    private var informationSection: some View {
        Section {
            NavigationLink {
                CompanyInformationView(companyID: companyID)
            } label: {
                LabeledContent("企業研究・記録") {
                    Text("\(store.informationItems(for: companyID).count)件")
                        .foregroundStyle(.secondary)
                }
                .fullWidthTappableArea()
            }
        }
    }

    private var selectionSection: some View {
        Section {
            let steps = store.steps(for: companyID)
            if steps.isEmpty {
                Button("選考を追加", systemImage: "calendar.badge.plus") { isAddingSelection = true }
            } else {
                ForEach(steps) { step in
                    HStack(alignment: .top, spacing: 0) {
                        if step.status == .cancelled {
                            Image(systemName: "minus.circle")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                                .accessibilityLabel("中止")
                        } else {
                            Button {
                                Task { await toggleSelectionCompletion(step) }
                            } label: {
                                Group {
                                    if store.savingSelectionStepID == step.id {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: step.status == .completed ? "checkmark.circle.fill" : "circle")
                                            .font(.title3)
                                            .foregroundStyle(step.status == .completed ? Color.green : Color.secondary)
                                    }
                                }
                                .frame(width: 44, height: 44)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .disabled(store.isSaving)
                            .accessibilityLabel(step.status == .completed
                                ? "「\(step.displayTitle)」を予定に戻す"
                                : "「\(step.displayTitle)」を完了にする")
                        }
                        Button { selectedStep = step } label: {
                            SelectionStepRow(
                                step: step,
                                companyName: nil,
                                showsMemo: true,
                                showsTypeIcon: false,
                                showsCompletedStyle: true
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("選考の詳細を表示")
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("削除") { deletingStep = step }
                            .tint(.red)
                            .disabled(store.isSaving)
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

    @MainActor
    private func toggleSelectionCompletion(_ step: SelectionStep) async {
        guard !store.isSaving else { return }
        guard let userID = session.userID, store.loadedUserID == userID else {
            store.errorMessage = "ログイン状態または読み込み中のデータが変わりました。データを再読み込みしてください。"
            return
        }
        guard let current = store.selectionSteps.first(where: {
            $0.id == step.id && $0.version == step.version && $0.companyID == companyID
        }) else {
            store.errorMessage = "予定が更新または削除されています。再読み込みして内容を確認してください。"
            return
        }
        guard current.status != .cancelled else { return }
        _ = await store.setSelectionStepStatus(
            current,
            status: current.status == .completed ? .scheduled : .completed
        )
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
                        Button { selectedTask = task } label: {
                            TaskRow(task: task, companyName: nil)
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
                .disabled(store.isSaving)
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
