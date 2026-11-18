import SwiftUI

struct ToolsView: View {
    var body: some View {
        NavigationStack {
            List {
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
