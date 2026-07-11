import SwiftUI

struct TaskCompletionButton: View {
    let task: RecruitTask
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(task.isCompleted ? Color.green : Color.secondary)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(task.isCompleted ? "未完了に戻す" : "完了にする")
    }
}
