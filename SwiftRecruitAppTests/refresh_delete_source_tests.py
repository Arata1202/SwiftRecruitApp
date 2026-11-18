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

    def test_refresh_does_not_replace_loaded_empty_hosts_with_loading_view(self):
        for path in ["Home/HomeView.swift", "Calendar/RecruitCalendarView.swift", "Tasks/TasksView.swift", "Companies/CompaniesView.swift"]:
            source = (ROOT / path).read_text()
            self.assertIn("if store.isLoading && store.loadedUserID == nil &&", source, path)
        companies = (ROOT / "Companies/CompaniesView.swift").read_text()
        self.assertIn("ZStack {", companies.split("private func companyList", 1)[1])

    def test_empty_company_selection_is_informational_only(self):
        source = (ROOT / "Tasks/TaskEditorView.swift").read_text()
        company_section = source.split("if fixesCompany == false {", 1)[1].split('Section("期限")', 1)[0]
        empty, populated = company_section.split("} else {", 1)
        self.assertIn("if store.companies.isEmpty {", empty)
        self.assertIn('LabeledContent("関連企業", value: "なし")', empty)
        self.assertIn('Text("企業を登録すると関連付けられます")', empty)
        for interactive in ["Picker(", "NavigationLink(", "Button(", "draft.companyID ="]:
            self.assertNotIn(interactive, empty)
        self.assertIn('selection: $draft.companyID', populated)
        self.assertIn('Text("なし").tag(nil as UUID?)', populated)
        self.assertIn('ForEach(store.companies)', populated)
        self.assertIn('.pickerStyle(.navigationLink)', populated)
        self.assertIn('self.fixesCompany = fixesCompany && task == nil && companyID != nil', source)
        self.assertIn('if task == nil { initialDraft.companyID = companyID }', source)
        save_button = source.split('ToolbarItem(placement: .confirmationAction)', 1)[1].split('.disabled(store.isSaving)', 1)[0]
        self.assertNotIn('companyID', save_button)
        self.assertNotIn('companies', save_button)

    def test_confirmation_swipes_do_not_claim_immediate_destruction(self):
        for path, expected_count in [("Companies/CompanyDetailView.swift", 2), ("Tasks/TasksView.swift", 1)]:
            source = (ROOT / path).read_text()
            swipes = source.split(".swipeActions")[1:]
            self.assertEqual(len(swipes), expected_count)
            for swipe in swipes:
                opener = swipe.split("\n                    }", 1)[0]
                self.assertIn("allowsFullSwipe: false", opener)
                self.assertIn('Button("削除")', opener)
                self.assertIn(".tint(.red)", opener)
                self.assertIn(".disabled(store.isSaving)", opener)
                self.assertNotIn("role: .destructive", opener)
                self.assertNotIn("await store.delete", opener)
            self.assertIn('Button("削除", role: .destructive)', source)
            self.assertIn('Button("キャンセル", role: .cancel)', source)
            self.assertIn("await store.deleteTask(deletingTask)", source)
        company = (ROOT / "Companies/CompanyDetailView.swift").read_text()
        self.assertIn("await store.deleteSelectionStep(deletingStep)", company)

    def test_status_is_navigation_picker_with_draft_binding(self):
        source = (ROOT / "Companies/SelectionStepEditorView.swift").read_text()
        start = source.index('Picker("状態"')
        self.assertIn('selection: $draft.status', source[start:start+400])
        self.assertIn('.pickerStyle(.navigationLink)', source[start:start+400])
        self.assertIn('状態の変更は保存すると反映されます', source)

if __name__ == "__main__": unittest.main()
