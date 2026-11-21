"""UI wiring contracts; rendered layout still requires a device check."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]


def source(path):
    return (ROOT / "SwiftRecruitApp" / path).read_text()


class UICopyPolishContracts(unittest.TestCase):
    def test_home_onboarding_actions_share_first_use_predicate(self):
        home = source("Views/Home/HomeView.swift")
        self.assertIn("store.companies.isEmpty && store.tasks.isEmpty", home)
        empty = home.split("private var emptyState:", 1)[1].split("@ViewBuilder", 1)[0]
        self.assertEqual(empty.count("if isFirstUse {"), 3)
        for text in ["企業を追加", "ToDoを追加", "直近の予定はありません", "7日以内の予定と、進行中または期限を過ぎた未完了の項目を表示します。"]:
            self.assertIn(text, empty)
        self.assertNotIn("if store.companies.isEmpty", empty)

    def test_company_url_helper_removed_but_placeholder_and_validation_remain(self):
        for name in ["CompanyEditorView", "CompanyFieldEditorView"]:
            editor = source("Views/Companies/" + name + ".swift")
            self.assertNotIn("公式サイトや採用ページなど", editor)
            self.assertIn("企業サイトURLを入力", editor)
            self.assertIn("有効なWebサイトのURLを入力してください。", editor)

    def test_optional_company_explanation_is_grouped_not_an_action(self):
        editor = source("Views/Tasks/TaskEditorView.swift")
        empty = editor.split("if store.companies.isEmpty {", 1)[1].split("} else {", 1)[0]
        self.assertIn("VStack(alignment: .leading, spacing: 4)", empty)
        self.assertIn('LabeledContent("関連企業（任意）", value: "なし")', empty)
        self.assertIn('Text("企業を登録すると選択できます")', empty)
        self.assertNotIn("Button", empty)
        self.assertNotIn("Picker", empty)
        self.assertIn('Picker("関連企業（任意）"', editor)

    def test_deadline_order_changes_only_within_existing_section(self):
        editor = source("Views/Tasks/TaskEditorView.swift")
        deadline = editor.split('Section("期限") {', 1)[1].split("Section {", 1)[0]
        labels = ['"期限を設定"', '"時刻も指定"', '"日付"', '"時刻"']
        positions = [deadline.index(label) for label in labels]
        self.assertEqual(positions, sorted(positions))
        self.assertIn("if draft.hasDueDate", deadline)
        self.assertIn("if draft.dueHasTime", deadline)
        self.assertIn("draft.setDueHasTime($0)", deadline)

    def test_task_empty_search_copy_and_actions(self):
        tasks = source("Views/Tasks/TasksView.swift")
        for text in ["ToDoはありません", "やることを追加しましょう。", "該当するToDoがありません", "検索条件を変更してください。", "検索をクリア", "ToDoを追加"]:
            self.assertIn(text, tasks)

    def test_calendar_task_only_omits_unspecified_time(self):
        calendar = source("Views/Calendar/RecruitCalendarView.swift")
        self.assertIn("この日の選考・締切や、期限付きのToDoはありません。", calendar)
        row = calendar.split("private func eventRow", 1)[1].split("private var monthDates", 1)[0]
        task = row.split("case .task", 1)[1]
        self.assertIn("dateLabelOverride: event.hasTime ? DateFormatting.calendarMetadata(", task)
        self.assertIn(') : "期限"', task)
        self.assertIn("milestoneLabelOverride: kind == .start ? DateFormatting.schedule(step) : dateLabel", row)
        self.assertIn("時刻未設定", source("Utilities/DateFormatting.swift"))

    def test_company_filter_highlight_reset_and_sort_are_separate(self):
        companies = source("Views/Companies/CompaniesView.swift")
        self.assertIn("systemImage: statusFilter != nil", companies)
        predicate = companies.split("private var hasCustomFiltering:", 1)[1].split("private var emptyTitle", 1)[0]
        self.assertIn("statusFilter != nil", predicate)
        self.assertIn("searchText.trimmingCharacters", predicate)
        self.assertNotIn("sortOrder", predicate)
        reset = companies.split("private func resetFilters()", 1)[1].split("private func reload", 1)[0]
        self.assertIn('searchText = ""', reset)
        self.assertIn("statusFilter = nil", reset)
        self.assertNotIn("sortOrder", reset)
        self.assertEqual(companies.count("resetFilters()"), 3)

    def test_spinner_is_only_in_notification_rows_and_only_for_loading_message(self):
        status = source("Views/Components/NotificationPlanStatusView.swift")
        self.assertIn('if isLoading && message == "通知予定を確認中…"', status)
        self.assertIn("ProgressView().controlSize(.small)", status)
        for path in ["Tasks/TaskEditorView", "Companies/SelectionStepEditorView"]:
            editor = source("Views/" + path + ".swift")
            self.assertIn("NotificationPlanStatusView(message: store.", editor)
            self.assertIn("isLoading: store.isLoading", editor)
            self.assertIn("TimelineView", editor)
            self.assertNotIn("if store.isLoading", editor)

    def test_version_and_maintained_notification_labels(self):
        project = (ROOT / "project.yml").read_text()
        self.assertIn('MARKETING_VERSION: "1.1.0"', project)
        self.assertIn("CURRENT_PROJECT_VERSION: 4", project)
        detail = source("Views/Companies/SelectionStepDetailView.swift")
        self.assertIn('LabeledContent("通知タイミング"', detail)
        self.assertIn('LabeledContent("通知時刻"', detail)
        self.assertIn("notificationDescription(now: now, isPreview: false)", detail)
