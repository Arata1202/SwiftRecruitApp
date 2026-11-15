import SwiftUI

struct CompanyInformationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    let companyID: UUID
    let item: CompanyInformationItem?
    @State private var draft: CompanyInformationDraft
    @State private var initialDraft: CompanyInformationDraft
    @State private var confirmsDiscard = false
    @State private var confirmsDeletion = false

    init(
        companyID: UUID,
        category: CompanyInformationCategory = .research,
        item: CompanyInformationItem? = nil
    ) {
        self.companyID = companyID
        self.item = item
        let initialDraft = item.map(CompanyInformationDraft.init) ?? CompanyInformationDraft(category: category)
        _draft = State(initialValue: initialDraft)
        _initialDraft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("種類") {
                    Picker("種類", selection: $draft.category) {
                        ForEach(CompanyInformationCategory.allCases) { category in
                            Label(category.title, systemImage: category.systemImage).tag(category)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("内容") {
                    TextField(
                        "タイトル",
                        text: $draft.title,
                        prompt: Text(draft.category.titlePlaceholder)
                    )
                    if InputLimits.length(of: normalizedTitle) > InputLimits.companyInformationTitle {
                        validationText("タイトルは\(InputLimits.companyInformationTitle)文字以内で入力してください。")
                    }

                    TextField("内容を入力", text: $draft.body, axis: .vertical)
                        .lineLimit(6...16)
                    if InputLimits.length(of: normalizedBody) > InputLimits.companyInformationBody {
                        validationText("内容は\(InputLimits.companyInformationBody)文字以内で入力してください。")
                    }
                }

                if showsDateSection {
                    Section(draft.category == .interview ? "面接日" : "記録日（任意）") {
                        Toggle(
                            draft.category == .interview ? "面接日を記録" : "日付を記録",
                            isOn: $draft.hasDate.animation()
                        )
                        if draft.hasDate {
                            DatePicker("日付", selection: $draft.date, displayedComponents: .date)
                        }
                    }
                }

                if item != nil {
                    Section {
                        Button("記録を削除", role: .destructive) {
                            confirmsDeletion = true
                        }
                    }
                }
            }
            .navigationTitle(item == nil ? "記録を追加" : "記録を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        if hasUnsavedChanges {
                            confirmsDiscard = true
                        } else {
                            dismiss()
                        }
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
            .onChange(of: draft.category) { _, newCategory in
                guard item == nil else { return }
                draft.hasDate = newCategory == .interview
            }
            .alert("記録を削除しますか？", isPresented: $confirmsDeletion) {
                Button("削除", role: .destructive) {
                    Task { await deleteItem() }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この操作は取り消せません。")
            }
            .recruitErrorAlert(store: store)
        }
        .interactiveDismissDisabled(store.isSaving || hasUnsavedChanges)
        .alert("変更を破棄しますか？", isPresented: $confirmsDiscard) {
            Button("変更を破棄", role: .destructive) { dismiss() }
            Button("編集を続ける", role: .cancel) {}
        } message: {
            Text("保存していない変更は失われます。")
        }
    }

    private var hasUnsavedChanges: Bool {
        draft.hasChanges(comparedTo: initialDraft)
    }

    private var normalizedTitle: String {
        draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedBody: String {
        draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isInvalid: Bool {
        normalizedTitle.isEmpty
            || normalizedBody.isEmpty
            || InputLimits.length(of: normalizedTitle) > InputLimits.companyInformationTitle
            || InputLimits.length(of: normalizedBody) > InputLimits.companyInformationBody
    }

    private var showsDateSection: Bool {
        draft.category == .interview || item?.occurredOn != nil
    }

    private func validationText(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(.red)
    }

    private func save() async {
        if let item {
            if await store.updateCompanyInformationItem(item, draft: draft) != nil { dismiss() }
        } else if let userID = session.userID,
                  await store.createCompanyInformationItem(
                    userID: userID,
                    companyID: companyID,
                    draft: draft
                  ) != nil {
            dismiss()
        }
    }

    private func deleteItem() async {
        guard let item else { return }
        if await store.deleteCompanyInformationItem(item) { dismiss() }
    }
}
