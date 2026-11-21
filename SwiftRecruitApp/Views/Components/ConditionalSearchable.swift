import SwiftUI

extension View {
    @ViewBuilder
    func searchableWhen(
        _ condition: Bool,
        text: Binding<String>,
        placement: SearchFieldPlacement = .automatic,
        prompt: String
    ) -> some View {
        if condition {
            searchable(text: text, placement: placement, prompt: prompt)
        } else {
            self
        }
    }
}
