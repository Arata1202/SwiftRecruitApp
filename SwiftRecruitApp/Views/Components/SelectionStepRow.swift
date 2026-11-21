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
                    .fixedSize()
                    .frame(minWidth: 26)
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
                        .foregroundStyle(.primary)
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
                        if milestone.kind == .start {
                            ScheduleRangeLabel(step: step, referenceDate: referenceDate)
                        } else {
                            MetadataLabel(milestoneLabelOverride ?? milestoneTitle(milestone), systemImage: "calendar")
                                .foregroundStyle(preferPastMilestone ? Color.red : Color.primary)
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.primary)
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
        let date = DateFormatting.listDate(
            milestone.date, hasTime: milestone.hasTime, referenceDate: referenceDate
        )
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

extension SelectionStep {
    func completionAccessibilityLabel(isWorking: Bool) -> String {
        if isWorking { return "「\(displayTitle)」を更新中" }
        return status == .completed ? "「\(displayTitle)」を予定に戻す" : "「\(displayTitle)」を完了にする"
    }
}
