import SwiftUI

struct NotificationTimingPicker: View {
    @Binding var enabled: Bool
    @Binding var timedPreset: TimedNotificationPreset?
    @Binding var datePreset: DateNotificationPreset?
    @Binding var timedCustom: CustomNotificationTiming?
    @Binding var dateCustom: CustomNotificationTiming?
    let hasTime: Bool
    let kind: NotificationAnchor

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
            Text("カスタム…").tag("custom")
        }
        .pickerStyle(.navigationLink)
        if enabled, activeCustom != nil {
            customControls
        }
        Text("時刻あり・日付のみの設定は別々に保持され、切り替えると各設定に戻ります。")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var selection: Binding<String> {
        Binding(
            get: {
                if enabled, activeCustom != nil { return "custom" }
                return NotificationTimingChoice.value(enabled: enabled, hasTime: hasTime, kind: kind,
                                               timed: timedPreset, date: datePreset)
            },
            set: { value in
                if value == "custom" {
                    enabled = true
                    if activeCustom == nil { activeCustom = hasTime ? .elapsed() : .calendar() }
                    return
                }
                if value != NotificationTimingChoice.none { activeCustom = nil }
                NotificationTimingChoice.select(value, hasTime: hasTime, kind: kind,
                                                enabled: &enabled, timed: &timedPreset, date: &datePreset)
            }
        )
    }

    private var activeCustom: CustomNotificationTiming? {
        get { hasTime ? timedCustom : dateCustom }
        nonmutating set {
            if hasTime { timedCustom = newValue } else { dateCustom = newValue }
        }
    }

    private func field<Value>(_ keyPath: WritableKeyPath<CustomNotificationTiming, Value>) -> Binding<Value> {
        Binding(get: { (activeCustom ?? .calendar())[keyPath: keyPath] }, set: { value in
            var custom = activeCustom ?? .calendar()
            custom[keyPath: keyPath] = value
            activeCustom = custom
        })
    }

    @ViewBuilder private var customControls: some View {
        if let custom = activeCustom {
            if hasTime {
                Picker("指定方法", selection: Binding(get: { custom.mode }, set: { mode in
                    activeCustom = mode == .elapsed ? .elapsed() : .calendar()
                })) {
                    Text("開始・期限からの時間差").tag(CustomNotificationTiming.Mode.elapsed)
                    Text("当日・日前の時刻").tag(CustomNotificationTiming.Mode.calendar)
                }
                .pickerStyle(.navigationLink)
            }
            if custom.mode == .elapsed {
                TextField("数値", value: field(\.value), format: .number)
                    .keyboardType(.numberPad)
                Picker("単位（前）", selection: Binding(get: { custom.unit ?? .minutes }, set: { unit in
                    var updated = custom
                    updated.unit = unit
                    activeCustom = updated
                })) {
                    Text("分前").tag(CustomNotificationTiming.Unit.minutes)
                    Text("時間前").tag(CustomNotificationTiming.Unit.hours)
                }
                Text(custom.unit == .hours ? "1〜8,760時間前で指定できます。" : "1〜525,600分前で指定できます。")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                TextField("何日前（当日は0）", value: field(\.value), format: .number)
                    .keyboardType(.numberPad)
                DatePicker("通知時刻", selection: clock, displayedComponents: .hourAndMinute)
                    .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                Text("0〜365日前。時刻は端末の現地時刻です。夏時間で存在しない時刻は当日内の次の有効時刻、重複する時刻は最初の時刻を使います。")
                    .font(.footnote).foregroundStyle(.secondary)
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
