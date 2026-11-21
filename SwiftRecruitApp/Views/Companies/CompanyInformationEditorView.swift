import SwiftUI

struct CompanyInformationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    let companyID: UUID
    let item: CompanyInformationItem?
    let onDeleted: (() -> Void)?
    @State private var draft: CompanyInformationDraft
    @State private var initialDraft: CompanyInformationDraft
    @State private var confirmsDiscard = false
    @State private var confirmsDeletion = false
    @State private var isDeleting = false

    init(
        companyID: UUID,
        category: CompanyInformationCategory = .research,
        item: CompanyInformationItem? = nil,
        onDeleted: (() -> Void)? = nil
    ) {
        self.companyID = companyID
        self.item = item
        self.onDeleted = onDeleted
        let initialDraft = item.map(CompanyInformationDraft.init) ?? CompanyInformationDraft(category: category)
        _draft = State(initialValue: initialDraft)
        _initialDraft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            Form {
                RecruitSection("種類") {
                    Picker("種類", selection: $draft.category) {
                        ForEach(CompanyInformationCategory.allCases) { category in
                            Text(category.title).tag(category).foregroundStyle(Color.primary)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                RecruitSection("内容") {
                    TextField("内容を入力", text: $draft.body, axis: .vertical)
                        .lineLimit(6...16)
                    if InputLimits.length(of: normalizedBody) > InputLimits.companyInformationBody {
                        validationText("内容は\(InputLimits.companyInformationBody)文字以内で入力してください。")
                    }
                }

                RecruitSection(draft.category == .interview ? "面接日（任意）" : "記録日（任意）") {
                    Toggle(
                        draft.category == .interview ? "面接日を記録" : "日付を記録",
                        isOn: $draft.hasDate.animation(reduceMotion ? nil : .default)
                    )
                    if draft.hasDate {
                        AdaptiveDatePicker(title: "日付", selection: $draft.date, displayedComponents: .date)
                    }
                }

                if item != nil {
                    Section {
                        DestructiveActionButton("記録を削除") {
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
                        if isDeleting {
                            ProgressView("削除中")
                                .controlSize(.small)
                        } else {
                            SaveButtonLabel(isSaving: store.isSaving)
                        }
                    }
                    .disabled(isInvalid || store.isSaving)
                }
            }
            .disabled(store.isSaving)
            .scrollDismissesKeyboard(.interactively)
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

    private var normalizedBody: String {
        draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isInvalid: Bool {
        normalizedBody.isEmpty
            || InputLimits.length(of: normalizedBody) > InputLimits.companyInformationBody
    }

    private func validationText(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(RecruitTextColor.red)
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
        guard store.isSaving == false, let item else { return }
        isDeleting = true
        defer { isDeleting = false }
        if await store.deleteCompanyInformationItem(item) {
            if let onDeleted { onDeleted() } else { dismiss() }
        }
    }
}
