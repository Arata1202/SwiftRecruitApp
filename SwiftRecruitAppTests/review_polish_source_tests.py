"""Account deletion copy and accessibility motion preferences."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class ReviewPolishContracts(unittest.TestCase):
    def test_account_deletion_names_current_entities(self):
        source = (ROOT / "SwiftRecruitApp/Views/Settings/AccountDeletionView.swift").read_text(encoding="utf-8")
        self.assertIn("企業・選考・ToDo・企業研究の記録", source)
        self.assertNotIn("自己分析・ES", source)

    def test_calendar_list_motion_obeys_reduce_motion(self):
        source = (ROOT / "SwiftRecruitApp/Views/Calendar/RecruitCalendarView.swift").read_text(encoding="utf-8")
        self.assertIn("accessibilityReduceMotion", source)
        for value in ("store.selectionSteps", "store.tasks"):
            self.assertIn(f".animation(reduceMotion ? nil : .snappy, value: {value})", source)
