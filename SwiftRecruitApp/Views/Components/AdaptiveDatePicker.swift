import SwiftUI

struct AdaptiveDatePicker: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: LocalizedStringKey
    @Binding var selection: Date
    let displayedComponents: DatePickerComponents

    var body: some View {
        let picker = DatePicker(title, selection: $selection, displayedComponents: displayedComponents)
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).accessibilityHidden(true)
                picker.labelsHidden()
            }
        } else {
            picker
        }
    }
}
