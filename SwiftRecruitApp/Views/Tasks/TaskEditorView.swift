import SwiftUI

struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    let task: RecruitTask?
    @State private var draft: RecruitTaskDraft

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

            }
            .navigationTitle(task == nil ? "ToDoを追加" : "ToDoを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
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
                    )
                }
            }
            .disabled(store.isSaving)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: draft.hasDueDate) { _, hasDueDate in
                if hasDueDate == false { draft.notificationEnabled = false }
            }
            .recruitErrorAlert(store: store)
        }
        .interactiveDismissDisabled(store.isSaving)
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
}
