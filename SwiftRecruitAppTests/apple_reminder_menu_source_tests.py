from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[1]

class AppleReminderMenuSourceTests(unittest.TestCase):
    def test_exact_reference_option_order_for_both_precision_modes(self):
        model = (ROOT/'SwiftRecruitApp/Models/RelativeNotificationTiming.swift').read_text()
        options = model.split('let values: [(Int, RelativeNotificationTiming.Unit)] = hasTime')[1].split('return values.map')[0]
        timed, date = options.split(': [')
        parse = lambda text: [(int(n), unit) for n, unit in re.findall(r'\((\d+), \.(\w+)\)', text)]
        self.assertEqual(parse(timed), [(5,'minutes'), (15,'minutes'), (30,'minutes'), (1,'hours'), (2,'hours'), (1,'days'), (2,'days'), (1,'weeks'), (1,'months')])
        self.assertEqual(parse(date), [(1,'days'), (2,'days'), (1,'weeks'), (2,'weeks'), (1,'months'), (3,'months'), (6,'months')])
        picker = (ROOT/'SwiftRecruitApp/Views/Components/NotificationTimingPicker.swift').read_text()
        menu = picker.split('Picker("通知タイミング", selection: selection) {')[1].split('.pickerStyle(.menu)')[0]
        self.assertIn('Text("なし").tag("none")', menu)
        self.assertIn('Text("カスタム").tag("relative_custom")', menu)
        self.assertIn('Text(option.title).tag(option.id)', menu)
        self.assertNotIn('currentValueTitle', menu)
        self.assertNotIn('Menu {', picker)
        self.assertNotIn('chevron.up.chevron.down', picker)

    def test_preserves_original_layout_outside_option_inventory(self):
        picker = (ROOT/'SwiftRecruitApp/Views/Components/NotificationTimingPicker.swift').read_text()
        editor = (ROOT/'SwiftRecruitApp/Views/Components/RelativeNotificationEditor.swift').read_text()
        self.assertIn('LabeledContent("通知時刻", value: DateOnlyNotificationTime(minutes: dateOnlyNotificationMinutes).title)', picker)
        self.assertNotIn('.frame(maxWidth: .infinity, alignment: .trailing)', editor)

    def test_custom_units_include_months_in_both_modes_and_cap_200(self):
        model = (ROOT/'SwiftRecruitApp/Models/RelativeNotificationTiming.swift').read_text()
        self.assertIn('case minutes, hours, days, weeks, months', model)
        self.assertIn('units(hasTime: Bool) -> [Unit] { Unit.allCases }', model)
        self.assertIn('min(200, maximum(hasTime: hasTime))', model)
        editor = (ROOT/'SwiftRecruitApp/Views/Components/RelativeNotificationEditor.swift').read_text()
        self.assertIn('unit.title.replacingOccurrences(of: "前", with: "")', editor)
        self.assertNotIn('TextField', editor)

    def test_months_are_calendar_months_not_30_day_conversion(self):
        source = (ROOT/'SwiftRecruitApp/Models/NotificationTiming.swift').read_text()
        self.assertIn('case .months: component = .month', source)
        self.assertIn('calendar.date(byAdding: component, value: -custom.value', source)
        sql = (ROOT/'supabase/migrations/20261119060000_add_calendar_relative_notification_units.sql').read_text()
        self.assertIn("value->>'mode' = 'relative'", sql)
        self.assertIn("'minutes','hours','days','weeks','months'", sql)
        self.assertIn('between 1 and 200', sql)

    def test_new_draft_defaults_preserve_legacy_read_fallbacks(self):
        source = (ROOT/'SwiftRecruitApp/Models/Drafts.swift').read_text()
        self.assertEqual(source.count('var notificationDatePreset: DateNotificationPreset? = .previousDay'), 2)
        self.assertIn('var notificationTimedPreset: TimedNotificationPreset? = .oneHour', source)
        self.assertIn('notificationTimedPreset = task.notificationTimedPreset ?? NotificationAnchor.taskDue.defaultTimedPreset', source)
        self.assertIn('notificationDatePreset = step.notificationDatePreset ?? notificationAnchor.defaultDatePreset', source)

    def test_configurable_date_only_time_reaches_scheduler_and_ui(self):
        settings = (ROOT/'SwiftRecruitApp/Views/Settings/SettingsView.swift').read_text()
        model = (ROOT/'SwiftRecruitApp/Models/NotificationTiming.swift').read_text()
        self.assertIn('DatePicker("時刻未指定の通知時刻"', settings)
        self.assertIn('.task(id: dateOnlyNotificationMinutes)', settings)
        self.assertIn('await store.rescheduleAllNotificationsIfAuthorized()', settings)
        self.assertIn('dateOnlyTime: DateOnlyNotificationTime = .load()', model)
        self.assertIn('static let defaultMinutes = 9 * 60', model)
        self.assertIn('hour: dateOnlyTime.hour, minute: dateOnlyTime.minute', model)
        self.assertIn('!hasTime && custom.hour == 9 && custom.minute == 0', model)
