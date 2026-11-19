"""Timezone changes must replan local clocks without changing absolute triggers."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1] / "SwiftRecruitApp"

class NotificationTimezoneContracts(unittest.TestCase):
    def test_active_timezone_and_significant_time_changes_reconcile(self):
        source = (ROOT / "App/RootView.swift").read_text()
        for name in (".NSSystemTimeZoneDidChange", "UIApplication.significantTimeChangeNotification"):
            block = source.split("publisher(for: " + name + ")", 1)[1].split(".on", 1)[0]
            self.assertIn("scenePhase == .active", block)
            self.assertIn("store.loadedUserID == userID", block)
            self.assertIn("rescheduleAllNotificationsIfAuthorized()", block)

    def test_trigger_encodes_absolute_instant_in_utc(self):
        source = (ROOT / "Services/LocalNotificationService.swift").read_text()
        self.assertIn("Calendar(identifier: .gregorian)", source)
        self.assertIn("calendar.timeZone = TimeZone(secondsFromGMT: 0)!", source)
        self.assertIn("components.timeZone = calendar.timeZone", source)
