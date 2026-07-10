import SwiftUI

struct CompanyEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    let company: Company?
    @State private var draft: CompanyDraft

    init(company: Company? = nil) {
        self.company = company
        _draft = State(initialValue: company.map(CompanyDraft.init) ?? CompanyDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("企業") {
                    TextField("企業名", text: $draft.name)
                        .textInputAutocapitalization(.never)

                    Picker("志望度", selection: $draft.priority) {
                        ForEach(1...5, id: \.self) { value in
                            Text(String(repeating: "★", count: value)).tag(value)
                        }
                    }

                    Picker("ステータス", selection: $draft.status) {
                        ForEach(CompanyStatus.allCases) { status in
                            Label(status.title, systemImage: status.systemImage).tag(status)
                        }
                    }
                }

                Section("情報") {
                    TextField("採用ページURL（任意）", text: $draft.url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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
                    Button("保存") { Task { await save() } }
                        .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSaving)
                }
            }
            .disabled(store.isSaving)
            .recruitErrorAlert(store: store)
        }
    }

    private func save() async {
        if let company {
            if await store.updateCompany(company, draft: draft) != nil { dismiss() }
        } else if let userID = session.userID,
                  await store.createCompany(userID: userID, draft: draft) != nil {
            dismiss()
        }
    }
}

