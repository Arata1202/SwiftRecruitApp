import SwiftUI

struct DataLoadFailureView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("データを読み込めませんでした", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("再読み込み", action: retry)
                .buttonStyle(.borderedProminent)
        }
    }
}
