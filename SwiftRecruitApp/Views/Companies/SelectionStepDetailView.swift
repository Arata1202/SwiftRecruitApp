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
                        Section("選考") {
                            LabeledContent("企業", value: companyName(for: step))
                            LabeledContent("種類", value: step.type.title)
                            if step.type == .other {
                                LabeledContent("選考名", value: step.displayTitle)
                            }
                            LabeledContent("状態", value: step.status.title)
                        }
                        Section("日程") {
                            if let date = step.startDate() {
                                LabeledContent("予定", value: formattedDate(date, hasTime: step.startsHasTime))
                            }
                            if let date = step.deadlineDate() {
                                LabeledContent("締切", value: formattedDate(date, hasTime: step.deadlineHasTime))
                            }
                            if step.startDate() == nil && step.deadlineDate() == nil {
                                Text("日程未設定").foregroundStyle(.secondary)
                            }
                        }
                        Section {
                            LabeledContent("通知設定", value: step.notificationEnabled ? "オン" : "オフ")
                            Text(notificationDescription(for: step))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } header: {
                            Text("通知")
                        }
                        Section("メモ") {
                            Text(nonemptyMemo(step.memo) ?? "メモはありません")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .textSelection(.enabled)
                } else {
                    ContentUnavailableView(
                        "選考が見つかりません",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("選考が削除されたか、ログイン状態または読み込み中のデータが変わりました。閉じて一覧を確認してください。")
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

    private func notificationDescription(for step: SelectionStep) -> String {
        guard step.status == .scheduled else {
            return "完了・中止中は通知されません。予定に戻すと、通知設定と日時に応じて通知が再設定されます。"
        }
        guard step.notificationEnabled else { return "この選考の通知はオフです。" }

        var descriptions: [String] = []
        if let date = step.startDate() {
            let timing = step.startsHasTime ? "予定時刻の1時間前" : "予定日の9時"
            let fireDate = NotificationScheduleCalculator.selectionStartDate(startsAt: date, hasTime: step.startsHasTime)
            descriptions.append(notificationTiming(timing, fireDate: fireDate))
        }
        if let date = step.deadlineDate() {
            let fireDate = NotificationScheduleCalculator.selectionDeadlineDate(deadlineAt: date)
            descriptions.append(notificationTiming("締切前日の20時", fireDate: fireDate))
        }
        guard !descriptions.isEmpty else { return "日程が未設定のため、通知されません。" }
        descriptions.append("端末の通知設定などによっては届かない場合があります。")
        return descriptions.joined(separator: "\n")
    }

    private func notificationTiming(_ timing: String, fireDate: Date?) -> String {
        fireDate == nil
            ? "通知時刻（\(timing)）を過ぎているため、この日程では通知されません。"
            : "\(timing)に通知予定です。"
    }
}
