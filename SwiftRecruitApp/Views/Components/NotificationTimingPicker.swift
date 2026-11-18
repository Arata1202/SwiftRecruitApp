import SwiftUI

struct NotificationTimingPicker: View {
    @Binding var enabled: Bool
    @Binding var timedPreset: TimedNotificationPreset?
    @Binding var datePreset: DateNotificationPreset?
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
        }
        .pickerStyle(.navigationLink)
        Text("時刻あり・日付のみの設定は別々に保持され、切り替えると各設定に戻ります。")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var selection: Binding<String> {
        Binding(
            get: {
                NotificationTimingChoice.value(enabled: enabled, hasTime: hasTime, kind: kind,
                                               timed: timedPreset, date: datePreset)
            },
            set: { value in
                NotificationTimingChoice.select(value, hasTime: hasTime, kind: kind,
                                                enabled: &enabled, timed: &timedPreset, date: &datePreset)
            }
        )
    }
}
