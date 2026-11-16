import SwiftUI

struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    let task: RecruitTask?
    @State private var draft: RecruitTaskDraft
    @State private var confirmsDeletion = false
    @State private var calendarBusy = false
    @State private var calendarRevision = 0

    init(task: RecruitTask? = nil, companyID: UUID? = nil, initialDueDate: Date? = nil) {
        self.task = task
        var initialDraft = task.map(RecruitTaskDraft.init)
            ?? initialDueDate.map { RecruitTaskDraft(dueDate: $0) }
            ?? RecruitTaskDraft()
        if task == nil { initialDraft.companyID = companyID }
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
                    Picker("関連企業（任意）", selection: $draft.companyID) {
                        Text("なし").tag(nil as UUID?)
                        ForEach(store.companies) { company in
                            Text(company.name).tag(company.id as UUID?)
                        }
                    }
                    .pickerStyle(.navigationLink)
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

                Section("期限") {
                    Toggle("期限を設定", isOn: $draft.hasDueDate.animation())
                    if draft.hasDueDate {
                        DatePicker(
                            "日付",
                            selection: $draft.dueAt,
                            displayedComponents: .date
                        )
                        Toggle("時刻も指定", isOn: $draft.dueHasTime.animation())
                        if draft.dueHasTime {
                            DatePicker(
                                "時刻",
                                selection: $draft.dueAt,
                                displayedComponents: .hourAndMinute
                            )
                        }
                    }
                }

                Section("通知") {
                    Toggle("通知する", isOn: $draft.notificationEnabled)
                        .disabled(draft.hasDueDate == false)
                    if draft.notificationEnabled && draft.hasDueDate {
                        Text(
                            draft.dueHasTime
                                ? "設定した期限時刻に通知します。"
                                : "期限日の9時に通知します。"
                        )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Appleカレンダー") {
                    if let task, let saved = store.tasks.first(where: { $0.id == task.id }) {
                        if saved.dueDate() != nil {
                            let exported = store.isTaskExported(id: saved.id)
                            Text(exported ? "保存済みの期限：追加済み" : "保存済みの期限：未追加")
                            Button(exported ? "カレンダーから削除" : "カレンダーに追加") {
                                calendarBusy = true
                                Task {
                                    if exported { _ = await store.removeTaskFromAppleCalendar(id: saved.id) }
                                    else { _ = await store.exportTask(saved) }
                                    calendarRevision += 1
                                    calendarBusy = false
                                }
                            }
                            .disabled(calendarBusy)
                        } else {
                            Text("保存済みの期限がありません。")
                        }
                        Text("操作には保存済みの内容を使います。編集中の変更は保存後に反映されます。")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text(task == nil ? "保存後にカレンダーへ追加できます。" : "保存済みのToDoが見つかりません。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .id(calendarRevision)

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
                    Button("キャンセル") { dismiss() }
                        .disabled(store.isSaving || calendarBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        SaveButtonLabel(isSaving: store.isSaving)
                    }
                    .disabled(
                        normalizedTitle.isEmpty
                            || InputLimits.length(of: normalizedTitle) > InputLimits.taskTitle
                            || InputLimits.length(of: normalizedMemo) > InputLimits.memo
                            || store.isSaving
                            || calendarBusy
                    )
                }
            }
            .disabled(store.isSaving || calendarBusy)
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
        .interactiveDismissDisabled(store.isSaving || calendarBusy)
    }

    private var normalizedTitle: String {
        draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedMemo: String {
        draft.memo.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() async {
        if let task {
            if await store.updateTask(task, draft: draft) != nil { dismiss() }
        } else if let userID = session.userID,
                  await store.createTask(userID: userID, draft: draft) != nil {
            dismiss()
        }
    }

    private func deleteTask() async {
        guard let task else { return }
        if await store.deleteTask(task) { dismiss() }
    }
}
