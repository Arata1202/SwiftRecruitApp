"""Keep explanatory copy concise without dropping recovery or safety guidance."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1] / "SwiftRecruitApp"

class UserFacingCopyContracts(unittest.TestCase):
    def test_notification_errors_have_one_visible_owner(self):
        picker = (ROOT / "Views/Components/NotificationTimingPicker.swift").read_text()
        self.assertNotIn("保持されます", picker)
        self.assertNotIn("Text(message)", picker)
        for name in ["Tasks/TaskEditorView.swift", "Companies/SelectionStepEditorView.swift"]:
            source = (ROOT / "Views" / name).read_text()
            self.assertEqual(source.count("Text(message).font(.footnote).foregroundStyle(.red)"), 1)
            self.assertIn("カスタム設定の入力をやり直す", source)
            self.assertNotIn("通知が再設定されます", source)
        task = (ROOT / "Views/Tasks/TaskEditorView.swift").read_text()
        self.assertNotIn("footer:", task)  # Completed status is already in its preview.
        step = (ROOT / "Views/Companies/SelectionStepEditorView.swift").read_text()
        self.assertIn("if draft.status != .scheduled {", step)

    def test_notification_plan_is_not_a_delivery_confirmation(self):
        source = (ROOT / "State/RecruitStore.swift").read_text()
        for text in ["通知予定：", "64件", "予約対象外", "アプリ停止中は追加されません", "一覧を更新してください"]:
            self.assertIn(text, source)
        self.assertNotIn("端末への登録・配信を確認したものではありません", source)
        timing = (ROOT / "Models/NotificationTiming.swift").read_text()
        self.assertNotIn("端末の設定により届かない", timing)
        self.assertIn("過ぎているため、通知されません", timing)
        settings = (ROOT / "Views/Settings/SettingsView.swift").read_text()
        self.assertIn("選考・ToDoの編集画面で通知を設定できます", settings)
        self.assertIn("notificationStatus == .denied", settings)
        self.assertIn("iOSの設定を開く", settings)
        self.assertNotIn("計算上の予約対象", source)
        self.assertNotIn("通知計画", source)

    def test_configuration_failure_offers_the_requested_recovery(self):
        source = (ROOT / "App/RootView.swift").read_text().split("private struct ConfigurationMissingView", 1)[1]
        self.assertIn("お問い合わせください", source)
        self.assertIn('Link("お問い合わせ", destination: AppLinks.support)', source)

    def test_destructive_and_reauthentication_warnings_remain(self):
        for name in ["Tasks/TaskEditorView.swift", "Companies/SelectionStepEditorView.swift", "Companies/CompanyInformationEditorView.swift"]:
            source = (ROOT / "Views" / name).read_text()
            self.assertIn("この操作は取り消せません", source)
            self.assertIn("保存していない変更は失われます", source)
        account = (ROOT / "Views/Settings/AccountDeletionView.swift").read_text()
        self.assertIn("本人確認", account)
        self.assertIn("削除", account)
