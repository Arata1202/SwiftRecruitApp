"""Contracts for account copy, motion preferences, and the CI test entrypoint."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class ReviewPolishContracts(unittest.TestCase):
    def test_account_deletion_names_current_entities(self):
        source = (ROOT / "SwiftRecruitApp/Views/Settings/AccountDeletionView.swift").read_text()
        self.assertIn("企業・選考・ToDo・企業研究の記録", source)
        self.assertNotIn("自己分析・ES", source)

    def test_calendar_list_motion_obeys_reduce_motion(self):
        source = (ROOT / "SwiftRecruitApp/Views/Calendar/RecruitCalendarView.swift").read_text()
        self.assertIn("accessibilityReduceMotion", source)
        for value in ("store.selectionSteps", "store.tasks"):
            self.assertIn(f".animation(reduceMotion ? nil : .snappy, value: {value})", source)

    def test_source_tests_are_documented_and_run_by_ios_ci(self):
        command = "python3 -m unittest discover -s SwiftRecruitAppTests -p '*_source_tests.py' -v"
        self.assertIn(command, (ROOT / "README.md").read_text())
        self.assertIn(command, (ROOT / ".github/workflows/ios-ci.yml").read_text())
