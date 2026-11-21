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
    @State private var referenceDate = Date()

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
        .task { await refreshReferenceDate() }
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
                } else if store.loadErrorMessage == nil && !filteredCompanies.isEmpty {
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
        ZStack {
            if store.isLoading && store.loadedUserID == nil && store.companies.isEmpty {
                ProgressView("企業を読み込み中")
            } else if let message = store.loadErrorMessage {
                DataLoadFailureView(message: message) {
                    Task { await reload() }
                }
            } else if filteredCompanies.isEmpty {
                GeometryReader { geometry in
                    ScrollView {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: geometry.size.height, alignment: .center)
                    }
                    .scrollBounceBehavior(.always)
                }
            } else if usesSelection {
                List(selection: selectedCompanyBinding) {
                    ForEach(filteredCompanies) { company in
                        NavigationLink(value: company.id) {
                            CompanyRow(
                                company: company,
                                nextStep: nextStep(for: company.id, relativeTo: referenceDate),
                                referenceDate: referenceDate
                            )
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                List(filteredCompanies) { company in
                    NavigationLink(value: company.id) {
                        CompanyRow(
                            company: company,
                            nextStep: nextStep(for: company.id, relativeTo: referenceDate),
                            referenceDate: referenceDate
                        )
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("企業")
        .searchableWhen(
            store.companies.isEmpty == false,
            text: $searchText,
            placement: usesSelection ? .navigationBarDrawer(displayMode: .always) : .automatic,
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
                .foregroundStyle(RecruitTextColor.supporting)
        } actions: {
            if store.companies.isEmpty {
                Button("企業を追加") { isAddingCompany = true }
                    .prominentAction()
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
                        systemImage: statusFilter != nil
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
        let now = referenceDate
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = store.companies.filter { company in
            let matchesSearch = query.isEmpty || company.name.localizedCaseInsensitiveContains(query)
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
        statusFilter != nil || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        relativeTo now: Date
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
    }

    private func reload() async {
        if let userID = session.userID { await store.reload(userID: userID, force: true) }
    }

    private func refreshReferenceDate() async {
        while Task.isCancelled == false {
            referenceDate = Date()
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                return
            }
        }
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
        case .updated: "企業情報の更新順"
        case .name: "企業名順"
        }
    }
}

private struct CompanyRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let company: Company
    let nextStep: SelectionStep?
    let referenceDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            layout {
                companyName
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                CompanyStatusBadge(status: company.status)
                    .fixedSize()
            }

            if let nextStep, let milestone = nextStep.nextMilestone(relativeTo: referenceDate) {
                VStack(alignment: .leading, spacing: 4) {
                    MetadataLabel(nextStep.displayTitle, systemImage: "list.bullet.rectangle", iconScale: .small)
                        .foregroundStyle(.primary)
                    Group {
                        if milestone.kind == .start {
                            ScheduleRangeLabel(step: nextStep, referenceDate: referenceDate)
                        } else {
                            MetadataLabel(
                                "締切 \(DateFormatting.listDate(milestone.date, hasTime: milestone.hasTime, referenceDate: referenceDate))",
                                systemImage: "calendar"
                            )
                        }
                    }
                    .foregroundStyle(.primary)
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
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .multilineTextAlignment(.leading)
    }
}
