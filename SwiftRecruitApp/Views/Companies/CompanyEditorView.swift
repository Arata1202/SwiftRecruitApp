import SwiftUI

struct CompanyEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    let company: Company?
    let onSaved: ((Company) -> Void)?
    @State private var draft: CompanyDraft

    init(company: Company? = nil, onSaved: ((Company) -> Void)? = nil) {
        self.company = company
        self.onSaved = onSaved
        _draft = State(initialValue: company.map(CompanyDraft.init) ?? CompanyDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("企業") {
                    TextField("企業名", text: $draft.name)
                    if normalizedName.count > 120 {
                        Text("企業名は120文字以内で入力してください。")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Picker("志望度", selection: $draft.priority) {
                        ForEach(1...5, id: \.self) { value in
                            Text(String(repeating: "★", count: value)).tag(value)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    Picker("ステータス", selection: $draft.status) {
                        ForEach(CompanyStatus.allCases) { status in
                            Label(status.title, systemImage: status.systemImage).tag(status)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("情報") {
                    TextField("採用ページURL（任意）", text: $draft.url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if WebURLNormalizer.isValidOrEmpty(draft.url) == false {
                        Text("有効なWebサイトのURLを入力してください。")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    TextField("メモ（任意）", text: $draft.memo, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(company == nil ? "企業を追加" : "企業を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        SaveButtonLabel(isSaving: store.isSaving)
                    }
                    .disabled(
                        normalizedName.isEmpty
                            || normalizedName.count > 120
                            || WebURLNormalizer.isValidOrEmpty(draft.url) == false
                            || store.isSaving
                    )
                }
            }
            .disabled(store.isSaving)
            .scrollDismissesKeyboard(.interactively)
            .recruitErrorAlert(store: store)
        }
        .interactiveDismissDisabled(store.isSaving)
    }

    private var normalizedName: String {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() async {
        if let company {
            if let updated = await store.updateCompany(company, draft: draft) {
                onSaved?(updated)
                dismiss()
            }
        } else if let userID = session.userID,
                  let created = await store.createCompany(userID: userID, draft: draft) {
            onSaved?(created)
            dismiss()
        }
    }
}
