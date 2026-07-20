import SwiftUI
import UIKit

struct ESTemplatesView: View {
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    @State private var searchText = ""
    @State private var creatingCategory: ESTemplateCategory?
    @State private var editingTemplate: ESTemplate?
    @State private var deletingTemplate: ESTemplate?
    @State private var copiedTemplate: ESTemplate?

    var body: some View {
        Group {
            if store.esTemplates.isEmpty {
                emptyState
            } else if filteredTemplates.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    ForEach(nonEmptyCategories) { category in
                        Section(category.title) {
                            ForEach(filteredTemplates.filter { $0.category == category }) { template in
                                HStack(alignment: .center, spacing: 8) {
                                    Button { editingTemplate = template } label: {
                                        ESTemplateRow(template: template)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        copy(template)
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .frame(width: 44, height: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("本文をコピー")
                                }
                                .swipeActions {
                                    Button("削除", role: .destructive) { deletingTemplate = template }
                                    Button("コピー", systemImage: "doc.on.doc") { copy(template) }
                                        .tint(.blue)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("ESテンプレート")
        .navigationBarTitleDisplayMode(.inline)
        .searchableWhen(
            store.esTemplates.isEmpty == false,
            text: $searchText,
            prompt: "タイトル・本文を検索"
        )
        .refreshable {
            if let userID = session.userID {
                await store.reload(userID: userID, force: true)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { addMenu }
        }
        .overlay(alignment: .bottom) {
            if let copiedTemplate {
                Label("「\(copiedTemplate.title)」をコピーしました", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: $creatingCategory) { category in
            ESTemplateEditorView(category: category)
        }
        .sheet(item: $editingTemplate) { template in
            ESTemplateEditorView(template: template)
        }
        .alert(
            "テンプレートを削除しますか？",
            isPresented: Binding(
                get: { deletingTemplate != nil },
                set: { if $0 == false { deletingTemplate = nil } }
            )
        ) {
            Button("削除", role: .destructive) {
                guard let deletingTemplate else { return }
                Task {
                    if await store.deleteESTemplate(deletingTemplate) {
                        self.deletingTemplate = nil
                    }
                }
            }
            Button("キャンセル", role: .cancel) { deletingTemplate = nil }
        } message: {
            Text("この操作は取り消せません。")
        }
        .recruitErrorAlert(store: store)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("ESの文章を再利用しましょう", systemImage: "doc.on.doc")
        } description: {
            Text("ガクチカや自己PRを保存すると、応募先に合わせてすぐ利用できます。")
        } actions: {
            addMenu.buttonStyle(.borderedProminent)
        }
    }

    private var filteredTemplates: [ESTemplate] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return store.esTemplates }
        return store.esTemplates.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.body.localizedCaseInsensitiveContains(query)
                || $0.category.title.localizedCaseInsensitiveContains(query)
        }
    }

    private var nonEmptyCategories: [ESTemplateCategory] {
        ESTemplateCategory.allCases.filter { category in
            filteredTemplates.contains { $0.category == category }
        }
    }

    private var addMenu: some View {
        Menu {
            ForEach(ESTemplateCategory.allCases) { category in
                Button(category.title, systemImage: category.systemImage) {
                    creatingCategory = category
                }
            }
        } label: {
            Label("テンプレートを追加", systemImage: "plus")
        }
    }

    private func copy(_ template: ESTemplate) {
        UIPasteboard.general.string = template.body
        withAnimation(.snappy) { copiedTemplate = template }
        UIAccessibility.post(notification: .announcement, argument: "本文をコピーしました")
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard copiedTemplate?.id == template.id else { return }
            withAnimation(.snappy) { copiedTemplate = nil }
        }
    }
}

private struct ESTemplateRow: View {
    let template: ESTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(template.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(template.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Text("\(InputLimits.length(of: template.body))文字")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .fullWidthTappableArea()
        .accessibilityElement(children: .combine)
    }
}
