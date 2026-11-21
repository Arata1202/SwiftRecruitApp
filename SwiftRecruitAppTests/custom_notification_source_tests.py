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
        self.assertEqual(source.count('if let message = draft.notificationValidationMessage()'), 3)
        self.assertIn('if let message = draft.notificationValidationMessage(isCompleted: task.isCompleted)', source)

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
        self.assertIn('2_016_000', source)
        self.assertIn('33_600', source)

    def test_inline_relative_controls_do_not_offer_old_mode_editors(self):
        source = self.source('Views/Components/NotificationTimingPicker.swift')
        for required in ['choices.select(', 'choices.selectReminder(', 'RelativeNotificationEditor(value:', 'custom.isValid(hasTime: hasTime)', 'custom.hour ?? 9', 'custom.minute ?? 0']:
            self.assertIn(required, source)
        for forbidden in ['customControls', 'numberPicker(', 'DatePicker("通知日時"', '指定方法', '以前の', 'TextField(', '.onAppear']:
            self.assertNotIn(forbidden, source)

    def test_manual_number_interface_is_removed(self):
        self.assertFalse((ROOT / 'SwiftRecruitApp/Views/Components/NotificationNumberPicker.swift').exists())
        source = self.source('Views/Components/RelativeNotificationEditor.swift')
        self.assertNotIn('TextField(', source)
        self.assertNotIn('数字を入力', source)
        self.assertNotIn('.sheet', source)

    def test_migration_is_nullable_shape_checked_and_guards_legacy_writes(self):
        sql = (ROOT / 'supabase/migrations/20261119030000_add_custom_notification_timing.sql').read_text()
        self.assertEqual(sql.count('add column'), 4)
        self.assertIn("if value is null then return true", sql)
        self.assertIn("is distinct from 'object'", sql)
        self.assertIn("value ?& array", sql)
        self.assertIn("exception when invalid_text_representation", sql)
        self.assertEqual(sql.count('create trigger'), 2)
        self.assertIn('new.notification_timed_custom = old.notification_timed_custom', sql)

    def test_forward_migration_expands_only_existing_wire_validation(self):
        sql = (ROOT / 'supabase/migrations/20261119050000_expand_notification_timing_to_200_weeks.sql').read_text()
        self.assertIn('create or replace function public.valid_custom_notification_timing', sql)
        for bound in ['2016000', '33600', '1400']:
            self.assertIn(bound, sql)
        for forbidden in ['drop table', 'drop column', 'update public.', 'create trigger']:
            self.assertNotIn(forbidden, sql)
        self.assertIn('20261119050000_expand_notification_timing_to_200_weeks.sql', (ROOT / 'README.md').read_text())


if __name__ == '__main__':
    unittest.main()
