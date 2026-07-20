import SwiftUI

struct SelfAnalysisAnswersView: View {
    @Environment(RecruitStore.self) private var store

    @State private var creatingCategory: SelfAnalysisCategory?
    @State private var editingAnswer: SelfAnalysisAnswer?
    @State private var deletingAnswer: SelfAnalysisAnswer?

    var body: some View {
        Group {
            if store.selfAnalysisAnswers.isEmpty {
                ContentUnavailableView {
                    Label("自分への質問に答えましょう", systemImage: "person.crop.circle.badge.questionmark")
                } description: {
                    Text("価値観や強みを言葉にすると、企業選びや志望動機の軸が見つかります。")
                } actions: {
                    addMenu.buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(nonEmptyCategories) { category in
                        Section(category.title) {
                            ForEach(store.selfAnalysisAnswers.filter { $0.category == category }) { answer in
                                Button { editingAnswer = answer } label: {
                                    SelfAnalysisAnswerRow(answer: answer)
                                }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button("削除", role: .destructive) { deletingAnswer = answer }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("質問への回答")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { addMenu }
        }
        .sheet(item: $creatingCategory) { SelfAnalysisAnswerEditorView(category: $0) }
        .sheet(item: $editingAnswer) { SelfAnalysisAnswerEditorView(answer: $0) }
        .alert(
            "回答を削除しますか？",
            isPresented: Binding(
                get: { deletingAnswer != nil },
                set: { if $0 == false { deletingAnswer = nil } }
            )
        ) {
            Button("削除", role: .destructive) {
                guard let deletingAnswer else { return }
                Task {
                    if await store.deleteSelfAnalysisAnswer(deletingAnswer) {
                        self.deletingAnswer = nil
                    }
                }
            }
            Button("キャンセル", role: .cancel) { deletingAnswer = nil }
        } message: {
            Text("この操作は取り消せません。")
        }
        .recruitErrorAlert(store: store)
    }

    private var nonEmptyCategories: [SelfAnalysisCategory] {
        SelfAnalysisCategory.allCases.filter { category in
            store.selfAnalysisAnswers.contains { $0.category == category }
        }
    }

    private var addMenu: some View {
        Menu {
            ForEach(SelfAnalysisCategory.allCases) { category in
                Button(category.title) { creatingCategory = category }
            }
        } label: {
            Label("回答を追加", systemImage: "plus")
        }
    }
}

private struct SelfAnalysisAnswerRow: View {
    let answer: SelfAnalysisAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(answer.question)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(answer.answer)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
        .padding(.vertical, 4)
        .fullWidthTappableArea()
        .accessibilityElement(children: .combine)
    }
}
