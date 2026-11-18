"""Source contracts supplement XCTest; not a substitute for device gestures."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1] / "SwiftRecruitApp" / "Views"
class RefreshDeleteContracts(unittest.TestCase):
    def test_refresh_is_on_all_four_screens(self):
        for path in ["Tasks/TasksView.swift", "Companies/CompaniesView.swift", "Companies/CompanyInformationView.swift", "Companies/CompanyDetailView.swift"]:
            source = (ROOT / path).read_text()
            self.assertIn(".refreshable", source, path)
            self.assertIn("store.reload(userID: userID, force: true)", source, path)
    def test_empty_lists_have_scroll_surface(self):
        for path in ["Tasks/TasksView.swift", "Companies/CompaniesView.swift", "Companies/CompanyInformationView.swift"]:
            source = (ROOT / path).read_text()
            self.assertIn("ScrollView {", source, path)
            self.assertIn(".scrollBounceBehavior(.always)", source, path)
    def test_empty_views_center_in_viewport_without_fixed_screen_height(self):
        for path in ["Tasks/TasksView.swift", "Companies/CompaniesView.swift", "Companies/CompanyInformationView.swift"]:
            source = (ROOT / path).read_text()
            self.assertLess(source.index("GeometryReader { geometry in"), source.index("ScrollView {"), path)
            self.assertIn(".frame(minHeight: geometry.size.height, alignment: .center)", source, path)
            self.assertNotIn("UIScreen.main.bounds", source, path)
        home = (ROOT / "Home/HomeView.swift").read_text()
        self.assertIn(".frame(minHeight: max(0, geometry.size.height - undoContentClearance), alignment: .center)", home)
        self.assertIn(".padding(.bottom, undoContentClearance)", home)

    def test_delete_acknowledgement_only_follows_success(self):
        for folder, name, record, method in [("Tasks", "Task", "task", "deleteTask"), ("Companies", "SelectionStep", "step", "deleteSelectionStep")]:
            editor = (ROOT / folder / (name + "EditorView.swift")).read_text()
            self.assertEqual(editor.count("onDeleted?()"), 1)
            self.assertIn("if await store." + method + "(" + record + ") {\n            onDeleted?()\n            dismiss()", editor)
            detail = (ROOT / folder / (name + "DetailView.swift")).read_text()
            self.assertIn("onDismiss:", detail)
            self.assertIn("deletionDismissal.editorDidDismiss()", detail)
            self.assertIn("deletionDismissal.deletionSucceeded()", detail)
            self.assertIn("if isMissing && !store.isSaving", detail)
if __name__ == "__main__": unittest.main()
