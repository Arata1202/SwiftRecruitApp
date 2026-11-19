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
        Menu {
            menuOption("なし", id: "none")
            Divider()
            ForEach(ReminderMenuOption.options(hasTime: hasTime)) { option in
                menuOption(option.title, id: option.id)
            }
            Divider()
            menuOption("カスタム", id: "relative_custom")
        } label: {
            HStack {
                Text("通知タイミング")
                Spacer()
                Text(selectedMenuTitle).foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .onChange(of: resetRevision) {
            choices = AbsoluteNotificationSelection()
            timedRelative = RelativeNotificationPresentation()
            dateRelative = RelativeNotificationPresentation()
        }
        if let currentValueTitle { Text(currentValueTitle).foregroundStyle(.secondary) }
        if enabled, absoluteAt != nil {
            if let warning = AbsoluteNotificationTiming.anchorWarning(absoluteAt, anchor: anchorDate, hasTime: hasTime, kind: kind) {
                Text(warning).font(.footnote).foregroundStyle(.orange)
            }
        } else if enabled, let relative = relativeValue, selection.wrappedValue == "relative_custom", relative.isSelectable(hasTime: hasTime) {
            RelativeNotificationEditor(value: Binding(get: { relative }, set: { value in
                guard value.isSelectable(hasTime: hasTime) else { return }
                relativePresentation.edit(value)
                selectRelative(value)
            }), hasTime: hasTime)
        }
    }

    private var selectedMenuTitle: String {
        if selection.wrappedValue == "none" { return "なし" }
        return ReminderMenuOption.options(hasTime: hasTime)
            .first(where: { $0.id == selection.wrappedValue })?.title ?? "カスタム"
    }

    private func menuOption(_ title: String, id: String) -> some View {
        Button { selection.wrappedValue = id } label: {
            if selection.wrappedValue == id {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private var selection: Binding<String> {
        Binding(
            get: {
                if currentValueTitle != nil { return "relative_custom" }
                if enabled, relativeValue != nil {
                    if relativePresentation.isCustom { return "relative_custom" }
                    let normalized = activeCustom.flatMap { RelativeNotificationTiming(custom: $0, hasTime: hasTime) }
                    if let option = ReminderMenuOption.options(hasTime: hasTime).first(where: { $0.timing == normalized }) {
                        return option.id
                    }
                    return "relative_custom"
                }
                if enabled, let legacyRelative,
                   let option = ReminderMenuOption.options(hasTime: hasTime).first(where: { $0.timing == legacyRelative }) {
                    return option.id
                }
                return NotificationTimingPresentation.selection(enabled: enabled, hasTime: hasTime, kind: kind,
                    timed: timedPreset, date: datePreset, custom: activeCustom)
            },
            set: { value in
                if value == "relative_custom" {
                    let initial = RelativeNotificationTiming.initialSelection(
                        current: relativeValue ?? legacyRelative, remembered: rememberedRelative, hasTime: hasTime
                    )
                    relativePresentation.edit(initial)
                    selectRelative(initial)
                    return
                }
                relativePresentation.selectPreset()
                if let option = ReminderMenuOption.options(hasTime: hasTime).first(where: { $0.id == value }) {
                    selectRelative(option.timing)
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
        if let relative = relativeValue, !relative.isSelectable(hasTime: hasTime) {
            return relative.title
        }
        if let custom = activeCustom, relativeValue == nil {
            guard custom.isValid(hasTime: hasTime) else { return "要確認" }
            let day = custom.value == 0 ? "当日" : "\(custom.value)日前"
            return day + String(format: " %d:%02d", custom.hour ?? 9, custom.minute ?? 0)
        }
        if activeCustom == nil, let legacyRelative,
           !ReminderMenuOption.options(hasTime: hasTime).contains(where: { $0.timing == legacyRelative }) {
            return legacyRelative.title
        }
        if activeCustom == nil, hasTime, (timedPreset ?? kind.defaultTimedPreset) == .atTime {
            return NotificationTimingChoice.title(for: .atTime, kind: kind)
        }
        return nil
    }

    private var legacyRelative: RelativeNotificationTiming? {
        guard activeCustom == nil else { return nil }
        if hasTime {
            switch timedPreset ?? kind.defaultTimedPreset {
            case .atTime: return nil
            case .tenMinutes: return .init(value: 10, unit: .minutes)
            case .thirtyMinutes: return .init(value: 30, unit: .minutes)
            case .oneHour: return .init(value: 1, unit: .hours)
            case .oneDay: return .init(value: 1, unit: .days)
            case .threeDays: return .init(value: 3, unit: .days)
            }
        }
        return RelativeNotificationTiming(custom: .calendar(daysBefore: (datePreset ?? kind.defaultDatePreset).daysBefore), hasTime: false)
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
