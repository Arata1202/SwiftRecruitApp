"""Selection title UI wiring; draft behavior is covered by XCTest, not these contracts."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SelectionTitleContracts(unittest.TestCase):
    def test_length_error_is_outside_other_only_field_and_has_recovery(self):
        source = (ROOT / "SwiftRecruitApp/Views/Companies/SelectionStepEditorView.swift").read_text(encoding="utf-8")
        section = source.split('RecruitSection("選考")', 1)[1].split('if step != nil', 1)[0]
        self.assertRegex(section, r'if draft\.type == \.other \{\s*TextField\("選考名（必須）", text: \$draft.customTitle\)\s*\}\s*if draft.isCustomTitleTooLong')
        self.assertIn('Text("選考名は', section)
        self.assertIn("種類を選び直してください", section)
        self.assertRegex(section, r'Button\("「その他」に戻して選考名を編集"\)\s*\{\s*draft.type = \.other\s*\}')
        self.assertNotRegex(section, r'\bdraft\.customTitle\s*=(?!=)')

    def test_save_guard_uses_same_unconditional_limit_as_error(self):
        source = (ROOT / "SwiftRecruitApp/Views/Companies/SelectionStepEditorView.swift").read_text(encoding="utf-8")
        invalid = source.split("private var isInvalid: Bool", 1)[1].split("}", 1)[0]
        self.assertRegex(invalid, r'\|\|\s*draft\.isCustomTitleTooLong\s*(?:\|\||$)')
        self.assertIn("draft.type == .other && normalizedCustomTitle.isEmpty", invalid)
        self.assertIn(".disabled(isInvalid || store.isSaving)", source)
        save = source.split("private func save() async", 1)[1]
        self.assertIn("guard !store.isSaving, !isInvalid else { return }", save)
