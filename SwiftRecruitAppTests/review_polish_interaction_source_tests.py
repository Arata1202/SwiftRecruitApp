"""Static UI contracts, not evidence of rendered gestures or animation."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1] / "SwiftRecruitApp"

class ReviewPolishInteractionContracts(unittest.TestCase):
    def test_new_empty_fades_are_removed_and_old_animations_remain(self):
        self.assertFalse((ROOT / "Views/Components/EmptyStateTransition.swift").exists())
        for path in ["Home/HomeView", "Companies/CompaniesView", "Tasks/TasksView", "Companies/CompanyInformationView", "Calendar/RecruitCalendarView"]:
            view = (ROOT / ("Views/" + path + ".swift")).read_text()
            self.assertNotIn("emptyStateTransition", view, path)
            self.assertNotIn("EmptyStateContentFade", view, path)
        home = (ROOT / "Views/Home/HomeView.swift").read_text()
        self.assertIn(".animation(reduceMotion ? nil : .snappy, value: hasItems)", home)
        self.assertIn(".transition(.opacity)", home)  # Existing undo toast.
        calendar = (ROOT / "Views/Calendar/RecruitCalendarView.swift").read_text()
        self.assertIn(".animation(reduceMotion ? nil : .snappy, value: store.tasks)", calendar)
        self.assertNotIn("previousEventsEmpty", calendar)

    def test_home_empty_refresh_has_stable_native_scroll_host(self):
        source = (ROOT / "Views/Home/HomeView.swift").read_text()
        empty = source.split("} else if hasItems == false {", 1)[1].split("} else {", 1)[0]
        self.assertIn("HomeEmptyRefreshView(reload: reload)", empty)
        self.assertIn(".padding(.bottom, undoContentClearance)", empty)
        for token in ["GeometryReader", "containerRelativeFrame", ".id(", "sleep", ".allowsHitTesting(false)"]:
            self.assertNotIn(token, empty)
        host = (ROOT / "Views/Home/HomeEmptyRefreshView.swift").read_text()
        for token in ["UIScrollView()", "UIRefreshControl()", "scrollView.frameLayoutGuide.heightAnchor", "endRefreshing()", "cancelRefresh()"]:
            self.assertIn(token, host)
        for token in ["contentOffset =", "Task.sleep", "DispatchQueue", "GeometryReader"]:
            self.assertNotIn(token, host)

    def test_research_has_only_body_input_and_preserves_categories_dates(self):
        source = (ROOT / "Views/Companies/CompanyInformationEditorView.swift").read_text()
        self.assertNotIn("$draft.title", source)
        self.assertEqual(source.count("TextField("), 1)
        for token in ["$draft.body", "$draft.category", "$draft.hasDate", "$draft.date", "draft.hasChanges"]:
            self.assertIn(token, source)

    def test_research_row_shows_body_not_persisted_title(self):
        source = (ROOT / "Views/Companies/CompanyInformationView.swift").read_text()
        row = source.split("private struct CompanyInformationRow", 1)[1]
        self.assertNotIn("Text(item.title)", row)
        self.assertIn("Text(item.body)", row)
        self.assertIn(".foregroundStyle(.primary)", row)
        self.assertIn("DateFormatting.companyInformationDate(item)", row)
        self.assertIn('Image(systemName: "chevron.right")', row)
        self.assertIn("Section(category.title)", source)

    def test_calendar_add_text_and_home_company_icons(self):
        calendar = (ROOT / "Views/Calendar/RecruitCalendarView.swift").read_text()
        header = calendar.split("private var selectedDateHeader:", 1)[1].split("private func eventRow", 1)[0]
        self.assertIn('Label("予定を追加", systemImage: "plus.circle.fill")', header)
        menu = header.split("Menu {", 1)[1].split("} label:", 1)[0]
        self.assertIn('"選考を追加")', menu)
        self.assertIn('Button("ToDoを追加")', menu)
        self.assertNotIn('systemImage:', menu)
        home = (ROOT / "Views/Home/HomeView.swift").read_text()
        self.assertIn('MetadataLabel(companyName, systemImage: "building.2")', home)
        self.assertIn('MetadataLabel(store.company(id: step.companyID)?.name ?? "企業", systemImage: "building.2")', home)

    def test_edit_status_precedes_schedule_and_delete_stays_below_memo(self):
        source = (ROOT / "Views/Companies/SelectionStepEditorView.swift").read_text()
        status = source.index('Picker("状態"')
        self.assertLess(source.index('Section("選考")'), status)
        self.assertLess(status, source.index('Section("日程")'))
        self.assertLess(source.index('Section("メモ（任意）")'), source.index('Button("選考を削除"'))
        before_status = source[:status]
        self.assertIn('if step != nil {', before_status)

if __name__ == "__main__":
    unittest.main()
