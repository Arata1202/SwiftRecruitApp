import SwiftUI

struct ToolsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("応募書類") {
                    NavigationLink {
                        ESTemplatesView()
                    } label: {
                        Label("ESテンプレート", systemImage: "doc.on.doc")
                            .fullWidthTappableArea()
                    }
                }

            }
            .navigationTitle("ツール")
        }
    }
}
