import SwiftUI

struct SelectionStepRow: View {
    let step: SelectionStep
    let companyName: String?
    var showsStatus = false
    var showsMilestoneKind = true
    var showsMemo = false
    var showsTypeIcon = true
    var referenceDate = Date()
    var homeLineLimits = false
    var preferPastMilestone = false
    var milestoneLabelOverride: String? = nil
    var showsCompletedStyle = false

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
                    .foregroundStyle(showsCompletedStyle && step.status == .completed ? Color.secondary : Color.primary)
                    .lineLimit(homeLineLimits ? 2 : nil)
                    .fixedSize(horizontal: false, vertical: homeLineLimits)

                if showsMemo, let memo = step.memo, memo.isEmpty == false {
                    Text(memo)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                VStack(alignment: .leading, spacing: 3) {
                    if let companyName {
                        MetadataLabel(companyName, systemImage: "building.2")
                            .lineLimit(homeLineLimits ? 2 : nil)
                    }
                    if showsStatus {
                        MetadataLabel(step.status.title, systemImage: statusImage)
                    }
                    if let milestone = displayedMilestone {
                        MetadataLabel(milestoneLabelOverride ?? milestoneTitle(milestone), systemImage: "calendar")
                            .foregroundStyle(preferPastMilestone && milestone.kind == .deadline ? Color.red : Color.secondary)
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
        if preferPastMilestone {
            return HomeSelectionMilestones.earliestPast(for: step, relativeTo: referenceDate)
        }
        return step.nextMilestone(relativeTo: referenceDate)
            ?? HomeSelectionMilestones.all(for: step).min { $0.date < $1.date }
    }

    private func milestoneTitle(_ milestone: SelectionMilestone) -> String {
        if milestone.kind == .start { return DateFormatting.schedule(step) }
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
