import SwiftUI

struct DataLoadFailureView: View {
    var title: LocalizedStringKey = "データを読み込めませんでした"
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
                .foregroundStyle(RecruitTextColor.supporting)
        } actions: {
            Button("再読み込み", action: retry)
                .prominentAction()
        }
    }
}
