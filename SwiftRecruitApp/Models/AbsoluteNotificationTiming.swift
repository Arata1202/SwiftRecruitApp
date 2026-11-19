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
    private var timedCompatibility: Legacy?
    private var dateCompatibility: Legacy?
    private var timedRelative: Legacy?
    private var dateRelative: Legacy?
    private var absolute: Absolute?
    private var remembersThreeDays = false
    private var remembersDateThreeDays = false

    func timedChoices(activeSelection: String) -> [TimedNotificationPreset] {
        TimedNotificationPreset.allCases.filter {
            $0 != .threeDays || activeSelection == $0.rawValue || remembersThreeDays
        }
    }

    func dateChoices(activeSelection: String) -> [DateNotificationPreset] {
        DateNotificationPreset.allCases.filter { $0 != .threeDays || activeSelection == $0.rawValue || remembersDateThreeDays }
    }

    mutating func selectRelative(_ value: RelativeNotificationTiming, hasTime: Bool, kind: NotificationAnchor,
                                enabled: inout Bool, absoluteAt: inout Date?,
                                timedPreset: inout TimedNotificationPreset?, datePreset: inout DateNotificationPreset?,
                                timedCustom: inout CustomNotificationTiming?, dateCustom: inout CustomNotificationTiming?) {
        guard let custom = value.custom(hasTime: hasTime) else { return }
        let original = hasTime ? timedCustom : dateCustom
        let remembered = hasTime ? timedRelative : dateRelative
        select("none", hasTime: hasTime, kind: kind, computed: nil,
               enabled: &enabled, absoluteAt: &absoluteAt,
               timedPreset: &timedPreset, datePreset: &datePreset,
               timedCustom: &timedCustom, dateCustom: &dateCustom)
        // A round trip through the editor must not normalize a saved wire representation.
        if original.flatMap({ RelativeNotificationTiming(custom: $0, hasTime: hasTime) }) != value {
            let restored = remembered.flatMap { RelativeNotificationTiming(custom: $0.custom, hasTime: hasTime) == value ? $0 : nil }
            if hasTime {
                timedCustom = restored?.custom ?? custom
                if let restored { timedPreset = restored.timedPreset }
            } else {
                dateCustom = restored?.custom ?? custom
                if let restored { datePreset = restored.datePreset }
            }
        }
        absoluteAt = nil
        enabled = true
    }

    var hasRememberedAbsolute: Bool { absolute != nil }

    func rememberedRelativeCustom(hasTime: Bool) -> CustomNotificationTiming? {
        guard let custom = (hasTime ? timedRelative : dateRelative)?.custom,
              RelativeNotificationTiming(custom: custom, hasTime: hasTime) != nil else { return nil }
        return custom
    }

    func rememberedCustom(hasTime: Bool) -> CustomNotificationTiming? {
        (hasTime ? (timedCompatibility ?? timed) : (dateCompatibility ?? date))?.custom
    }

    mutating func select(_ value: String, hasTime: Bool, kind: NotificationAnchor, computed: Date?,
                         enabled: inout Bool, absoluteAt: inout Date?,
                         timedPreset: inout TimedNotificationPreset?, datePreset: inout DateNotificationPreset?,
                         timedCustom: inout CustomNotificationTiming?, dateCustom: inout CustomNotificationTiming?,
                         now: Date = Date()) {
        if enabled, hasTime, absoluteAt == nil, timedCustom == nil, timedPreset == .threeDays {
            remembersThreeDays = true
        }
        if enabled, !hasTime, absoluteAt == nil, dateCustom == nil, datePreset == .threeDays {
            remembersDateThreeDays = true
        }
        if let custom = hasTime ? timedCustom : dateCustom {
            let memory = Legacy(custom: custom, timedPreset: timedPreset, datePreset: datePreset)
            if RelativeNotificationTiming(custom: custom, hasTime: hasTime) == nil {
                if hasTime { timedCompatibility = memory } else { dateCompatibility = memory }
            } else {
                if hasTime { timedRelative = memory } else { dateRelative = memory }
            }
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
            guard let previous = hasTime ? (timedCompatibility ?? timed) : (dateCompatibility ?? date) else { return }
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
