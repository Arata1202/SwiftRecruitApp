import SwiftUI

struct CompanyInformationView: View {
    @Environment(RecruitStore.self) private var store

    let companyID: UUID
    @State private var creatingCategory: CompanyInformationCategory?
    @State private var editingItem: CompanyInformationItem?
    @State private var deletingItem: CompanyInformationItem?

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView {
                    Label("企業情報を整理しましょう", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("企業研究、志望理由、面接記録、逆質問を企業ごとに残せます。")
                } actions: {
                    addMenu
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(nonEmptyCategories) { category in
                        Section(category.title) {
                            ForEach(items.filter { $0.category == category }) { item in
                                Button { editingItem = item } label: {
                                    CompanyInformationRow(item: item)
                                }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button("削除", role: .destructive) { deletingItem = item }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("企業研究・記録")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { addMenu }
        }
        .sheet(item: $creatingCategory) { category in
            CompanyInformationEditorView(companyID: companyID, category: category)
        }
        .sheet(item: $editingItem) { item in
            CompanyInformationEditorView(companyID: companyID, item: item)
        }
        .alert(
            "記録を削除しますか？",
            isPresented: Binding(
                get: { deletingItem != nil },
                set: { if $0 == false { deletingItem = nil } }
            )
        ) {
            Button("削除", role: .destructive) {
                guard let deletingItem else { return }
                Task {
                    if await store.deleteCompanyInformationItem(deletingItem) {
                        self.deletingItem = nil
                    }
                }
            }
            Button("キャンセル", role: .cancel) { deletingItem = nil }
        } message: {
            Text("この操作は取り消せません。")
        }
        .recruitErrorAlert(store: store)
    }

    private var items: [CompanyInformationItem] {
        store.informationItems(for: companyID)
    }

    private var nonEmptyCategories: [CompanyInformationCategory] {
        CompanyInformationCategory.allCases.filter { category in
            items.contains { $0.category == category }
        }
    }

    private var addMenu: some View {
        Menu {
            ForEach(CompanyInformationCategory.allCases) { category in
                Button(category.title, systemImage: category.systemImage) {
                    creatingCategory = category
                }
            }
        } label: {
            Label("記録を追加", systemImage: "plus")
        }
    }
}

private struct CompanyInformationRow: View {
    let item: CompanyInformationItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if let date = item.occurredOn {
                    Text(DateFormatting.localDateWithYear(date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(item.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
        .fullWidthTappableArea()
        .accessibilityElement(children: .combine)
    }
}
