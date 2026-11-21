from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]

class AbsoluteNotificationSourceTests(unittest.TestCase):
    def source(self, path):
        return (ROOT / 'SwiftRecruitApp' / path).read_text()

    def test_wire_and_previews_include_absolute_and_null_clear(self):
        source = self.source('Repositories/SupabaseRecruitRepository.swift')
        self.assertEqual(source.count('let notificationAbsoluteAt: Date?'), 4)
        self.assertEqual(source.count('try container.encode(notificationAbsoluteAt,'), 2)
        self.assertEqual(source.count('AbsoluteNotificationTiming.validationMessage(date, original:'), 4)
        self.assertEqual(self.source('State/RecruitStore.swift').count('notificationAbsoluteAt: draft.notificationAbsoluteAt'), 2)

    def test_existing_absolute_is_current_value_not_editable_mode(self):
        source = self.source('Views/Components/NotificationTimingPicker.swift')
        self.assertIn('Text(currentValueTitle).foregroundStyle(Color.primary)', source)
        self.assertNotIn('.tag("current")', source)
        self.assertNotIn('.tag("absolute")', source)
        self.assertIn('absoluteAt.formatted(.dateTime.year().month().day().hour().minute())', source)
        self.assertIn('AbsoluteNotificationTiming.anchorWarning', source)
        for forbidden in ['DatePicker("通知日時"', '以前の', '.tag("absolute")', '.tag("custom")', '.onAppear']:
            self.assertNotIn(forbidden, source)

    def test_dirty_and_fixed_precedence(self):
        for name in ['Tasks/TaskEditorView.swift', 'Companies/SelectionStepEditorView.swift']:
            self.assertIn('notificationAbsoluteAt != initial.notificationAbsoluteAt', self.source('Views/' + name))
        source = self.source('Models/NotificationTiming.swift')
        self.assertLess(source.index('if let absoluteAt { return absoluteAt }'), source.index('if let custom = hasTime'))
        self.assertIn('step.notificationAbsoluteAt == nil || step.startDate(calendar: calendar) == nil', self.source('Services/LocalNotificationService.swift'))

    def test_append_only_finite_nullable_schema(self):
        sql = (ROOT / 'supabase/migrations/20261119040000_add_absolute_notification_timing.sql').read_text()
        self.assertEqual(sql.count('add column notification_absolute_at timestamptz'), 2)
        self.assertEqual(sql.count('isfinite(notification_absolute_at)'), 2)
        self.assertNotIn('> now()', sql)
        self.assertNotIn('disable row level security', sql.lower())
        self.assertEqual(sql.count('create trigger'), 2)
