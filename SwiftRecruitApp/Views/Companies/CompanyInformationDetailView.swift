import SwiftUI

struct CompanyInformationDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    let itemID: UUID
    let companyID: UUID
    let ownerUserID: UUID
    let onDeleted: () -> Void
    @State private var editingItem: CompanyInformationItem?

    var body: some View {
        NavigationStack {
            Group {
                if let item = currentItem {
                    List {
                        Section("記録") {
                            Text(item.title).font(.headline)
                            LabeledContent("種類", value: item.category.title)
                            if let date = item.occurredOn {
                                LabeledContent(
                                    item.category == .interview ? "面接日" : "記録日",
                                    value: DateFormatting.localDateWithYear(date)
                                )
                            }
                        }
                        Section("内容") {
                            Text(item.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .textSelection(.enabled)
                } else {
                    ContentUnavailableView(
                        "記録が見つかりません",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("この項目を表示できません。閉じて一覧を更新してください。")
                    )
                }
            }
            .navigationTitle("記録の詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("編集") { editingItem = currentItem }
                        .disabled(currentItem == nil || store.isSaving)
                }
            }
            .sheet(item: $editingItem) { item in
                CompanyInformationEditorView(companyID: companyID, item: item, onDeleted: onDeleted)
            }
            .onChange(of: session.userID) { _, _ in editingItem = nil }
            .onChange(of: store.loadedUserID) { _, _ in editingItem = nil }
        }
    }

    private var currentItem: CompanyInformationItem? {
        guard session.userID == ownerUserID, store.loadedUserID == ownerUserID else { return nil }
        return store.companyInformationItems.first {
            $0.id == itemID && $0.companyID == companyID && $0.userID == ownerUserID
        }
    }
}
