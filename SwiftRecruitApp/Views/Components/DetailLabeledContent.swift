import SwiftUI

struct DetailLabeledContent: View {
    let title: LocalizedStringKey
    let value: String

    init(_ title: LocalizedStringKey, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        LabeledContent(title) {
            Text(value).foregroundStyle(Color.primary)
        }
    }
}
