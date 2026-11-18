# 2026-11-18 decision coverage

Publication is review-only: no merge, deployment, database execution, or device calendar modification.
PR #18 (`fix/company-list-label-colors`) carries the daily application decisions below. Paths are relative to SwiftRecruitApp unless qualified.

| Memo | Decision / coverage | Files / validation |
| --- | --- | --- |
| 09:57, 11:03 | Notification permission/settings link; reschedule retained data after reload failure; inline logout progress and duplicate prevention | Views/Settings/SettingsView.swift, State/AppSession.swift, App/RootView.swift; SettingsAccountSafetyTests |
| 10:38–11:03 | Explain immediate deletion after Apple verification, disable consent during work; mismatch guidance and uncertain-result handling without claiming success | Views/Settings/AccountDeletionView.swift, State/AppSession.swift, Utilities/UserFacingError.swift, supabase/functions/delete-account/index.ts; SettingsAccountSafetyTests |
| 10:38, 10:51 | Remove external Apple calendar settings, permission, exports, sync, account cleanup and EventKit service/coordinator | SettingsView, AccountDeletionView, RecruitCalendarView, RecruitStore, AppContainer, RootView, ErrorAlertModifier, project.yml; obsolete calendar tests removed; mixed notification integration tests retained |
| 10:28–11:22 | Overlay completion notice, short fade, company names, empty refresh, reduced-motion-aware expansion, Undo progress, visibility epoch | Views/Home/HomeView.swift; home_calendar_polish_source_tests.py |
| 11:31 | Refresh current day on day change/foreground without moving viewed month/selection; updating accessibility label | Views/Calendar/RecruitCalendarView.swift; source contracts, CalendarEventIndexTests |
| 14:07 | Shared reference date for company ordering/card; protect dirty company creation and saving dismissal; reset behaviors unchanged | Views/Companies/CompaniesView.swift, CompanyEditorView.swift, Models/Drafts.swift; CompanySelectionPolishDraftTests |
| 14:37–14:56, 15:12 | Standard selection supplemental input removed but stored data retained; other name kept; timeline memo 2 lines; company in detail; standard duplicate name hidden; state draft menu; type icons removed from picker/company card | Views/Companies/SelectionStepEditorView.swift, SelectionStepDetailView.swift, CompanyDetailView.swift, CompaniesView.swift; SelectionStepEditorDraftTests |
| 14:37, 15:09, 15:12 | Dirty field/selection edits protected; saving dismissal/deletion entry and confirmation blocked | CompanyFieldEditorView.swift, SelectionStepEditorView.swift, CompanyDetailView.swift; CompanySelectionPolishDraftTests |
| 14:49, 15:09, 16:30 | Common ToDo detail → edit at all entries; company fixed for related creation only; expired-notification explanation; dirty protection; basic/deadline/notification/memo order | Views/Tasks/TaskDetailView.swift, TaskEditorView.swift, TasksView.swift, HomeView.swift, RecruitCalendarView.swift, CompanyDetailView.swift; TaskPolishLocalTests |
| 16:30 | Trim search; shared task reference date; restrained reduced-motion-aware completion movement; keep deadline-only model and section rules | Views/Tasks/TasksView.swift, Views/Components/TaskRow.swift; TaskPolishLocalTests |
| 16:30 | Normal reconcile preserves unrelated delivered notifications; completed/cancelled/deleted target removal only; logout/reset clears app notifications | Services/LocalNotificationService.swift, State/RecruitStore.swift; LocalNotificationServiceTests, RecruitStoreIntegrationTests |
| 17:28 | Tools code removal with separate selective restoration Drafts; existing database preserved | Removal PR #19; self-analysis/motivation restore Draft #20; ES restore Draft #21; see tools-retirement.md |

## Preservation / non-goals

- Internal calendar and local notifications remain. No EventKit access remains: previously exported device events and legacy preferences are left untouched, not cleaned or migrated. Existing events may remain in Apple Calendar without future app synchronization.
- Optional 15:12 status/record progress and selection-announcement polish is not promoted to required scope. No additional animation or custom notification-time settings.
- Existing normal-selection customTitle values are retained. No data-erasing migration.
- Question-answer grouping with self-analysis restoration is provisional, not an owner decision. Tools removal remains Draft pending confirmation.
- Database table cleanup requires separate backup/disposal, old-client and dependency confirmation. Applied migrations stay unchanged.
- The Apple mismatch Edge Function change needs a separately authorized deployment. This PR does not deploy it.

## Verification boundaries

Linux source-contract tests and diff checks are available locally. Swift/Xcode are unavailable locally; exact-head simulator build/XCTest is verified through GitHub Actions. Physical-device UI, VoiceOver, permissions/auth failure scenarios and production RLS/application are separate release gates, not claimed by CI.
