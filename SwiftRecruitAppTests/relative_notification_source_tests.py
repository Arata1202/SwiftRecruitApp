from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]

class RelativeNotificationSourceTests(unittest.TestCase):
    def source(self, name):
        return (ROOT / 'SwiftRecruitApp' / name).read_text()

    def test_simple_menu_and_conditional_compatibility(self):
        s = self.source('Views/Components/NotificationTimingPicker.swift')
        for item in ['Text("カスタム…").tag("relative_custom")', 'Text("2日前")', 'Text("1週間前")',
                     'if absoluteAt != nil || choices.hasRememberedAbsolute', 'if hasLegacyCustom',
                     'relativeValue == nil', 'Text("通知時刻は9:00です")']:
            self.assertIn(item, s)
        self.assertNotIn('Text("日時を指定…")', s)
        self.assertIn('relativePresentation.edit(initial)', s)

    def test_custom_native_controls_are_inline_without_manual_or_nested_transaction(self):
        s = self.source('Views/Components/RelativeNotificationEditor.swift')
        self.assertEqual(s.count('.pickerStyle(.wheel)'), 1)
        self.assertIn('UIPickerViewDataSource, UIPickerViewDelegate', s)
        self.assertIn('parent.range.count', s)
        self.assertIn('parent.value = parent.range.lowerBound + row', s)
        self.assertIn('@Binding var value', s)
        self.assertIn('LabeledContent("通知タイミング", value: value.title)', s)
        self.assertIn('.disabled(!value.supports(unit, hasTime: hasTime))', s)
        for forbidden in ['TextField', 'Button(', 'NavigationStack', '.sheet', '.alert', '.confirmationDialog', 'DatePicker']:
            self.assertNotIn(forbidden, s)
        picker = self.source('Views/Components/NotificationTimingPicker.swift')
        self.assertIn('RelativeNotificationEditor(value: Binding(', picker)
        self.assertNotIn('.sheet', picker)
        self.assertIn('if relativePresentation.isCustom { return "relative_custom" }', picker)
        self.assertIn('timedRelative = RelativeNotificationPresentation()', picker)
        self.assertIn('dateRelative = RelativeNotificationPresentation()', picker)

    def test_outer_transaction_and_legacy_discard_alert_are_consistent(self):
        for path in ['Views/Tasks/TaskEditorView.swift', 'Views/Companies/SelectionStepEditorView.swift']:
            s = self.source(path)
            self.assertIn('.interactiveDismissDisabled(store.isSaving || hasUnsavedChanges)', s)
            self.assertIn('if hasUnsavedChanges { confirmsDiscard = true } else { dismiss() }', s)
            self.assertIn('draft.notificationValidationMessage', s)
            self.assertIn('NotificationPreview(', s)
        for path in ['Views/Tasks/TaskEditorView.swift', 'Views/Companies/SelectionStepEditorView.swift', 'Views/Components/NotificationNumberPicker.swift']:
            s = self.source(path)
            self.assertIn('.alert("変更を破棄しますか？", isPresented: $confirmsDiscard)', s)
            self.assertIn('Button("編集を続ける", role: .cancel)', s)
            self.assertIn('Text("保存していない変更は失われます。")', s)
            self.assertNotIn('.confirmationDialog', s)

    def test_existing_storage_and_elapsed_semantics_not_reinterpreted(self):
        s = self.source('Models/RelativeNotificationTiming.swift')
        self.assertIn('value * 24, unit: .hours', s)
        self.assertIn('value * 168, unit: .hours', s)
        self.assertIn('.calendar(daysBefore:', s)
        self.assertNotIn('Codable', s)
        self.assertIn('guard custom.isValid(hasTime: hasTime)', s)
        self.assertIn('custom.hour == 9, custom.minute == 0', s)

    def test_unmodified_and_restored_wire_values_are_preserved(self):
        s = self.source('Models/AbsoluteNotificationTiming.swift')
        for required in ['rememberedRelativeCustom', 'timedCompatibility', 'dateCompatibility',
                         'original.flatMap', 'let restored = remembered.flatMap',
                         'guard let custom = value.custom(hasTime: hasTime) else { return }']:
            self.assertIn(required, s)
