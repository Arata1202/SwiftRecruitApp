import SwiftUI

struct TaskRow: View {
    let task: RecruitTask
    let companyName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.title)
                .strikethrough(task.isCompleted)
                .foregroundStyle(task.isCompleted ? Color.secondary : Color.primary)

            VStack(alignment: .leading, spacing: 3) { metadata }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .fullWidthTappableArea()
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var metadata: some View {
        if let companyName {
            MetadataLabel(companyName, systemImage: "building.2")
        }
        if let dueAt = task.dueAt {
            MetadataLabel(
                task.dueHasTime
                    ? DateFormatting.dateTime.string(from: dueAt)
                    : DateFormatting.day.string(from: dueAt),
                systemImage: "calendar"
            )
            .foregroundStyle(
                dueAt < Date() && task.isCompleted == false ? Color.red : Color.secondary
            )
        }
    }
}
