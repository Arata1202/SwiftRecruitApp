"""Bounded UI wiring contracts; device rendering and async gestures remain unverified."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1] / "SwiftRecruitApp"

class EditorFeedbackContracts(unittest.TestCase):
    def test_all_four_explicit_editor_animations_respect_reduce_motion(self):
        for name, count in [("Tasks/TaskEditorView.swift", 2), ("Companies/SelectionStepEditorView.swift", 1), ("Companies/CompanyInformationEditorView.swift", 1)]:
            source = (ROOT / "Views" / name).read_text(encoding="utf-8")
            self.assertIn("accessibilityReduceMotion", source)
            self.assertEqual(source.count(".animation(reduceMotion ? nil : .default)"), count)
            self.assertNotIn(".animation()", source)

    def test_delete_feedback_is_local_and_clears_on_all_results(self):
        for name in ["Tasks/TaskEditorView.swift", "Companies/SelectionStepEditorView.swift", "Companies/CompanyInformationEditorView.swift"]:
            source = (ROOT / "Views" / name).read_text(encoding="utf-8")
            self.assertIn("@State private var isDeleting = false", source)
            label = source.split("ToolbarItem(placement: .confirmationAction)", 1)[1].split(".disabled", 1)[0]
            self.assertIn('if isDeleting {', label)
            self.assertIn('ProgressView("削除中")', label)
            self.assertIn('} else {', label)
            self.assertIn('SaveButtonLabel(isSaving: store.isSaving)', label)
            delete = source.split("    private func delete", 1)[1]
            self.assertLess(delete.index("guard "), delete.index("isDeleting = true"))
            self.assertLess(delete.index("defer { isDeleting = false }"), delete.index("if await store.delete"))
            self.assertIn("if let onDeleted { onDeleted() } else { dismiss() }", delete)
            self.assertIn(".interactiveDismissDisabled(store.isSaving || hasUnsavedChanges)", source)

    def test_status_progress_targets_selected_row_without_optimistic_mutation(self):
        source = (ROOT / "Views/Companies/CompanyDetailView.swift").read_text(encoding="utf-8").split("private struct CompanyStatusSelectionView", 1)[1]
        self.assertIn("if updatingStatus == status", source)
        self.assertIn('ProgressView()', source)
        self.assertIn('else if status == company?.status', source)
        self.assertIn(".disabled(store.isSaving || updatingStatus != nil)", source)
        self.assertIn("guard !store.isSaving, updatingStatus == nil, let company else { return }", source)
        self.assertIn("defer { updatingStatus = nil }", source)
        self.assertIn("if await store.updateCompany(company, draft: draft) != nil", source)
        self.assertNotIn("company.status =", source)

    def test_three_list_date_consumers_forward_reference_date(self):
        for path in ["Views/Components/TaskRow.swift", "Views/Components/SelectionStepRow.swift", "Views/Companies/CompaniesView.swift"]:
            source = (ROOT / path).read_text(encoding="utf-8")
            self.assertIn("DateFormatting.listDate(", source)
            call = source.split("DateFormatting.listDate(", 1)[1].split(")", 1)[0]
            self.assertIn("referenceDate: referenceDate", call)
            self.assertNotIn("DateFormatting.dateTime.string", source)
            self.assertNotIn("DateFormatting.day.string", source)

    def test_company_related_task_controls_align_to_multiline_row_top(self):
        source = (ROOT / "Views/Companies/CompanyDetailView.swift").read_text(encoding="utf-8").split("private var taskSection", 1)[1].split("private func deleteSection", 1)[0]
        self.assertIn("HStack(alignment: .top, spacing: 0)", source)
        self.assertIn("TaskCompletionButton(", source)
        self.assertIn("TaskRow(task: task, companyName: nil)", source)
