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
                    TextField("企業名を入力", text: $draft.name)
                    if InputLimits.length(of: normalizedName) > InputLimits.companyName {
                        Text("企業名は\(InputLimits.companyName)文字以内で入力してください。")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Picker("ステータス", selection: $draft.status) {
                        ForEach(CompanyStatus.allCases) { status in
                            Label(status.title, systemImage: status.systemImage).tag(status)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    Picker("優先度", selection: $draft.priority) {
                        ForEach(1...5, id: \.self) { priority in
                            Text(CompanyPriority.title(for: priority)).tag(priority)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("情報（任意）") {
                    TextField("採用ページURLを入力", text: $draft.url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if WebURLNormalizer.isValidOrEmpty(draft.url) == false {
                        Text("有効なWebサイトのURLを入力してください。")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    } else if normalizedURLLength > InputLimits.webURL {
                        Text("URLは\(InputLimits.webURL)文字以内で入力してください。")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    TextField("メモを入力", text: $draft.memo, axis: .vertical)
                        .lineLimit(3...8)
                    if InputLimits.length(of: normalizedMemo) > InputLimits.memo {
                        Text("メモは\(InputLimits.memo)文字以内で入力してください。")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
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
                            || InputLimits.length(of: normalizedName) > InputLimits.companyName
                            || WebURLNormalizer.isValidOrEmpty(draft.url) == false
                            || normalizedURLLength > InputLimits.webURL
                            || InputLimits.length(of: normalizedMemo) > InputLimits.memo
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

    private var normalizedURLLength: Int {
        InputLimits.length(
            of: WebURLNormalizer.normalizedString(from: draft.url)
                ?? draft.url.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private var normalizedMemo: String {
        draft.memo.trimmingCharacters(in: .whitespacesAndNewlines)
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
