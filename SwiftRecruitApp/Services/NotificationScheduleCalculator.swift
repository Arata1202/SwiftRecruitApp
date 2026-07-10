import Foundation

enum NotificationScheduleCalculator {
    static func selectionStartDate(startsAt: Date, now: Date = Date()) -> Date? {
        let date = startsAt.addingTimeInterval(-3_600)
        return date > now ? date : nil
    }

    static func selectionDeadlineDate(
        deadlineAt: Date,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Date? {
        guard let previousDay = calendar.date(byAdding: .day, value: -1, to: deadlineAt),
              let date = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: previousDay)
        else { return nil }
        return date > now ? date : nil
    }

    static func taskDate(
        dueAt: Date,
        hasTime: Bool,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Date? {
        let date = hasTime
            ? dueAt
            : calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dueAt)
        guard let date, date > now else { return nil }
        return date
    }
}

