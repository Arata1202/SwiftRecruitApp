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
        self.assertIn('if value == "relative_custom" { showsRelativeEditor = true; return }', s)

    def test_custom_native_controls_commit_only_and_cancel_protected(self):
        s = self.source('Views/Components/RelativeNotificationEditor.swift')
        self.assertEqual(s.count('.pickerStyle(.wheel)'), 2)
        self.assertNotIn('@Binding', s)
        self.assertEqual(s.count('onSave(value)'), 1)
        self.assertIn('Button("完了") { onSave(value); dismiss() }', s)
        self.assertIn('.disabled(value.custom(hasTime: hasTime) == nil)', s)
        self.assertIn('.interactiveDismissDisabled(value != initial)', s)
        self.assertIn('Button("変更を破棄", role: .destructive) { dismiss() }', s)
        self.assertNotIn('DatePicker', s)
        self.assertNotIn('CustomNotificationTiming.Mode', s)

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
