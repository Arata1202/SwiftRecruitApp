import SwiftUI

/// Compact metadata that keeps its icon close to the text at every Dynamic Type size.
struct MetadataLabel: View {
    private let title: String
    private let systemImage: String
    private let iconScale: Image.Scale

    init(_ title: String, systemImage: String, iconScale: Image.Scale = .medium) {
        self.title = title
        self.systemImage = systemImage
        self.iconScale = iconScale
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: systemImage)
                .imageScale(iconScale)
                .fontWeight(.regular)
                .frame(width: 16)
            Text(title)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
