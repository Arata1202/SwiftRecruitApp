import SwiftUI

struct CompanyInformationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    let companyID: UUID
    let item: CompanyInformationItem?
    @State private var draft: CompanyInformationDraft

    init(
        companyID: UUID,
        category: CompanyInformationCategory = .research,
        item: CompanyInformationItem? = nil
    ) {
        self.companyID = companyID
        self.item = item
        _draft = State(initialValue: item.map(CompanyInformationDraft.init) ?? CompanyInformationDraft(category: category))
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
                    TextField("タイトル", text: $draft.title)
                    if InputLimits.length(of: normalizedTitle) > InputLimits.companyInformationTitle {
                        validationText("タイトルは\(InputLimits.companyInformationTitle)文字以内で入力してください。")
                    }

                    TextField("内容を入力", text: $draft.body, axis: .vertical)
                        .lineLimit(6...16)
                    if InputLimits.length(of: normalizedBody) > InputLimits.companyInformationBody {
                        validationText("内容は\(InputLimits.companyInformationBody)文字以内で入力してください。")
                    }
                }

                Section("日付（任意）") {
                    Toggle("日付を記録", isOn: $draft.hasDate.animation())
                    if draft.hasDate {
                        DatePicker("日付", selection: $draft.date, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle(item == nil ? "記録を追加" : "記録を編集")
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
            .onChange(of: draft.category) { oldCategory, newCategory in
                if normalizedTitle.isEmpty || normalizedTitle == oldCategory.title {
                    draft.title = newCategory.title
                }
                if newCategory == .interview && item == nil { draft.hasDate = true }
            }
            .recruitErrorAlert(store: store)
        }
        .interactiveDismissDisabled(store.isSaving)
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
}
