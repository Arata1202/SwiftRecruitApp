import SwiftUI

/// Only content/empty boundaries animate; first appearance and unavailable states do not.
struct EmptyStateTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isEmpty: Bool?
    @State private var previous: Bool?
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .transaction { transaction in
                if appeared, let previous, let isEmpty, previous != isEmpty {
                    transaction.animation = reduceMotion ? nil : .easeInOut(duration: 0.18)
                } else if previous != isEmpty {
                    transaction.animation = nil
                }
            }
            .onAppear {
                previous = isEmpty
                appeared = true
            }
            .onDisappear { appeared = false }
            .onChange(of: isEmpty) { _, value in previous = value }
    }
}

extension View {
    func emptyStateTransition(isEmpty: Bool?) -> some View {
        modifier(EmptyStateTransition(isEmpty: isEmpty))
    }
}
