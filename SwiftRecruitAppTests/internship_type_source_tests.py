import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
class InternshipTypeSourceTests(unittest.TestCase):
    def test_type_display_and_default(self):
        source = (ROOT / "SwiftRecruitApp/Models/SelectionStep.swift").read_text(encoding="utf-8")
        self.assertIn("case internship", source)
        self.assertIn('case .internship: "インターンシップ"', source)
        self.assertIn("case .briefing, .internship, .interview, .offer, .other: .schedule", source)
    def test_forward_migration_adds_type(self):
        source = (ROOT / "supabase/migrations/20261119090000_add_internship_selection_type.sql").read_text(encoding="utf-8")
        self.assertIn("'internship'", source)
        self.assertIn("add constraint selection_steps_type_check", source)
