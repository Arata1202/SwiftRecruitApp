import SwiftUI

struct SelectionStepRow: View {
    let step: SelectionStep
    let companyName: String?
    var showsStatus = false
    var showsMilestoneKind = false
    var showsMemo = false
    var showsTypeIcon = true
    var referenceDate = Date()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if showsTypeIcon {
                Image(systemName: step.type.systemImage)
                    .foregroundStyle(iconColor)
                    .frame(width: 26)
                    .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(step.displayTitle)
                    .font(.headline)

                if showsMemo, let memo = step.memo, memo.isEmpty == false {
                    Text(memo)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                VStack(alignment: .leading, spacing: 3) {
                    if let companyName {
                        MetadataLabel(companyName, systemImage: "building.2")
                    }
                    if showsStatus {
                        MetadataLabel(step.status.title, systemImage: statusImage)
                    }
                    if let milestone = displayedMilestone {
                        MetadataLabel(milestoneTitle(milestone), systemImage: "calendar")
                            .foregroundStyle(Color.secondary)
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
        if let upcoming = step.nextMilestone(relativeTo: referenceDate) { return upcoming }
        let milestones = [
            step.startDate().map {
                SelectionMilestone(kind: .start, date: $0, hasTime: step.startsHasTime)
            },
            step.deadlineDate().map {
                SelectionMilestone(kind: .deadline, date: $0, hasTime: step.deadlineHasTime)
            },
        ].compactMap { $0 }
        return milestones.min { $0.date < $1.date }
    }

    private func milestoneTitle(_ milestone: SelectionMilestone) -> String {
        let date = milestone.hasTime
            ? DateFormatting.dateTime.string(from: milestone.date)
            : DateFormatting.day.string(from: milestone.date)
        return (showsMilestoneKind || milestone.kind == .deadline) ? "\(milestone.kind.title) \(date)" : date
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
        case .scheduled: "clock"
        case .completed: "checkmark.circle"
        case .cancelled: "xmark.circle"
        }
    }
}
