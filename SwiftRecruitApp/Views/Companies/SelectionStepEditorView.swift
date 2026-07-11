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
                    Toggle("予定を設定", isOn: $draft.hasStartsAt.animation())
                    if draft.hasStartsAt {
                        DatePicker("日付", selection: $draft.startsAt, displayedComponents: .date)
                        Toggle("時刻も指定", isOn: $draft.startsHasTime.animation())
                        if draft.startsHasTime {
                            DatePicker("時刻", selection: $draft.startsAt, displayedComponents: .hourAndMinute)
                        }
                    }

                    Toggle("締切を設定", isOn: $draft.hasDeadline.animation())
                    if draft.hasDeadline {
                        DatePicker("日付", selection: $draft.deadlineAt, displayedComponents: .date)
                        Toggle("時刻も指定", isOn: $draft.deadlineHasTime.animation())
                        if draft.deadlineHasTime {
                            DatePicker("時刻", selection: $draft.deadlineAt, displayedComponents: .hourAndMinute)
                        }
                    }
                }

                Section("通知") {
                    Toggle("通知する", isOn: $draft.notificationEnabled)
                        .disabled(draft.status != .scheduled)
                    if draft.status != .scheduled {
                        Text("予定の選考だけ通知できます。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if draft.notificationEnabled, let notificationDescription {
                        Text(notificationDescription)
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

    private var notificationDescription: String? {
        var timings: [String] = []
        if draft.hasStartsAt {
            timings.append(draft.startsHasTime ? "予定時刻の1時間前" : "予定日の9時")
        }
        if draft.hasDeadline {
            timings.append("締切前日の20時")
        }
        guard timings.isEmpty == false else { return nil }
        return "\(timings.joined(separator: "、"))に通知します。"
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
