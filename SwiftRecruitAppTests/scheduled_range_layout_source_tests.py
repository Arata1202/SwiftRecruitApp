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
        self.assertEqual(source.count('MetadataLabel(nextStep.displayTitle, systemImage: "list.bullet.rectangle", iconScale: .small)'), 1)
        self.assertNotIn('nextStep.type.systemImage', source)

    def test_metadata_glyph_scale_is_independent_of_gutter(self):
        source = (ROOT / "Views/Components/MetadataLabel.swift").read_text()
        self.assertIn('.imageScale(iconScale)', source)
        self.assertIn('.fontWeight(.regular)', source)
        self.assertIn('.frame(width: 16)', source)
        self.assertIn('iconScale: Image.Scale = .medium', source)

    def test_editable_detail_content_fills_space_before_disclosure(self):
        source = (ROOT / "Views/Companies/CompanyDetailView.swift").read_text()
        section = source.split('private func companySection')[1].split('private var editDisclosureIndicator')[0]
        for field, next_field in [('name', 'url'), ('url', 'memo')]:
            row = section.split('editingCompanyField = .' + field)[1].split('editingCompanyField = .' + next_field)[0]
            self.assertIn('.frame(maxWidth: .infinity, alignment: .leading)', row)
            self.assertIn('.fullWidthTappableArea()', row)
        self.assertIn('.lineLimit(nil)', section)
        self.assertIn('.fixedSize(horizontal: false, vertical: true)', section)
        hit_area = (ROOT / "Views/Components/FullWidthTappableArea.swift").read_text()
        self.assertIn('.contentShape(.rect)', hit_area)

    def test_company_card_keeps_native_disclosure_and_flexible_name(self):
        source = (ROOT / "Views/Companies/CompaniesView.swift").read_text()
        self.assertIn('NavigationLink(value: company.id)', source)
        row = source.split('private struct CompanyRow')[1]
        self.assertIn('.frame(maxWidth: .infinity, alignment: .leading)', row)
        self.assertIn('CompanyStatusBadge(status: company.status)', row)
        self.assertIn('.fullWidthTappableArea()', row)
        self.assertNotIn('chevron.right', row)
