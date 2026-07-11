import SwiftUI

extension View {
    /// Keeps separators consistent when SwiftUI cannot infer a stable leading edge
    /// from compound rows such as navigation-link pickers and custom buttons.
    func fullWidthListSeparator() -> some View {
        alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}
