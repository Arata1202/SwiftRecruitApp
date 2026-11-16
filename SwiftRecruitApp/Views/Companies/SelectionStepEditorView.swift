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
    @State private var calendarBusy = false
    @State private var calendarRevision = 0

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

                    if draft.type == .other {
                        TextField("選考名を入力", text: $draft.customTitle)
                        if InputLimits.length(of: normalizedCustomTitle) > InputLimits.selectionTitle {
                            Text("選考名は\(InputLimits.selectionTitle)文字以内で入力してください。")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }

                    Picker("状態", selection: $draft.status) {
                        ForEach(SelectionStepStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("日程") {
                    Picker("日程種別", selection: $draft.dateKind) {
                        ForEach(SelectionDateKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    DatePicker("日付", selection: $draft.date, displayedComponents: .date)
                    Toggle("時刻も指定", isOn: $draft.hasTime.animation())
                    if draft.hasTime {
                        DatePicker("時刻", selection: $draft.date, displayedComponents: .hourAndMinute)
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
                    TextField("メモを入力", text: $draft.memo, axis: .vertical)
                        .lineLimit(3...8)
                    if InputLimits.length(of: normalizedMemo) > InputLimits.memo {
                        Text("メモは\(InputLimits.memo)文字以内で入力してください。")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section("Appleカレンダー") {
                    if let step, let saved = store.selectionSteps.first(where: { $0.id == step.id }) {
                        if saved.startDate() != nil { calendarRow(saved, kind: .start) }
                        if saved.deadlineDate() != nil { calendarRow(saved, kind: .deadline) }
                        if saved.startDate() == nil && saved.deadlineDate() == nil {
                            Text("保存済みの日程がありません。")
                        }
                        Text("操作には保存済みの内容を使います。編集中の変更は保存後に反映されます。")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text(step == nil ? "保存後にカレンダーへ追加できます。" : "保存済みの選考が見つかりません。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .id(calendarRevision)

                if step != nil {
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
                        .disabled(store.isSaving || calendarBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        SaveButtonLabel(isSaving: store.isSaving)
                    }
                    .disabled(isInvalid || store.isSaving || calendarBusy)
                }
            }
            .disabled(store.isSaving || calendarBusy)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: draft.status) { _, status in
                if status != .scheduled { draft.notificationEnabled = false }
            }
            .onChange(of: draft.type) { _, type in
                draft.dateKind = type.defaultDateKind
            }
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
        .interactiveDismissDisabled(store.isSaving || calendarBusy)
    }

    private func calendarRow(_ saved: SelectionStep, kind: SelectionMilestoneKind) -> some View {
        let exported = store.isSelectionExported(id: saved.id, kind: kind)
        return HStack {
            Text("保存済みの\(kind.title)：\(exported ? "追加済み" : "未追加")")
            Spacer()
            Button(exported ? "削除" : "追加") {
                calendarBusy = true
                Task {
                    if exported { _ = await store.removeSelectionFromAppleCalendar(id: saved.id, kind: kind) }
                    else { _ = await store.exportSelection(saved, kind: kind) }
                    calendarRevision += 1
                    calendarBusy = false
                }
            }
            .disabled(calendarBusy || (!exported && saved.status == .cancelled))
            .accessibilityLabel("\(kind.title)をカレンダー\(exported ? "から削除" : "に追加")")
        }
    }

    private var isInvalid: Bool {
        selectedCompanyID == nil
            || (
                draft.type == .other
                    && (
                        normalizedCustomTitle.isEmpty
                            || InputLimits.length(of: normalizedCustomTitle) > InputLimits.selectionTitle
                    )
            )
            || InputLimits.length(of: normalizedMemo) > InputLimits.memo
    }

    private var normalizedCustomTitle: String {
        draft.customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedMemo: String {
        draft.memo.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var notificationDescription: String? {
        var timings: [String] = []
        if draft.dateKind == .deadline {
            timings.append("締切前日の20時")
        } else {
            timings.append(draft.hasTime ? "予定時刻の1時間前" : "予定日の9時")
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

    private func deleteStep() async {
        guard let step else { return }
        if await store.deleteSelectionStep(step) { dismiss() }
    }
}
