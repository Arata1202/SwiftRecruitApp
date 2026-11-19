import SwiftUI
import UIKit

/// Edits only the owning form’s draft; its Save/Cancel controls own the transaction.
struct RelativeNotificationEditor: View {
    @Binding var value: RelativeNotificationTiming
    let hasTime: Bool

    var body: some View {
        Text(value.title)
            .accessibilityLabel("通知タイミング、" + value.title)
        HStack(spacing: 0) {
            RelativeNotificationNumberWheel(value: $value.value, range: value.wheelValues(hasTime: hasTime))
                .frame(maxWidth: .infinity)
                .clipped()
            Picker("単位", selection: $value.unit) {
                ForEach(RelativeNotificationTiming.units(hasTime: hasTime)) { unit in
                    Text(unit.title.replacingOccurrences(of: "前", with: "")).tag(unit)
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

/// Native number wheel for the bounded selectable range.
private struct RelativeNotificationNumberWheel: UIViewRepresentable {
    @Binding var value: Int
    let range: ClosedRange<Int>

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        picker.accessibilityLabel = "数"
        return picker
    }

    func updateUIView(_ picker: UIPickerView, context: Context) {
        let changed = context.coordinator.parent.range != range
        context.coordinator.parent = self
        if changed { picker.reloadAllComponents() }
        let row = value - range.lowerBound
        if picker.selectedRow(inComponent: 0) != row {
            picker.selectRow(row, inComponent: 0, animated: false)
        }
    }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        var parent: RelativeNotificationNumberWheel
        init(_ parent: RelativeNotificationNumberWheel) { self.parent = parent }
        func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }
        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            parent.range.count
        }
        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            String(parent.range.lowerBound + row)
        }
        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            parent.value = parent.range.lowerBound + row
        }
    }
}
