"""Local source contracts complement XCTest and isolated PostgreSQL validation."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CustomNotificationSourceTests(unittest.TestCase):
    def source(self, name):
        return (ROOT / "SwiftRecruitApp" / name).read_text()

    def test_all_payloads_include_custom_fields_and_updates_encode_null(self):
        source = self.source("Repositories/SupabaseRecruitRepository.swift")
        self.assertEqual(source.count('let notificationTimedCustom: CustomNotificationTiming?'), 4)
        self.assertEqual(source.count('let notificationDateCustom: CustomNotificationTiming?'), 4)
        self.assertEqual(source.count('try container.encode(notificationTimedCustom,'), 2)
        self.assertEqual(source.count('try container.encode(notificationDateCustom,'), 2)
        self.assertEqual(source.count('guard draft.notificationValidationMessage() == nil'), 3)
        self.assertIn('guard draft.notificationValidationMessage(isCompleted: task.isCompleted) == nil', source)

    def test_editor_controls_and_dirty_checks_cover_both_preferences(self):
        for name in ['Views/Tasks/TaskEditorView.swift', 'Views/Companies/SelectionStepEditorView.swift']:
            source = self.source(name)
            for field in ['notificationTimedCustom', 'notificationDateCustom']:
                self.assertIn(f'draft.{field}', source)
                self.assertIn(f'{field} != initial.{field}', source)
            self.assertIn('draft.notificationValidationMessage', source)
            if 'Tasks/' in name:
                self.assertEqual(source.count('draft.notificationValidationMessage(isCompleted: task?.isCompleted ?? false)'), 4)
            else:
                self.assertIn('draft.notificationValidationMessage() != nil', source)

    def test_shared_calculator_rejects_after_anchor_and_pins_dst_policy(self):
        source = self.source('Models/NotificationTiming.swift')
        self.assertIn('!hasTime || result <= anchor', source)
        self.assertIn('matchingPolicy: .nextTime, repeatedTimePolicy: .first', source)
        self.assertIn('calendar.isDate(result, inSameDayAs: day)', source)
        self.assertIn('525_600', source)
        self.assertIn('8_760', source)

    def test_inline_custom_controls_use_tested_presentation_transitions(self):
        source = self.source('Views/Components/NotificationTimingPicker.swift')
        self.assertIn('@State private var presentation = NotificationTimingPresentation()', source)
        for transition in ['choices.select(', 'presentation.changeMode(', 'presentation.changeDay(']:
            self.assertIn(transition, source)
        self.assertIn('if enabled, activeCustom != nil', source)
        self.assertIn('if hasTime {\n                Picker("指定方法"', source)
        self.assertIn('if presentation.dayChoice(custom, hasTime: hasTime) == .arbitrary', source)
        self.assertIn('Text("以前のカスタム設定")', source)
        self.assertNotIn('Text(message)', source)  # Editors show the shared validation once.
        self.assertIn('func inputMessage(hasTime: Bool)', self.source('Models/NotificationTiming.swift'))
        self.assertIn('numberPicker(custom, title: NotificationTimingPresentation.elapsedInputTitle', source)
        self.assertNotIn('TextField(', source)
        self.assertIn('.pickerStyle(.menu)', source)
        for obsolete in ['.navigationLink', '数値', '単位（前）', '夏時間', '.onAppear', '.task {']:
            self.assertNotIn(obsolete, source)

    def test_number_selection_full_row_and_explicit_commit_contract(self):
        # Structural contracts only; these do not prove on-device hit testing.
        source = self.source('Views/Components/NotificationNumberPicker.swift')
        for required in ['showsChoices = true', '.sheet(isPresented: $showsChoices)',
                         'NavigationStack', 'List {', 'kind.choices(including: value)',
                         'if number == value', 'Image(systemName: "chevron.right")',
                         '.frame(minHeight: 44)', '.fullWidthTappableArea()',
                         'Text("別の値を入力…")', '.focused($isFocused)',
                         '.task { isFocused = true }', 'Button("完了")',
                         'guard let number = entry.confirmedValue else { return }',
                         '.disabled(entry.confirmedValue == nil)',
                         'Text(entry.validationMessage ?? entry.kind.inputHint)',
                         '.interactiveDismissDisabled(entry.hasChanges)',
                         'Button("変更を破棄", role: .destructive) { dismiss() }']:
            self.assertIn(required, source)
        self.assertNotIn('@Binding', source)
        self.assertNotIn('.onChange(of: entry.text)', source)
        self.assertNotIn('Stepper(', source)

    def test_migration_is_nullable_shape_checked_and_guards_legacy_writes(self):
        sql = (ROOT / 'supabase/migrations/20261119030000_add_custom_notification_timing.sql').read_text()
        self.assertEqual(sql.count('add column'), 4)
        self.assertIn("if value is null then return true", sql)
        self.assertIn("is distinct from 'object'", sql)
        self.assertIn("value ?& array", sql)
        self.assertIn("exception when invalid_text_representation", sql)
        self.assertEqual(sql.count('create trigger'), 2)
        self.assertIn('new.notification_timed_custom = old.notification_timed_custom', sql)


if __name__ == '__main__':
    unittest.main()
