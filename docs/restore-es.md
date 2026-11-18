# Selective restoration Draft: ES templates

Base: chore/remove-tools. Source: 374b3cf89a90a2828942a2bb37a22ffc1d0ad31e. This Draft restores real views, model/draft validation, store operations/loading, repository protocol/queries/serialization, limits and regression tests for this feature only. Apple external calendar is not restored; self-analysis/questions/motivation remain absent.

Schema/RLS provenance: supabase/migrations/20260720213004_add_es_templates.sql (es_templates). Existing tables and data were never removed. No migration execution is needed or performed. These retained files define owner-only USING/WITH CHECK auth.uid() policies, authenticated CRUD grants, anon revocation, service_role grants, auth.users cascade FK, validation/indexes, shared timestamp/version triggers. See tools-retirement.md for dependency and cleanup gates. If a later separately approved drop occurs, recreate schema/RLS/grants/triggers and restore backed-up data via a separately reviewed forward migration, not by replaying old migration IDs.

This Draft is not approval to ship. Validate exact-head CI, rebase/review shared tab/store/protocol changes if combining the sibling Draft, and re-test RLS against a local database before release. No live DB/calendar data touched.
