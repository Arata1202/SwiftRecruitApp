import Foundation

/// Transient editor memory only; persisted preferences remain the source of truth.
struct NotificationTimingPresentation {
    enum DayChoice: String, CaseIterable {
        case sameDay = "当日", previousDay = "前日", arbitrary = "○日前"
    }

    private struct CustomMemory {
        var last: CustomNotificationTiming?
        var elapsed: CustomNotificationTiming?
        var calendar: CustomNotificationTiming?
        var arbitraryDays = 2
        var selectedDay: DayChoice?

        mutating func remember(_ custom: CustomNotificationTiming?) {
            guard let custom else { return }
            last = custom
            if custom.mode == .elapsed {
                elapsed = custom
            } else {
                calendar = custom
                if selectedDay == .arbitrary || (custom.value != 0 && custom.value != 1) { arbitraryDays = custom.value }
            }
        }
    }

    private var timed = CustomMemory()
    private var date = CustomMemory()

    static func elapsedTitle(kind: NotificationAnchor) -> String {
        kind == .selectionStart ? "開始の前" : "期限の前"
    }

    static func elapsedInputTitle(kind: NotificationAnchor, unit: CustomNotificationTiming.Unit) -> String {
        let anchor = kind == .selectionStart ? "開始の何" : "期限の何"
        return anchor + (unit == .hours ? "時間前" : "分前")
    }

    static func selection(enabled: Bool, hasTime: Bool, kind: NotificationAnchor,
                          timed: TimedNotificationPreset?, date: DateNotificationPreset?,
                          custom: CustomNotificationTiming?) -> String {
        if enabled, custom != nil { return "custom" }
        return NotificationTimingChoice.value(enabled: enabled, hasTime: hasTime, kind: kind, timed: timed, date: date)
    }

    static func customTitle(_ custom: CustomNotificationTiming?) -> String {
        guard let custom else { return "カスタム…" }
        guard custom.isValid(hasTime: true) else { return "カスタム（要入力）…" }
        let summary: String
        if custom.mode == .elapsed {
            summary = "\(custom.value)\(custom.unit == .hours ? "時間前" : "分前")"
        } else {
            let day = custom.value == 0 ? "当日" : custom.value == 1 ? "前日" : "\(custom.value)日前"
            summary = "\(day)\(custom.hour!):" + String(format: "%02d", custom.minute!)
        }
        return "\(summary)（カスタム）…"
    }

    func dayChoice(_ custom: CustomNotificationTiming, hasTime: Bool) -> DayChoice {
        let selected = (hasTime ? timed : date).selectedDay
        if selected == .arbitrary { return .arbitrary }
        return custom.value == 0 ? .sameDay : custom.value == 1 ? .previousDay : .arbitrary
    }

    mutating func editNumber(_ text: String, custom: inout CustomNotificationTiming, hasTime: Bool) {
        if custom.mode == .calendar {
            if hasTime { timed.selectedDay = .arbitrary } else { date.selectedDay = .arbitrary }
        }
        custom.value = CustomNotificationTiming.parsedInput(text) ?? -1
    }

    mutating func reset(custom: CustomNotificationTiming?, hasTime: Bool) {
        if hasTime { timed = CustomMemory() } else { date = CustomMemory() }
        remember(custom, hasTime: hasTime)
    }

    static func inputMessage(_ custom: CustomNotificationTiming, hasTime: Bool) -> String? {
        custom.inputMessage(hasTime: hasTime)
    }

    mutating func remember(_ custom: CustomNotificationTiming?, hasTime: Bool) {
        if hasTime { timed.remember(custom) } else { date.remember(custom) }
    }

    mutating func select(_ value: String, hasTime: Bool, kind: NotificationAnchor,
                         enabled: inout Bool, timedPreset: inout TimedNotificationPreset?,
                         datePreset: inout DateNotificationPreset?, custom: inout CustomNotificationTiming?) {
        remember(custom, hasTime: hasTime)
        if value == "custom" {
            enabled = true
            if custom == nil {
                let memory = hasTime ? timed : date
                custom = memory.last ?? (hasTime ? .elapsed() : .calendar())
            }
        } else {
            let validPreset = hasTime ? TimedNotificationPreset(rawValue: value) != nil : DateNotificationPreset(rawValue: value) != nil
            if validPreset { custom = nil }
            NotificationTimingChoice.select(value, hasTime: hasTime, kind: kind,
                                            enabled: &enabled, timed: &timedPreset, date: &datePreset)
        }
    }

    mutating func changeMode(_ mode: CustomNotificationTiming.Mode, custom: inout CustomNotificationTiming, hasTime: Bool) {
        remember(custom, hasTime: hasTime)
        let memory = hasTime ? timed : date
        custom = mode == .elapsed ? (memory.elapsed ?? .elapsed()) : (memory.calendar ?? .calendar())
    }

    mutating func changeDay(_ choice: DayChoice, custom: inout CustomNotificationTiming, hasTime: Bool) {
        remember(custom, hasTime: hasTime)
        if hasTime { timed.selectedDay = choice } else { date.selectedDay = choice }
        switch choice {
        case .sameDay: custom.value = 0
        case .previousDay: custom.value = 1
        case .arbitrary: custom.value = (hasTime ? timed : date).arbitraryDays
        }
    }
}
