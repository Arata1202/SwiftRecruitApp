import SwiftUI

/// Only content/empty boundaries animate; first appearance and unavailable states do not.
struct EmptyStateTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isEmpty: Bool?
    @State private var previous: Bool?

    func body(content: Content) -> some View {
        content
            .transaction { transaction in
                if let previous, let isEmpty, previous != isEmpty {
                    transaction.animation = reduceMotion ? nil : .easeInOut(duration: 0.18)
                } else if previous != isEmpty {
                    transaction.animation = nil
                }
            }
            .onChange(of: isEmpty, initial: true) { _, value in previous = value }
    }
}

extension View {
    func emptyStateTransition(isEmpty: Bool?) -> some View {
        modifier(EmptyStateTransition(isEmpty: isEmpty))
    }
}

/// A List keeps its section identity; fade new content without animating row geometry.
struct EmptyStateContentFade: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isEmpty: Bool?
    @State private var opacity = 1.0

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .onChange(of: isEmpty) { oldValue, newValue in
                guard let oldValue, let newValue, oldValue != newValue, !reduceMotion else { return }
                opacity = 0
                withAnimation(.easeInOut(duration: 0.18)) { opacity = 1 }
            }
    }
}
