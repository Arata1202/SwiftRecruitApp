from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]

class SameDayNotificationPolishSourceTests(unittest.TestCase):
    def test_detail_keeps_schedule_and_status_messages(self):
        source = (ROOT / 'SwiftRecruitApp/Views/Companies/SelectionStepDetailView.swift').read_text()
        self.assertIn('LabeledContent("通知タイミング", value: timing.timing)', source)
        self.assertIn('LabeledContent("通知時刻", value: clock)', source)
        self.assertNotIn('LabeledContent("通知設定"', source)
        for token in ['TimelineView', 'store.notificationPlanDescription', 'notificationDescription(now: now, isPreview: false)', '完了済みのため通知されません。', '中止のため通知されません。']:
            self.assertIn(token, source)

    def test_same_day_uses_existing_calendar_storage_and_clock_editor(self):
        model = (ROOT / 'SwiftRecruitApp/Models/RelativeNotificationTiming.swift').read_text()
        self.assertIn('if value == 0, unit == .days { return .calendar(hour: hour, minute: minute) }', model)
        self.assertIn('custom.mode == .calendar, custom.value == 0', model)
        picker = (ROOT / 'SwiftRecruitApp/Views/Components/NotificationTimingPicker.swift').read_text()
        self.assertIn('ReminderMenuOption.options(hasTime: hasTime)', picker)
        self.assertIn('DatePicker("通知時刻", selection: notificationClock', picker)
        self.assertIn('guard let custom = value.clockCustom', picker)
        self.assertNotIn('.onAppear', picker)
