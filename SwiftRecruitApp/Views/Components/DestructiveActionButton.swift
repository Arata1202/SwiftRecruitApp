import SwiftUI

private let destructiveTextColor = Color(uiColor: UIColor { traits in
    UIColor.systemRed.resolvedColor(with: traits.modifyingTraits { $0.accessibilityContrast = .high })
})

struct DestructiveActionButton: View {
    private let title: LocalizedStringKey
    private let action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(role: .destructive, action: action) {
            Text(title).foregroundStyle(destructiveTextColor)
        }
    }
}
