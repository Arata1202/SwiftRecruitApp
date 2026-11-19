import SwiftUI

/// The presentation supplies identity only; display and editing resolve the current owned record.
struct TaskDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    let taskID: UUID
    let ownerUserID: UUID
    let onDeleted: () -> Void
    @State private var editingTask: RecruitTask?

    var body: some View {
        NavigationStack {
            Group {
                if let task = currentTask {
                    List {
                        Section("ToDo") {
                            Text(task.title).font(.headline)
                            LabeledContent("関連企業", value: companyName(for: task))
                            LabeledContent("状態", value: task.isCompleted ? "完了" : "未完了")
                        }
                        Section("期限") {
                            if let date = task.dueDate() {
                                LabeledContent("期限", value: formattedDate(date, hasTime: task.dueHasTime))
                            } else {
                                Text("期限なし").foregroundStyle(.secondary)
                            }
                            if let completedAt = task.completedAt {
                                LabeledContent("完了日時", value: formattedDate(completedAt, hasTime: true))
                            }
                        }
                        Section("通知") {
                            LabeledContent("通知設定", value: task.notificationEnabled ? "オン" : "オフ")
                            TimelineView(.periodic(from: .now, by: 60)) { context in
                                Text(TaskNotificationDescription.text(
                                    enabled: task.notificationEnabled,
                                    isCompleted: task.isCompleted,
                                    dueAt: task.dueDate(),
                                    hasTime: task.dueHasTime,
                                    timedPreset: task.notificationTimedPreset,
                                    datePreset: task.notificationDatePreset,
                                    timedCustom: task.notificationTimedCustom,
                                    dateCustom: task.notificationDateCustom,
                                    now: context.date
                                ))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }
                        }
                        Section("メモ") {
                            Text(nonemptyMemo(task.memo) ?? "メモはありません")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .textSelection(.enabled)
                } else {
                    ContentUnavailableView(
                        "ToDoが見つかりません",
                        systemImage: "checklist",
                        description: Text("ToDoが削除されたか、ログイン状態または読み込み中のデータが変わりました。閉じて一覧を確認してください。")
                    )
                }
            }
            .navigationTitle("ToDoの詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("編集") { editingTask = currentTask }
                        .disabled(currentTask == nil || store.isSaving)
                }
            }
            .sheet(item: $editingTask) { task in
                TaskEditorView(task: task, onDeleted: onDeleted)
            }
            .onChange(of: session.userID) { _, _ in editingTask = nil }
            .onChange(of: store.loadedUserID) { _, _ in editingTask = nil }
        }
    }

    private var currentTask: RecruitTask? {
        guard session.userID == ownerUserID, store.loadedUserID == ownerUserID else { return nil }
        return store.tasks.first { $0.id == taskID && $0.userID == ownerUserID }
    }

    private func companyName(for task: RecruitTask) -> String {
        guard let companyID = task.companyID else { return "なし" }
        guard let company = store.company(id: companyID), company.userID == ownerUserID else {
            return "企業が見つかりません"
        }
        return company.name
    }

    private func formattedDate(_ date: Date, hasTime: Bool) -> String {
        let style = Date.FormatStyle.dateTime.year().month(.wide).day().weekday(.wide)
        return hasTime ? date.formatted(style.hour().minute()) : date.formatted(style)
    }

    private func nonemptyMemo(_ memo: String?) -> String? {
        guard let memo, !memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return memo
    }
}

/// Shared by detail and editor so the copy agrees with actual scheduling eligibility.
enum TaskNotificationDescription {
    static func text(
        enabled: Bool,
        isCompleted: Bool,
        dueAt: Date?,
        hasTime: Bool,
        timedPreset: TimedNotificationPreset? = nil,
        datePreset: DateNotificationPreset? = nil,
        timedCustom: CustomNotificationTiming? = nil,
        dateCustom: CustomNotificationTiming? = nil,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> String {
        guard !isCompleted else {
            return "完了中は通知されません。未完了に戻すと、通知設定と日時に応じて通知が再設定されます。"
        }
        guard enabled else { return "このToDoの通知はオフです。" }
        guard let dueAt else { return "期限が未設定のため、通知されません。" }
        if let error = NotificationScheduleCalculator.validationMessage(
            anchor: dueAt, hasTime: hasTime, kind: .taskDue,
            timedCustom: timedCustom, dateCustom: dateCustom, calendar: calendar
        ) { return error }
        return NotificationScheduleCalculator.reminderDescription(
            NotificationScheduleCalculator.reminderDate(
                anchor: dueAt, hasTime: hasTime, kind: .taskDue,
                timedPreset: timedPreset, datePreset: datePreset,
                timedCustom: timedCustom, dateCustom: dateCustom, calendar: calendar
            ), now: now, calendar: calendar
        )
    }
}
