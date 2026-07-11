import SwiftUI

struct TaskRow: View {
    let task: RecruitTask
    let companyName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.title)
                .strikethrough(task.isCompleted)
                .foregroundStyle(task.isCompleted ? Color.secondary : Color.primary)

            HStack(spacing: 10) {
                if let companyName {
                    Label(companyName, systemImage: "building.2")
                }
                if let dueAt = task.dueAt {
                    Label(
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
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .fullWidthTappableArea()
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
