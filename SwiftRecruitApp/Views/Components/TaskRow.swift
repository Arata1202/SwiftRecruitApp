import SwiftUI

struct TaskRow: View {
    let task: RecruitTask
    let companyName: String?
    var showsDueLabel = true
    var homeLineLimits = false
    var dateLabelOverride: String? = nil
    var referenceDate = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(task.title)
                .font(.headline)
                .lineLimit(homeLineLimits ? 2 : nil)
                .fixedSize(horizontal: false, vertical: homeLineLimits)
                .foregroundStyle(task.isCompleted ? Color.secondary : Color.primary)

            if let memo = task.memo, memo.isEmpty == false {
                Text(memo)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if companyName != nil || task.dueDate() != nil {
                VStack(alignment: .leading, spacing: 3) { metadata }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .frame(minHeight: 44, alignment: .leading)
        .fullWidthTappableArea()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var metadata: some View {
        if let companyName {
            MetadataLabel(companyName, systemImage: "building.2")
                .lineLimit(homeLineLimits ? 2 : nil)
        }
        if let dueAt = task.dueDate() {
            let date = DateFormatting.listDate(
                dueAt, hasTime: task.dueHasTime, referenceDate: referenceDate
            )
            MetadataLabel(
                dateLabelOverride ?? (showsDueLabel ? "期限 \(date)" : date),
                systemImage: "calendar"
            )
            .foregroundStyle(
                task.isOverdue(relativeTo: referenceDate) ? Color.red : Color.secondary
            )
        }
    }
}
