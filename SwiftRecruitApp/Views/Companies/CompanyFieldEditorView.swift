import SwiftUI

enum CompanyEditableField: String, Identifiable {
    case name
    case url
    case memo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "企業名"
        case .url: "採用ページURL"
        case .memo: "メモ"
        }
    }
}

struct CompanyFieldEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RecruitStore.self) private var store

    let companyID: UUID
    let field: CompanyEditableField
    @State private var value: String
    @FocusState private var isFocused: Bool

    init(company: Company, field: CompanyEditableField) {
        companyID = company.id
        self.field = field
        let initialValue: String
        switch field {
        case .name:
            initialValue = company.name
        case .url:
            initialValue = company.url ?? ""
        case .memo:
            initialValue = company.memo ?? ""
        }
        _value = State(initialValue: initialValue)
    }

    var body: some View {
        Form {
            Section(field.title) {
                fieldInput
                if let validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("\(field.title)を編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button { Task { await save() } } label: {
                    SaveButtonLabel(isSaving: store.isSaving)
                }
                .disabled(validationMessage != nil || store.isSaving)
            }
        }
        .disabled(store.isSaving)
        .scrollDismissesKeyboard(.interactively)
        .task { isFocused = true }
        .recruitErrorAlert(store: store)
    }

    @ViewBuilder
    private var fieldInput: some View {
        switch field {
        case .name:
            TextField("企業名", text: $value)
                .focused($isFocused)
        case .url:
            TextField("https://example.com", text: $value)
                .focused($isFocused)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        case .memo:
            TextField("メモを入力", text: $value, axis: .vertical)
                .focused($isFocused)
                .lineLimit(3...8)
        }
    }

    private var validationMessage: String? {
        switch field {
        case .name:
            let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { return "企業名を入力してください。" }
            if name.count > 120 { return "企業名は120文字以内で入力してください。" }
            return nil
        case .url:
            return WebURLNormalizer.isValidOrEmpty(value)
                ? nil
                : "有効なWebサイトのURLを入力してください。"
        case .memo:
            return nil
        }
    }

    private func save() async {
        guard let company = store.company(id: companyID) else { return }

        var draft = CompanyDraft(company: company)
        switch field {
        case .name: draft.name = value
        case .url: draft.url = value
        case .memo: draft.memo = value
        }

        if await store.updateCompany(company, draft: draft) != nil {
            dismiss()
        }
    }
}
