import SwiftUI

struct SelfAnalysisAnswerEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    let answer: SelfAnalysisAnswer?
    @State private var draft: SelfAnalysisAnswerDraft
    @State private var confirmsDeletion = false

    init(category: SelfAnalysisCategory = .values, answer: SelfAnalysisAnswer? = nil) {
        self.answer = answer
        _draft = State(initialValue: answer.map(SelfAnalysisAnswerDraft.init) ?? SelfAnalysisAnswerDraft(category: category))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("テーマ") {
                    Picker("テーマ", selection: $draft.category) {
                        ForEach(SelfAnalysisCategory.allCases) { category in
                            Text(category.title).tag(category)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    TextField(
                        "質問",
                        text: $draft.question,
                        prompt: Text("質問を入力"),
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                    if InputLimits.length(of: normalizedQuestion) > InputLimits.selfAnalysisQuestion {
                        validationText("質問は\(InputLimits.selfAnalysisQuestion)文字以内で入力してください。")
                    }
                }

                Section("回答") {
                    TextField("自分の考えや経験を入力", text: $draft.answer, axis: .vertical)
                        .lineLimit(8...20)
                    HStack {
                        if InputLimits.length(of: normalizedAnswer) > InputLimits.selfAnalysisAnswer {
                            validationText("回答は\(InputLimits.selfAnalysisAnswer)文字以内で入力してください。")
                        }
                        Spacer()
                        Text("\(InputLimits.length(of: normalizedAnswer))文字")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if answer != nil {
                    Section {
                        Button("回答を削除", role: .destructive) {
                            confirmsDeletion = true
                        }
                    }
                }
            }
            .navigationTitle(answer == nil ? "回答を追加" : "回答を編集")
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
                if normalizedQuestion.isEmpty || normalizedQuestion == oldCategory.defaultQuestion {
                    draft.question = newCategory.defaultQuestion
                }
            }
            .alert("回答を削除しますか？", isPresented: $confirmsDeletion) {
                Button("削除", role: .destructive) {
                    Task { await deleteAnswer() }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この操作は取り消せません。")
            }
            .recruitErrorAlert(store: store)
        }
        .interactiveDismissDisabled(store.isSaving)
    }

    private var normalizedQuestion: String {
        draft.question.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedAnswer: String {
        draft.answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isInvalid: Bool {
        normalizedQuestion.isEmpty
            || normalizedAnswer.isEmpty
            || InputLimits.length(of: normalizedQuestion) > InputLimits.selfAnalysisQuestion
            || InputLimits.length(of: normalizedAnswer) > InputLimits.selfAnalysisAnswer
    }

    private func validationText(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(.red)
    }

    private func save() async {
        if let answer {
            if await store.updateSelfAnalysisAnswer(answer, draft: draft) != nil { dismiss() }
        } else if let userID = session.userID,
                  await store.createSelfAnalysisAnswer(userID: userID, draft: draft) != nil {
            dismiss()
        }
    }

    private func deleteAnswer() async {
        guard let answer else { return }
        if await store.deleteSelfAnalysisAnswer(answer) { dismiss() }
    }
}
