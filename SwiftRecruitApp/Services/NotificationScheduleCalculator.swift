import Foundation

enum NotificationScheduleCalculator {
    static func selectionStartDate(
        startsAt: Date,
        hasTime: Bool,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Date? {
        future(reminderDate(anchor: startsAt, hasTime: hasTime, kind: .selectionStart,
                            timedPreset: nil, datePreset: nil, calendar: calendar), now: now)
    }

    static func selectionDeadlineDate(
        deadlineAt: Date,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Date? {
        future(reminderDate(anchor: deadlineAt, hasTime: false, kind: .selectionDeadline,
                            timedPreset: nil, datePreset: nil, calendar: calendar), now: now)
    }

    static func taskDate(
        dueAt: Date,
        hasTime: Bool,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Date? {
        future(reminderDate(anchor: dueAt, hasTime: hasTime, kind: .taskDue,
                            timedPreset: nil, datePreset: nil, calendar: calendar), now: now)
    }

    private static func future(_ date: Date?, now: Date) -> Date? {
        guard let date, date > now else { return nil }
        return date
    }
}
