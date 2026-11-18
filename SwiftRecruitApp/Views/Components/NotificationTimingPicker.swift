import SwiftUI

struct NotificationTimingPicker: View {
    @Binding var enabled: Bool
    @Binding var timedPreset: TimedNotificationPreset?
    @Binding var datePreset: DateNotificationPreset?
    let hasTime: Bool

    var body: some View {
        Picker("通知タイミング", selection: selection) {
            Text("なし").tag("none")
            if hasTime {
                if timedPreset == nil { Text("従来の設定を維持").tag("legacy") }
                ForEach(TimedNotificationPreset.allCases, id: \.self) { preset in
                    Text(preset.title).tag(preset.rawValue)
                }
            } else {
                if datePreset == nil { Text("従来の設定を維持").tag("legacy") }
                ForEach(DateNotificationPreset.allCases, id: \.self) { preset in
                    Text(preset.title).tag(preset.rawValue)
                }
            }
        }
        .pickerStyle(.navigationLink)
        Text("時刻あり・日付のみの設定は別々に保持され、切り替えると各設定に戻ります。")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var selection: Binding<String> {
        Binding(
            get: {
                guard enabled else { return "none" }
                return (hasTime ? timedPreset?.rawValue : datePreset?.rawValue) ?? "legacy"
            },
            set: { value in
                enabled = value != "none"
                guard enabled, value != "legacy" else { return }
                if hasTime { timedPreset = TimedNotificationPreset(rawValue: value) }
                else { datePreset = DateNotificationPreset(rawValue: value) }
            }
        )
    }
}
