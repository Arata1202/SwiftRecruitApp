import SwiftUI

/// Prefer a break between endpoints, but let either endpoint wrap at large text sizes.
struct ScheduleRangeLabel: View {
    let step: SelectionStep
    var referenceDate = Date()
    var showsIcon = true

    var body: some View {
        let text = DateFormatting.scheduleText(step, referenceDate: referenceDate)
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if showsIcon {
                Image(systemName: "calendar")
                    .fixedSize()
                    .frame(minWidth: 16)
            }
            ViewThatFits(in: .horizontal) {
                Text(text.compact)
                    .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.start)
                    if let end = text.end { Text("〜" + end) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.accessibilityLabel)
    }
}
