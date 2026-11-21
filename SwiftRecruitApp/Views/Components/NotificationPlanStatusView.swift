import SwiftUI

struct NotificationPlanStatusView: View {
    let message: String
    let isLoading: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if isLoading && message == "通知予定を確認中…" {
                ProgressView().controlSize(.small)
            }
            Text(message)
        }
    }
}
