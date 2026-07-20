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

                Section("キャリア") {
                    NavigationLink {
                        SelfAnalysisView()
                    } label: {
                        Label("自己分析", systemImage: "chart.xyaxis.line")
                            .fullWidthTappableArea()
                    }
                }
            }
            .navigationTitle("ツール")
        }
    }
}
