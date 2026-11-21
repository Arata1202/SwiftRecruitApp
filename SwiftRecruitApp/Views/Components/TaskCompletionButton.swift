import SwiftUI

struct TaskCompletionButton: View {
    let task: RecruitTask
    let isDisabled: Bool
    let isWorking: Bool
    let action: () -> Void

    init(
        task: RecruitTask,
        isDisabled: Bool = false,
        isWorking: Bool = false,
        action: @escaping () -> Void
    ) {
        self.task = task
        self.isDisabled = isDisabled
        self.isWorking = isWorking
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(task.isCompleted ? Color.green : Color.secondary)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(completionAccessibilityLabel)
    }

    var completionAccessibilityLabel: String {
        if isWorking { return "「\(task.title)」を更新中" }
        return task.isCompleted
            ? "「\(task.title)」を未完了に戻す"
            : "「\(task.title)」を完了にする"
    }
}
