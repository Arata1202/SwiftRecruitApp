import SwiftUI

struct CompanyEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    let company: Company?
    let onSaved: ((Company) -> Void)?
    @State private var draft: CompanyDraft
    @State private var initialDraft: CompanyDraft
    @State private var confirmsDiscard = false

    init(company: Company? = nil, onSaved: ((Company) -> Void)? = nil) {
        self.company = company
        self.onSaved = onSaved
        let initialDraft = company.map(CompanyDraft.init) ?? CompanyDraft()
        _draft = State(initialValue: initialDraft)
        _initialDraft = State(initialValue: initialDraft)
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

                    NavigationLink {
                        CompanyDraftStatusSelectionView(selection: $draft.status)
                    } label: {
                        HStack {
                            Text("ステータス")
                            Spacer()
                            CompanyStatusBadge(status: draft.status)
                        }
                    }
                }

                Section("情報（任意）") {
                    TextField("企業サイトURLを入力", text: $draft.url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !isURLValid {
                        Text("有効なWebサイトのURLを入力してください。")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    } else if !isURLUnchanged && normalizedURLLength > InputLimits.webURL {
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
                    Button("キャンセル") {
                        guard !store.isSaving else { return }
                        if hasUnsavedChanges { confirmsDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        SaveButtonLabel(isSaving: store.isSaving)
                    }
                    .disabled(
                        normalizedName.isEmpty
                            || InputLimits.length(of: normalizedName) > InputLimits.companyName
                            || !isURLValid
                            || !isURLUnchanged && normalizedURLLength > InputLimits.webURL
                            || InputLimits.length(of: normalizedMemo) > InputLimits.memo
                            || store.isSaving
                    )
                }
            }
            .disabled(store.isSaving)
            .scrollDismissesKeyboard(.interactively)
            .recruitErrorAlert(store: store)
        }
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

    private var hasUnsavedChanges: Bool {
        draft.hasChanges(comparedTo: initialDraft)
    }

    private var normalizedName: String {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isURLUnchanged: Bool { company != nil && draft.url == company?.url }

    private var isURLValid: Bool { isURLUnchanged || WebURLNormalizer.isValidOrEmpty(draft.url) }

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
        guard !store.isSaving else { return }
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

private struct CompanyDraftStatusSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: CompanyStatus

    var body: some View {
        List(CompanyStatus.allCases) { status in
            Button {
                selection = status
                dismiss()
            } label: {
                HStack {
                    CompanyStatusBadge(status: status)
                    Spacer()
                    if status == selection {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .fullWidthTappableArea()
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(status == selection ? .isSelected : [])
        }
        .navigationTitle("ステータス")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension CompanyDraft {
    func hasChanges(comparedTo initial: CompanyDraft) -> Bool {
        name != initial.name || status != initial.status || url != initial.url || memo != initial.memo
    }
}
