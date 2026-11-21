import SwiftUI

struct CompanyDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RecruitStore.self) private var store
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var isVisible = false

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
                ContentUnavailableView(
                    "企業が見つかりません", systemImage: "building.2.crop.circle",
                    description: Text("企業一覧に戻って更新してください。").foregroundColor(RecruitTextColor.supporting)
                )
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
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }

    private var swipeActionsAvailable: Bool {
        isVisible && router.selectedTab == .companies
            && !isAddingSelection && !isAddingTask && editingCompanyField == nil
            && selectedStep == nil && selectedTask == nil
    }

    private func companySection(_ company: Company) -> some View {
        let website = company.url.flatMap(WebURLNormalizer.normalizedString(from:)).flatMap { URL(string: $0) }
        return Section {
            Button { editingCompanyField = .name } label: {
                HStack(spacing: 12) {
                    LabeledContent("企業名") {
                        Text(company.name)
                            .foregroundStyle(Color.primary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    editDisclosureIndicator
                }
                .fullWidthTappableArea()
            }
            .buttonStyle(.plain)
            NavigationLink {
                CompanyStatusSelectionView(companyID: company.id)
            } label: {
                CompanyStatusField(status: company.status)
                    .fullWidthTappableArea()
            }
            Button { editingCompanyField = .url } label: {
                HStack(spacing: 12) {
                    LabeledContent("企業サイトURL") {
                        Text(website?.host ?? (company.url == nil ? "未設定" : "要確認"))
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(Color.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    editDisclosureIndicator
                }
                .fullWidthTappableArea()
            }
            .buttonStyle(.plain)
            if let website {
                Link("企業サイトを開く", destination: website)
            }
            Button { editingCompanyField = .memo } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("メモ")
                        Text(company.memo ?? "未設定")
                            .font(.subheadline)
                            .foregroundStyle(Color.primary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    editDisclosureIndicator
                }
                .fullWidthTappableArea()
            }
            .buttonStyle(.plain)
        } header: {
            Text("企業情報").foregroundStyle(Color.primary)
        }
    }

    private var editDisclosureIndicator: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .fixedSize()
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
                        .foregroundStyle(Color.primary)
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
                                .frame(minWidth: 44, minHeight: 44)
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
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .disabled(store.isSaving)
                            .accessibilityLabel(step.completionAccessibilityLabel(isWorking: store.savingSelectionStepID == step.id))
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
                    .modifier(ConfirmedDeleteSwipe(
                        isAvailable: swipeActionsAvailable,
                        isSaving: store.isSaving,
                        isConfirming: deletingStep?.id == step.id,
                        requestConfirmation: { deletingStep = step }
                    ))
                }
            }
        } header: {
            HStack {
                Text("選考タイムライン").foregroundStyle(Color.primary)
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
            store.errorMessage = UserFacingError.completionRecoveryMessage(userID: session.userID)
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
                    HStack(alignment: .top, spacing: 0) {
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
                    .modifier(ConfirmedDeleteSwipe(
                        isAvailable: swipeActionsAvailable,
                        isSaving: store.isSaving,
                        isConfirming: deletingTask?.id == task.id,
                        requestConfirmation: { deletingTask = task }
                    ))
                }
            }
        } header: {
            HStack {
                Text("関連ToDo").foregroundStyle(Color.primary)
                Spacer()
                Button { isAddingTask = true } label: { Image(systemName: "plus.circle") }
                    .accessibilityLabel("ToDoを追加")
            }
        }
    }

    private func deleteSection(_ company: Company) -> some View {
        Section {
            DestructiveActionButton("企業を削除") { confirmsCompanyDeletion = true }
                .disabled(store.isSaving)
        }
    }
}

private struct CompanyStatusSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RecruitStore.self) private var store

    @State private var updatingStatus: CompanyStatus?

    let companyID: UUID

    var body: some View {
        List(CompanyStatus.allCases) { status in
            Button {
                Task { await updateStatus(status) }
            } label: {
                HStack {
                    CompanyStatusBadge(status: status)
                    Spacer()
                    if updatingStatus == status {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("更新中")
                    } else if status == company?.status {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .fullWidthTappableArea()
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(status == company?.status ? .isSelected : [])
            .disabled(store.isSaving || updatingStatus != nil)
        }
        .navigationTitle("ステータス")
        .navigationBarTitleDisplayMode(.inline)
        .recruitErrorAlert(store: store)
    }

    private var company: Company? {
        store.company(id: companyID)
    }

    private func updateStatus(_ status: CompanyStatus) async {
        guard !store.isSaving, updatingStatus == nil, let company else { return }
        guard status != company.status else {
            dismiss()
            return
        }

        updatingStatus = status
        defer { updatingStatus = nil }
        var draft = CompanyDraft(company: company)
        draft.status = status
        if await store.updateCompany(company, draft: draft) != nil {
            dismiss()
        }
    }
}
