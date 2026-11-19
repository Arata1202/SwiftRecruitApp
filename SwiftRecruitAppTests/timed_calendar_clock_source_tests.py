import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
def read(path): return (ROOT / path).read_text()
class TimedCalendarClockTests(unittest.TestCase):
    def test_same_row_and_unit_gate(self):
        ui = read("SwiftRecruitApp/Views/Components/NotificationTimingPicker.swift")
        self.assertIn("if showsNotificationClock", ui)
        self.assertIn("(relativeValue ?? legacyRelative)?.usesNotificationClock == true", ui)
        self.assertIn("choices.selectReminder(value", ui)
        self.assertIn("timedCustom = value.clockCustom", ui)
        self.assertNotIn(".onAppear", ui)
    def test_new_defaults_and_legacy_storage(self):
        model = read("SwiftRecruitApp/Models/Drafts.swift")
        self.assertIn("notificationTimedCustom = dateKind == .deadline ? defaultClock : nil", model)
        self.assertIn("var notificationTimedCustom: CustomNotificationTiming? = nil", model)
        selection = read("SwiftRecruitApp/Models/AbsoluteNotificationTiming.swift")
        self.assertIn("let hour = timedCustom?.hour ?? 9", selection)
        self.assertIn("timedCustom = .relative(value.value, unit: unit)", selection)
    def test_target_clock_and_database_agree(self):
        model = read("SwiftRecruitApp/Models/NotificationTiming.swift")
        self.assertIn("if hasTime, let hour = custom.hour, let minute = custom.minute", model)
        self.assertIn("calendarReminder(anchor: $0, daysBefore: 0", model)
        sql = read("supabase/migrations/20261119080000_add_timed_calendar_notification_clock.sql")
        self.assertIn("not allows_elapsed or value->>'unit' in ('days','weeks','months')", sql)
