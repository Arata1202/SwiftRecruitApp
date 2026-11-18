import SwiftUI

struct CompanyInformationView: View {
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    let companyID: UUID
    @State private var creatingCategory: CompanyInformationCategory?
    @State private var selectedItem: CompanyInformationItem?

    var body: some View {
        Group {
            if items.isEmpty {
                GeometryReader { geometry in
                    ScrollView {
                        ContentUnavailableView {
                            Label("まだ記録がありません", systemImage: "doc.text.magnifyingglass")
                        } description: {
                            Text("企業研究、志望理由、面接記録、逆質問を企業ごとに残せます。")
                        } actions: {
                            addMenu
                                .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity)
                            .frame(minHeight: geometry.size.height, alignment: .center)
                    }
                    .scrollBounceBehavior(.always)
                }
            } else {
                List {
                    ForEach(nonEmptyCategories) { category in
                        Section(category.title) {
                            ForEach(items.filter { $0.category == category }) { item in
                                Button { selectedItem = item } label: {
                                    CompanyInformationRow(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .refreshable {
            if let userID = session.userID { await store.reload(userID: userID, force: true) }
        }
        .navigationTitle("企業研究・記録")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { addMenu }
        }
        .sheet(item: $creatingCategory) { category in
            CompanyInformationEditorView(companyID: companyID, category: category)
        }
        .sheet(item: $selectedItem) { item in
            CompanyInformationDetailView(
                itemID: item.id, companyID: companyID, ownerUserID: item.userID,
                onDeleted: { if selectedItem?.id == item.id { selectedItem = nil } }
            )
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(item.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .fullWidthTappableArea()
        .accessibilityElement(children: .combine)
    }
}
