"""Static UI contracts, not evidence of rendered gestures or animation."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1] / "SwiftRecruitApp"

class ReviewPolishInteractionContracts(unittest.TestCase):
    def test_home_content_changes_respect_reduce_motion(self):
        home = (ROOT / "Views/Home/HomeView.swift").read_text(encoding="utf-8")
        self.assertIn("accessibilityReduceMotion", home)
        self.assertRegex(home, r"\.animation\(\s*reduceMotion\s*\?\s*nil\s*:[^,]+,\s*value:\s*hasItems\s*\)")

    def test_empty_home_supports_pull_to_refresh(self):
        source = (ROOT / "Views/Home/HomeView.swift").read_text(encoding="utf-8")
        empty = source.split("} else if hasItems == false {", 1)[1].split("} else {", 1)[0]
        self.assertIn(".refreshable", empty)
        self.assertIn("await reload()", empty)

    def test_research_has_only_body_input_and_preserves_categories_dates(self):
        source = (ROOT / "Views/Companies/CompanyInformationEditorView.swift").read_text(encoding="utf-8")
        self.assertNotIn("$draft.title", source)
        self.assertEqual(source.count("TextField("), 1)
        for token in ["$draft.body", "$draft.category", "$draft.hasDate", "$draft.date", "draft.hasChanges"]:
            self.assertIn(token, source)

    def test_research_row_shows_body_not_persisted_title(self):
        source = (ROOT / "Views/Companies/CompanyInformationView.swift").read_text(encoding="utf-8")
        row = source.split("private struct CompanyInformationRow", 1)[1]
        self.assertNotIn("Text(item.title)", row)
        self.assertIn("Text(item.body)", row)
        self.assertIn(".foregroundStyle(.primary)", row)
        self.assertIn("DateFormatting.companyInformationDate(item)", row)
        self.assertIn('Image(systemName: "chevron.right")', row)
        self.assertIn("RecruitSection(LocalizedStringKey(category.title))", source)

    def test_calendar_add_text_and_home_company_icons(self):
        calendar = (ROOT / "Views/Calendar/RecruitCalendarView.swift").read_text(encoding="utf-8")
        header = calendar.split("private var selectedDateHeader:", 1)[1].split("private func eventRow", 1)[0]
        self.assertIn('Label("予定を追加", systemImage: "plus.circle.fill")', header)
        menu = header.split("Menu {", 1)[1].split("} label:", 1)[0]
        self.assertIn('"選考を追加")', menu)
        self.assertIn('Button("ToDoを追加")', menu)
        self.assertNotIn('systemImage:', menu)
        home = (ROOT / "Views/Home/HomeView.swift").read_text(encoding="utf-8")
        self.assertIn('MetadataLabel(company, systemImage: "building.2")', home)
        self.assertIn('company: store.company(id: step.companyID)?.name ?? "企業"', home)

    def test_edit_status_precedes_schedule_and_delete_stays_below_memo(self):
        source = (ROOT / "Views/Companies/SelectionStepEditorView.swift").read_text(encoding="utf-8")
        status = source.index('Picker("状態"')
        self.assertLess(source.index('Section("選考")'), status)
        self.assertLess(status, source.index('Section("日程")'))
        self.assertLess(source.index('Section("メモ（任意）")'), source.index('Button("選考を削除"'))
        self.assertRegex(source, r'if step != nil \{\s*Section \{\s*Picker\("状態"')

if __name__ == "__main__":
    unittest.main()
