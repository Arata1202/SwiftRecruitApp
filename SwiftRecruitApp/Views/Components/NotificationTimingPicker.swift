import SwiftUI

struct NotificationTimingPicker: View {
    @Binding var enabled: Bool
    @Binding var timedPreset: TimedNotificationPreset?
    @Binding var datePreset: DateNotificationPreset?
    @Binding var timedCustom: CustomNotificationTiming?
    @Binding var dateCustom: CustomNotificationTiming?
    let hasTime: Bool
    let kind: NotificationAnchor
    var resetRevision: Int = 0
    @State private var presentation = NotificationTimingPresentation()

    var body: some View {
        Picker("通知タイミング", selection: selection) {
            Text("なし").tag("none")
            if hasTime {
                ForEach(TimedNotificationPreset.allCases, id: \.self) { preset in
                    Text(NotificationTimingChoice.title(for: preset, kind: kind)).tag(preset.rawValue)
                }
            } else {
                ForEach(DateNotificationPreset.allCases, id: \.self) { preset in
                    Text(preset.title).tag(preset.rawValue)
                }
            }
            Text(NotificationTimingPresentation.customTitle(activeCustom)).tag("custom")
        }
        .pickerStyle(.menu)
        .onChange(of: resetRevision) {
            presentation.reset(custom: timedCustom, hasTime: true)
            presentation.reset(custom: dateCustom, hasTime: false)
        }
        if enabled, activeCustom != nil {
            customControls
        }
        Text("時刻あり・日付のみの設定は別々に保持されます。")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var selection: Binding<String> {
        Binding(
            get: {
                NotificationTimingPresentation.selection(enabled: enabled, hasTime: hasTime, kind: kind,
                    timed: timedPreset, date: datePreset, custom: activeCustom)
            },
            set: { value in
                var custom = activeCustom
                presentation.select(value, hasTime: hasTime, kind: kind, enabled: &enabled,
                                    timedPreset: &timedPreset, datePreset: &datePreset, custom: &custom)
                activeCustom = custom
            }
        )
    }

    private var activeCustom: CustomNotificationTiming? {
        get { hasTime ? timedCustom : dateCustom }
        nonmutating set {
            if hasTime { timedCustom = newValue } else { dateCustom = newValue }
        }
    }

    private var numericText: Binding<String> {
        Binding(get: {
            guard let value = activeCustom?.value, value >= 0 else { return "" }
            return String(value)
        }, set: { text in
            var custom = activeCustom ?? .calendar()
            presentation.editNumber(text, custom: &custom, hasTime: hasTime)
            activeCustom = custom
        })
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
                HStack {
                    TextField(NotificationTimingPresentation.elapsedInputTitle(kind: kind, unit: custom.unit ?? .minutes), text: numericText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel(NotificationTimingPresentation.elapsedInputTitle(kind: kind, unit: custom.unit ?? .minutes))
                    Picker(NotificationTimingPresentation.elapsedTitle(kind: kind) + "の単位", selection: Binding(get: { custom.unit ?? .minutes }, set: { unit in
                        var updated = custom
                        updated.unit = unit
                        activeCustom = updated
                    })) {
                        Text("分前").tag(CustomNotificationTiming.Unit.minutes)
                        Text("時間前").tag(CustomNotificationTiming.Unit.hours)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
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
                    HStack {
                        TextField("何日前", text: numericText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text("日前")
                    }
                }
                DatePicker("通知時刻", selection: clock, displayedComponents: .hourAndMinute)
                    .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            }
            if let message = NotificationTimingPresentation.inputMessage(custom, hasTime: hasTime) {
                Text(message).font(.footnote).foregroundStyle(.red)
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
