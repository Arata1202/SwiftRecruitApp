import SwiftUI

struct RecruitCalendarView: View {
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    @State private var displayedMonth = Calendar.current.startOfMonth(containing: Date())
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var editingStep: SelectionStep?
    @State private var editingTask: RecruitTask?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdaySymbols = Calendar.current.veryShortStandaloneWeekdaySymbols

    var body: some View {
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
                            calendarGrid
                            selectedDateEvents
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
            Spacer()
            Text(displayedMonth.formatted(.dateTime.year().month(.wide)))
                .font(.headline)
            Spacer()
            Button("次の月", systemImage: "chevron.right") { moveMonth(by: 1) }
                .labelStyle(.iconOnly)
        }
        .padding(.top, 8)
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(weekdayColor(index: index))
                    .frame(maxWidth: .infinity)
            }

            ForEach(monthDates, id: \.self) { date in
                dayCell(date)
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let isInMonth = Calendar.current.isDate(date, equalTo: displayedMonth, toGranularity: .month)
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
        let events = events(on: date)

        return Button {
            selectedDate = date
            if isInMonth == false {
                displayedMonth = Calendar.current.startOfMonth(containing: date)
            }
        } label: {
            VStack(spacing: 5) {
                Text(date.formatted(.dateTime.day()))
                    .font(.subheadline.weight(Calendar.current.isDateInToday(date) ? .bold : .regular))
                    .frame(width: 30, height: 30)
                    .background(isSelected ? Color.accentColor : Color.clear, in: Circle())
                    .foregroundStyle(isSelected ? Color.white : dayTextColor(date, isInMonth: isInMonth))

                HStack(spacing: 2) {
                    if events.contains(where: { $0.isSelection }) {
                        Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                    }
                    if events.contains(where: { $0.isDeadline }) {
                        Circle().fill(Color.orange).frame(width: 5, height: 5)
                    }
                    if events.contains(where: { $0.isTask }) {
                        Circle().fill(Color.green).frame(width: 5, height: 5)
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

    @ViewBuilder
    private var selectedDateEvents: some View {
        let events = events(on: selectedDate)
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
                }
            }
        }
    }

    private var monthDates: [Date] {
        Calendar.current.datesCoveringMonth(containing: displayedMonth)
    }

    private func events(on date: Date) -> [CalendarEvent] {
        let calendar = Calendar.current
        var values: [CalendarEvent] = []

        for step in store.selectionSteps where step.status != .cancelled {
            if let startsAt = step.startsAt, calendar.isDate(startsAt, inSameDayAs: date) {
                values.append(.selection(step, .start, startsAt, step.startsHasTime))
            }
            if let deadlineAt = step.deadlineAt, calendar.isDate(deadlineAt, inSameDayAs: date) {
                values.append(.selection(step, .deadline, deadlineAt, step.deadlineHasTime))
            }
        }
        for task in store.tasks {
            if let dueAt = task.dueAt, calendar.isDate(dueAt, inSameDayAs: date) {
                values.append(.task(task, dueAt))
            }
        }
        return values.sorted { $0.sortDate < $1.sortDate }
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

    private func weekdayColor(index: Int) -> Color {
        if index == 0 { return .red }
        if index == 6 { return .blue }
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
        return events.isEmpty ? "\(dateText)、予定なし" : "\(dateText)、予定\(events.count)件"
    }
}

private enum CalendarEvent: Identifiable {
    case selection(SelectionStep, SelectionMilestoneKind, Date, Bool)
    case task(RecruitTask, Date)

    var id: String {
        switch self {
        case .selection(let step, let kind, _, _): "selection-\(step.id)-\(kind == .start ? "start" : "deadline")"
        case .task(let task, _): "task-\(task.id)"
        }
    }

    var title: String {
        switch self {
        case .selection(let step, _, _, _): step.displayTitle
        case .task(let task, _): task.title
        }
    }

    var kindTitle: String {
        switch self {
        case .selection(_, .start, _, _): "選考予定"
        case .selection(_, .deadline, _, _): "選考締切"
        case .task(let task, _): task.isCompleted ? "完了済みToDo" : "ToDo"
        }
    }

    var systemImage: String {
        switch self {
        case .selection(let step, .start, _, _): step.type.systemImage
        case .selection(_, .deadline, _, _): "exclamationmark.circle"
        case .task(let task, _): task.isCompleted ? "checkmark.circle.fill" : "checklist"
        }
    }

    var color: Color {
        switch self {
        case .selection(_, .start, _, _): .accentColor
        case .selection(_, .deadline, _, _): .orange
        case .task: .green
        }
    }

    var sortDate: Date {
        switch self {
        case .selection(_, _, let date, _), .task(_, let date): date
        }
    }

    var timeText: String? {
        switch self {
        case .selection(_, _, let date, let hasTime): hasTime ? date.formatted(date: .omitted, time: .shortened) : nil
        case .task(let task, let date): task.dueHasTime ? date.formatted(date: .omitted, time: .shortened) : nil
        }
    }

    var isSelection: Bool {
        if case .selection(_, .start, _, _) = self { return true }
        return false
    }

    var isDeadline: Bool {
        if case .selection(_, .deadline, _, _) = self { return true }
        return false
    }

    var isTask: Bool {
        if case .task = self { return true }
        return false
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
