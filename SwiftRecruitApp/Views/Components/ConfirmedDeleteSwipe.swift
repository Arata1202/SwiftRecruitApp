import SwiftUI

/// Native destructive swipes may retire their rendered row before confirmation.
/// Rebuild only that row when the prompt closes; the store stays authoritative.
struct ConfirmedDeleteSwipe: ViewModifier {
    let isAvailable: Bool
    let isSaving: Bool
    let isConfirming: Bool
    let requestConfirmation: () -> Void
    @State private var rowRevision = 0

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if isAvailable {
                    Button("削除", systemImage: "trash", role: .destructive) {
                        guard isAvailable, !isSaving else { return }
                        requestConfirmation()
                    }
                    .disabled(isSaving)
                }
            }
            .id(rowRevision)
            .onChange(of: isConfirming) { wasConfirming, confirming in
                if wasConfirming && !confirming {
                    rowRevision += 1
                }
            }
    }
}
