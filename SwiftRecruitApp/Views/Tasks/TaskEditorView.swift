import SwiftUI

struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    let task: RecruitTask?
    @State private var draft: RecruitTaskDraft

    init(task: RecruitTask? = nil, companyID: UUID? = nil) {
        self.task = task
        var initialDraft = task.map(RecruitTaskDraft.init) ?? RecruitTaskDraft()
        if task == nil { initialDraft.companyID = companyID }
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("ToDo") {
                    TextField("やること", text: $draft.title)
                    Picker("関連企業", selection: $draft.companyID) {
                        Text("なし").tag(nil as UUID?)
                        ForEach(store.companies) { company in
                            Text(company.name).tag(company.id as UUID?)
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
                        Text(draft.dueHasTime ? "指定した時刻に通知します。" : "当日の9時に通知します。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("メモ") {
                    TextField("内容（任意）", text: $draft.memo, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(task == nil ? "ToDoを追加" : "ToDoを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSaving)
                }
            }
            .disabled(store.isSaving)
            .onChange(of: draft.hasDueDate) { _, hasDueDate in
                if hasDueDate == false { draft.notificationEnabled = false }
            }
            .recruitErrorAlert(store: store)
        }
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

