import SwiftUI

struct SelectionStepRow: View {
    let step: SelectionStep
    let companyName: String?
    var showsStatus = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: step.type.systemImage)
                .foregroundStyle(iconColor)
                .frame(width: 26)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 10) {
                Text(step.displayTitle)
                    .font(.headline)

                VStack(alignment: .leading, spacing: 3) {
                    if let companyName {
                        MetadataLabel(companyName, systemImage: "building.2")
                    }
                    if showsStatus {
                        MetadataLabel(step.status.title, systemImage: statusImage)
                    }
                    if let milestone = displayedMilestone {
                        MetadataLabel(milestoneTitle(milestone), systemImage: "calendar")
                            .foregroundStyle(
                                milestone.kind == .deadline ? Color.orange : Color.secondary
                            )
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .fullWidthTappableArea()
        .accessibilityElement(children: .combine)
    }

    private var displayedMilestone: SelectionMilestone? {
        if let upcoming = step.nextMilestone() { return upcoming }
        let milestones = [
            step.startsAt.map {
                SelectionMilestone(kind: .start, date: $0, hasTime: step.startsHasTime)
            },
            step.deadlineAt.map {
                SelectionMilestone(kind: .deadline, date: $0, hasTime: step.deadlineHasTime)
            },
        ].compactMap { $0 }
        return milestones.min { $0.date < $1.date }
    }

    private func milestoneTitle(_ milestone: SelectionMilestone) -> String {
        let date = milestone.hasTime
            ? DateFormatting.dateTime.string(from: milestone.date)
            : DateFormatting.day.string(from: milestone.date)
        return milestone.kind == .deadline ? "締切 \(date)" : date
    }

    private var iconColor: Color {
        switch step.status {
        case .scheduled: .accentColor
        case .completed: .green
        case .cancelled: .secondary
        }
    }

    private var statusImage: String {
        switch step.status {
        case .scheduled: "calendar"
        case .completed: "checkmark.circle"
        case .cancelled: "xmark.circle"
        }
    }
}
