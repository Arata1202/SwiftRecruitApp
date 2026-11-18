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
        case .oneDay: "24時間前"
        case .threeDays: "72時間前"
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

enum NotificationAnchor: Equatable {
    case selectionStart, selectionDeadline, taskDue

    var defaultTimedPreset: TimedNotificationPreset {
        switch self {
        case .selectionStart: .oneHour
        case .selectionDeadline: .oneDay
        case .taskDue: .atTime
        }
    }

    var defaultDatePreset: DateNotificationPreset {
        self == .selectionDeadline ? .previousDay : .sameDay
    }
}

extension NotificationScheduleCalculator {
    /// Missing preferences resolve to the same context defaults as the editor and persistence.
    static func reminderDate(
        anchor: Date?, hasTime: Bool, kind: NotificationAnchor,
        timedPreset: TimedNotificationPreset?, datePreset: DateNotificationPreset?,
        calendar: Calendar = .current
    ) -> Date? {
        guard let anchor else { return nil }
        if hasTime {
            return anchor.addingTimeInterval(-(timedPreset ?? kind.defaultTimedPreset).secondsBefore)
        }
        let preset = datePreset ?? kind.defaultDatePreset
        guard let day = calendar.date(byAdding: .day, value: -preset.daysBefore, to: anchor) else { return nil }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)
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

/// Shared picker semantics; none never discards either precision preference.
enum NotificationTimingChoice {
    static let none = "none"

    static func value(enabled: Bool, hasTime: Bool, kind: NotificationAnchor,
                      timed: TimedNotificationPreset?, date: DateNotificationPreset?) -> String {
        guard enabled else { return none }
        return hasTime ? (timed ?? kind.defaultTimedPreset).rawValue
            : (date ?? kind.defaultDatePreset).rawValue
    }

    static func title(for preset: TimedNotificationPreset, kind: NotificationAnchor) -> String {
        guard preset == .atTime else { return preset.title }
        return kind == .selectionStart ? "開始時刻" : "期限時刻"
    }

    static func select(_ value: String, hasTime: Bool, kind: NotificationAnchor,
                       enabled: inout Bool, timed: inout TimedNotificationPreset?, date: inout DateNotificationPreset?) {
        if value == none { enabled = false; return }
        if hasTime, let preset = TimedNotificationPreset(rawValue: value) {
            enabled = true
            timed = preset
        } else if !hasTime, let preset = DateNotificationPreset(rawValue: value) {
            enabled = true
            date = preset
        }
    }
}
