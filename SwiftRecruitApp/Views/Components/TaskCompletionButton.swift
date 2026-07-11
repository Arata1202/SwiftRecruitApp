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
            .frame(width: 44, height: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(
            isWorking ? "更新中" : (task.isCompleted ? "未完了に戻す" : "完了にする")
        )
    }
}
