import SwiftUI

struct TaskRow: View {
    let task: RecruitTask
    let companyName: String?
    var showsDueLabel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(task.title)
                .font(.headline)
                .strikethrough(task.isCompleted)
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
        }
        if let dueAt = task.dueDate() {
            let date = task.dueHasTime
                ? DateFormatting.dateTime.string(from: dueAt)
                : DateFormatting.day.string(from: dueAt)
            MetadataLabel(
                showsDueLabel ? "期限 \(date)" : date,
                systemImage: "calendar"
            )
            .foregroundStyle(
                task.isOverdue() ? Color.red : Color.secondary
            )
        }
    }
}
