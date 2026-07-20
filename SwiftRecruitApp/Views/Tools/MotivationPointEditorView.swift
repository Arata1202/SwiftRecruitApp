import SwiftUI

struct MotivationPointEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @Environment(RecruitStore.self) private var store

    let point: MotivationPoint?
    @State private var draft: MotivationPointDraft

    init(point: MotivationPoint? = nil) {
        self.point = point
        _draft = State(initialValue: point.map(MotivationPointDraft.init) ?? MotivationPointDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("時期") {
                    Stepper("年齢 \(draft.age)歳", value: $draft.age, in: 0...100)
                }

                Section("幸福度") {
                    Stepper("幸福度 \(draft.happiness)", value: $draft.happiness, in: 0...10)
                    ProgressView(value: Double(draft.happiness), total: 10)
                        .tint(happinessColor)
                    Text("0が最も低く、10が最も高い状態です。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("その理由") {
                    TextField("出来事や感じていたことを入力", text: $draft.reason, axis: .vertical)
                        .lineLimit(5...12)
                    HStack {
                        if InputLimits.length(of: normalizedReason) > InputLimits.motivationReason {
                            Text("理由は\(InputLimits.motivationReason)文字以内で入力してください。")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                        Spacer()
                        Text("\(InputLimits.length(of: normalizedReason))文字")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(point == nil ? "経験を記録" : "記録を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        SaveButtonLabel(isSaving: store.isSaving)
                    }
                    .disabled(isInvalid || store.isSaving)
                }
            }
            .disabled(store.isSaving)
            .scrollDismissesKeyboard(.interactively)
            .recruitErrorAlert(store: store)
        }
        .interactiveDismissDisabled(store.isSaving)
    }

    private var normalizedReason: String {
        draft.reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isInvalid: Bool {
        normalizedReason.isEmpty
            || InputLimits.length(of: normalizedReason) > InputLimits.motivationReason
    }

    private var happinessColor: Color {
        if draft.happiness >= 7 { return .green }
        if draft.happiness <= 3 { return .orange }
        return .accentColor
    }

    private func save() async {
        if let point {
            if await store.updateMotivationPoint(point, draft: draft) != nil { dismiss() }
        } else if let userID = session.userID,
                  await store.createMotivationPoint(userID: userID, draft: draft) != nil {
            dismiss()
        }
    }
}
