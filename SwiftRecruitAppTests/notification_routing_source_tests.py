"""Source wiring contracts; behavioral coverage lives in XCTest."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1] / "SwiftRecruitApp"


class NotificationRoutingSourceTests(unittest.TestCase):
    def test_default_tap_only_and_owner_forwarded(self):
        source = (ROOT / "App/AppDelegate.swift").read_text()
        self.assertIn("response.actionIdentifier == UNNotificationDefaultActionIdentifier", source)
        self.assertIn('eventUserInfo["user_id"] = userID', source)

    def test_shared_details_not_editors_and_distinct_retry(self):
        source = (ROOT / "App/NotificationRoutePresentation.swift").read_text()
        self.assertIn("TaskDetailView(taskID:", source)
        self.assertIn("SelectionStepDetailView(stepID:", source)
        self.assertNotIn("EditorView(", source)
        self.assertIn("この項目は見つかりません。削除された可能性があります", source)
        self.assertIn('Button("再試行")', source)
        self.assertIn("store.successfulReloadRevision != revision", source)
        self.assertIn("while store.isLoading || store.isSaving", source)

    def test_pending_taps_do_not_dismiss_existing_presentations(self):
        source = (ROOT / "App/MainTabView.swift").read_text()
        self.assertIn("NotificationPresentationProbe.isBlocked(presentationController)", source)
        self.assertNotIn("dismiss(animated:", source)
        self.assertIn("router.notificationRoute.pending", source)

    def test_dates_use_explicit_calendar_and_no_memo(self):
        source = (ROOT / "Services/LocalNotificationService.swift").read_text()
        self.assertIn("formatter.calendar = calendar", source)
        self.assertIn("formatter.timeZone = calendar.timeZone", source)
        self.assertIn('hasTime ? "yyyy年M月d日 H:mm" : "yyyy年M月d日"', source)
        self.assertNotIn(".memo", source)


if __name__ == "__main__":
    unittest.main()
