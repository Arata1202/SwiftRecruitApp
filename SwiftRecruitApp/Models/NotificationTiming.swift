import Foundation

/// Timed day offsets are elapsed 24/72 hours, not calendar-day subtraction.
enum TimedNotificationPreset: String, Codable, CaseIterable, Sendable {
    case atTime = "at_time"
    case tenMinutes = "ten_minutes"
    case thirtyMinutes = "thirty_minutes"
    case oneHour = "one_hour"
    case oneDay = "one_day"
    case threeDays = "three_days"

    var secondsBefore: TimeInterval {
        switch self {
        case .atTime: 0
        case .tenMinutes: 600
        case .thirtyMinutes: 1_800
        case .oneHour: 3_600
        case .oneDay: 86_400
        case .threeDays: 259_200
        }
    }

    var title: String {
        switch self {
        case .atTime: "指定時刻"
        case .tenMinutes: "10分前"
        case .thirtyMinutes: "30分前"
        case .oneHour: "1時間前"
        case .oneDay: "1日前（24時間前）"
        case .threeDays: "3日前（72時間前）"
        }
    }
}

enum DateNotificationPreset: String, Codable, CaseIterable, Sendable {
    case sameDay = "same_day"
    case previousDay = "previous_day"
    case threeDays = "three_days"

    var daysBefore: Int {
        switch self {
        case .sameDay: 0
        case .previousDay: 1
        case .threeDays: 3
        }
    }

    var title: String {
        switch self {
        case .sameDay: "当日 9:00"
        case .previousDay: "前日 9:00"
        case .threeDays: "3日前 9:00"
        }
    }
}

enum NotificationAnchor {
    case selectionStart, selectionDeadline, taskDue
}

extension NotificationScheduleCalculator {
    /// Nil retains the legacy schedule. Precision changes retain both independent choices.
    static func reminderDate(
        anchor: Date?, hasTime: Bool, kind: NotificationAnchor,
        timedPreset: TimedNotificationPreset?, datePreset: DateNotificationPreset?,
        calendar: Calendar = .current
    ) -> Date? {
        guard let anchor else { return nil }
        if hasTime, let timedPreset {
            return anchor.addingTimeInterval(-timedPreset.secondsBefore)
        }
        if !hasTime, let datePreset {
            guard let day = calendar.date(byAdding: .day, value: -datePreset.daysBefore, to: anchor) else { return nil }
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)
        }
        switch kind {
        case .selectionDeadline:
            guard let day = calendar.date(byAdding: .day, value: -1, to: anchor) else { return nil }
            return calendar.date(bySettingHour: 20, minute: 0, second: 0, of: day)
        case .selectionStart:
            return hasTime ? anchor.addingTimeInterval(-3_600)
                : calendar.date(bySettingHour: 9, minute: 0, second: 0, of: anchor)
        case .taskDue:
            return hasTime ? anchor : calendar.date(bySettingHour: 9, minute: 0, second: 0, of: anchor)
        }
    }

    static func reminderDescription(_ date: Date?, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date else { return "日程が未設定のため、通知されません。" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy年M月d日 H:mm"
        let timing = formatter.string(from: date)
        return date > now
            ? "通知予定：\(timing)。端末の通知設定によっては届かない場合があります。"
            : "通知時刻（\(timing)）を過ぎているため、通知されません。設定は保持されます。"
    }
}
