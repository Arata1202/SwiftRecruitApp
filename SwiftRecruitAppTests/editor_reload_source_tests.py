"""Source contracts for SwiftUI wiring; these do not replace XCTest or device tests."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1] / "SwiftRecruitApp"

class EditorReloadContracts(unittest.TestCase):
    def test_field_editor_keeps_original_snapshot_and_version(self):
        source = (ROOT / "Views/Companies/CompanyFieldEditorView.swift").read_text(encoding="utf-8")
        self.assertIn("@State private var originalCompany: Company", source)
        self.assertIn("_originalCompany = State(initialValue: company)", source)
        save = source.split("private func save() async", 1)[1]
        self.assertIn("let company = originalCompany", save)
        self.assertIn("CompanyDraft(company: company)", save)
        self.assertIn("store.updateCompany(company, draft: draft)", save)
        self.assertNotIn("let company = store.company", save)

    def test_field_editor_requires_current_owner_and_existing_record(self):
        source = (ROOT / "Views/Companies/CompanyFieldEditorView.swift").read_text(encoding="utf-8")
        save = source.split("private func save() async", 1)[1]
        source = save[:save.index("store.updateCompany")]
        self.assertIn("else { return }", source)
        self.assertIn("session.userID == originalCompany.userID", source)
        self.assertIn("store.loadedUserID == originalCompany.userID", source)
        self.assertIn("store.company(id: companyID) != nil", source)

    def test_unloaded_idle_root_offers_retry_not_permanent_progress(self):
        source = (ROOT / "App/RootView.swift").read_text(encoding="utf-8")
        branch = source.split("store.loadErrorMessage == nil", 1)[1].split("MainTabView()", 1)[0]
        self.assertIn("if store.isLoading", branch)
        branch = branch.split("} else {", 1)[1]
        self.assertIn('Button("再読み込み")', branch)
        self.assertIn("store.reload(userID: userID, force: true)", branch)
        self.assertEqual(source.count("store.loadErrorMessage != nil || store.loadedUserID != userID"), 2)

if __name__ == "__main__":
    unittest.main()
