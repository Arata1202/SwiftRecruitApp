-- NULL preserves legacy scheduling, including previous-day 20:00 deadlines.
-- Keep preferences for both date precisions; changing precision is lossless.
-- No backfill: existing disabled flags and delivery times remain untouched.
alter table public.selection_steps
  add column notification_timed_preset text check (notification_timed_preset in
    ('at_time', 'ten_minutes', 'thirty_minutes', 'one_hour', 'one_day', 'three_days')),
  add column notification_date_preset text check (notification_date_preset in
    ('same_day', 'previous_day', 'three_days'));

alter table public.tasks
  add column notification_timed_preset text check (notification_timed_preset in
    ('at_time', 'ten_minutes', 'thirty_minutes', 'one_hour', 'one_day', 'three_days')),
  add column notification_date_preset text check (notification_date_preset in
    ('same_day', 'previous_day', 'three_days'));
