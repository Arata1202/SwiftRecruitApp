import Foundation

enum AbsoluteNotificationTiming {
    static func minute(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .minute, for: date)?.start ?? date
    }

    static func initialDate(computed: Date?, now: Date = Date(), calendar: Calendar = .current) -> Date {
        if let computed, minute(computed, calendar: calendar) > now {
            return minute(computed, calendar: calendar)
        }
        return minute(now.addingTimeInterval(3_600), calendar: calendar)
    }

    static func validationMessage(_ date: Date, original: Date?, now: Date = Date()) -> String? {
        guard date.timeIntervalSinceReferenceDate.isFinite else { return "有効な通知日時を指定してください。" }
        guard date != original, date <= now else { return nil }
        return "これからの通知日時を指定してください。"
    }

    static func anchorWarning(_ date: Date?, anchor: Date?, hasTime: Bool, kind: NotificationAnchor, calendar: Calendar = .current) -> String? {
        guard let date, let anchor else { return nil }
        let after = hasTime ? date > anchor
            : calendar.startOfDay(for: date) > calendar.startOfDay(for: anchor)
        guard after else { return nil }
        let label = kind == .selectionStart ? "開始" : "期限"
        return "通知日時が" + label + "より後です。必要に応じて通知日・時刻を変更してください。"
    }
}

/// Session-local restore memory includes the presets guarded by database compatibility triggers.
struct AbsoluteNotificationSelection {
    private struct Legacy {
        var custom: CustomNotificationTiming
        var timedPreset: TimedNotificationPreset?
        var datePreset: DateNotificationPreset?
    }
    private struct Absolute {
        var date: Date
        var timedPreset: TimedNotificationPreset?
        var datePreset: DateNotificationPreset?
        var timedCustom: CustomNotificationTiming?
        var dateCustom: CustomNotificationTiming?
    }
    private var timed: Legacy?
    private var date: Legacy?
    private var absolute: Absolute?

    func rememberedCustom(hasTime: Bool) -> CustomNotificationTiming? { (hasTime ? timed : date)?.custom }

    mutating func select(_ value: String, hasTime: Bool, kind: NotificationAnchor, computed: Date?,
                         enabled: inout Bool, absoluteAt: inout Date?,
                         timedPreset: inout TimedNotificationPreset?, datePreset: inout DateNotificationPreset?,
                         timedCustom: inout CustomNotificationTiming?, dateCustom: inout CustomNotificationTiming?,
                         now: Date = Date()) {
        if let custom = hasTime ? timedCustom : dateCustom {
            let memory = Legacy(custom: custom, timedPreset: timedPreset, datePreset: datePreset)
            if hasTime { timed = memory } else { date = memory }
        }
        if let absoluteAt {
            absolute = Absolute(date: absoluteAt, timedPreset: timedPreset, datePreset: datePreset,
                                timedCustom: timedCustom, dateCustom: dateCustom)
        }
        if value == "absolute" {
            if let absolute {
                absoluteAt = absolute.date
                timedPreset = absolute.timedPreset
                datePreset = absolute.datePreset
                timedCustom = absolute.timedCustom
                dateCustom = absolute.dateCustom
            } else {
                absoluteAt = AbsoluteNotificationTiming.initialDate(computed: computed, now: now)
            }
            enabled = true
        } else if value == "custom" {
            guard let previous = hasTime ? timed : date else { return }
            if hasTime {
                timedCustom = previous.custom
                timedPreset = previous.timedPreset
            } else {
                dateCustom = previous.custom
                datePreset = previous.datePreset
            }
            absoluteAt = nil
            enabled = true
        } else if value == "none" {
            enabled = false
        } else {
            let valid = hasTime ? TimedNotificationPreset(rawValue: value) != nil : DateNotificationPreset(rawValue: value) != nil
            guard valid else { return }
            if hasTime { timedCustom = nil } else { dateCustom = nil }
            absoluteAt = nil
            NotificationTimingChoice.select(value, hasTime: hasTime, kind: kind,
                                            enabled: &enabled, timed: &timedPreset, date: &datePreset)
        }
    }
}
