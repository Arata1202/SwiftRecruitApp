"""Source contracts for shared notification calculation and additive persistence."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NotificationPresetSourceTests(unittest.TestCase):
    def test_all_surfaces_share_the_calculator(self):
        for name in ["Models/Drafts.swift", "Views/Tasks/TaskDetailView.swift", "Services/LocalNotificationService.swift"]:
            self.assertIn("NotificationScheduleCalculator.reminderDate(", (ROOT / "SwiftRecruitApp" / name).read_text(encoding="utf-8"))

    def test_migration_is_additive_without_backfill(self):
        sql = (ROOT / "supabase/migrations/20261119010000_add_notification_timing_presets.sql").read_text(encoding="utf-8")
        statements = "\n".join(line for line in sql.splitlines() if not line.startswith("--")).lower()
        self.assertEqual(statements.count("add column"), 4)
        for forbidden in ["update ", "delete ", "drop ", "default ", "not null"]:
            self.assertNotIn(forbidden, statements)

    def test_scheduler_keeps_seconds_and_rechecks_actual_trigger(self):
        source = (ROOT / "SwiftRecruitApp/Services/LocalNotificationService.swift").read_text(encoding="utf-8")
        self.assertIn(".minute, .second", source)
        self.assertIn("guard item.fireDate > Date()", source)
        self.assertIn("trigger.nextTriggerDate()", source)
        self.assertEqual(source.count("fireDate > now"), 3)

    def test_detail_refreshes_preview(self):
        source = (ROOT / "SwiftRecruitApp/Views/Companies/SelectionStepDetailView.swift").read_text(encoding="utf-8")
        self.assertIn("TimelineView(.periodic", source)
        self.assertIn("notificationDescription(now: now, isPreview: false)", source)

    def test_picker_disables_without_erasing_precision_preferences(self):
        source = (ROOT / "SwiftRecruitApp/Views/Components/NotificationTimingPicker.swift").read_text(encoding="utf-8")
        self.assertIn("choices.select(value", source)
        helper = (ROOT / "SwiftRecruitApp/Models/AbsoluteNotificationTiming.swift").read_text(encoding="utf-8")
        self.assertIn("NotificationTimingChoice.select(value", helper)
        self.assertNotIn("従来の設定を維持", source)
        self.assertIn('return legacyRelative.title', source)
        self.assertNotIn("ForEach(TimedNotificationPreset.allCases", source)
        self.assertNotIn('.tag("three_days")', source)

    def test_no_deadline_only_special_option(self):
        source = (ROOT / "SwiftRecruitApp/Views/Components/NotificationTimingPicker.swift").read_text(encoding="utf-8")
        self.assertNotIn("previousDayAtTwenty", source)
        self.assertNotIn("20:00", source)
