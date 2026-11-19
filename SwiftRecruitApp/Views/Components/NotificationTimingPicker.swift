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
    @State private var presentation = NotificationTimingPresentation()
    @State private var showsRelativeEditor = false

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
                if choices.timedChoices(activeSelection: selection.wrappedValue).contains(.threeDays) {
                    Text("72時間前（以前の設定）").tag("three_days")
                }
            } else {
                Text("当日").tag("same_day")
                Text("1日前").tag("previous_day")
                Text("2日前").tag("relative_2")
                Text("1週間前").tag("relative_7")
                if choices.dateChoices(activeSelection: selection.wrappedValue).contains(.threeDays) {
                    Text("3日前").tag("three_days")
                }
            }
            Text("カスタム…").tag("relative_custom")
            if absoluteAt != nil || choices.hasRememberedAbsolute {
                Text("以前の日時指定").tag("absolute")
            }
            if hasLegacyCustom {
                Text("以前のカスタム設定").tag("custom")
            }
        }
        .pickerStyle(.menu)
        .sheet(isPresented: $showsRelativeEditor) {
            RelativeNotificationEditor(initial: relativeValue ?? rememberedRelative ?? .init(), hasTime: hasTime) { value in
                selectRelative(value)
            }
        }
        .onChange(of: resetRevision) {
            choices = AbsoluteNotificationSelection()
            presentation.reset(custom: timedCustom, hasTime: true)
            presentation.reset(custom: dateCustom, hasTime: false)
        }
        if !hasTime, enabled, absoluteAt == nil, (activeCustom == nil || relativeValue != nil) {
            Text("通知時刻は9:00です").font(.footnote).foregroundStyle(.secondary)
        }
        if enabled, absoluteAt != nil {
            DatePicker("通知日", selection: absoluteDate, displayedComponents: .date)
            DatePicker("通知時刻", selection: absoluteDate, displayedComponents: .hourAndMinute)
            if let warning = AbsoluteNotificationTiming.anchorWarning(absoluteAt, anchor: anchorDate, hasTime: hasTime, kind: kind) {
                Text(warning).font(.footnote).foregroundStyle(.orange)
            }
        } else if enabled, let relative = relativeValue, selection.wrappedValue == "relative_custom" {
            Button {
                showsRelativeEditor = true
            } label: {
                HStack {
                    Text("通知タイミング")
                    Spacer()
                    Text(relative.title).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }.frame(minHeight: 44).fullWidthTappableArea()
            }.buttonStyle(.plain)
        } else if enabled, activeCustom != nil, relativeValue == nil {
            customControls
        }
    }

    private var selection: Binding<String> {
        Binding(
            get: {
                if enabled, absoluteAt != nil { return "absolute" }
                if enabled, let relative = relativeValue {
                    if relative == .init(value: 2, unit: .days) { return "relative_2" }
                    if relative == .init(value: 1, unit: .weeks) { return "relative_7" }
                    return "relative_custom"
                }
                return NotificationTimingPresentation.selection(enabled: enabled, hasTime: hasTime, kind: kind,
                    timed: timedPreset, date: datePreset, custom: activeCustom)
            },
            set: { value in
                if value == "relative_custom" { showsRelativeEditor = true; return }
                if value == "relative_2" || value == "relative_7" {
                    selectRelative(.init(value: value == "relative_2" ? 2 : 7, unit: .days))
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

    private var relativeValue: RelativeNotificationTiming? {
        guard let activeCustom else { return nil }
        return RelativeNotificationTiming(custom: activeCustom, hasTime: hasTime)
    }

    private var rememberedRelative: RelativeNotificationTiming? {
        guard let value = choices.rememberedRelativeCustom(hasTime: hasTime) else { return nil }
        return RelativeNotificationTiming(custom: value, hasTime: hasTime)
    }

    private var hasLegacyCustom: Bool {
        choices.hasRememberedLegacyCustom(hasTime: hasTime) ||
            [activeCustom, choices.rememberedCustom(hasTime: hasTime)].compactMap { $0 }.contains {
                RelativeNotificationTiming(custom: $0, hasTime: hasTime) == nil
            }
    }

    private func selectRelative(_ value: RelativeNotificationTiming) {
        choices.selectRelative(value, hasTime: hasTime, kind: kind,
                               enabled: &enabled, absoluteAt: &absoluteAt,
                               timedPreset: &timedPreset, datePreset: &datePreset,
                               timedCustom: &timedCustom, dateCustom: &dateCustom)
    }

    private var absoluteDate: Binding<Date> {
        Binding(get: { absoluteAt ?? AbsoluteNotificationTiming.initialDate(computed: nil) }, set: {
            absoluteAt = AbsoluteNotificationTiming.minute($0)
        })
    }

    private var activeCustom: CustomNotificationTiming? {
        get { hasTime ? timedCustom : dateCustom }
        nonmutating set {
            if hasTime { timedCustom = newValue } else { dateCustom = newValue }
        }
    }

    private func numberPicker(_ custom: CustomNotificationTiming, title: String) -> some View {
        NotificationNumberPicker(title: title, kind: .init(custom: custom), value: custom.value) { number in
            var updated = custom
            presentation.editNumber(String(number), custom: &updated, hasTime: hasTime)
            activeCustom = updated
        }
    }

    @ViewBuilder private var customControls: some View {
        if let custom = activeCustom {
            if hasTime {
                Picker("指定方法", selection: Binding(get: { custom.mode }, set: { mode in
                    var updated = custom
                    presentation.changeMode(mode, custom: &updated, hasTime: hasTime)
                    activeCustom = updated
                })) {
                    Text(NotificationTimingPresentation.elapsedTitle(kind: kind)).tag(CustomNotificationTiming.Mode.elapsed)
                    Text("日と時刻を指定").tag(CustomNotificationTiming.Mode.calendar)
                }
                .pickerStyle(.menu)
            }
            if custom.mode == .elapsed {
                numberPicker(custom, title: NotificationTimingPresentation.elapsedInputTitle(kind: kind, unit: custom.unit ?? .minutes))
                Picker(NotificationTimingPresentation.elapsedTitle(kind: kind) + "の単位", selection: Binding(get: { custom.unit ?? .minutes }, set: { unit in
                    var updated = custom
                    updated.unit = unit
                    activeCustom = updated
                })) {
                    Text("分前").tag(CustomNotificationTiming.Unit.minutes)
                    Text("時間前").tag(CustomNotificationTiming.Unit.hours)
                }
                .pickerStyle(.menu)
            } else {
                Picker("通知する日", selection: Binding(get: {
                    presentation.dayChoice(custom, hasTime: hasTime)
                }, set: { choice in
                    var updated = custom
                    presentation.changeDay(choice, custom: &updated, hasTime: hasTime)
                    activeCustom = updated
                })) {
                    ForEach(NotificationTimingPresentation.DayChoice.allCases, id: \.self) { choice in
                        Text(choice.rawValue).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                if presentation.dayChoice(custom, hasTime: hasTime) == .arbitrary {
                    numberPicker(custom, title: "何日前")
                }
                DatePicker("通知時刻", selection: clock, displayedComponents: .hourAndMinute)
                    .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            }
        }
    }

    // This is a wall-clock input, not an absolute notification date.
    private var clock: Binding<Date> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2001, month: 1, day: 15))!
        return Binding(get: {
            calendar.date(bySettingHour: activeCustom?.hour ?? 9, minute: activeCustom?.minute ?? 0, second: 0, of: day) ?? day
        }, set: { date in
            var custom = activeCustom ?? .calendar()
            custom.hour = calendar.component(.hour, from: date)
            custom.minute = calendar.component(.minute, from: date)
            activeCustom = custom
        })
    }

}
