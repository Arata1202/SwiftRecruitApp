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
                        RecruitSection("ToDo") {
                            Text(task.title).font(.headline)
                            DetailLabeledContent("関連企業", value: companyName(for: task))
                            DetailLabeledContent("状態", value: task.isCompleted ? "完了" : "未完了")
                        }
                        RecruitSection("期限") {
                            if let date = task.dueDate() {
                                DetailLabeledContent("期限", value: formattedDate(date, hasTime: task.dueHasTime))
                            } else {
                                Text("期限なし").foregroundStyle(RecruitTextColor.supporting)
                            }
                            if let completedAt = task.completedAt {
                                DetailLabeledContent("完了日時", value: formattedDate(completedAt, hasTime: true))
                            }
                        }
                        RecruitSection("通知") {
                            let timing = NotificationTimingDetailPresentation(
                                enabled: task.notificationEnabled, hasTime: task.dueHasTime, kind: .taskDue,
                                anchor: task.dueDate(), timed: task.notificationTimedPreset, date: task.notificationDatePreset,
                                timedCustom: task.notificationTimedCustom, dateCustom: task.notificationDateCustom,
                                absoluteAt: task.notificationAbsoluteAt
                            )
                            DetailLabeledContent("通知タイミング", value: timing.timing)
                            if let clock = timing.clock {
                                DetailLabeledContent("通知時刻", value: clock)
                            }
                            TimelineView(.periodic(from: .now, by: 60)) { context in
                                NotificationPlanStatusView(
                                    status: notificationDescription(for: task, now: context.date)
                                )
                                .font(.footnote)
                            }
                        }
                        RecruitSection("メモ") {
                            Text(nonemptyMemo(task.memo) ?? "メモはありません")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .textSelection(.enabled)
                } else {
                    ContentUnavailableView(
                        "ToDoが見つかりません",
                        systemImage: "checklist",
                        description: Text("この項目を表示できません。閉じて一覧を更新してください。").foregroundColor(RecruitTextColor.supporting)
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

    private func notificationDescription(for task: RecruitTask, now: Date) -> NotificationPlanStatus {
        let fallback = TaskNotificationDescription.text(
            enabled: task.notificationEnabled, isCompleted: task.isCompleted,
            dueAt: task.dueDate(), hasTime: task.dueHasTime,
            timedPreset: task.notificationTimedPreset, datePreset: task.notificationDatePreset,
            timedCustom: task.notificationTimedCustom, dateCustom: task.notificationDateCustom,
            absoluteAt: task.notificationAbsoluteAt, now: now
        )
        guard !task.isCompleted, task.notificationEnabled else { return .message(fallback) }
        return store.notificationPlanDescription(
            identifiers: NotificationPlanBuilder.taskIdentifiers(task.id),
            userID: ownerUserID, fallback: fallback, now: now
        )
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
        absoluteAt: Date? = nil,
        calendar: Calendar = .current,
        now: Date = Date(),
        isPreview: Bool = false
    ) -> String {
        guard !isCompleted else {
            return "完了済みのため通知されません。"
        }
        guard enabled else { return "このToDoの通知はオフです。" }
        guard let dueAt else { return "期限が未設定のため、通知されません。" }
        if absoluteAt == nil, let error = NotificationScheduleCalculator.validationMessage(
            anchor: dueAt, hasTime: hasTime, kind: .taskDue,
            timedCustom: timedCustom, dateCustom: dateCustom, calendar: calendar
        ) { return error }
        return NotificationScheduleCalculator.reminderDescription(
            NotificationScheduleCalculator.reminderDate(
                anchor: dueAt, hasTime: hasTime, kind: .taskDue,
                timedPreset: timedPreset, datePreset: datePreset,
                timedCustom: timedCustom, dateCustom: dateCustom, absoluteAt: absoluteAt, calendar: calendar
            ), now: now, calendar: calendar, isPreview: isPreview
        )
    }
}
