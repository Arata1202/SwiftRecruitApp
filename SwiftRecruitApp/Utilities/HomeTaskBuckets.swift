import Foundation

enum HomeOrdering {
    static func precedes(_ lhsDate: Date, _ lhsCreated: Date, _ lhsID: UUID,
                         _ rhsDate: Date, _ rhsCreated: Date, _ rhsID: UUID) -> Bool {
        if lhsDate != rhsDate { return lhsDate < rhsDate }
        if lhsCreated != rhsCreated { return lhsCreated < rhsCreated }
        return lhsID.uuidString < rhsID.uuidString
    }

    static func steps(_ steps: [SelectionStep], relativeTo now: Date) -> [SelectionStep] {
        steps.sorted { lhs, rhs in
            precedes(lhs.nextDate(relativeTo: now) ?? .distantFuture, lhs.createdAt, lhs.id,
                     rhs.nextDate(relativeTo: now) ?? .distantFuture, rhs.createdAt, rhs.id)
        }
    }
}

struct HomeTaskBuckets {
    let overdue: [RecruitTask]
    let upcoming: [RecruitTask]

    static func make(
        tasks: [RecruitTask],
        relativeTo now: Date,
        calendar: Calendar = .current,
        upcomingDays: Int = 7
    ) -> HomeTaskBuckets {
        let end = calendar.date(byAdding: .day, value: upcomingDays, to: now) ?? now
        let active = tasks.filter { $0.isCompleted == false && $0.dueDate(calendar: calendar) != nil }
        let overdue = active
            .filter { $0.isOverdue(relativeTo: now, calendar: calendar) }
            .sorted { HomeOrdering.precedes($0.dueDate(calendar: calendar) ?? .distantPast, $0.createdAt, $0.id, $1.dueDate(calendar: calendar) ?? .distantPast, $1.createdAt, $1.id) }
        let upcoming = active
            .filter { task in
                guard task.isOverdue(relativeTo: now, calendar: calendar) == false,
                      let dueDate = task.dueDate(calendar: calendar)
                else { return false }
                return task.dueHasTime
                    ? dueDate <= end
                    : calendar.startOfDay(for: dueDate) <= calendar.startOfDay(for: end)
            }
            .sorted { HomeOrdering.precedes($0.dueDate(calendar: calendar) ?? .distantFuture, $0.createdAt, $0.id, $1.dueDate(calendar: calendar) ?? .distantFuture, $1.createdAt, $1.id) }
        return HomeTaskBuckets(overdue: overdue, upcoming: upcoming)
    }
}

enum HomeSelectionMilestones {
    static func all(for step: SelectionStep, calendar: Calendar = .current) -> [SelectionMilestone] {
        [
            step.startDate(calendar: calendar).map { SelectionMilestone(kind: .start, date: $0, hasTime: step.startsHasTime) },
            step.deadlineDate(calendar: calendar).map { SelectionMilestone(kind: .deadline, date: $0, hasTime: step.deadlineHasTime) }
        ].compactMap { $0 }
    }

    static func isPast(_ milestone: SelectionMilestone, relativeTo now: Date, calendar: Calendar = .current) -> Bool {
        milestone.hasTime ? milestone.date < now : calendar.startOfDay(for: milestone.date) < calendar.startOfDay(for: now)
    }

    static func earliestPast(for step: SelectionStep, relativeTo now: Date, calendar: Calendar = .current) -> SelectionMilestone? {
        all(for: step, calendar: calendar)
            .filter { isPast($0, relativeTo: now, calendar: calendar) }
            .min { $0.date < $1.date }
    }
}

// Each selection appears once; a nearby upcoming milestone takes priority.
struct HomeSelectionBuckets {
    let past: [SelectionStep]
    let upcoming: [SelectionStep]

    static func make(steps: [SelectionStep], relativeTo now: Date, calendar: Calendar = .current) -> HomeSelectionBuckets {
        let end = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        typealias Entry = (step: SelectionStep, date: Date)
        var upcoming: [Entry] = []
        var past: [Entry] = []
        let finalDay = calendar.startOfDay(for: end)
        for step in steps where step.status == .scheduled {
            let milestones = HomeSelectionMilestones.all(for: step, calendar: calendar)
            let next = milestones.filter { milestone in
                let isUpcoming = !HomeSelectionMilestones.isPast(milestone, relativeTo: now, calendar: calendar)
                let isOngoing = milestone.kind == .start && step.isOngoing(relativeTo: now, calendar: calendar)
                let inWindow = milestone.hasTime ? milestone.date <= end : calendar.startOfDay(for: milestone.date) <= finalDay
                return (isUpcoming || isOngoing) && inWindow
            }.map(\.date).min()
            if let next {
                upcoming.append((step, next))
            } else if let previous = milestones.filter({ HomeSelectionMilestones.isPast($0, relativeTo: now, calendar: calendar) }).map(\.date).min() {
                past.append((step, previous))
            }
        }
        func sortedSteps(_ entries: [Entry]) -> [SelectionStep] {
            entries.sorted {
                HomeOrdering.precedes($0.date, $0.step.createdAt, $0.step.id, $1.date, $1.step.createdAt, $1.step.id)
            }.map(\.step)
        }
        return HomeSelectionBuckets(past: sortedSteps(past), upcoming: sortedSteps(upcoming))
    }
}
