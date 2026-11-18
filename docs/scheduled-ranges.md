# Scheduled date ranges

Selections retain two distinct date kinds: a schedule and a single deadline. ToDo deadlines are unchanged.

For a schedule, choose its start date and optionally a time. The shared **時刻も指定** switch above the start/end sections applies to both endpoints. Enable **終了を指定** to add an end with the same precision. An end is not required; existing schedules remain start-only. End dates/times must not precede the start. Switching to a deadline and saving removes the schedule’s end; cancelling leaves the record unchanged.

- Date-only schedules include the final day. Their end is stored as a calendar date, not a timezone-dependent timestamp.
- Timed schedules cover the interval from start up to, but not including, end. An end at midnight does not add an event to the following day. Equal start/end is allowed and appears on the start day.
- The calendar shows the schedule on each covered day without allocating the entire range. Completed schedules remain visible; cancelled schedules are excluded.
- Home and company next-schedule summaries retain ongoing schedules. After the end, Home keeps unfinished schedules in its past-items section, without deadline warning color. Passing the end never completes a selection automatically.
- Notifications remain based solely on the start. Adding an end does not create an end reminder or change deadline/ToDo reminders.

Range labels omit the current year within that year, show a noncurrent year once, and show both years across a year boundary. Narrow layouts prefer a line break between endpoints; large text can also wrap an endpoint without hiding the end. VoiceOver retains both full dates. Company next-selection titles use one generic selection icon, independent of selection type.

## Database rollout

Apply `20261118170000_add_optional_selection_end.sql` before distributing a client that writes ranges. It adds nullable `ends_at` and `ends_on` columns with a precision/order constraint; it does not rewrite existing rows or historical migrations. Existing start-date compatibility mirrors remain unchanged. There were no end columns in the preceding schema.

Older clients can still read records and edit start-only schedules. They do not display or edit ends. On a ranged record, old-client edits that conflict with the stored end (switching date kind/precision or moving the start past the end) are rejected by the constraint rather than silently dropping the end. Use the updated client to edit these records. Compatible edits and status-only updates preserve the end.

`supabase/tests/selection_schedule_ranges.sql` exercises persistence and constraints in a disposable database after migrations. Its fixture inserts into `auth.users`; do not run it against production. It rolls back its test data.
