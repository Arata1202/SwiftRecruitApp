import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
def read(path): return (ROOT / path).read_text(encoding="utf-8")
class TimedCalendarClockTests(unittest.TestCase):
    def test_same_row_and_unit_gate(self):
        ui = read("SwiftRecruitApp/Views/Components/NotificationTimingPicker.swift")
        self.assertIn("if showsNotificationClock", ui)
        self.assertIn("$0.usesNotificationClock && $0.isSelectable(hasTime: true)", ui)
        self.assertIn("choices.selectReminder(value", ui)
        self.assertIn("guard let custom = value.clockCustom", ui)
        self.assertNotIn(".onAppear", ui)
    def test_new_defaults_and_legacy_storage(self):
        model = read("SwiftRecruitApp/Models/Drafts.swift")
        self.assertIn("notificationTimedCustom = dateKind == .deadline ? defaultClock : nil", model)
        self.assertIn("var notificationTimedCustom: CustomNotificationTiming? = nil", model)
        selection = read("SwiftRecruitApp/Models/AbsoluteNotificationTiming.swift")
        self.assertIn("let hour = timedCustom?.hour ?? clock?.hour", selection)
        self.assertIn("timedCustom = .relative(value.value, unit: unit)", selection)
    def test_target_clock_and_database_agree(self):
        model = read("SwiftRecruitApp/Models/NotificationTiming.swift")
        self.assertIn("let hour = custom.hour ?? 9, minute = custom.minute ?? 0", model)
        self.assertIn("calendarReminder(anchor: $0, daysBefore: 0", model)
        sql = read("supabase/migrations/20261119080000_add_timed_calendar_notification_clock.sql")
        self.assertIn("not allows_elapsed or value->>'unit' in ('days','weeks','months')", sql)

    def test_invalid_clock_edit_does_not_clear_stored_value(self):
        ui = read("SwiftRecruitApp/Views/Components/NotificationTimingPicker.swift")
        self.assertIn("minute: parts.minute ?? 0) else { return }", ui)
        self.assertIn("timedPreset = timedPreset ?? kind.defaultTimedPreset", ui)
        self.assertIn("timedCustom = custom", ui)

    def test_compatibility_snapshot_is_not_overwritten(self):
        source = read("SwiftRecruitApp/Models/AbsoluteNotificationTiming.swift")
        self.assertIn("if timedCompatibility == nil { timedCompatibility = memory }", source)
        self.assertIn("else if dateCompatibility == nil", source)
