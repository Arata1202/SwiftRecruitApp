import SwiftUI

struct NotificationNumberPicker: View {
    let title: String
    let kind: NotificationNumberSelection.Kind
    let value: Int
    let onSelect: (Int) -> Void
    @State private var showsChoices = false

    var body: some View {
        Button {
            showsChoices = true
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(value >= 0 ? "\(value)\(kind.suffix)" : "要入力")
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            .fullWidthTappableArea()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .sheet(isPresented: $showsChoices) {
            NotificationNumberChoices(title: title, kind: kind, value: value, onSelect: onSelect)
        }
    }
}

private struct NotificationNumberChoices: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let kind: NotificationNumberSelection.Kind
    let value: Int
    let onSelect: (Int) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("候補から選択") {
                    ForEach(kind.choices(including: value), id: \.self) { number in
                        Button {
                            onSelect(number)
                            dismiss()
                        } label: {
                            HStack {
                                Text(number >= 0 ? "\(number)\(kind.suffix)" : "要入力")
                                Spacer()
                                if number == value {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .frame(minHeight: 44)
                            .fullWidthTappableArea()
                        }
                        .disabled(!kind.range.contains(number))
                        .accessibilityAddTraits(number == value ? .isSelected : [])
                    }
                }
                Section {
                    NavigationLink {
                        NotificationNumberManualEntry(title: title, kind: kind, value: value) { number in
                            onSelect(number)
                            dismiss()
                        }
                    } label: {
                        Text("別の値を入力…")
                            .frame(minHeight: 44)
                            .fullWidthTappableArea()
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
    }
}

private struct NotificationNumberManualEntry: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var entry: NotificationNumberSelection
    @State private var confirmsDiscard = false
    let title: String
    let onSave: (Int) -> Void

    init(title: String, kind: NotificationNumberSelection.Kind, value: Int, onSave: @escaping (Int) -> Void) {
        self.title = title
        self.onSave = onSave
        _entry = State(initialValue: NotificationNumberSelection(kind: kind, value: value))
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                    HStack {
                        TextField(title, text: $entry.text)
                            .keyboardType(.numberPad)
                            .focused($isFocused)
                            .frame(minHeight: 44)
                        Text(entry.kind.suffix)
                    }
                }
            } footer: {
                Text(entry.validationMessage ?? entry.kind.inputHint)
                    .foregroundStyle(entry.validationMessage == nil ? Color.secondary : Color.red)
            }
        }
        .navigationTitle("別の値を入力")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .interactiveDismissDisabled(entry.hasChanges)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") {
                    if entry.hasChanges { confirmsDiscard = true } else { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("完了") {
                    guard let number = entry.confirmedValue else { return }
                    onSave(number)
                }
                .disabled(entry.confirmedValue == nil)
            }
        }
        .confirmationDialog("入力した変更を破棄しますか？", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("変更を破棄", role: .destructive) { dismiss() }
            Button("入力を続ける", role: .cancel) { }
        }
        .task { isFocused = true }
    }
}
