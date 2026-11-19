import SwiftUI

/// Edits only the owning form’s draft; its Save/Cancel controls own the transaction.
struct RelativeNotificationEditor: View {
    @Binding var value: RelativeNotificationTiming
    let hasTime: Bool

    var body: some View {
        LabeledContent("通知タイミング", value: value.title)
        HStack(spacing: 0) {
            Picker("数", selection: $value.value) {
                ForEach(value.wheelValues(hasTime: hasTime), id: \.self) { number in
                    Text("\(number)").tag(number)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()
            Picker("単位", selection: $value.unit) {
                ForEach(RelativeNotificationTiming.units(hasTime: hasTime)) { unit in
                    Text(unit.title).tag(unit)
                        .disabled(!value.supports(unit, hasTime: hasTime))
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()
        }
        .frame(height: 180)
    }
}
