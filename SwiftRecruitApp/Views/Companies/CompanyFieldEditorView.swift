import SwiftUI

enum CompanyEditableField: String, Identifiable {
    case name
    case url
    case memo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "企業名"
        case .url: "企業サイトURL"
        case .memo: "メモ"
        }
    }
}

struct CompanyFieldEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RecruitStore.self) private var store
    @Environment(AppSession.self) private var session

    let companyID: UUID
    let field: CompanyEditableField
    @State private var originalCompany: Company
    @State private var value: String
    @State private var initialValue: String
    @State private var confirmsDiscard = false
    @FocusState private var isFocused: Bool

    init(company: Company, field: CompanyEditableField) {
        companyID = company.id
        _originalCompany = State(initialValue: company)
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
        _initialValue = State(initialValue: initialValue)
    }

    var body: some View {
        Form {
            RecruitSection(LocalizedStringKey(field.title)) {
                fieldInput
                if let validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(RecruitTextColor.red)
                }
            }
        }
        .navigationTitle(field.title)
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
                .disabled(validationMessage != nil || store.isSaving)
            }
        }
        .disabled(store.isSaving)
        .scrollDismissesKeyboard(.interactively)
        .task { isFocused = true }
        .recruitErrorAlert(store: store)
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

    private var hasUnsavedChanges: Bool { value != initialValue }

    @ViewBuilder
    private var fieldInput: some View {
        switch field {
        case .name:
            TextField("企業名を入力", text: $value)
                .focused($isFocused)
        case .url:
            TextField("企業サイトURLを入力", text: $value)
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
            if InputLimits.length(of: name) > InputLimits.companyName {
                return "企業名は\(InputLimits.companyName)文字以内で入力してください。"
            }
            return nil
        case .url:
            guard WebURLNormalizer.isValidOrEmpty(value) else {
                return "有効なWebサイトのURLを入力してください。"
            }
            let length = InputLimits.length(
                of: WebURLNormalizer.normalizedString(from: value)
                    ?? value.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            return length <= InputLimits.webURL
                ? nil
                : "URLは\(InputLimits.webURL)文字以内で入力してください。"
        case .memo:
            return InputLimits.length(
                of: value.trimmingCharacters(in: .whitespacesAndNewlines)
            ) <= InputLimits.memo
                ? nil
                : "メモは\(InputLimits.memo)文字以内で入力してください。"
        }
    }

    private func save() async {
        guard !store.isSaving,
              session.userID == originalCompany.userID,
              store.loadedUserID == originalCompany.userID,
              store.company(id: companyID) != nil else { return }
        // Keep the version that the user started editing, even after a refresh.
        let company = originalCompany

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
