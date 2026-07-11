import SwiftUI

struct SelectionStepEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    let step: SelectionStep?
    let fixedCompanyID: UUID?
    @State private var selectedCompanyID: UUID?
    @State private var draft: SelectionStepDraft

    init(companyID: UUID? = nil, step: SelectionStep? = nil) {
        self.step = step
        fixedCompanyID = step?.companyID ?? companyID
        _selectedCompanyID = State(initialValue: step?.companyID ?? companyID)
        _draft = State(initialValue: step.map(SelectionStepDraft.init) ?? SelectionStepDraft())
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

                    if draft.type == .other {
                        TextField("選考名を入力", text: $draft.customTitle)
                    }

                    Picker("状態", selection: $draft.status) {
                        ForEach(SelectionStepStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("日時") {
                    Toggle("開始日時を設定", isOn: $draft.hasStartsAt.animation())
                    if draft.hasStartsAt {
                        DatePicker("開始", selection: $draft.startsAt)
                    }

                    Toggle("締切日時を設定", isOn: $draft.hasDeadline.animation())
                    if draft.hasDeadline {
                        DatePicker("締切", selection: $draft.deadlineAt)
                    }
                }

                Section("通知") {
                    Toggle("通知する", isOn: $draft.notificationEnabled)
                        .disabled(draft.status != .scheduled)
                    if draft.status != .scheduled {
                        Text("予定の選考だけ通知できます。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if draft.notificationEnabled {
                        Text("開始は1時間前、締切は前日の20時に通知します。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("メモ（任意）") {
                    TextField("内容を入力", text: $draft.memo, axis: .vertical)
                        .lineLimit(3...8)
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
            .onChange(of: draft.status) { _, status in
                if status != .scheduled { draft.notificationEnabled = false }
            }
            .recruitErrorAlert(store: store)
        }
        .interactiveDismissDisabled(store.isSaving)
    }

    private var isInvalid: Bool {
        selectedCompanyID == nil
            || (draft.type == .other && draft.customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            || (draft.hasStartsAt == false && draft.hasDeadline == false)
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
}
