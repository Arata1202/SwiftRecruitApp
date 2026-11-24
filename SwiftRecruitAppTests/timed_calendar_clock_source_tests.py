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
        self.assertIn("value.updateClock(hour:", ui)
    def test_new_defaults_and_legacy_storage(self):
        model = read("SwiftRecruitApp/Models/Drafts.swift")
        self.assertIn("notificationTimedCustom = dateKind == .deadline ? defaultClock : nil", model)
        self.assertIn("var notificationTimedCustom: CustomNotificationTiming? = nil", model)
        selection = read("SwiftRecruitApp/Models/AbsoluteNotificationTiming.swift")
        self.assertIn("let hour = timedCustom?.hour ?? clock?.hour", selection)
        self.assertIn("timedCustom = .relative(value.value, unit: unit)", selection)
    def test_compatibility_snapshot_is_not_overwritten(self):
        source = read("SwiftRecruitApp/Models/AbsoluteNotificationTiming.swift")
        self.assertIn("if timedCompatibility == nil { timedCompatibility = memory }", source)
        self.assertIn("else if dateCompatibility == nil", source)
