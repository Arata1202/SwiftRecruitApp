import SwiftUI

struct SelectionStepEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    let onDeleted: (() -> Void)?
    let step: SelectionStep?
    let fixedCompanyID: UUID?
    @State private var selectedCompanyID: UUID?
    @State private var draft: SelectionStepDraft
    @State private var initialDraft: SelectionStepDraft
    @State private var initialCompanyID: UUID?
    @State private var notificationPreviewID = UUID()
    @State private var notificationResetRevision = 0
    @State private var confirmsDiscard = false
    @State private var confirmsDeletion = false

    init(companyID: UUID? = nil, step: SelectionStep? = nil, initialDate: Date? = nil, onDeleted: (() -> Void)? = nil) {
        self.onDeleted = onDeleted
        self.step = step
        fixedCompanyID = step?.companyID ?? companyID
        _selectedCompanyID = State(initialValue: step?.companyID ?? companyID)
        let initialDraft = step.map(SelectionStepDraft.init)
            ?? initialDate.map { SelectionStepDraft(date: $0) }
            ?? SelectionStepDraft()
        _draft = State(initialValue: initialDraft)
        _initialDraft = State(initialValue: initialDraft)
        _initialCompanyID = State(initialValue: step?.companyID ?? companyID)
    }

    var body: some View {
        NavigationStack {
            Form {
                if fixedCompanyID == nil {
                    Section("企業") {
                        Picker("関連企業", selection: $selectedCompanyID) {
                            Text("選択してください").tag(nil as UUID?)
                            ForEach(
                                store.companies.filter {
                                    $0.status == .considering || $0.status == .active
                                }
                            ) { company in
                                Text(company.name).tag(company.id as UUID?)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                }

                Section("選考") {
                    Picker("種類", selection: $draft.type) {
                        ForEach(SelectionType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    if draft.type == .other {
                        TextField("選考名（必須）", text: $draft.customTitle)
                        if InputLimits.length(of: normalizedCustomTitle) > InputLimits.selectionTitle {
                            Text("選考名は\(InputLimits.selectionTitle)文字以内で入力してください。")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("日程") {
                    Picker("日程種別", selection: $draft.dateKind) {
                        ForEach(SelectionDateKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("時刻も指定", isOn: Binding(
                        get: { draft.hasTime },
                        set: { draft.setHasTime($0) }
                    ).animation())
                }

                Section(draft.dateKind == .schedule ? "開始" : "締切") {
                    DatePicker("日付", selection: $draft.date, displayedComponents: .date)
                    if draft.hasTime {
                        DatePicker(draft.dateKind == .schedule ? "開始時刻" : "締切時刻", selection: $draft.date, displayedComponents: .hourAndMinute)
                    }
                }

                if draft.dateKind == .schedule {
                    Section {
                        Toggle("終了を指定", isOn: Binding(
                            get: { draft.hasEnd },
                            set: { draft.setHasEnd($0) }
                        ))
                        if draft.hasEnd {
                            DatePicker("終了日", selection: $draft.endDate, displayedComponents: .date)
                            if draft.hasTime {
                                DatePicker("終了時刻", selection: $draft.endDate, displayedComponents: .hourAndMinute)
                            }
                            if !draft.isValidRange() {
                                Text("終了は開始以降に設定してください。")
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                        }
                    } header: {
                        Text("終了（任意）")
                    } footer: {
                        Text(draft.hasTime ? "終了時刻までの予定です。通知は開始日時を基準にします。" : "終了日を含む予定です。通知は開始日を基準にします。")
                    }
                }

                Section {
                    NotificationTimingPicker(
                        enabled: $draft.notificationEnabled,
                        timedPreset: $draft.notificationTimedPreset,
                        datePreset: $draft.notificationDatePreset,
                        timedCustom: $draft.notificationTimedCustom,
                        dateCustom: $draft.notificationDateCustom,
                        hasTime: draft.hasTime,
                        kind: draft.dateKind == .schedule ? .selectionStart : .selectionDeadline,
                        resetRevision: notificationResetRevision
                    )
                    .disabled(draft.status != .scheduled)
                    if draft.status == .scheduled, draft.notificationEnabled, draft.notificationValidationMessage() == nil {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            Text(store.selectionNotificationPreview(
                                draft: draft, step: step, previewID: notificationPreviewID,
                                companyID: selectedCompanyID, userID: session.userID,
                                fallback: draft.notificationDescription(now: context.date) ?? "",
                                now: context.date
                            ))
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    if let message = draft.notificationValidationMessage() {
                        Text(message).font(.footnote).foregroundStyle(.red)
                        if draft.notificationTimedCustom?.isValid(hasTime: true) == false
                            || draft.notificationDateCustom?.isValid(hasTime: false) == false {
                            Button("入力途中のカスタム設定を取り消す") {
                                notificationResetRevision += 1
                                if draft.notificationTimedCustom?.isValid(hasTime: true) == false {
                                    draft.notificationTimedCustom = initialDraft.notificationTimedCustom
                                }
                                if draft.notificationDateCustom?.isValid(hasTime: false) == false {
                                    draft.notificationDateCustom = initialDraft.notificationDateCustom
                                }
                            }
                        }
                    }
                } header: {
                    Text("通知")
                } footer: {
                    Text("完了・中止中は通知されません。予定に戻して保存すると、通知設定と日時に応じて通知が再設定されます。")
                }

                Section("メモ（任意）") {
                    TextField("メモを入力", text: $draft.memo, axis: .vertical)
                        .lineLimit(3...8)
                    if InputLimits.length(of: normalizedMemo) > InputLimits.memo {
                        Text("メモは\(InputLimits.memo)文字以内で入力してください。")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if step != nil {
                    Section {
                        Picker("状態", selection: $draft.status) {
                            ForEach(SelectionStepStatus.allCases) { status in
                                Text(status.title).tag(status)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    } footer: {
                        Text("状態の変更は保存すると反映されます。")
                    }

                    Section {
                        Button("選考を削除", role: .destructive) {
                            confirmsDeletion = true
                        }
                        .disabled(store.isSaving)
                    }
                }
            }
            .navigationTitle(step == nil ? "選考を追加" : "選考を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        guard !store.isSaving else { return }
                        if hasUnsavedChanges { confirmsDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        SaveButtonLabel(isSaving: store.isSaving)
                    }
                    .disabled(isInvalid || store.isSaving)
                }
            }
            .disabled(store.isSaving)
            .scrollDismissesKeyboard(.interactively)
            .alert("選考を削除しますか？", isPresented: $confirmsDeletion) {
                Button("削除", role: .destructive) {
                    Task { await deleteStep() }
                }
                .disabled(store.isSaving)
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この操作は取り消せません。")
            }
            .recruitErrorAlert(store: store)
        }
        .interactiveDismissDisabled(store.isSaving || hasUnsavedChanges)
        .alert("変更を破棄しますか？", isPresented: $confirmsDiscard) {
            Button("変更を破棄", role: .destructive) {
                guard !store.isSaving else { return }
                dismiss()
            }
            .disabled(store.isSaving)
            Button("編集を続ける", role: .cancel) {}
        } message: {
            Text("保存していない変更は失われます。")
        }
    }

    private var hasUnsavedChanges: Bool {
        selectedCompanyID != initialCompanyID || draft.hasChanges(comparedTo: initialDraft)
    }

    private var isInvalid: Bool {
        !draft.isValidRange()
            || draft.notificationValidationMessage() != nil
            || selectedCompanyID == nil
            || (draft.type == .other && normalizedCustomTitle.isEmpty)
            || InputLimits.length(of: normalizedCustomTitle) > InputLimits.selectionTitle
            || InputLimits.length(of: normalizedMemo) > InputLimits.memo
    }

    private var normalizedCustomTitle: String {
        draft.customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedMemo: String {
        draft.memo.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() async {
        guard !store.isSaving, !isInvalid else { return }
        if let step {
            if await store.updateSelectionStep(step, draft: draft) != nil { dismiss() }
        } else if let userID = session.userID,
                  let companyID = selectedCompanyID,
                  await store.createSelectionStep(userID: userID, companyID: companyID, draft: draft) != nil {
            dismiss()
        }
    }

    private func deleteStep() async {
        guard !store.isSaving, let step else { return }
        if await store.deleteSelectionStep(step) {
            // The presentation owner closes the entire stack after deletion.
            // Standalone editors close themselves. Never request both dismissals.
            if let onDeleted { onDeleted() } else { dismiss() }
        }
    }
}

extension SelectionStepDraft {
    /// Compare the calendar fields the editor exposes, ignoring hidden time/seconds.
    func hasChanges(comparedTo initial: SelectionStepDraft, calendar: Calendar = .current) -> Bool {
        let sameDate = hasTime
            ? calendar.isDate(date, equalTo: initial.date, toGranularity: .minute)
            : calendar.isDate(date, inSameDayAs: initial.date)
        let sameEnd = hasTime
            ? calendar.isDate(endDate, equalTo: initial.endDate, toGranularity: .minute)
            : calendar.isDate(endDate, inSameDayAs: initial.endDate)
        let endChanged = dateKind == .schedule && (hasEnd != initial.hasEnd || (hasEnd && !sameEnd))
        return endChanged || type != initial.type
            || customTitle != initial.customTitle
            || dateKind != initial.dateKind
            || hasTime != initial.hasTime
            || !sameDate
            || status != initial.status
            || memo != initial.memo
            || notificationEnabled != initial.notificationEnabled
            || notificationTimedPreset != initial.notificationTimedPreset
            || notificationDatePreset != initial.notificationDatePreset
            || notificationTimedCustom != initial.notificationTimedCustom
            || notificationDateCustom != initial.notificationDateCustom
    }
}
