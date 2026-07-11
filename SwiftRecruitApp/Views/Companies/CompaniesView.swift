import SwiftUI

struct CompaniesView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AppRouter.self) private var router
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    @State private var searchText = ""
    @State private var statusFilter: CompanyStatus?
    @State private var sortOrder: CompanySortOrder = .upcoming
    @State private var isAddingCompany = false

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                splitLayout
            } else {
                compactLayout
            }
        }
        .sheet(isPresented: $isAddingCompany) { CompanyEditorView() }
        .recruitErrorAlert(store: store)
    }

    private var compactLayout: some View {
        NavigationStack(path: companyPathBinding) {
            companyList(usesSelection: false)
                .navigationDestination(for: UUID.self) { companyID in
                    CompanyDetailView(companyID: companyID)
                }
        }
    }

    private var splitLayout: some View {
        NavigationSplitView {
            companyList(usesSelection: true)
                .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
        } detail: {
            NavigationStack {
                if let companyID = selectedCompanyID,
                   store.company(id: companyID) != nil {
                    CompanyDetailView(companyID: companyID)
                } else {
                    ContentUnavailableView(
                        "企業を選択してください",
                        systemImage: "building.2"
                    )
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func companyList(usesSelection: Bool) -> some View {
        Group {
            if store.isLoading && store.companies.isEmpty {
                ProgressView("企業を読み込み中")
            } else if let message = store.loadErrorMessage {
                DataLoadFailureView(message: message) {
                    Task { await reload() }
                }
            } else if filteredCompanies.isEmpty {
                emptyState
            } else if usesSelection {
                List(selection: selectedCompanyBinding) {
                    ForEach(filteredCompanies) { company in
                        NavigationLink(value: company.id) {
                            CompanyRow(company: company, nextStep: nextStep(for: company.id))
                        }
                    }
                }
                .listStyle(.insetGrouped)
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
        .toolbar { companyToolbar }
        .refreshable {
            if let userID = session.userID { await store.reload(userID: userID, force: true) }
        }
    }

    private var emptyState: some View {
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
    }

    @ToolbarContentBuilder
    private var companyToolbar: some ToolbarContent {
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

    private var selectedCompanyID: UUID? {
        router.companyPath.first
    }

    private var selectedCompanyBinding: Binding<UUID?> {
        Binding(
            get: { selectedCompanyID },
            set: { router.companyPath = $0.map { [$0] } ?? [] }
        )
    }

    private var companyPathBinding: Binding<[UUID]> {
        Binding(
            get: { router.companyPath },
            set: { router.companyPath = $0 }
        )
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

    private func reload() async {
        if let userID = session.userID { await store.reload(userID: userID, force: true) }
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
            HStack(alignment: .top, spacing: 12) {
                companyName
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                CompanyStatusBadge(status: company.status)
                    .labelStyle(.titleAndIcon)
                    .fixedSize()
            }

            if let nextStep, let milestone = nextStep.nextMilestone() {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: nextStep.type.systemImage)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 16)
                        Text(nextStep.displayTitle)
                    }
                    MetadataLabel(
                        milestone.kind == .deadline
                            ? "締切 \(milestone.hasTime ? DateFormatting.dateTime.string(from: milestone.date) : DateFormatting.day.string(from: milestone.date))"
                            : (milestone.hasTime ? DateFormatting.dateTime.string(from: milestone.date) : DateFormatting.day.string(from: milestone.date)),
                        systemImage: "calendar"
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
