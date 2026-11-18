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

    def test_delete_acknowledgement_closes_only_owner(self):
        for folder, name, record, method in [("Tasks", "Task", "task", "deleteTask"), ("Companies", "SelectionStep", "step", "deleteSelectionStep")]:
            editor = (ROOT / folder / (name + "EditorView.swift")).read_text()
            deletion = editor[editor.index("    private func delete"):]
            self.assertIn("if await store." + method + "(" + record + ") {", deletion)
            self.assertIn("if let onDeleted { onDeleted() } else { dismiss() }", deletion)
            detail = (ROOT / folder / (name + "DetailView.swift")).read_text()
            self.assertNotIn("onDismiss:", detail)
            self.assertIn("onDeleted: onDeleted", detail)
            self.assertNotIn("current" + ("Task" if name == "Task" else "Step") + " == nil) {", detail)
        for path in ["Tasks/TasksView.swift", "Companies/CompanyDetailView.swift", "Home/HomeView.swift", "Calendar/RecruitCalendarView.swift"]:
            source = (ROOT / path).read_text()
            self.assertIn("ownerUserID: task.userID, onDeleted:", source)
            if not path.startswith("Tasks"):
                self.assertIn("if selectedStep?.id == step.id { selectedStep = nil }", source)

    def test_status_is_navigation_picker_with_draft_binding(self):
        source = (ROOT / "Companies/SelectionStepEditorView.swift").read_text()
        start = source.index('Picker("状態"')
        self.assertIn('selection: $draft.status', source[start:start+400])
        self.assertIn('.pickerStyle(.navigationLink)', source[start:start+400])
        self.assertIn('状態の変更は保存すると反映されます', source)

if __name__ == "__main__": unittest.main()
