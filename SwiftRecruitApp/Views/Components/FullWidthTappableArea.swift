import SwiftUI

extension View {
    func fullWidthTappableArea(alignment: Alignment = .leading) -> some View {
        frame(maxWidth: .infinity, alignment: alignment)
            .contentShape(.rect)
    }
}
