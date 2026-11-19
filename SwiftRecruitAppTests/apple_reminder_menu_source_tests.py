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
        menu = picker.split('Menu {')[1].split('} label:')[0]
        self.assertEqual(menu.count('menuOption('), 3)
        self.assertIn('menuOption("なし", id: "none")', menu)
        self.assertIn('menuOption("カスタム", id: "relative_custom")', menu)
        self.assertNotIn('currentValueTitle', menu)

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
