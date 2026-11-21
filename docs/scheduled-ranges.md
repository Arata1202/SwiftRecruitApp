# Scheduled date ranges

A selection can have a schedule or a single deadline. A schedule has a start and an optional end. Both endpoints use the same precision, and the end must be on or after the start. Saving a selection as a deadline clears its schedule end.

- A date-only schedule includes its final calendar day. Its end is stored as a date (`ends_on`) so that changing time zones does not shift it.
- A timed schedule excludes its end instant (`ends_at`). A schedule ending at midnight therefore does not appear on the following day. When start and end are equal, the calendar shows the schedule on its start day.
- The calendar shows completed schedules and hides cancelled ones. Home and company summaries include ongoing schedules. After the end, an unfinished selection appears among past items on Home until the user completes it.
- Notifications use the start of the schedule. Adding an end does not schedule a second reminder.

The [SQL tests for schedule ranges](../supabase/tests/selection_schedule_ranges.sql) check the database constraints. Run them in a disposable local database because they create test users in `auth.users`.
