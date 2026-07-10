import SwiftUI

extension View {
    @ViewBuilder
    func searchableWhen(
        _ condition: Bool,
        text: Binding<String>,
        prompt: String
    ) -> some View {
        if condition {
            searchable(text: text, prompt: prompt)
        } else {
            self
        }
    }
}
