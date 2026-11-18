from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1] / "SwiftRecruitApp"


class ScheduledRangeLayoutContracts(unittest.TestCase):
    def test_shared_precision_precedes_both_endpoint_sections(self):
        source = (ROOT / "Views/Companies/SelectionStepEditorView.swift").read_text()
        self.assertEqual(source.count('Toggle("時刻も指定"'), 1)
        self.assertLess(source.index('Toggle("時刻も指定"'), source.index('Section(draft.dateKind == .schedule ? "開始"'))
        self.assertLess(source.index('Section(draft.dateKind == .schedule ? "開始"'), source.index('Text("終了（任意）")'))

    def test_range_layout_has_endpoint_fallback_and_full_accessibility(self):
        source = (ROOT / "Views/Components/ScheduleRangeLabel.swift").read_text()
        self.assertIn('ViewThatFits(in: .horizontal)', source)
        self.assertIn('Text(text.start)', source)
        self.assertIn('Text("〜" + end)', source)
        self.assertIn('.accessibilityLabel(text.accessibilityLabel)', source)
        self.assertNotIn('.lineLimit(', source)
        for path in ['Views/Components/SelectionStepRow.swift', 'Views/Companies/CompaniesView.swift', 'Views/Companies/SelectionStepDetailView.swift']:
            self.assertIn('ScheduleRangeLabel(', (ROOT / path).read_text())

    def test_company_selection_uses_one_generic_metadata_icon(self):
        source = (ROOT / "Views/Companies/CompaniesView.swift").read_text()
        self.assertEqual(source.count('MetadataLabel(nextStep.displayTitle, systemImage: "list.bullet.rectangle")'), 1)
        self.assertNotIn('nextStep.type.systemImage', source)
