import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
class SelectionDateKindSourceTests(unittest.TestCase):
    def test_editor_routes_explicit_choices(self):
        source = (ROOT / "SwiftRecruitApp/Views/Companies/SelectionStepEditorView.swift").read_text(encoding="utf-8")
        self.assertIn("set: { draft.setType($0) }", source)
        self.assertIn("set: { draft.setDateKind($0) }", source)
        self.assertNotIn("selection: $draft.dateKind", source)
