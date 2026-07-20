import Charts
import SwiftUI

struct SelfAnalysisView: View {
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    @State private var isAddingMotivationPoint = false
    @State private var editingPoint: MotivationPoint?
    @State private var deletingPoint: MotivationPoint?

    var body: some View {
        List {
            Section("質問への回答") {
                NavigationLink {
                    SelfAnalysisAnswersView()
                } label: {
                    LabeledContent("回答を整理") {
                        Text("\(store.selfAnalysisAnswers.count)件")
                            .foregroundStyle(.secondary)
                    }
                    .fullWidthTappableArea()
                }
            }

            Section {
                if store.motivationPoints.isEmpty {
                    ContentUnavailableView(
                        "記録はありません",
                        systemImage: "chart.xyaxis.line",
                        description: Text("年齢ごとの幸福度と理由を記録すると、経験の傾向を振り返れます。")
                    )
                } else {
                    motivationChart
                }
            } header: {
                HStack {
                    Text("モチベーショングラフ")
                    Spacer()
                    Button { isAddingMotivationPoint = true } label: {
                        Image(systemName: "plus.circle")
                    }
                    .accessibilityLabel("モチベーション記録を追加")
                }
            } footer: {
                Text("幸福度は0（低い）から10（高い）で記録します。日々の気分ではなく、人生の経験を振り返るための自己分析です。")
            }

            if store.motivationPoints.isEmpty == false {
                Section("経験の記録") {
                    ForEach(store.motivationPoints) { point in
                        Button { editingPoint = point } label: {
                            MotivationPointRow(point: point)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("削除", role: .destructive) { deletingPoint = point }
                        }
                    }
                }
            }
        }
        .navigationTitle("自己分析")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("記録を追加", systemImage: "plus") { isAddingMotivationPoint = true }
            }
        }
        .refreshable {
            if let userID = session.userID {
                await store.reload(userID: userID, force: true)
            }
        }
        .sheet(isPresented: $isAddingMotivationPoint) { MotivationPointEditorView() }
        .sheet(item: $editingPoint) { MotivationPointEditorView(point: $0) }
        .alert(
            "記録を削除しますか？",
            isPresented: Binding(
                get: { deletingPoint != nil },
                set: { if $0 == false { deletingPoint = nil } }
            )
        ) {
            Button("削除", role: .destructive) {
                guard let deletingPoint else { return }
                Task {
                    if await store.deleteMotivationPoint(deletingPoint) {
                        self.deletingPoint = nil
                    }
                }
            }
            Button("キャンセル", role: .cancel) { deletingPoint = nil }
        } message: {
            Text("この操作は取り消せません。")
        }
        .recruitErrorAlert(store: store)
    }

    private var motivationChart: some View {
        Chart(store.motivationPoints) { point in
            LineMark(
                x: .value("年齢", point.age),
                y: .value("幸福度", point.happiness)
            )
            .interpolationMethod(.catmullRom)
            PointMark(
                x: .value("年齢", point.age),
                y: .value("幸福度", point.happiness)
            )
            .symbolSize(55)
        }
        .chartYScale(domain: 0...10)
        .chartYAxis {
            AxisMarks(values: [0, 2, 4, 6, 8, 10])
        }
        .chartXAxisLabel("年齢")
        .chartYAxisLabel("幸福度")
        .frame(height: 220)
        .padding(.vertical, 8)
        .accessibilityLabel("年齢ごとのモチベーショングラフ")
    }
}

private struct MotivationPointRow: View {
    let point: MotivationPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(point.age)歳")
                    .font(.headline)
                Spacer()
                Text("幸福度 \(point.happiness)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(happinessColor)
            }
            Text(point.reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
        .fullWidthTappableArea()
        .accessibilityElement(children: .combine)
    }

    private var happinessColor: Color {
        if point.happiness >= 7 { return .green }
        if point.happiness <= 3 { return .orange }
        return .secondary
    }
}
