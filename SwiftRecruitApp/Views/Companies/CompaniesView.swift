import SwiftUI

struct CompaniesView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    @State private var searchText = ""
    @State private var statusFilter: CompanyStatus?
    @State private var sortOrder: CompanySortOrder = .upcoming
    @State private var isAddingCompany = false

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.companyPath) {
            Group {
                if store.isLoading && store.companies.isEmpty {
                    ProgressView("企業を読み込み中")
                } else if filteredCompanies.isEmpty {
                    ContentUnavailableView {
                        Label(emptyTitle, systemImage: "building.2")
                    } description: {
                        Text(emptyDescription)
                    } actions: {
                        if store.companies.isEmpty {
                            Button("企業を追加") { isAddingCompany = true }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button("条件をリセット") { resetFilters() }
                                .buttonStyle(.bordered)
                        }
                    }
                } else {
                    List(filteredCompanies) { company in
                        NavigationLink(value: company.id) {
                            CompanyRow(company: company, nextStep: nextStep(for: company.id))
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("企業")
            .searchableWhen(
                store.companies.isEmpty == false,
                text: $searchText,
                prompt: "企業名を検索"
            )
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                if store.companies.isEmpty == false {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Picker("ステータス", selection: $statusFilter) {
                                Text("すべて").tag(nil as CompanyStatus?)
                                ForEach(CompanyStatus.allCases) { status in
                                    Text(status.title).tag(status as CompanyStatus?)
                                }
                            }
                            Picker("並び順", selection: $sortOrder) {
                                ForEach(CompanySortOrder.allCases) { order in
                                    Text(order.title).tag(order)
                                }
                            }
                            if hasCustomFiltering {
                                Divider()
                                Button("条件をリセット", systemImage: "arrow.counterclockwise") {
                                    resetFilters()
                                }
                            }
                        } label: {
                            Label(
                                "絞り込みと並び替え",
                                systemImage: hasCustomFiltering
                                    ? "line.3.horizontal.decrease.circle.fill"
                                    : "line.3.horizontal.decrease"
                            )
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("企業を追加", systemImage: "plus") { isAddingCompany = true }
                }
            }
            .navigationDestination(for: UUID.self) { companyID in
                CompanyDetailView(companyID: companyID)
            }
            .refreshable {
                if let userID = session.userID { await store.reload(userID: userID, force: true) }
            }
            .sheet(isPresented: $isAddingCompany) { CompanyEditorView() }
            .recruitErrorAlert(store: store)
        }
    }

    private var filteredCompanies: [Company] {
        let now = Date()
        let filtered = store.companies.filter { company in
            let matchesSearch = searchText.isEmpty || company.name.localizedCaseInsensitiveContains(searchText)
            let matchesStatus = statusFilter == nil || company.status == statusFilter
            return matchesSearch && matchesStatus
        }

        return filtered.sorted { lhs, rhs in
            switch sortOrder {
            case .upcoming:
                let lhsDate = nextStep(for: lhs.id, relativeTo: now)?.nextDate(relativeTo: now)
                let rhsDate = nextStep(for: rhs.id, relativeTo: now)?.nextDate(relativeTo: now)
                switch (lhsDate, rhsDate) {
                case let (lhsDate?, rhsDate?):
                    return lhsDate == rhsDate ? lhs.updatedAt > rhs.updatedAt : lhsDate < rhsDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.updatedAt > rhs.updatedAt
                }
            case .updated:
                return lhs.updatedAt > rhs.updatedAt
            case .name:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
    }

    private var hasCustomFiltering: Bool {
        statusFilter != nil || sortOrder != .upcoming
    }

    private var emptyTitle: String {
        store.companies.isEmpty ? "企業を登録しましょう" : "該当する企業がありません"
    }

    private var emptyDescription: String {
        store.companies.isEmpty
            ? "気になる企業を追加すると、選考やToDoをまとめて管理できます。"
            : "検索条件や絞り込みを変更してください。"
    }

    private func nextStep(
        for companyID: UUID,
        relativeTo now: Date = Date()
    ) -> SelectionStep? {
        return store.steps(for: companyID)
            .filter { $0.status == .scheduled && $0.nextDate(relativeTo: now) != nil }
            .min {
                ($0.nextDate(relativeTo: now) ?? .distantFuture)
                    < ($1.nextDate(relativeTo: now) ?? .distantFuture)
            }
    }

    private func resetFilters() {
        searchText = ""
        statusFilter = nil
        sortOrder = .upcoming
    }
}

private enum CompanySortOrder: String, CaseIterable, Identifiable {
    case upcoming
    case updated
    case name

    var id: String { rawValue }
    var title: String {
        switch self {
        case .upcoming: "次の予定順"
        case .updated: "更新順"
        case .name: "企業名順"
        }
    }
}

private struct CompanyRow: View {
    let company: Company
    let nextStep: SelectionStep?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    companyName
                    Spacer()
                    CompanyStatusBadge(status: company.status)
                }
                VStack(alignment: .leading, spacing: 8) {
                    companyName
                    CompanyStatusBadge(status: company.status)
                }
            }

            if let nextStep, let milestone = nextStep.nextMilestone() {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: nextStep.type.systemImage)
                        .foregroundStyle(Color.accentColor)
                    Text(nextStep.displayTitle)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(
                        milestone.kind == .deadline
                            ? "締切 \(DateFormatting.day.string(from: milestone.date))"
                            : DateFormatting.day.string(from: milestone.date)
                    )
                        .foregroundStyle(milestone.kind == .deadline ? Color.orange : Color.secondary)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 5)
        .fullWidthTappableArea()
        .accessibilityElement(children: .combine)
    }

    private var companyName: some View {
        Text(company.name)
            .font(.headline)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
    }
}
