import SwiftUI

enum CompanyActivityEditor: Hashable, Identifiable {
    case selection(companyID: UUID)
    case task(companyID: UUID)

    var id: Self { self }
}

struct CompaniesView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AppRouter.self) private var router
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    @State private var searchText = ""
    @State private var statusFilter: CompanyStatus?
    @State private var sortOrder: CompanySortOrder = .upcoming
    @State private var isAddingCompany = false
    @State private var activityEditor: CompanyActivityEditor?
    @State private var referenceDate = Date()

    // Keep the navigation hierarchy alive when folding or rotating changes its width.
    private var usesSplitNavigation: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        Group {
            if usesSplitNavigation {
                splitLayout
            } else {
                @Bindable var router = router
                NavigationStack(path: $router.companyPath) {
                    companyList
                        .navigationDestination(for: UUID.self) { companyID in
                            companyDetail(companyID)
                        }
                }
            }
        }
        .sheet(isPresented: $isAddingCompany) { CompanyEditorView() }
        .sheet(item: $activityEditor) { editor in
            switch editor {
            case .selection(let companyID): SelectionStepEditorView(companyID: companyID)
            case .task(let companyID): TaskEditorView(companyID: companyID)
            }
        }
        .recruitErrorAlert(store: store)
        .task { await refreshReferenceDate() }
    }

    private func companyDetail(_ id: UUID) -> some View {
        CompanyDetailView(companyID: id) { activityEditor = $0 }
    }

    private var splitLayout: some View {
        NavigationSplitView {
            companyList
                .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
        } detail: {
            NavigationStack {
                if let companyID = selectedCompanyID,
                   store.company(id: companyID) != nil {
                    companyDetail(companyID)
                } else if store.loadErrorMessage == nil && !matchingCompanies.isEmpty {
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
    private var companyList: some View {
        let upcoming = upcomingStepsByCompany
        let filteredCompanies = sortedCompanies(matchingCompanies, upcoming: upcoming)
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
            } else {
                List(selection: usesSplitNavigation ? selectedCompanyBinding : nil) {
                    ForEach(filteredCompanies) { company in
                        NavigationLink(value: company.id) {
                            CompanyRow(
                                company: company,
                                nextStep: upcoming[company.id]?.step,
                                referenceDate: referenceDate
                            )
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("企業")
        .searchableWhen(
            store.companies.isEmpty == false,
            text: $searchText,
            placement: horizontalSizeClass == .regular ? .navigationBarDrawer(displayMode: .always) : .automatic,
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

    private var matchingCompanies: [Company] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.companies.filter { company in
            let matchesSearch = query.isEmpty || company.name.localizedCaseInsensitiveContains(query)
            let matchesStatus = statusFilter == nil || company.status == statusFilter
            return matchesSearch && matchesStatus
        }
    }

    private typealias UpcomingStep = (step: SelectionStep, date: Date)

    private func sortedCompanies(_ companies: [Company], upcoming: [UUID: UpcomingStep]) -> [Company] {
        companies.sorted { lhs, rhs in
            switch sortOrder {
            case .upcoming:
                let lhsDate = upcoming[lhs.id]?.date
                let rhsDate = upcoming[rhs.id]?.date
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

    private var upcomingStepsByCompany: [UUID: UpcomingStep] {
        var result: [UUID: UpcomingStep] = [:]
        for step in store.selectionSteps where step.status == .scheduled {
            guard let date = step.nextDate(relativeTo: referenceDate) else { continue }
            if let current = result[step.companyID] {
                if current.date < date { continue }
                if current.date == date,
                   (current.step.earliestDate ?? .distantFuture) <= (step.earliestDate ?? .distantFuture) { continue }
            }
            result[step.companyID] = (step, date)
        }
        return result
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
