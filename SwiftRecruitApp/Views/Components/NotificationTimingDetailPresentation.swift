import Foundation

/// Read-only effective preference, using the same relative labels as the editor.
/// Reading this representation never normalizes or updates saved preferences.
struct NotificationTimingDetailPresentation {
    let timing: String
    let clock: String?

    init(enabled: Bool, hasTime: Bool, kind: NotificationAnchor, anchor: Date?,
         timed: TimedNotificationPreset?, date: DateNotificationPreset?,
         timedCustom: CustomNotificationTiming?, dateCustom: CustomNotificationTiming?,
         absoluteAt: Date? = nil, calendar: Calendar = .current) {
        guard enabled else { timing = String(localized: "なし"); clock = nil; return }
        if let absoluteAt {
            timing = absoluteAt.formatted(.dateTime.year().month().day().hour().minute())
            clock = nil
            return
        }
        let custom = hasTime ? timedCustom : dateCustom
        if let custom, !custom.isValid(hasTime: hasTime) {
            timing = String(localized: "この通知タイミングは使用できません。編集画面で選び直してください。")
            clock = nil
            return
        }
        let relative = custom.flatMap {
            RelativeNotificationTiming(custom: hasTime ? $0 : $0.standardClockRepresentation, hasTime: hasTime)
        }
        let usesClock: Bool
        if let relative {
            timing = relative.title
            usesClock = !hasTime || relative.usesNotificationClock
        } else if let custom, custom.mode == .calendar {
            timing = custom.value == 0 ? String(localized: "当日") : String(localized: "\(custom.value)日前")
            usesClock = true
        } else if hasTime {
            let preset = timed ?? kind.defaultTimedPreset
            // Match the editor's day-unit labels without altering elapsed semantics.
            switch preset {
            case .oneDay: timing = String(localized: "1日前")
            case .threeDays: timing = String(localized: "3日前")
            default: timing = NotificationTimingChoice.title(for: preset, kind: kind)
            }
            usesClock = preset == .oneDay || preset == .threeDays
        } else {
            let days = (date ?? kind.defaultDatePreset).daysBefore
            timing = days == 0 ? String(localized: "当日") : String(localized: "\(days)日前")
            usesClock = true
        }
        if usesClock {
            let computed = NotificationScheduleCalculator.reminderDate(
                anchor: anchor, hasTime: hasTime, kind: kind, timedPreset: timed, datePreset: date,
                timedCustom: timedCustom, dateCustom: dateCustom, calendar: calendar)
            let hour = computed.map { calendar.component(.hour, from: $0) } ?? custom?.hour ?? 9
            let minute = computed.map { calendar.component(.minute, from: $0) } ?? custom?.minute ?? 0
            clock = String(format: "%d:%02d", hour, minute)
        } else {
            clock = nil
        }
    }
}
