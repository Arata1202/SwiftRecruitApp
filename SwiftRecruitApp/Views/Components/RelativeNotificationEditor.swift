import SwiftUI

/// Transactional sheet: only Done writes through to the owning editor.
struct RelativeNotificationEditor: View {
    let initial: RelativeNotificationTiming
    let hasTime: Bool
    let onSave: (RelativeNotificationTiming) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var value: RelativeNotificationTiming
    @State private var confirmsDiscard = false
    @State private var input = ""
    @State private var showsInput = false

    init(initial: RelativeNotificationTiming, hasTime: Bool, onSave: @escaping (RelativeNotificationTiming) -> Void) {
        self.initial = initial
        self.hasTime = hasTime
        self.onSave = onSave
        _value = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Picker("数", selection: $value.value) {
                            ForEach(value.wheelValues(hasTime: hasTime), id: \.self) { Text("\($0)").tag($0) }
                        }.pickerStyle(.wheel).frame(maxWidth: .infinity).clipped()
                        Picker("単位", selection: $value.unit) {
                            ForEach(RelativeNotificationTiming.units(hasTime: hasTime)) { Text($0.title).tag($0) }
                        }.pickerStyle(.wheel)
                    }.frame(height: 180)
                    Button("数字を入力…") { input = String(value.value); showsInput = true }
                        .frame(minHeight: 44)
                } footer: {
                    if value.custom(hasTime: hasTime) == nil {
                        Text("\(value.minimum(hasTime: hasTime))〜\(value.maximum(hasTime: hasTime))\(value.unit.title)で指定してください。")
                            .foregroundStyle(.red)
                    } else if !hasTime { Text("指定した日の9:00に通知します") }
                }
            }
            .navigationTitle("カスタム通知")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { if value != initial { confirmsDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { onSave(value); dismiss() }.disabled(value.custom(hasTime: hasTime) == nil)
                }
            }
            .alert("数字を入力", isPresented: $showsInput) {
                TextField("数字", text: $input).keyboardType(.numberPad)
                Button("キャンセル", role: .cancel) {}
                Button("設定") { value.value = CustomNotificationTiming.parsedInput(input) ?? -1 }
            }
            .confirmationDialog("変更を破棄しますか？", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                Button("変更を破棄", role: .destructive) { dismiss() }
                Button("編集を続ける", role: .cancel) {}
            }
            .interactiveDismissDisabled(value != initial)
        }
    }
}
