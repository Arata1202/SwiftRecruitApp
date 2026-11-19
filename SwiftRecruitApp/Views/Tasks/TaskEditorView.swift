import SwiftUI

struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    let onDeleted: (() -> Void)?
    let task: RecruitTask?
    let fixesCompany: Bool
    @State private var initialDraft: RecruitTaskDraft
    @State private var draft: RecruitTaskDraft
    @State private var confirmsDeletion = false
    @State private var confirmsDiscard = false

    init(task: RecruitTask? = nil, companyID: UUID? = nil, initialDueDate: Date? = nil, fixesCompany: Bool = false, onDeleted: (() -> Void)? = nil) {
        self.onDeleted = onDeleted
        self.task = task
        self.fixesCompany = fixesCompany && task == nil && companyID != nil
        var initialDraft = task.map(RecruitTaskDraft.init)
            ?? initialDueDate.map { RecruitTaskDraft(dueDate: $0) }
            ?? RecruitTaskDraft()
        if task == nil { initialDraft.companyID = companyID }
        _initialDraft = State(initialValue: initialDraft)
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("ToDo") {
                    TextField("やることを入力", text: $draft.title)
                    if InputLimits.length(of: normalizedTitle) > InputLimits.taskTitle {
                        Text("ToDoは\(InputLimits.taskTitle)文字以内で入力してください。")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if fixesCompany == false {
                        if store.companies.isEmpty {
                            LabeledContent("関連企業", value: "なし")
                            Text("企業を登録すると関連付けられます")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("関連企業（任意）", selection: $draft.companyID) {
                                Text("なし").tag(nil as UUID?)
                                ForEach(store.companies) { company in
                                    Text(company.name).tag(company.id as UUID?)
                                }
                            }
                            .pickerStyle(.navigationLink)
                        }
                    }
                }

                Section("期限") {
                    Toggle("期限を設定", isOn: $draft.hasDueDate.animation())
                    if draft.hasDueDate {
                        DatePicker(
                            "日付",
                            selection: $draft.dueAt,
                            displayedComponents: .date
                        )
                        Toggle("時刻も指定", isOn: Binding(
                            get: { draft.dueHasTime },
                            set: { draft.setDueHasTime($0) }
                        ).animation())
                        if draft.dueHasTime {
                            DatePicker(
                                "時刻",
                                selection: $draft.dueAt,
                                displayedComponents: .hourAndMinute
                            )
                        }
                    }
                }

                Section {
                    NotificationTimingPicker(
                        enabled: $draft.notificationEnabled,
                        timedPreset: $draft.notificationTimedPreset,
                        datePreset: $draft.notificationDatePreset,
                        timedCustom: $draft.notificationTimedCustom,
                        dateCustom: $draft.notificationDateCustom,
                        hasTime: draft.dueHasTime,
                        kind: .taskDue
                    )
                    .disabled(draft.hasDueDate == false)
                    if draft.notificationEnabled && draft.hasDueDate && draft.notificationValidationMessage() == nil {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            Text(TaskNotificationDescription.text(
                                enabled: draft.notificationEnabled,
                                isCompleted: task?.isCompleted ?? false,
                                dueAt: draft.hasDueDate ? draft.dueAt : nil,
                                hasTime: draft.dueHasTime,
                                timedPreset: draft.notificationTimedPreset,
                                datePreset: draft.notificationDatePreset,
                                timedCustom: draft.notificationTimedCustom,
                                dateCustom: draft.notificationDateCustom,
                                now: context.date
                            ))
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    if let message = draft.notificationValidationMessage() {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("通知")
                } footer: {
                    Text("完了中は通知されません。未完了に戻すと、通知設定と日時に応じて通知が再設定されます。")
                }

                Section("メモ（任意）") {
                    TextField("詳細や補足を入力", text: $draft.memo, axis: .vertical)
                        .lineLimit(3...8)
                    if InputLimits.length(of: normalizedMemo) > InputLimits.memo {
                        Text("メモは\(InputLimits.memo)文字以内で入力してください。")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if task != nil {
                    Section {
                        Button("ToDoを削除", role: .destructive) {
                            confirmsDeletion = true
                        }
                    }
                }
            }
            .navigationTitle(task == nil ? "ToDoを追加" : "ToDoを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        guard store.isSaving == false else { return }
                        if hasUnsavedChanges { confirmsDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        SaveButtonLabel(isSaving: store.isSaving)
                    }
                    .disabled(
                        normalizedTitle.isEmpty
                            || InputLimits.length(of: normalizedTitle) > InputLimits.taskTitle
                            || InputLimits.length(of: normalizedMemo) > InputLimits.memo
                            || draft.notificationValidationMessage() != nil
                            || store.isSaving
                    )
                }
            }
            .disabled(store.isSaving)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: draft.hasDueDate) { _, hasDueDate in
                if hasDueDate == false { draft.notificationEnabled = false }
            }
            .alert("ToDoを削除しますか？", isPresented: $confirmsDeletion) {
                Button("削除", role: .destructive) {
                    Task { await deleteTask() }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この操作は取り消せません。")
            }
            .recruitErrorAlert(store: store)
        }
        .interactiveDismissDisabled(store.isSaving || hasUnsavedChanges)
        .alert("変更を破棄しますか？", isPresented: $confirmsDiscard) {
            Button("破棄する", role: .destructive) {
                guard store.isSaving == false else { return }
                dismiss()
            }
            .disabled(store.isSaving)
            Button("編集を続ける", role: .cancel) {}
        } message: {
            Text("保存していない変更は失われます。")
        }
    }

    private var hasUnsavedChanges: Bool {
        draft.hasTaskEditorChanges(comparedTo: initialDraft)
    }

    private var normalizedTitle: String {
        draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedMemo: String {
        draft.memo.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() async {
        guard store.isSaving == false, draft.notificationValidationMessage() == nil else { return }
        if let task {
            if await store.updateTask(task, draft: draft) != nil { dismiss() }
        } else if let userID = session.userID,
                  await store.createTask(userID: userID, draft: draft) != nil {
            dismiss()
        }
    }

    private func deleteTask() async {
        guard store.isSaving == false, let task else { return }
        if await store.deleteTask(task) {
            // The presentation owner closes the entire stack after deletion.
            // Standalone editors close themselves. Never request both dismissals.
            if let onDeleted { onDeleted() } else { dismiss() }
        }
    }
}

// Compare visible, persisted values, ignoring hidden date/time state.
extension RecruitTaskDraft {
    func hasTaskEditorChanges(comparedTo initial: Self, calendar: Calendar = .current) -> Bool {
        if title != initial.title || memo != initial.memo || companyID != initial.companyID
            || hasDueDate != initial.hasDueDate || notificationEnabled != initial.notificationEnabled
            || notificationTimedPreset != initial.notificationTimedPreset
            || notificationDatePreset != initial.notificationDatePreset
            || notificationTimedCustom != initial.notificationTimedCustom
            || notificationDateCustom != initial.notificationDateCustom {
            return true
        }
        guard hasDueDate else { return false }
        if dueHasTime != initial.dueHasTime { return true }
        return dueHasTime
            ? !calendar.isDate(dueAt, equalTo: initial.dueAt, toGranularity: .minute)
            : !calendar.isDate(dueAt, inSameDayAs: initial.dueAt)
    }
}
