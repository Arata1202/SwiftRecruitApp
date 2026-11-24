"""Selection title UI wiring; draft behavior is covered by XCTest, not these contracts."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def block(source, marker):
    start = source.index("{", source.index(marker))
    depth = 1
    for end in range(start + 1, len(source)):
        depth += (source[end] == "{") - (source[end] == "}")
        if depth == 0:
            return source[start + 1:end]
    raise AssertionError(f"Unclosed block: {marker}")


class SelectionTitleContracts(unittest.TestCase):
    def test_length_error_is_outside_other_only_field_and_has_recovery(self):
        source = (ROOT / "SwiftRecruitApp/Views/Companies/SelectionStepEditorView.swift").read_text(encoding="utf-8")
        selection = block(source, 'Section("選考")')
        other_only = block(selection, "if draft.type == .other")
        self.assertIn('TextField("選考名（必須）", text: $draft.customTitle)', other_only)
        self.assertNotIn("isCustomTitleTooLong", other_only)
        # The error must be a direct child of the section, not nested in a type branch.
        error_offset = selection.index("if draft.isCustomTitleTooLong")
        preceding = selection[:error_offset]
        self.assertEqual(preceding.count("{"), preceding.count("}"))
        error = block(selection, "if draft.isCustomTitleTooLong")
        self.assertIn('Text("選考名は', error)
        recovery = block(error, "if draft.type != .other")
        self.assertIn("種類を選び直してください", recovery)
        action = block(recovery, 'Button("「その他」に戻して選考名を編集")')
        self.assertEqual(action.strip(), "draft.type = .other")
        self.assertNotIn("draft.customTitle =", source)

    def test_save_guard_uses_same_unconditional_limit_as_error(self):
        source = (ROOT / "SwiftRecruitApp/Views/Companies/SelectionStepEditorView.swift").read_text(encoding="utf-8")
        invalid = block(source, "private var isInvalid: Bool")
        self.assertIn("\n            || draft.isCustomTitleTooLong\n", invalid)
        self.assertIn("draft.type == .other && normalizedCustomTitle.isEmpty", invalid)
        self.assertIn(".disabled(isInvalid || store.isSaving)", source)
        self.assertIn("guard !store.isSaving, !isInvalid else { return }", block(source, "private func save() async"))


if __name__ == "__main__":
    unittest.main()
