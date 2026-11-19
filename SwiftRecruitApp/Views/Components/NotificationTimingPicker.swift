import SwiftUI

struct NotificationTimingPicker: View {
    @Binding var enabled: Bool
    @Binding var timedPreset: TimedNotificationPreset?
    @Binding var datePreset: DateNotificationPreset?
    @Binding var timedCustom: CustomNotificationTiming?
    @Binding var dateCustom: CustomNotificationTiming?
    @Binding var absoluteAt: Date?
    let anchorDate: Date?
    let hasTime: Bool
    let kind: NotificationAnchor
    var resetRevision: Int = 0
    @State private var choices = AbsoluteNotificationSelection()
    @State private var timedRelative = RelativeNotificationPresentation()
    @State private var dateRelative = RelativeNotificationPresentation()

    var body: some View {
        Picker("通知タイミング", selection: selection) {
            Text("なし").tag("none")
            if hasTime {
                ForEach([TimedNotificationPreset.atTime, .tenMinutes, .thirtyMinutes, .oneHour], id: \.self) { preset in
                    Text(NotificationTimingChoice.title(for: preset, kind: kind)).tag(preset.rawValue)
                }
                Text("1日前").tag("one_day")
                Text("2日前").tag("relative_2")
                Text("1週間前").tag("relative_7")
            } else {
                Text("当日").tag("same_day")
                Text("1日前").tag("previous_day")
                Text("2日前").tag("relative_2")
                Text("1週間前").tag("relative_7")
            }
            Text("カスタム…").tag("relative_custom")
            if let currentValueTitle {
                Text(currentValueTitle).tag("current")
            }
        }
        .pickerStyle(.menu)
        .onChange(of: resetRevision) {
            choices = AbsoluteNotificationSelection()
            timedRelative = RelativeNotificationPresentation()
            dateRelative = RelativeNotificationPresentation()
        }
        if !hasTime, enabled, absoluteAt == nil, (activeCustom == nil || relativeValue != nil) {
            LabeledContent("通知時刻", value: "9:00")
        }
        if enabled, absoluteAt != nil {
            if let warning = AbsoluteNotificationTiming.anchorWarning(absoluteAt, anchor: anchorDate, hasTime: hasTime, kind: kind) {
                Text(warning).font(.footnote).foregroundStyle(.orange)
            }
        } else if enabled, let relative = relativeValue, selection.wrappedValue == "relative_custom" {
            RelativeNotificationEditor(value: Binding(get: { relative }, set: { value in
                guard value.custom(hasTime: hasTime) != nil else { return }
                relativePresentation.edit(value)
                selectRelative(value)
            }), hasTime: hasTime)
        }
    }

    private var selection: Binding<String> {
        Binding(
            get: {
                if currentValueTitle != nil { return "current" }
                if enabled, relativeValue != nil {
                    if relativePresentation.isCustom { return "relative_custom" }
                    let normalized = activeCustom.flatMap { RelativeNotificationTiming(custom: $0, hasTime: hasTime) }
                    if normalized == .init(value: 2, unit: .days) { return "relative_2" }
                    if normalized == .init(value: 1, unit: .weeks) { return "relative_7" }
                    return "relative_custom"
                }
                return NotificationTimingPresentation.selection(enabled: enabled, hasTime: hasTime, kind: kind,
                    timed: timedPreset, date: datePreset, custom: activeCustom)
            },
            set: { value in
                guard value != "current" else { return }
                if value == "relative_custom" {
                    let initial = relativeValue ?? rememberedRelative ?? .init()
                    relativePresentation.edit(initial)
                    selectRelative(initial)
                    return
                }
                relativePresentation.selectPreset()
                if value == "relative_2" || value == "relative_7" {
                    selectRelative(.init(value: value == "relative_2" ? 2 : 1, unit: value == "relative_2" ? .days : .weeks))
                    return
                }
                let computed = NotificationScheduleCalculator.reminderDate(
                    anchor: anchorDate, hasTime: hasTime, kind: kind,
                    timedPreset: timedPreset, datePreset: datePreset,
                    timedCustom: timedCustom, dateCustom: dateCustom)
                choices.select(value, hasTime: hasTime, kind: kind, computed: computed,
                               enabled: &enabled, absoluteAt: &absoluteAt,
                               timedPreset: &timedPreset, datePreset: &datePreset,
                               timedCustom: &timedCustom, dateCustom: &dateCustom)
            }
        )
    }

    private var relativePresentation: RelativeNotificationPresentation {
        get { hasTime ? timedRelative : dateRelative }
        nonmutating set {
            if hasTime { timedRelative = newValue } else { dateRelative = newValue }
        }
    }

    private var relativeValue: RelativeNotificationTiming? {
        guard let activeCustom else { return nil }
        return relativePresentation.value(custom: activeCustom, hasTime: hasTime)
    }

    private var rememberedRelative: RelativeNotificationTiming? {
        guard let value = choices.rememberedRelativeCustom(hasTime: hasTime) else { return nil }
        return relativePresentation.value(custom: value, hasTime: hasTime)
    }

    private var currentValueTitle: String? {
        guard enabled else { return nil }
        if let absoluteAt {
            return absoluteAt.formatted(.dateTime.year().month().day().hour().minute())
        }
        if let custom = activeCustom, relativeValue == nil {
            guard custom.isValid(hasTime: hasTime) else { return "要確認" }
            let day = custom.value == 0 ? "当日" : "\(custom.value)日前"
            return day + String(format: " %d:%02d", custom.hour ?? 9, custom.minute ?? 0)
        }
        if activeCustom == nil, (hasTime ? timedPreset == .threeDays : datePreset == .threeDays) {
            return "3日前"
        }
        return nil
    }

    private func selectRelative(_ value: RelativeNotificationTiming) {
        choices.selectRelative(value, hasTime: hasTime, kind: kind,
                               enabled: &enabled, absoluteAt: &absoluteAt,
                               timedPreset: &timedPreset, datePreset: &datePreset,
                               timedCustom: &timedCustom, dateCustom: &dateCustom)
    }

    private var activeCustom: CustomNotificationTiming? {
        hasTime ? timedCustom : dateCustom
    }
}
