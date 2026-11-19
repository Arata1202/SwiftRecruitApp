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

/// A separate nullable preference overrides (but never rewrites) the legacy preset.
struct CustomNotificationTiming: Codable, Hashable, Sendable {
    enum Mode: String, Codable, CaseIterable, Sendable { case elapsed, calendar }
    enum Unit: String, Codable, CaseIterable, Sendable { case minutes, hours }
    var mode: Mode
    var value: Int
    var unit: Unit?
    var hour: Int?
    var minute: Int?

    static func elapsed(_ value: Int = 60, unit: Unit = .minutes) -> Self {
        Self(mode: .elapsed, value: value, unit: unit)
    }

    static func calendar(daysBefore: Int = 0, hour: Int = 9, minute: Int = 0) -> Self {
        Self(mode: .calendar, value: daysBefore, hour: hour, minute: minute)
    }

    static func parsedInput(_ text: String) -> Int? {
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return Int(text)
    }

    func inputMessage(hasTime: Bool) -> String? {
        guard !isValid(hasTime: hasTime) else { return nil }
        if mode == .elapsed {
            return unit == .hours ? "1〜33,600時間前で入力してください。" : "1〜2,016,000分前で入力してください。"
        }
        return "0〜1,400日前と有効な時刻を入力してください。"
    }

    func isValid(hasTime: Bool) -> Bool {
        switch mode {
        case .elapsed:
            guard hasTime, let unit, hour == nil, minute == nil else { return false }
            return (1...(unit == .minutes ? 2_016_000 : 33_600)).contains(value)
        case .calendar:
            guard unit == nil, let hour, let minute else { return false }
            return (0...1_400).contains(value) && (0...23).contains(hour) && (0...59).contains(minute)
        }
    }
}

enum NotificationTimingError: LocalizedError {
    case invalid, invalidAbsolute
    var errorDescription: String? {
        switch self {
        case .invalid: "通知の指定が無効です。入力範囲と開始・期限より後になっていないか確認してください。"
        case .invalidAbsolute: "これからの通知日時を指定してください。"
        }
    }
}
extension NotificationScheduleCalculator {
    /// Missing preferences resolve to the same context defaults as the editor and persistence.
    static func reminderDate(
        anchor: Date?, hasTime: Bool, kind: NotificationAnchor,
        timedPreset: TimedNotificationPreset?, datePreset: DateNotificationPreset?,
        timedCustom: CustomNotificationTiming? = nil, dateCustom: CustomNotificationTiming? = nil,
        absoluteAt: Date? = nil, calendar: Calendar = .current
    ) -> Date? {
        guard let anchor else { return nil }
        if let absoluteAt { return absoluteAt }
        if let custom = hasTime ? timedCustom : dateCustom {
            guard custom.isValid(hasTime: hasTime) else { return nil }
            let result: Date?
            switch custom.mode {
            case .elapsed:
                result = anchor.addingTimeInterval(-Double(custom.value) * (custom.unit == .hours ? 3_600 : 60))
            case .calendar:
                result = calendarReminder(anchor: anchor, daysBefore: custom.value,
                                          hour: custom.hour!, minute: custom.minute!, calendar: calendar)
            }
            guard let result, !hasTime || result <= anchor else { return nil }
            return result
        }
        if hasTime {
            return anchor.addingTimeInterval(-(timedPreset ?? kind.defaultTimedPreset).secondsBefore)
        }
        let preset = datePreset ?? kind.defaultDatePreset
        return calendarReminder(anchor: anchor, daysBefore: preset.daysBefore, hour: 9, minute: 0, calendar: calendar)
    }

    private static func calendarReminder(anchor: Date, daysBefore: Int, hour: Int, minute: Int, calendar: Calendar) -> Date? {
        guard let day = calendar.date(byAdding: .day, value: -daysBefore, to: calendar.startOfDay(for: anchor)),
              let result = calendar.nextDate(after: calendar.startOfDay(for: day).addingTimeInterval(-1),
                                             matching: DateComponents(hour: hour, minute: minute, second: 0),
                                             matchingPolicy: .nextTime, repeatedTimePolicy: .first),
              calendar.isDate(result, inSameDayAs: day) else { return nil }
        return result
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
            ? "通知予定：\(timing)"
            : "通知時刻（\(timing)）を過ぎているため、通知されません。"
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

extension NotificationScheduleCalculator {
    static func preferenceValidationMessage(timedCustom: CustomNotificationTiming?, dateCustom: CustomNotificationTiming?) -> String? {
        if let timedCustom, let message = timedCustom.inputMessage(hasTime: true) {
            return "時刻を指定する場合の通知：" + message
        }
        if let dateCustom, let message = dateCustom.inputMessage(hasTime: false) {
            return "日付のみの場合の通知：" + message
        }
        return nil
    }

    static func validationMessage(anchor: Date, hasTime: Bool, kind: NotificationAnchor,
                                  timedCustom: CustomNotificationTiming?, dateCustom: CustomNotificationTiming?,
                                  calendar: Calendar = .current) -> String? {
        guard let custom = hasTime ? timedCustom : dateCustom else { return nil }
        guard custom.isValid(hasTime: hasTime) else { return "通知の数値・時刻を入力範囲内で指定してください。" }
        guard reminderDate(anchor: anchor, hasTime: hasTime, kind: kind, timedPreset: nil, datePreset: nil,
                           timedCustom: timedCustom, dateCustom: dateCustom, calendar: calendar) != nil else {
            return "通知時刻が開始・期限より後、または指定した日に設定できないため、通知されません。通知設定を変更してください。"
        }
        return nil
    }
}
