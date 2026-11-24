import SwiftUI

/// Resolves the current record on every render; the presentation snapshot is never displayed.
struct SelectionStepDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    let stepID: UUID
    let ownerUserID: UUID
    let onDeleted: () -> Void
    @State private var editingStep: SelectionStep?

    var body: some View {
        NavigationStack {
            Group {
                if let step = currentStep {
                    List {
                        RecruitSection("選考") {
                            DetailLabeledContent("企業", value: companyName(for: step))
                            DetailLabeledContent("種類", value: step.type.title)
                            if step.type == .other || step.displayTitle != step.type.title {
                                DetailLabeledContent("選考名", value: step.displayTitle)
                            }
                            DetailLabeledContent("状態", value: step.status.title)
                        }
                        RecruitSection("日程") {
                            if step.startDate() != nil {
                                ScheduleRangeLabel(step: step, showsIcon: false)
                            }
                            if let date = step.deadlineDate() {
                                DetailLabeledContent("締切", value: formattedDate(date, hasTime: step.deadlineHasTime))
                            }
                            if step.startDate() == nil && step.deadlineDate() == nil {
                                Text("日程未設定").foregroundStyle(RecruitTextColor.supporting)
                            }
                        }
                        RecruitSection("通知") {
                            let timing = notificationTiming(for: step)
                            DetailLabeledContent("通知タイミング", value: timing.timing)
                            if let clock = timing.clock {
                                DetailLabeledContent("通知時刻", value: clock)
                            }
                            TimelineView(.periodic(from: .now, by: 60)) { context in
                                NotificationPlanStatusView(status: notificationDescription(for: step, now: context.date))
                            }
                            .font(.footnote)
                        }
                        RecruitSection("メモ") {
                            Text(nonemptyMemo(step.memo) ?? "メモはありません")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .textSelection(.enabled)
                } else {
                    ContentUnavailableView(
                        "選考が見つかりません",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("この項目を表示できません。閉じて一覧を更新してください。").foregroundColor(RecruitTextColor.supporting)
                    )
                }
            }
            .navigationTitle("選考の詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("編集") {
                        // Fetch again at the moment editing starts, including the current version.
                        editingStep = currentStep
                    }
                    .disabled(currentStep == nil || store.isSaving)
                }
            }
            .sheet(item: $editingStep) { step in
                SelectionStepEditorView(step: step, onDeleted: onDeleted)
            }
            .onChange(of: session.userID) { _, _ in editingStep = nil }
            .onChange(of: store.loadedUserID) { _, _ in editingStep = nil }
        }
    }

    private var currentStep: SelectionStep? {
        guard session.userID == ownerUserID, store.loadedUserID == ownerUserID else { return nil }
        return store.selectionSteps.first { $0.id == stepID && $0.userID == ownerUserID }
    }

    private func companyName(for step: SelectionStep) -> String {
        guard let company = store.company(id: step.companyID), company.userID == ownerUserID else {
            return "企業が見つかりません"
        }
        return company.name
    }

    private func formattedDate(_ date: Date, hasTime: Bool) -> String {
        let style = Date.FormatStyle.dateTime.year().month(.wide).day().weekday(.wide)
        return hasTime
            ? date.formatted(style.hour().minute())
            : date.formatted(style)
    }

    private func nonemptyMemo(_ memo: String?) -> String? {
        guard let memo, !memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return memo
    }

    private func notificationTiming(for step: SelectionStep) -> NotificationTimingDetailPresentation {
        let draft = SelectionStepDraft(step: step)
        return NotificationTimingDetailPresentation(
            enabled: draft.notificationEnabled, hasTime: draft.hasTime, kind: draft.notificationAnchor,
            anchor: step.startDate() ?? step.deadlineDate(), timed: draft.notificationTimedPreset, date: draft.notificationDatePreset,
            timedCustom: draft.notificationTimedCustom, dateCustom: draft.notificationDateCustom,
            absoluteAt: draft.notificationAbsoluteAt
        )
    }

    private func notificationDescription(for step: SelectionStep, now: Date) -> NotificationPlanStatus {
        guard step.status == .scheduled else {
            return .message(step.status == .completed ? "完了済みのため通知されません。" : "中止のため通知されません。")
        }
        guard step.notificationEnabled else { return .message("この選考の通知はオフです。") }

        guard step.startDate() != nil || step.deadlineDate() != nil else {
            return .message("日程が未設定のため、通知されません。")
        }
        return store.notificationPlanDescription(
            identifiers: NotificationPlanBuilder.selectionIdentifiers(step.id), userID: ownerUserID,
            fallback: SelectionStepDraft(step: step).notificationDescription(now: now, isPreview: false)
                ?? "日程が未設定のため、通知されません。", now: now
        )
    }
}
