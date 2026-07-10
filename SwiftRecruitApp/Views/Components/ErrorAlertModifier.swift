import SwiftUI

extension View {
    func recruitErrorAlert(store: RecruitStore) -> some View {
        alert("処理を完了できませんでした", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if $0 == false { store.errorMessage = nil } }
        )) {
            Button("閉じる", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "時間をおいてもう一度お試しください。")
        }
    }
}

