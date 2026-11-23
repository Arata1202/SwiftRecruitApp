import SwiftUI

struct RecruitCalendarView: View {
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var currentDay = Calendar.current.startOfDay(for: Date())
    @State private var monthSelection = LocalDate(date: Calendar.current.startOfMonth(containing: Date()))
    @State private var daySelection = LocalDate(date: Date())
    @State private var selectedStep: SelectionStep?
    @State private var editingTask: RecruitTask?
    @State private var creationKind: CalendarCreationKind?
    @State private var completionMessage: String?

    @ScaledMetric(relativeTo: .subheadline) private var dayDiameter: CGFloat = 30
    private let holidays = JapaneseHolidayProvider()

    var body: some View {
        let eventIndex = CalendarEventIndex(
            selectionSteps: store.selectionSteps,
            tasks: store.tasks,
            calendar: .current
        )
        let dates = monthDates
        let holidayNames = holidays.holidays(
            containing: dates,
            timeZone: Calendar.current.timeZone
        )

        NavigationStack {
            Group {
                if store.isLoading && store.loadedUserID == nil && store.selectionSteps.isEmpty && store.tasks.isEmpty {
                    ProgressView("予定を読み込み中")
                } else if let message = store.loadErrorMessage {
                    DataLoadFailureView(message: message) {
                        Task { await reload() }
                    }
                } else {
                    List {
                        Section {
                            VStack(spacing: 12) {
                                monthHeader
                                calendarGrid(dates: dates, eventIndex: eventIndex, holidayNames: holidayNames)
                                    .fixedSize(horizontal: false, vertical: true)
                                Divider()
                                calendarLegend
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(16)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        if isSelectedDateVisible {
                            selectedDateEvents(eventIndex: eventIndex, holidayNames: holidayNames)
                        } else {
                            Section {
                                calendarPlaceholder("日付を選択", description: "カレンダーの日付を選ぶと、その日の予定を表示します。")
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .animation(reduceMotion ? nil : .snappy, value: store.selectionSteps)
                    .animation(reduceMotion ? nil : .snappy, value: store.tasks)
                    .refreshable { await reload() }
                }
            }
            .navigationTitle("カレンダー")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("今日") { moveToToday() }
                        .disabled(Calendar.current.isDate(displayedMonth, equalTo: currentDay, toGranularity: .month)
                            && Calendar.current.isDate(selectedDate, inSameDayAs: currentDay))
                }
            }
            .sheet(item: $selectedStep) { step in
                SelectionStepDetailView(stepID: step.id, ownerUserID: step.userID, onDeleted: {
                    if selectedStep?.id == step.id { selectedStep = nil }
                })
            }
            .sheet(item: $editingTask) { task in
                TaskDetailView(taskID: task.id, ownerUserID: task.userID, onDeleted: {
                    if editingTask?.id == task.id { editingTask = nil }
                })
            }
            .sheet(item: $creationKind) { kind in
                switch kind {
                case .selection:
                    SelectionStepEditorView(initialDate: selectedDate)
                case .task:
                    TaskEditorView(initialDueDate: selectedDate)
                }
            }
            .recruitErrorAlert(store: store)
            .alert("完了状態を変更できませんでした", isPresented: Binding(
                get: { completionMessage != nil },
                set: { if !$0 { completionMessage = nil } }
            )) {
                Button("閉じる", role: .cancel) { completionMessage = nil }
            } message: {
                Text(completionMessage ?? "")
            }
        }
        .onAppear { refreshCurrentDay() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            refreshCurrentDay()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            refreshCurrentDay()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshCurrentDay() }
        }
    }

    private var displayedMonth: Date {
        monthSelection.date() ?? Calendar.current.startOfMonth(containing: currentDay)
    }

    private var selectedDate: Date {
        daySelection.date() ?? currentDay
    }

    private var monthHeader: some View {
        HStack {
            Button {
                moveMonth(by: -1)
            } label: {
                Label("前の月", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            Spacer()
            Text(displayedMonth.formatted(.dateTime.year().month(.wide)))
                .font(.headline)
            Spacer()
            Button {
                moveMonth(by: 1)
            } label: {
                Label("次の月", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    private func calendarGrid(
        dates: [Date],
        eventIndex: CalendarEventIndex,
        holidayNames: [Date: String]
    ) -> some View {
        let grid = Grid(horizontalSpacing: 4, verticalSpacing: 10) {
            GridRow {
                ForEach(weekdayHeaders) { header in
                    Text(header.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(weekdayColor(weekday: header.weekday))
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(stride(from: 0, to: dates.count, by: 7)), id: \.self) { start in
                GridRow {
                    ForEach(dates[start..<min(start + 7, dates.count)], id: \.self) { date in
                        if Calendar.current.isDate(date, equalTo: displayedMonth, toGranularity: .month) {
                            dayCell(
                                date,
                                events: eventIndex.events(on: date),
                                holidayName: holidayNames[Calendar.current.startOfDay(for: date)]
                            )
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        return ViewThatFits(in: .horizontal) {
            grid.frame(minWidth: dayDiameter * 7 + 24)
            ScrollView(.horizontal) {
                grid.fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func dayCell(
        _ date: Date,
        events: [CalendarEvent],
        holidayName: String?
    ) -> some View {
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
        let markers = Set(events.map(\.marker))

        return Button {
            daySelection = LocalDate(date: date)
        } label: {
            VStack(spacing: 5) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.subheadline.weight(Calendar.current.isDate(date, inSameDayAs: currentDay) ? .bold : .regular))
                    .monospacedDigit()
                    .frame(width: dayDiameter, height: dayDiameter)
                    .background(isSelected ? Color.accentColor : Color.clear, in: Circle())
                    .overlay {
                        Circle().strokeBorder(Calendar.current.isDate(date, inSameDayAs: currentDay) && !isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    }
                    .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : dayTextColor(date, isHoliday: holidayName != nil))

                HStack(spacing: 2) {
                    ForEach(CalendarMarker.allCases.filter { markers.contains($0) }, id: \.self) { marker in
                        markerSymbol(marker, size: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dayAccessibilityLabel(date, events: events, holidayName: holidayName))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var calendarLegend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                legendItems
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 6) {
                legendItems
            }
        }
        .font(.caption2)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func markerSymbol(_ marker: CalendarMarker, size: CGFloat) -> some View {
        let shape = differentiateWithoutColor && marker == .task ? AnyShape(Rectangle()) : AnyShape(Circle())
        return shape.fill(marker.color).frame(width: size, height: size)
    }

    private var legendItems: some View {
        ForEach(CalendarMarker.allCases, id: \.self) { marker in
            HStack(spacing: 4) {
                markerSymbol(marker, size: 6)
                Text(marker.title).fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func calendarPlaceholder(_ title: LocalizedStringKey, description: LocalizedStringKey) -> some View {
        ContentUnavailableView(title, systemImage: "calendar", description: Text(description).foregroundColor(RecruitTextColor.supporting))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func selectedDateEvents(
        eventIndex: CalendarEventIndex,
        holidayNames: [Date: String]
    ) -> some View {
        let events = eventIndex.events(on: selectedDate)
        let holidayName = holidayNames[Calendar.current.startOfDay(for: selectedDate)]
        let groups = CalendarEventGroup.allCases.filter { group in events.contains { $0.group == group } }
        Section {
            dateHeader(holidayName: holidayName)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        if groups.isEmpty {
            Section {
                calendarPlaceholder("予定はありません", description: "この日の選考・締切や、期限付きのToDoはありません。")
            }
        }
        ForEach(groups, id: \.self) { group in
            let grouped = CalendarEventGroup.sortedEvents(events, in: group)
            Section {
                ForEach(grouped) { event in
                    HStack(alignment: .top, spacing: 0) {
                        Button { Task { await toggleCompletion(event) } } label: {
                            Group {
                                if event.isSaving(in: store) {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: event.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(event.isCompleted ? Color.green : Color.secondary)
                                }
                            }
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isSaving)
                        .accessibilityLabel(event.completionAccessibilityLabel(isWorking: event.isSaving(in: store)))
                        Button { open(event) } label: {
                            eventRow(event)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .contentShape(.rect)
                        .accessibilityHint(event.group == .selection ? "選考の詳細を表示" : "ToDoの詳細を表示")
                    }
                }
            } header: {
                Text(group.title).foregroundStyle(Color.primary)
            }
        }
    }

    private func dateHeader(holidayName: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            selectedDateHeader
            if let holidayName {
                Label(holidayName, systemImage: "flag.fill").foregroundStyle(RecruitTextColor.red)
            }
        }
    }

    private var selectedDateHeader: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout())
        return layout {
            Text(selectedDate.formatted(.dateTime.month(.wide).day().weekday(.wide)))
                .font(.headline)
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            Menu {
                Button(eligibleCompanies.isEmpty ? "選考を追加（検討中・選考中の企業が必要）" : "選考を追加") { creationKind = .selection }
                    .disabled(eligibleCompanies.isEmpty)
                Button("ToDoを追加") { creationKind = .task }
            } label: {
                if dynamicTypeSize.isAccessibilitySize {
                    Text("予定を追加")
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Label("予定を追加", systemImage: "plus.circle.fill")
                }
            }
            .accessibilityHint(eligibleCompanies.isEmpty ? "選考の追加には検討中または選考中の企業が必要です" : "選択中の日付に選考またはToDoを追加します")
        }
    }

    @ViewBuilder
    private func eventRow(_ event: CalendarEvent) -> some View {
        let dateLabel = DateFormatting.calendarMetadata(
            kind: event.kindTitle,
            date: event.sortDate, hasTime: event.hasTime
        )
        switch event {
        case .selection(let step, let kind, _, _):
            SelectionStepRow(
                step: step,
                companyName: event.companyName(in: store) ?? "企業",
                showsMemo: true,
                showsTypeIcon: false,
                homeLineLimits: true,
                milestoneLabelOverride: kind == .start ? DateFormatting.schedule(step) : dateLabel,
                showsCompletedStyle: true
            )
        case .task(let task, _):
            TaskRow(
                task: task,
                companyName: event.companyName(in: store),
                showsDueLabel: true,
                homeLineLimits: true,
                dateLabelOverride: DateFormatting.calendarMetadata(
                    kind: "期限", date: event.sortDate, hasTime: event.hasTime
                )
            )
        }
    }

    private var monthDates: [Date] {
        Calendar.current.datesCoveringMonth(containing: displayedMonth)
    }

    private func open(_ event: CalendarEvent) {
        switch event {
        case .selection(let step, _, _, _): selectedStep = step
        case .task(let task, _): editingTask = task
        }
    }

    @MainActor
    private func toggleCompletion(_ event: CalendarEvent) async {
        guard !store.isSaving else { return }
        guard let userID = session.userID, store.loadedUserID == userID else {
            completionMessage = UserFacingError.completionRecoveryMessage(userID: session.userID)
            return
        }
        switch event {
        case .selection(let step, _, _, _):
            guard let current = store.selectionSteps.first(where: { $0.id == step.id && $0.version == step.version }) else {
                completionMessage = "予定が更新または削除されています。再読み込みして内容を確認してください。"
                return
            }
            if current.status == .completed {
                _ = await store.setSelectionStepStatus(current, status: .scheduled)
            } else {
                _ = await store.setSelectionStepStatus(current, status: .completed)
            }
        case .task(let task, _):
            guard let current = store.tasks.first(where: { $0.id == task.id && $0.version == task.version }) else {
                completionMessage = "ToDoが更新または削除されています。再読み込みして内容を確認してください。"
                return
            }
            if current.isCompleted { _ = await store.setTaskCompleted(current, completed: false) }
            else { _ = await store.setTaskCompleted(current, completed: true) }

        }
    }

    private func moveMonth(by value: Int) {
        guard let month = Calendar.current.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        monthSelection = LocalDate(date: Calendar.current.startOfMonth(containing: month))
    }

    private func refreshCurrentDay() {
        // A day rollover must not move the user's month or selection.
        currentDay = Calendar.current.startOfDay(for: Date())
    }

    private func moveToToday() {
        refreshCurrentDay()
        monthSelection = LocalDate(date: Calendar.current.startOfMonth(containing: currentDay))
        daySelection = LocalDate(date: currentDay)
    }

    private func reload() async {
        if let userID = session.userID { await store.reload(userID: userID, force: true) }
    }

    private var eligibleCompanies: [Company] {
        store.companies.filter { $0.status == .considering || $0.status == .active }
    }

    private var weekdayHeaders: [WeekdayHeader] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return calendar.orderedWeekdays.map { weekday in
            WeekdayHeader(weekday: weekday, symbol: symbols[weekday - 1])
        }
    }

    private func weekdayColor(weekday: Int) -> Color {
        if weekday == 1 { return RecruitTextColor.red }
        if weekday == 7 { return .accentColor }
        return .primary
    }

    private var isSelectedDateVisible: Bool {
        Calendar.current.isDate(selectedDate, equalTo: displayedMonth, toGranularity: .month)
    }

    private func dayTextColor(_ date: Date, isHoliday: Bool) -> Color {
        if isHoliday { return RecruitTextColor.red }
        return weekdayColor(weekday: Calendar.current.component(.weekday, from: date))
    }

    private func dayAccessibilityLabel(
        _ date: Date,
        events: [CalendarEvent],
        holidayName: String?
    ) -> String {
        let dateText = date.formatted(.dateTime.year().month().day().weekday(.wide))
        let holidayText = holidayName.map { "、\($0)" } ?? ""
        guard events.isEmpty == false else { return "\(dateText)\(holidayText)、予定なし" }
        let categories = Set(events.map(\.marker))
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.title)
            .joined(separator: "、")
        return "\(dateText)\(holidayText)、予定\(events.count)件、\(categories)"
    }
}

private enum CalendarCreationKind: String, Identifiable {
    case selection
    case task

    var id: Self { self }
}

private struct WeekdayHeader: Identifiable {
    let weekday: Int
    let symbol: String
    var id: Int { weekday }
}

enum CalendarMarker: Int, CaseIterable, Hashable {
    case selection
    case task

    var title: String {
        switch self {
        case .selection: return "選考・締切"
        case .task: return "ToDo"
        }
    }

    var color: Color {
        switch self {
        case .selection: return .accentColor
        case .task: return .green
        }
    }
}

struct CalendarEventIndex {
    private let eventsByDay: [Date: [CalendarEvent]]
    private let rangedSteps: [SelectionStep]
    private let calendar: Calendar

    init(selectionSteps: [SelectionStep], tasks: [RecruitTask], calendar: Calendar) {
        self.calendar = calendar
        rangedSteps = selectionSteps.filter { $0.status != .cancelled && $0.endDate(calendar: calendar) != nil }
        var values: [Date: [CalendarEvent]] = [:]

        for step in selectionSteps where step.status != .cancelled {
            if step.endDate(calendar: calendar) == nil, let startDate = step.startDate(calendar: calendar) {
                values[calendar.startOfDay(for: startDate), default: []]
                    .append(.selection(step, .start, startDate, step.startsHasTime))
            }
            if let deadlineDate = step.deadlineDate(calendar: calendar) {
                values[calendar.startOfDay(for: deadlineDate), default: []]
                    .append(.selection(step, .deadline, deadlineDate, step.deadlineHasTime))
            }
        }
        for task in tasks {
            if let dueDate = task.dueDate(calendar: calendar) {
                values[calendar.startOfDay(for: dueDate), default: []].append(.task(task, dueDate))
            }
        }
        eventsByDay = values.mapValues { events in
            events.sorted {
                if $0.sortDate == $1.sortDate { return $0.id < $1.id }
                return $0.sortDate < $1.sortDate
            }
        }
    }

    func events(on date: Date) -> [CalendarEvent] {
        // Test only the requested day, never materialize every day of a long range.
        let ranges: [CalendarEvent] = rangedSteps.compactMap { step in
            guard step.covers(day: date, calendar: calendar), let start = step.startDate(calendar: calendar) else { return nil }
            return .selection(step, .start, start, step.startsHasTime)
        }
        return ((eventsByDay[calendar.startOfDay(for: date)] ?? []) + ranges).sorted {
            if $0.sortDate == $1.sortDate { return $0.id < $1.id }
            return $0.sortDate < $1.sortDate
        }
    }
}

enum CalendarEventGroup: CaseIterable {
    case selection, task

    static func sortedEvents(_ events: [CalendarEvent], in group: Self) -> [CalendarEvent] {
        events.filter { $0.group == group }.sorted {
            if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
            if $0.sortDate != $1.sortDate { return $0.sortDate < $1.sortDate }
            return $0.id < $1.id
        }
    }

    var title: String {
        switch self {
        case .selection: return "選考・締切"
        case .task: return "ToDo"
        }
    }
}

enum CalendarEvent: Identifiable {
    case selection(SelectionStep, SelectionMilestoneKind, Date, Bool)
    case task(RecruitTask, Date)

    func completionAccessibilityLabel(isWorking: Bool) -> String {
        switch self {
        case .selection(let step, _, _, _): step.completionAccessibilityLabel(isWorking: isWorking)
        case .task(let task, _): task.completionAccessibilityLabel(isWorking: isWorking)
        }
    }

    @MainActor
    func isSaving(in store: RecruitStore) -> Bool {
        switch self {
        case .selection(let step, _, _, _): return store.savingSelectionStepID == step.id
        case .task(let task, _): return store.savingTaskID == task.id
        }
    }

    var id: String {
        switch self {
        case .selection(let step, let kind, _, _): return "selection-\(step.id)-\(kind == .start ? "start" : "deadline")"
        case .task(let task, _): return "task-\(task.id)"
        }
    }

    var title: String {
        switch self {
        case .selection(let step, _, _, _): return step.displayTitle
        case .task(let task, _): return task.title
        }
    }

    var kindTitle: String {
        switch self {
        case .selection(_, .start, _, _): return "予定"
        case .selection(_, .deadline, _, _): return "締切"
        case .task(let task, _): return task.isCompleted ? "完了済みToDo" : "ToDo"
        }
    }

    var systemImage: String {
        switch self {
        case .selection(let step, .start, _, _): return step.type.systemImage
        case .selection(_, .deadline, _, _): return "exclamationmark.circle"
        case .task(let task, _): return task.isCompleted ? "checkmark.circle.fill" : "checklist"
        }
    }

    var color: Color {
        if isCompleted { return .secondary }
        switch self {
        case .selection(_, .start, _, _): return .accentColor
        case .selection(_, .deadline, _, _): return .orange
        case .task: return .green
        }
    }

    var group: CalendarEventGroup {
        switch self {
        case .selection: return .selection
        case .task: return .task
        }
    }

    var isCompleted: Bool {
        switch self {
        case .selection(let step, _, _, _): return step.status == .completed
        case .task(let task, _): return task.isCompleted
        }
    }

    var marker: CalendarMarker {
        switch self {
        case .selection: return .selection
        case .task: return .task
        }
    }

    var sortDate: Date {
        switch self {
        case .selection(_, _, let date, _), .task(_, let date): return date
        }
    }

    var hasTime: Bool {
        switch self {
        case .selection(_, _, _, let hasTime): return hasTime
        case .task(let task, _): return task.dueHasTime
        }
    }

    var timeText: String? {
        switch self {
        case .selection(_, _, let date, let hasTime): return hasTime ? date.formatted(date: .omitted, time: .shortened) : nil
        case .task(let task, let date): return task.dueHasTime ? date.formatted(date: .omitted, time: .shortened) : nil
        }
    }

    @MainActor
    func companyName(in store: RecruitStore) -> String? {
        let companyID: UUID?
        switch self {
        case .selection(let step, _, _, _): companyID = step.companyID
        case .task(let task, _): companyID = task.companyID
        }
        return companyID.flatMap { store.company(id: $0)?.name }
    }


}

extension Calendar {
    var orderedWeekdays: [Int] {
        (0..<7).map { ((firstWeekday - 1 + $0) % 7) + 1 }
    }

    func startOfMonth(containing date: Date) -> Date {
        dateInterval(of: .month, for: date)?.start ?? startOfDay(for: date)
    }

    func datesCoveringMonth(containing date: Date) -> [Date] {
        let monthStart = startOfMonth(containing: date)
        let leadingDays = component(.weekday, from: monthStart) - firstWeekday
        let normalizedLeadingDays = leadingDays >= 0 ? leadingDays : leadingDays + 7
        guard let gridStart = self.date(byAdding: .day, value: -normalizedLeadingDays, to: monthStart) else { return [] }

        return (0..<42).compactMap { self.date(byAdding: .day, value: $0, to: gridStart) }
    }
}
