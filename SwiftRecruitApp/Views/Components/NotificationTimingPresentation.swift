enum NotificationTimingPresentation {
    static func selection(enabled: Bool, hasTime: Bool, kind: NotificationAnchor,
                          timed: TimedNotificationPreset?, date: DateNotificationPreset?,
                          custom: CustomNotificationTiming?) -> String {
        if enabled, custom != nil { return "custom" }
        return NotificationTimingChoice.value(enabled: enabled, hasTime: hasTime, kind: kind, timed: timed, date: date)
    }
}
