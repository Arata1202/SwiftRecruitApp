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
