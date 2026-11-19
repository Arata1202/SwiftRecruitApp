"""Source contracts supplement simulator tests, not device interaction checks."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1] / "SwiftRecruitApp" / "Views"

class CompanyInformationDetailContracts(unittest.TestCase):
    def source(self, path):
        return (ROOT / path).read_text()

    def test_list_is_excerpt_with_optional_date_and_creation_stays_editor(self):
        source = self.source("Companies/CompanyInformationView.swift")
        row = source.split("private struct CompanyInformationRow", 1)[1]
        self.assertIn("if let date = DateFormatting.companyInformationDate(item)", row)
        self.assertIn('MetadataLabel(date, systemImage: "calendar")', row)
        self.assertIn(".font(.caption)", row)
        self.assertNotIn("createdAt", row)
        self.assertNotIn("category.systemImage", row)
        self.assertNotIn("Text(item.title)", row)
        self.assertIn(".lineLimit(3)", row)
        self.assertIn("CompanyInformationDetailView(", source)
        self.assertIn("CompanyInformationEditorView(companyID: companyID, category: category)", source)
        self.assertIn("if selectedItem?.id == item.id { selectedItem = nil }", source)

    def test_category_choices_are_text_only(self):
        editor = self.source("Companies/CompanyInformationEditorView.swift")
        listing = self.source("Companies/CompanyInformationView.swift")
        self.assertIn("Text(category.title).tag(category)", editor)
        self.assertIn("Button(category.title)", listing)
        self.assertNotIn("category.systemImage", editor + listing)

    def test_detail_uses_current_owned_record_and_untruncated_text(self):
        source = self.source("Companies/CompanyInformationDetailView.swift")
        for contract in ["session.userID == ownerUserID", "store.loadedUserID == ownerUserID",
                         "store.companyInformationItems.first", "$0.id == itemID",
                         "$0.companyID == companyID", "$0.userID == ownerUserID",
                         "Text(item.body)", "item.category.title",
                         "if let date = item.occurredOn", '"面接日" : "記録日"',
                         "editingItem = currentItem", ".textSelection(.enabled)"]:
            self.assertIn(contract, source)
        self.assertNotIn("Text(item.title)", source)
        self.assertNotIn(".lineLimit", source)
        self.assertNotIn("TextField", source)
        self.assertIn(".onChange(of: session.userID) { _, _ in editingItem = nil }", source)
        self.assertIn(".onChange(of: store.loadedUserID) { _, _ in editingItem = nil }", source)

    def test_only_acknowledged_delete_closes_owner_and_dirty_guard_survives(self):
        source = self.source("Companies/CompanyInformationEditorView.swift")
        deletion = source.split("private func deleteItem()", 1)[1]
        self.assertIn("guard store.isSaving == false, let item else { return }", deletion)
        self.assertIn("if await store.deleteCompanyInformationItem(item) {", deletion)
        self.assertIn("if let onDeleted { onDeleted() } else { dismiss() }", deletion)
        self.assertEqual(deletion.count("dismiss()"), 1)
        self.assertIn(".interactiveDismissDisabled(store.isSaving || hasUnsavedChanges)", source)
        self.assertIn("if hasUnsavedChanges {", source)
        self.assertIn("isOn: $draft.hasDate.animation(reduceMotion ? nil : .default)", source)
        detail = self.source("Companies/CompanyInformationDetailView.swift")
        self.assertIn("onDeleted: onDeleted", detail)
        self.assertNotIn("onDismiss:", detail)

    def test_shared_row_defaults_label_timeline_and_both_task_lists(self):
        task = self.source("Components/TaskRow.swift")
        step = self.source("Components/SelectionStepRow.swift")
        self.assertIn("var showsDueLabel = true", task)
        self.assertIn("dateLabelOverride ??", task)
        self.assertIn("var showsMilestoneKind = true", step)
        self.assertIn("milestoneLabelOverride ?? milestoneTitle(milestone)", step)
        for path in ["Companies/CompanyDetailView.swift", "Tasks/TasksView.swift", "Home/HomeView.swift"]:
            source = self.source(path)
            self.assertIn("TaskRow(", source)
            self.assertNotIn("showsDueLabel: false", source)
            self.assertNotIn("showsMilestoneKind: false", source)
        calendar = self.source("Calendar/RecruitCalendarView.swift")
        row = calendar.split("private func eventRow", 1)[1].split("private var monthDates", 1)[0]
        self.assertIn("milestoneLabelOverride: kind == .start ? DateFormatting.schedule(step) : dateLabel", row)
        self.assertIn("dateLabelOverride: DateFormatting.calendarMetadata(", row)
        self.assertIn('kind: "期限"', row)
        self.assertNotIn("DateFormatting.day", row)
        self.assertNotIn("DateFormatting.dateTime", row)

if __name__ == "__main__":
    unittest.main()
