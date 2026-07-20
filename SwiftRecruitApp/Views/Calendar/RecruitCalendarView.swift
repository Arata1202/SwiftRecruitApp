import SwiftUI
import UIKit

struct RecruitCalendarView: View {
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var editingStep: SelectionStep?
    @State private var editingTask: RecruitTask?

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
                            NativeRecruitCalendar(
                                selectedDate: $selectedDate,
                                markers: calendarMarkers
                            )
                            .frame(height: 360)
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

    private var calendarMarkers: [DateComponents: Set<CalendarMarker>] {
        let calendar = Calendar.current
        var markers: [DateComponents: Set<CalendarMarker>] = [:]

        for step in store.selectionSteps where step.status != .cancelled {
            if let startsAt = step.startsAt {
                markers[calendar.dayComponents(for: startsAt), default: []].insert(.selection)
            }
            if let deadlineAt = step.deadlineAt {
                markers[calendar.dayComponents(for: deadlineAt), default: []].insert(.deadline)
            }
        }
        for task in store.tasks where task.dueAt != nil {
            if let dueAt = task.dueAt {
                markers[calendar.dayComponents(for: dueAt), default: []].insert(.task)
            }
        }
        return markers
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

    private func reload() async {
        if let userID = session.userID { await store.reload(userID: userID, force: true) }
    }

}

private enum CalendarMarker: Int, Hashable, CaseIterable {
    case selection
    case deadline
    case task

    var color: UIColor {
        switch self {
        case .selection: .systemBlue
        case .deadline: .systemOrange
        case .task: .systemGreen
        }
    }
}

private struct NativeRecruitCalendar: UIViewRepresentable {
    @Binding var selectedDate: Date
    let markers: [DateComponents: Set<CalendarMarker>]

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.calendar = .current
        view.locale = .current
        view.delegate = context.coordinator

        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        selection.selectedDate = Calendar.current.dayComponents(for: selectedDate)
        view.selectionBehavior = selection
        context.coordinator.selection = selection
        context.coordinator.displayedMarkers = markers
        return view
    }

    func updateUIView(_ view: UICalendarView, context: Context) {
        context.coordinator.parent = self

        let selectedComponents = Calendar.current.dayComponents(for: selectedDate)
        let currentSelectedComponents = context.coordinator.selection?.selectedDate
            .flatMap { Calendar.current.date(from: $0) }
            .map { Calendar.current.dayComponents(for: $0) }
        if currentSelectedComponents != selectedComponents {
            context.coordinator.selection?.setSelected(selectedComponents, animated: false)
        }

        let previousMarkers = context.coordinator.displayedMarkers
        let changedComponents = Set(previousMarkers.keys).union(Set(markers.keys)).filter {
            previousMarkers[$0] != markers[$0]
        }
        if changedComponents.isEmpty == false {
            view.reloadDecorations(forDateComponents: Array(changedComponents), animated: true)
        }
        context.coordinator.displayedMarkers = markers
    }

    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var parent: NativeRecruitCalendar
        weak var selection: UICalendarSelectionSingleDate?
        var displayedMarkers: [DateComponents: Set<CalendarMarker>] = [:]

        init(parent: NativeRecruitCalendar) {
            self.parent = parent
        }

        func dateSelection(
            _ selection: UICalendarSelectionSingleDate,
            didSelectDate dateComponents: DateComponents?
        ) {
            guard let dateComponents,
                  let date = Calendar.current.date(from: dateComponents)
            else { return }
            parent.selectedDate = Calendar.current.startOfDay(for: date)
        }

        func dateSelection(
            _ selection: UICalendarSelectionSingleDate,
            canSelectDate dateComponents: DateComponents?
        ) -> Bool {
            dateComponents != nil
        }

        func calendarView(
            _ calendarView: UICalendarView,
            decorationFor dateComponents: DateComponents
        ) -> UICalendarView.Decoration? {
            guard let date = Calendar.current.date(from: dateComponents) else { return nil }
            let key = Calendar.current.dayComponents(for: date)
            guard let markers = parent.markers[key], markers.isEmpty == false else { return nil }
            let orderedMarkers = CalendarMarker.allCases.filter { markers.contains($0) }
            return .customView {
                let stack = UIStackView()
                stack.axis = .horizontal
                stack.spacing = 2
                stack.alignment = .center
                for marker in orderedMarkers {
                    let dot = UIView()
                    dot.backgroundColor = marker.color
                    dot.layer.cornerRadius = 2.5
                    dot.translatesAutoresizingMaskIntoConstraints = false
                    NSLayoutConstraint.activate([
                        dot.widthAnchor.constraint(equalToConstant: 5),
                        dot.heightAnchor.constraint(equalToConstant: 5),
                    ])
                    stack.addArrangedSubview(dot)
                }
                return stack
            }
        }
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

private extension Calendar {
    func dayComponents(for date: Date) -> DateComponents {
        dateComponents([.era, .year, .month, .day], from: date)
    }
}
