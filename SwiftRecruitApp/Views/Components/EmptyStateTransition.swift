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
    @State private var revision = 0

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: 1.0, trigger: revision) { view, opacity in
                view.opacity(reduceMotion ? 1 : opacity)
            } keyframes: { _ in
                LinearKeyframe(0.0, duration: 0)
                LinearKeyframe(1.0, duration: 0.18)
            }
            .onChange(of: isEmpty) { oldValue, newValue in
                guard let oldValue, let newValue, oldValue != newValue, !reduceMotion else { return }
                revision += 1
            }
    }
}
