import SwiftUI

struct RecruitCalendarView: View {
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    @State private var displayedMonth = Calendar.current.startOfMonth(containing: Date())
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var editingStep: SelectionStep?
    @State private var editingTask: RecruitTask?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        let eventIndex = CalendarEventIndex(
            selectionSteps: store.selectionSteps,
            tasks: store.tasks,
            calendar: .current
        )

        NavigationStack {
            Group {
                if store.isLoading && store.selectionSteps.isEmpty && store.tasks.isEmpty {
                    ProgressView("予定を読み込み中")
                } else if let message = store.loadErrorMessage {
                    DataLoadFailureView(message: message) {
                        Task { await reload() }
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            monthHeader
                            calendarGrid(eventIndex: eventIndex)
                            calendarLegend
                            selectedDateEvents(eventIndex: eventIndex)
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                    .refreshable { await reload() }
                }
            }
            .navigationTitle("カレンダー")
            .sheet(item: $editingStep) { SelectionStepEditorView(step: $0) }
            .sheet(item: $editingTask) { TaskEditorView(task: $0) }
            .recruitErrorAlert(store: store)
        }
    }

    private var monthHeader: some View {
        HStack {
            Button("前の月", systemImage: "chevron.left") { moveMonth(by: -1) }
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
            Spacer()
            Text(displayedMonth.formatted(.dateTime.year().month(.wide)))
                .font(.headline)
            Spacer()
            Button("次の月", systemImage: "chevron.right") { moveMonth(by: 1) }
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
        }
        .padding(.top, 8)
    }

    private func calendarGrid(eventIndex: CalendarEventIndex) -> some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(weekdayHeaders) { header in
                Text(header.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(weekdayColor(weekday: header.weekday))
                    .frame(maxWidth: .infinity)
            }

            ForEach(monthDates, id: \.self) { date in
                dayCell(date, events: eventIndex.events(on: date))
            }
        }
    }

    private func dayCell(_ date: Date, events: [CalendarEvent]) -> some View {
        let isInMonth = Calendar.current.isDate(date, equalTo: displayedMonth, toGranularity: .month)
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
        let markers = Set(events.map(\.marker))

        return Button {
            selectedDate = date
            if isInMonth == false {
                displayedMonth = Calendar.current.startOfMonth(containing: date)
            }
        } label: {
            VStack(spacing: 5) {
                Text(date.formatted(.dateTime.day()))
                    .font(.subheadline.weight(Calendar.current.isDateInToday(date) ? .bold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: 30, height: 30)
                    .background(isSelected ? Color.accentColor : Color.clear, in: Circle())
                    .foregroundStyle(isSelected ? Color.white : dayTextColor(date, isInMonth: isInMonth))

                HStack(spacing: 2) {
                    ForEach(CalendarMarker.allCases.filter { markers.contains($0) }, id: \.self) { marker in
                        Circle().fill(marker.color).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dayAccessibilityLabel(date, events: events))
    }

    private var calendarLegend: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 64), alignment: .leading)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(CalendarMarker.allCases, id: \.self) { marker in
                HStack(spacing: 4) {
                    Circle().fill(marker.color).frame(width: 6, height: 6)
                    Text(marker.title)
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func selectedDateEvents(eventIndex: CalendarEventIndex) -> some View {
        let events = eventIndex.events(on: selectedDate)
        VStack(alignment: .leading, spacing: 10) {
            Text(selectedDate.formatted(.dateTime.month(.wide).day().weekday(.wide)))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if events.isEmpty {
                ContentUnavailableView(
                    "予定はありません",
                    systemImage: "calendar.badge.checkmark",
                    description: Text("この日に登録された選考やToDoはありません。")
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
            } else {
                ForEach(events) { event in
                    Button { open(event) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: event.systemImage)
                                .foregroundStyle(event.color)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                HStack(spacing: 6) {
                                    Text(event.kindTitle)
                                    if let companyName = event.companyName(in: store) {
                                        Text("·")
                                        Text(companyName)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let time = event.timeText {
                                Text(time).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .opacity(event.isCompleted ? 0.65 : 1)
                }
            }
        }
    }

    private var monthDates: [Date] {
        Calendar.current.datesCoveringMonth(containing: displayedMonth)
    }

    private func open(_ event: CalendarEvent) {
        switch event {
        case .selection(let step, _, _, _): editingStep = step
        case .task(let task, _): editingTask = task
        }
    }

    private func moveMonth(by value: Int) {
        guard let month = Calendar.current.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        displayedMonth = Calendar.current.startOfMonth(containing: month)
        selectedDate = displayedMonth
    }

    private func reload() async {
        if let userID = session.userID { await store.reload(userID: userID, force: true) }
    }

    private var weekdayHeaders: [WeekdayHeader] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return calendar.orderedWeekdays.map { weekday in
            WeekdayHeader(weekday: weekday, symbol: symbols[weekday - 1])
        }
    }

    private func weekdayColor(weekday: Int) -> Color {
        if weekday == 1 { return .red }
        if weekday == 7 { return .blue }
        return .secondary
    }

    private func dayTextColor(_ date: Date, isInMonth: Bool) -> Color {
        guard isInMonth else { return .secondary.opacity(0.45) }
        let weekday = Calendar.current.component(.weekday, from: date)
        if weekday == 1 { return .red }
        if weekday == 7 { return .blue }
        return .primary
    }

    private func dayAccessibilityLabel(_ date: Date, events: [CalendarEvent]) -> String {
        let dateText = date.formatted(.dateTime.year().month().day().weekday(.wide))
        guard events.isEmpty == false else { return "\(dateText)、予定なし" }
        let categories = Set(events.map(\.marker))
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.title)
            .joined(separator: "、")
        return "\(dateText)、予定\(events.count)件、\(categories)"
    }
}

private struct WeekdayHeader: Identifiable {
    let weekday: Int
    let symbol: String
    var id: Int { weekday }
}

private enum CalendarMarker: Int, CaseIterable, Hashable {
    case selection
    case deadline
    case task
    case completed

    var title: String {
        switch self {
        case .selection: return "選考"
        case .deadline: return "締切"
        case .task: return "ToDo"
        case .completed: return "完了"
        }
    }

    var color: Color {
        switch self {
        case .selection: return .accentColor
        case .deadline: return .orange
        case .task: return .green
        case .completed: return .secondary
        }
    }
}

private struct CalendarEventIndex {
    private let eventsByDay: [Date: [CalendarEvent]]
    private let calendar: Calendar

    init(selectionSteps: [SelectionStep], tasks: [RecruitTask], calendar: Calendar) {
        self.calendar = calendar
        var values: [Date: [CalendarEvent]] = [:]

        for step in selectionSteps where step.status != .cancelled {
            if let startsAt = step.startsAt {
                values[calendar.startOfDay(for: startsAt), default: []]
                    .append(.selection(step, .start, startsAt, step.startsHasTime))
            }
            if let deadlineAt = step.deadlineAt {
                values[calendar.startOfDay(for: deadlineAt), default: []]
                    .append(.selection(step, .deadline, deadlineAt, step.deadlineHasTime))
            }
        }
        for task in tasks {
            if let dueAt = task.dueAt {
                values[calendar.startOfDay(for: dueAt), default: []].append(.task(task, dueAt))
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
        eventsByDay[calendar.startOfDay(for: date)] ?? []
    }
}

private enum CalendarEvent: Identifiable {
    case selection(SelectionStep, SelectionMilestoneKind, Date, Bool)
    case task(RecruitTask, Date)

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
        case .selection(_, .start, _, _): return "選考予定"
        case .selection(_, .deadline, _, _): return "選考締切"
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

    var isCompleted: Bool {
        switch self {
        case .selection(let step, _, _, _): return step.status == .completed
        case .task(let task, _): return task.isCompleted
        }
    }

    var marker: CalendarMarker {
        if isCompleted { return .completed }
        switch self {
        case .selection(_, .start, _, _): return .selection
        case .selection(_, .deadline, _, _): return .deadline
        case .task: return .task
        }
    }

    var sortDate: Date {
        switch self {
        case .selection(_, _, let date, _), .task(_, let date): return date
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
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }

    func datesCoveringMonth(containing date: Date) -> [Date] {
        let monthStart = startOfMonth(containing: date)
        guard let monthRange = range(of: .day, in: .month, for: monthStart) else { return [] }

        let leadingDays = component(.weekday, from: monthStart) - firstWeekday
        let normalizedLeadingDays = leadingDays >= 0 ? leadingDays : leadingDays + 7
        guard let gridStart = self.date(byAdding: .day, value: -normalizedLeadingDays, to: monthStart) else { return [] }

        let monthDayCount = monthRange.count
        let occupiedCount = normalizedLeadingDays + monthDayCount
        let cellCount = occupiedCount <= 35 ? 35 : 42
        return (0..<cellCount).compactMap { self.date(byAdding: .day, value: $0, to: gridStart) }
    }
}
