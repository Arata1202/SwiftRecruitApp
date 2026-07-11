import SwiftUI

/// Compact metadata that keeps its icon close to the text at every Dynamic Type size.
struct MetadataLabel: View {
    private let title: String
    private let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: systemImage)
                .frame(width: 16)
            Text(title)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
