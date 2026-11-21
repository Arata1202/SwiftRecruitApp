import SwiftUI

struct NotificationPlanStatusView: View {
    let status: NotificationPlanStatus

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if case .loading = status {
                ProgressView().controlSize(.small)
            }
            Text(status.text)
        }
    }
}
