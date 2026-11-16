import SwiftUI

struct RecruitCalendarView: View {
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    @State private var displayedMonth = Calendar.current.startOfMonth(containing: Date())
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var editingStep: SelectionStep?
    @State private var editingTask: RecruitTask?
    @State private var creationKind: CalendarCreationKind?
    @State private var completedTaskForUndo: RecruitTask?
    @State private var isUndoingTask = false
    @State private var completedSelectionForUndo: SelectionStep?
    @State private var selectionUndoNotificationEnabled = false
    @State private var isUndoingSelection = false
    @State private var exportingEventID: String?
    @State private var exportMessage: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
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
                if store.isLoading && store.selectionSteps.isEmpty && store.tasks.isEmpty {
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
                            Section { dateSelectionPrompt }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .animation(.snappy, value: store.selectionSteps)
                    .animation(.snappy, value: store.tasks)
                    .refreshable { await reload() }
                }
            }
            .navigationTitle("カレンダー")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("今日") { moveToToday() }
                        .disabled(Calendar.current.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
                            && Calendar.current.isDateInToday(selectedDate))
                }
            }
            .sheet(item: $editingStep) { SelectionStepEditorView(step: $0) }
            .sheet(item: $editingTask) { TaskEditorView(task: $0) }
            .sheet(item: $creationKind) { kind in
                switch kind {
                case .selection:
                    SelectionStepEditorView(initialDate: selectedDate)
                case .task:
                    TaskEditorView(initialDueDate: selectedDate)
                }
            }
            .recruitErrorAlert(store: store)
            .alert("Appleカレンダー", isPresented: exportMessagePresented) {
                Button("閉じる", role: .cancel) { exportMessage = nil }
            } message: {
                Text(exportMessage ?? "")
            }
            .safeAreaInset(edge: .bottom) {
                if let step = completedSelectionForUndo { selectionUndoBar(for: step) }
                else if let task = completedTaskForUndo { undoBar(for: task) }
            }
            .onChange(of: session.userID) { _, _ in
                completedSelectionForUndo = nil
                completedTaskForUndo = nil
            }
            .onChange(of: store.selectionSteps) { _, steps in
                guard let completed = completedSelectionForUndo else { return }
                if !steps.contains(where: { $0.id == completed.id && $0.status == .completed && $0.version == completed.version }) { completedSelectionForUndo = nil }
            }
            .onChange(of: store.tasks) { _, tasks in
                guard let completed = completedTaskForUndo else { return }
                if !tasks.contains(where: { $0.id == completed.id && $0.isCompleted && $0.version == completed.version }) { completedTaskForUndo = nil }
            }

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
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    private func calendarGrid(
        dates: [Date],
        eventIndex: CalendarEventIndex,
        holidayNames: [Date: String]
    ) -> some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(weekdayHeaders) { header in
                Text(header.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(weekdayColor(weekday: header.weekday))
                    .frame(maxWidth: .infinity)
            }

            ForEach(dates, id: \.self) { date in
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

    private func dayCell(
        _ date: Date,
        events: [CalendarEvent],
        holidayName: String?
    ) -> some View {
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
        let markers = Set(events.map(\.marker))

        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: 5) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.subheadline.weight(Calendar.current.isDateInToday(date) ? .bold : .regular))
                    .monospacedDigit()
                    .frame(width: 30, height: 30)
                    .background(isSelected ? Color.accentColor : Color.clear, in: Circle())
                    .foregroundStyle(isSelected ? Color.white : dayTextColor(date, isHoliday: holidayName != nil))

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
        .accessibilityLabel(dayAccessibilityLabel(date, events: events, holidayName: holidayName))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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

    private var dateSelectionPrompt: some View {
        ContentUnavailableView(
            "日付を選択",
            systemImage: "calendar",
            description: Text("カレンダーの日付を選ぶと、その日の予定を表示します。")
        )
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func selectedDateEvents(
        eventIndex: CalendarEventIndex,
        holidayNames: [Date: String]
    ) -> some View {
        let events = eventIndex.events(on: selectedDate)
        let holidayName = holidayNames[Calendar.current.startOfDay(for: selectedDate)]
        let groups = CalendarEventGroup.allCases.filter { group in events.contains { $0.group == group } }
        if groups.isEmpty {
            Section {
                if let holidayName {
                    Label(holidayName, systemImage: "flag.fill").foregroundStyle(.red)
                }
                ContentUnavailableView("予定はありません", systemImage: "calendar", description: Text("この日に登録された選考やToDoはありません。"))
            } header: {
                selectedDateHeader
            }
        }
        ForEach(groups, id: \.self) { group in
            let grouped = CalendarEventGroup.sortedEvents(events, in: group)
            Section {
                if group == groups.first, let holidayName {
                    Label(holidayName, systemImage: "flag.fill").foregroundStyle(.red)
                }
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
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isSaving)
                        .accessibilityLabel("「\(event.title)」を\(event.isCompleted ? "未完了に戻す" : "完了にする")")
                        Button { open(event) } label: {
                            eventRow(event)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .contentShape(.rect)
                        .accessibilityHint("編集")
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 8) {
                    if group == groups.first { selectedDateHeader }
                    Text(group.title)
                }
            }
        }
    }

    private var selectedDateHeader: some View {
        HStack {
            Text(selectedDate.formatted(.dateTime.month(.wide).day().weekday(.wide)))
            Spacer()
            Menu {
                Button(eligibleCompanies.isEmpty ? "選考を追加（企業の登録が必要）" : "選考を追加", systemImage: "person.crop.rectangle.stack") { creationKind = .selection }
                    .disabled(eligibleCompanies.isEmpty)
                Button("ToDoを追加", systemImage: "checklist") { creationKind = .task }
            } label: {
                Label("予定を追加", systemImage: "plus.circle.fill")
            }
            .accessibilityHint(eligibleCompanies.isEmpty ? "選考の追加には企業の登録が必要です" : "選択中の日付に選考またはToDoを追加します")
        }
    }

    @ViewBuilder
    private func eventRow(_ event: CalendarEvent) -> some View {
        let formattedDate = event.hasTime ? DateFormatting.dateTime.string(from: event.sortDate) : DateFormatting.day.string(from: event.sortDate)
        let dateLabel = "\(event.kindTitle) \(formattedDate)"
        switch event {
        case .selection(let step, _, _, _):
            SelectionStepRow(
                step: step,
                companyName: event.companyName(in: store) ?? "企業",
                showsMemo: true,
                showsTypeIcon: false,
                homeLineLimits: true,
                milestoneLabelOverride: dateLabel,
                showsCompletedStyle: true
            )
        case .task(let task, _):
            TaskRow(
                task: task,
                companyName: event.companyName(in: store),
                homeLineLimits: true,
                dateLabelOverride: dateLabel
            )
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

    private func export(_ event: CalendarEvent) async {
        exportingEventID = event.id
        defer { exportingEventID = nil }
        let succeeded: Bool
        switch event {
        case .selection(let step, let kind, _, _):
            succeeded = await store.exportSelection(step, kind: kind)
        case .task(let task, _):
            succeeded = await store.exportTask(task)
        }
        if succeeded {
            exportMessage = "Appleカレンダーに追加しました。以後、リクビジョンでの変更や削除も反映されます。"
        }
    }

    private func removeExport(_ event: CalendarEvent) async {
        exportingEventID = event.id
        defer { exportingEventID = nil }
        let succeeded: Bool
        switch event {
        case .selection(let step, let kind, _, _):
            succeeded = await store.removeSelectionFromAppleCalendar(id: step.id, kind: kind)
        case .task(let task, _):
            succeeded = await store.removeTaskFromAppleCalendar(id: task.id)
        }
        if succeeded {
            exportMessage = "Appleカレンダーから削除しました。"
        }
    }

    private var exportMessagePresented: Binding<Bool> {
        Binding(
            get: { exportMessage != nil },
            set: { if $0 == false { exportMessage = nil } }
        )
    }

    @MainActor
    private func toggleCompletion(_ event: CalendarEvent) async {
        guard let userID = session.userID, store.loadedUserID == userID else { return }
        switch event {
        case .selection(let step, _, _, _):
            guard let current = store.selectionSteps.first(where: { $0.id == step.id && $0.version == step.version }) else { return }
            if current.status == .completed {
                _ = await store.setSelectionStepStatus(current, status: .scheduled, notificationEnabled: false)
            } else {
                await completeSelection(current)
            }
        case .task(let task, _):
            guard let current = store.tasks.first(where: { $0.id == task.id && $0.version == task.version }) else { return }
            if current.isCompleted { _ = await store.setTaskCompleted(current, completed: false) }
            else { await completeTask(current) }

        }
    }

    private func undoBar(for task: RecruitTask) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("完了しました")
                Text(task.title).foregroundStyle(.secondary).lineLimit(1)
            }
            .font(.subheadline)
            Spacer(minLength: 0)
            Button("元に戻す") { Task { await undoTaskCompletion(task) } }
                .disabled(store.isSaving || isUndoingTask)
            Button("閉じる", systemImage: "xmark") { completedTaskForUndo = nil }
                .labelStyle(.iconOnly)
                .disabled(isUndoingTask)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @MainActor
    private func completeTask(_ task: RecruitTask) async {
        guard let userID = session.userID, store.loadedUserID == userID else { return }
        let success = await store.setTaskCompleted(task, completed: true)
        guard success, session.userID == userID, store.loadedUserID == userID,
              let updated = store.tasks.first(where: { $0.id == task.id && $0.isCompleted })
        else { return }
        completedSelectionForUndo = nil
        completedTaskForUndo = updated
    }

    @MainActor
    private func undoTaskCompletion(_ task: RecruitTask) async {
        guard !isUndoingTask, !store.isSaving,
              let userID = session.userID, store.loadedUserID == userID,
              completedTaskForUndo?.id == task.id,
              let current = store.tasks.first(where: {
                  $0.id == task.id && $0.isCompleted && $0.version == task.version
              }) else {
            return
        }
        isUndoingTask = true
        defer { isUndoingTask = false }
        let success = await store.setTaskCompleted(current, completed: false)
        if success, session.userID == userID, completedTaskForUndo?.id == task.id {
            completedTaskForUndo = nil
        }
    }

    private func selectionUndoBar(for step: SelectionStep) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("完了しました")
                Text(step.displayTitle).foregroundStyle(.secondary).lineLimit(1)
            }
            .font(.subheadline)
            Spacer(minLength: 0)
            Button("元に戻す") { Task { await undoSelectionCompletion(step) } }
                .disabled(store.isSaving || isUndoingSelection)
            Button("閉じる", systemImage: "xmark") { completedSelectionForUndo = nil }
                .labelStyle(.iconOnly).disabled(isUndoingSelection)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal).padding(.bottom, 8)
    }

    @MainActor
    private func completeSelection(_ step: SelectionStep) async {
        guard let userID = session.userID, store.loadedUserID == userID else { return }
        guard let updated = await store.setSelectionStepStatus(step, status: .completed),
              session.userID == userID, store.loadedUserID == userID,
              store.selectionSteps.contains(where: { $0.id == updated.id && $0.version == updated.version && $0.status == .completed }) else { return }
        completedTaskForUndo = nil
        selectionUndoNotificationEnabled = step.notificationEnabled
        completedSelectionForUndo = updated
    }

    @MainActor
    private func undoSelectionCompletion(_ step: SelectionStep) async {
        guard !isUndoingSelection, !store.isSaving,
              let userID = session.userID, store.loadedUserID == userID,
              completedSelectionForUndo?.id == step.id,
              let current = store.selectionSteps.first(where: {
                  $0.id == step.id && $0.status == .completed && $0.version == step.version
              }) else { return }
        isUndoingSelection = true
        defer { isUndoingSelection = false }
        let updated = await store.setSelectionStepStatus(current, status: .scheduled, notificationEnabled: selectionUndoNotificationEnabled)
        if updated != nil, session.userID == userID, completedSelectionForUndo?.id == step.id {
            completedSelectionForUndo = nil
        }
    }

    private func moveMonth(by value: Int) {
        guard let month = Calendar.current.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        displayedMonth = Calendar.current.startOfMonth(containing: month)
    }

    private func moveToToday() {
        let today = Date()
        displayedMonth = Calendar.current.startOfMonth(containing: today)
        selectedDate = Calendar.current.startOfDay(for: today)
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
        if weekday == 1 { return .red }
        if weekday == 7 { return .blue }
        return .secondary
    }

    private var isSelectedDateVisible: Bool {
        Calendar.current.isDate(selectedDate, equalTo: displayedMonth, toGranularity: .month)
    }

    private func dayTextColor(_ date: Date, isHoliday: Bool) -> Color {
        if isHoliday { return .red }
        let weekday = Calendar.current.component(.weekday, from: date)
        if weekday == 1 { return .red }
        if weekday == 7 { return .blue }
        return .primary
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

struct CalendarEventIndex {
    private let eventsByDay: [Date: [CalendarEvent]]
    private let calendar: Calendar

    init(selectionSteps: [SelectionStep], tasks: [RecruitTask], calendar: Calendar) {
        self.calendar = calendar
        var values: [Date: [CalendarEvent]] = [:]

        for step in selectionSteps where step.status != .cancelled {
            if let startDate = step.startDate(calendar: calendar) {
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
        eventsByDay[calendar.startOfDay(for: date)] ?? []
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
        case .selection: return "選考"
        case .task: return "ToDo"
        }
    }
}

enum CalendarEvent: Identifiable {
    case selection(SelectionStep, SelectionMilestoneKind, Date, Bool)
    case task(RecruitTask, Date)

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


    @MainActor
    func isExported(in store: RecruitStore) -> Bool {
        switch self {
        case .selection(let step, let kind, _, _):
            return store.isSelectionExported(id: step.id, kind: kind)
        case .task(let task, _):
            return store.isTaskExported(id: task.id)
        }
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
        let leadingDays = component(.weekday, from: monthStart) - firstWeekday
        let normalizedLeadingDays = leadingDays >= 0 ? leadingDays : leadingDays + 7
        guard let gridStart = self.date(byAdding: .day, value: -normalizedLeadingDays, to: monthStart) else { return [] }

        return (0..<42).compactMap { self.date(byAdding: .day, value: $0, to: gridStart) }
    }
}
