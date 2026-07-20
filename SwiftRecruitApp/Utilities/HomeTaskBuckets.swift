import Foundation

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
        let active = tasks.filter { $0.isCompleted == false && $0.dueDate() != nil }
        let overdue = active
            .filter { $0.isOverdue(relativeTo: now, calendar: calendar) }
            .sorted { ($0.dueDate() ?? .distantPast) > ($1.dueDate() ?? .distantPast) }
        let upcoming = active
            .filter { task in
                guard task.isOverdue(relativeTo: now, calendar: calendar) == false,
                      let dueDate = task.dueDate()
                else { return false }
                return task.dueHasTime
                    ? dueDate <= end
                    : calendar.startOfDay(for: dueDate) <= calendar.startOfDay(for: end)
            }
            .sorted { ($0.dueDate() ?? .distantFuture) < ($1.dueDate() ?? .distantFuture) }
        return HomeTaskBuckets(overdue: overdue, upcoming: upcoming)
    }
}
