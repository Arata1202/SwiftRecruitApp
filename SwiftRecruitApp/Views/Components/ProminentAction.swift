import SwiftUI

extension View {
    func prominentAction() -> some View {
        // The standard prominent style uses light text in both appearances.
        let fill = UIColor(resource: .accent)
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        return buttonStyle(.borderedProminent)
            .tint(Color(uiColor: fill))
    }
}
