import SwiftUI

struct ESTemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    let template: ESTemplate?
    @State private var draft: ESTemplateDraft
    @State private var confirmsDeletion = false

    init(category: ESTemplateCategory = .studentExperience, template: ESTemplate? = nil) {
        self.template = template
        _draft = State(initialValue: template.map(ESTemplateDraft.init) ?? ESTemplateDraft(category: category))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("種類") {
                    Picker("種類", selection: $draft.category) {
                        ForEach(ESTemplateCategory.allCases) { category in
                            Label(category.title, systemImage: category.systemImage).tag(category)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("テンプレート") {
                    TextField(
                        "タイトル",
                        text: $draft.title,
                        prompt: Text(draft.category.titlePlaceholder)
                    )
                    if InputLimits.length(of: normalizedTitle) > InputLimits.esTemplateTitle {
                        validationText(
                            "タイトルは\(InputLimits.esTemplateTitle)文字以内で入力してください。"
                        )
                    }

                    TextField("本文を入力", text: $draft.body, axis: .vertical)
                        .lineLimit(10...24)
                    HStack {
                        if InputLimits.length(of: normalizedBody) > InputLimits.esTemplateBody {
                            validationText(
                                "本文は\(InputLimits.esTemplateBody)文字以内で入力してください。"
                            )
                        }
                        Spacer()
                        Text("\(InputLimits.length(of: normalizedBody))文字")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if template != nil {
                    Section {
                        Button("テンプレートを削除", role: .destructive) {
                            confirmsDeletion = true
                        }
                    }
                }
            }
            .navigationTitle(template == nil ? "テンプレートを追加" : "テンプレートを編集")
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
            .alert("テンプレートを削除しますか？", isPresented: $confirmsDeletion) {
                Button("削除", role: .destructive) {
                    Task { await deleteTemplate() }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この操作は取り消せません。")
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
            || InputLimits.length(of: normalizedTitle) > InputLimits.esTemplateTitle
            || InputLimits.length(of: normalizedBody) > InputLimits.esTemplateBody
    }

    private func validationText(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(.red)
    }

    private func save() async {
        if let template {
            if await store.updateESTemplate(template, draft: draft) != nil { dismiss() }
        } else if let userID = session.userID,
                  await store.createESTemplate(userID: userID, draft: draft) != nil {
            dismiss()
        }
    }

    private func deleteTemplate() async {
        guard let template else { return }
        if await store.deleteESTemplate(template) { dismiss() }
    }
}
