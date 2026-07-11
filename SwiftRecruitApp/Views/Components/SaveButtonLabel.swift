import SwiftUI

struct SaveButtonLabel: View {
    let isSaving: Bool

    var body: some View {
        Group {
            if isSaving {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text("保存")
            }
        }
        .accessibilityLabel(isSaving ? "保存中" : "保存")
    }
}
