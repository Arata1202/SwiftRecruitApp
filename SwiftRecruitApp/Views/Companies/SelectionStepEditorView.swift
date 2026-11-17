import SwiftUI

struct SelectionStepEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    let step: SelectionStep?
    let fixedCompanyID: UUID?
    @State private var selectedCompanyID: UUID?
    @State private var draft: SelectionStepDraft
    @State private var confirmsDeletion = false

    init(companyID: UUID? = nil, step: SelectionStep? = nil, initialDate: Date? = nil) {
        self.step = step
        fixedCompanyID = step?.companyID ?? companyID
        _selectedCompanyID = State(initialValue: step?.companyID ?? companyID)
        _draft = State(
            initialValue: step.map(SelectionStepDraft.init)
                ?? initialDate.map { SelectionStepDraft(date: $0) }
                ?? SelectionStepDraft()
        )
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
                            Label(type.title, systemImage: type.systemImage).tag(type)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    TextField(
                        draft.type == .other ? "選考名（必須）" : "補足名（任意・例：一次）",
                        text: $draft.customTitle
                    )
                    if InputLimits.length(of: normalizedCustomTitle) > InputLimits.selectionTitle {
                        Text("選考名は\(InputLimits.selectionTitle)文字以内で入力してください。")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section("日程") {
                    Picker("日程種別", selection: $draft.dateKind) {
                        ForEach(SelectionDateKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    DatePicker("日付", selection: $draft.date, displayedComponents: .date)
                    Toggle("時刻も指定", isOn: Binding(
                        get: { draft.hasTime },
                        set: { draft.setHasTime($0) }
                    ).animation())
                    if draft.hasTime {
                        DatePicker("時刻", selection: $draft.date, displayedComponents: .hourAndMinute)
                    }
                }

                Section {
                    Toggle("通知する", isOn: $draft.notificationEnabled)
                        .disabled(draft.status != .scheduled)
                    if draft.status == .scheduled, draft.notificationEnabled, let notificationDescription {
                        Text(notificationDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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
                        LabeledContent("状態", value: draft.status.title)
                        if draft.status == .scheduled {
                            Button("選考を中止", role: .destructive) {
                                draft.status = .cancelled
                            }
                        } else if draft.status == .cancelled {
                            Button("予定に戻す") {
                                draft.status = .scheduled
                            }
                        }
                    } footer: {
                        Text("状態の変更は保存すると反映されます。")
                    }

                    Section {
                        Button("選考を削除", role: .destructive) {
                            confirmsDeletion = true
                        }
                    }
                }
            }
            .navigationTitle(step == nil ? "選考を追加" : "選考を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
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
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この操作は取り消せません。")
            }
            .recruitErrorAlert(store: store)
        }
        .interactiveDismissDisabled(store.isSaving)
    }

    private var isInvalid: Bool {
        selectedCompanyID == nil
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

    private var notificationDescription: String? {
        draft.notificationDescription()
    }

    private func save() async {
        if let step {
            if await store.updateSelectionStep(step, draft: draft) != nil { dismiss() }
        } else if let userID = session.userID,
                  let companyID = selectedCompanyID,
                  await store.createSelectionStep(userID: userID, companyID: companyID, draft: draft) != nil {
            dismiss()
        }
    }

    private func deleteStep() async {
        guard let step else { return }
        if await store.deleteSelectionStep(step) { dismiss() }
    }
}
