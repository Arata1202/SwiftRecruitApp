# Tools retirement and reversible restoration

## Review status

The next-release Tools removal is stacked on PR #18, branch `fix/company-list-label-colors`. It removes the Tools tab, views, models, repository protocol/implementation, store loading/mutations, limits, fixtures and feature tests. Internal calendar, notifications, company research and core session-race tests remain.

**Draft / owner decision pending:** existing question answers are provisionally grouped with self-analysis + motivation for preservation. This is not a settled product decision. Confirm this grouping before marking the removal PR ready. No question-answer records are deleted.

Two sibling Drafts, both based on `chore/remove-tools`:
- `restore/self-analysis-motivation`: self-analysis questions/answers + motivation chart, no ES.
- `restore/es-templates`: ES templates only, no self-analysis.

Each is a real selective code/test addition against the removal branch. Restoration source is commit `374b3cf89a90a2828942a2bb37a22ffc1d0ad31e` (already without Apple calendar integration). Shared tab/store/protocol edits must be reconciled if both Drafts are later combined. Future conflict-free merging is not promised. Neither restores EventKit.

## Database preserved: three tables

| Table | Provenance in supabase/migrations | Dependencies / protections |
| --- | --- | --- |
| public.es_templates | 20260720213004_add_es_templates.sql | user_id → auth.users(id), ON DELETE CASCADE; category/title/body checks, positive version; user/id and category/update indexes |
| public.self_analysis_answers | 20260720220539_add_self_analysis.sql | user_id → auth.users(id), ON DELETE CASCADE; category/question/answer checks, positive version; user/id and category/update indexes |
| public.motivation_points | 20260720220539_add_self_analysis.sql | user_id → auth.users(id), ON DELETE CASCADE; age 0–100, happiness 0–10, reason length; unique(user_id,age), positive version; user/id index |

All three enable RLS: authenticated ALL policies enforce `(select auth.uid()) = user_id` in USING and WITH CHECK; anon has no privileges; authenticated receives select/insert/update/delete; service_role has all privileges. Update triggers depend on shared `public.set_updated_at()` and `public.increment_record_version()`. Do not remove these shared functions. Repository migration search found no incoming foreign keys from retained company/selection/task tables; live DB and old-client dependencies have NOT been audited. Existing account deletion still cascades from auth.users by the established policy; this PR does not invoke it.

## Cleanup gate and restoration

No applied migration is edited, no destructive migration is added, no SQL is executed. Existing tables, rows, grants, policies, triggers and auth dependencies remain. Draft restoration therefore needs **no schema migration while these tables remain**; the exact original schema/RLS files above are retained as provenance on every branch.

Before any later DB cleanup: inventory live dependencies and deployed/old clients; confirm backup/export and restore test or explicit disposal consent; confirm question-answer scope; review a separate forward migration and rollback/data restoration plan. Do not drop tables merely because this client no longer references them. If cleanup later occurs, prepare an independently reviewed forward recreation migration from the provenance files, including indexes/constraints/triggers/RLS/grants and data restore. Do not replay already-applied migration IDs or use a blanket revert.

## Verification

Source contracts and diff checks run locally; macOS GitHub Actions supplies build/XCTest for each exact PR head. No Swift/Xcode locally. Draft status does not mean compilation is optional. Physical-device and live-DB checks remain separate gates.
