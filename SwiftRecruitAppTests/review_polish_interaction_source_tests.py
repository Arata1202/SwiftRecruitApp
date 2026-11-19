"""Static UI contracts, not evidence of rendered gestures or animation."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1] / "SwiftRecruitApp"

class ReviewPolishInteractionContracts(unittest.TestCase):
    def test_fade_is_shared_and_only_empty_boundary_triggers_it(self):
        source = (ROOT / "Views/Components/EmptyStateTransition.swift").read_text()
        for token in ["previous != isEmpty", "accessibilityReduceMotion", "duration: 0.18", ".onChange(of: isEmpty, initial: true)"]:
            self.assertIn(token, source)
        for path in ["Home/HomeView", "Companies/CompaniesView", "Tasks/TasksView", "Companies/CompanyInformationView"]:
            view = (ROOT / ("Views/" + path + ".swift")).read_text()
            self.assertIn(".emptyStateTransition(isEmpty:", view, path)
            self.assertIn(".transition(.opacity)", view, path)

    def test_calendar_fades_content_without_animating_section_geometry(self):
        source = (ROOT / "Views/Calendar/RecruitCalendarView.swift").read_text()
        self.assertIn("EmptyStateContentFade(isEmpty: groups.isEmpty)", source)
        self.assertIn("if previousEventsEmpty != eventsEmpty { transaction.animation = nil }", source)

    def test_home_empty_refresh_uses_native_list_without_remount_or_delay(self):
        source = (ROOT / "Views/Home/HomeView.swift").read_text()
        empty = source.split("} else if hasItems == false {", 1)[1].split("} else {", 1)[0]
        self.assertIn("List {", empty)
        self.assertIn(".refreshable { await reload() }", empty)
        self.assertNotIn("ScrollView", empty)
        self.assertNotIn(".id(", empty)
        self.assertNotIn("sleep", empty)

    def test_research_has_only_body_input_and_preserves_categories_dates(self):
        source = (ROOT / "Views/Companies/CompanyInformationEditorView.swift").read_text()
        self.assertNotIn("$draft.title", source)
        self.assertEqual(source.count("TextField("), 1)
        for token in ["$draft.body", "$draft.category", "$draft.hasDate", "$draft.date", "draft.hasChanges"]:
            self.assertIn(token, source)

    def test_calendar_add_text_and_home_company_icons(self):
        calendar = (ROOT / "Views/Calendar/RecruitCalendarView.swift").read_text()
        self.assertIn('Text("予定を追加")', calendar)
        self.assertNotIn('Label("予定を追加"', calendar)
        home = (ROOT / "Views/Home/HomeView.swift").read_text()
        self.assertIn('MetadataLabel(companyName, systemImage: "building.2")', home)
        self.assertIn('MetadataLabel(store.company(id: step.companyID)?.name ?? "企業", systemImage: "building.2")', home)

if __name__ == "__main__":
    unittest.main()
