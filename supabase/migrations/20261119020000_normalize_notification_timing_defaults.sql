-- Normalize only unspecified preferences. Explicit choices and disabled flags stay intact.
-- Deadline defaults intentionally replace the former previous-day 20:00 behavior.
update public.selection_steps
set notification_timed_preset = coalesce(notification_timed_preset,
      case when deadline_at is not null or deadline_on is not null then 'one_day' else 'one_hour' end),
    notification_date_preset = coalesce(notification_date_preset,
      case when deadline_at is not null or deadline_on is not null then 'previous_day' else 'same_day' end)
where notification_timed_preset is null or notification_date_preset is null;

update public.tasks
set notification_timed_preset = coalesce(notification_timed_preset, 'at_time'),
    notification_date_preset = coalesce(notification_date_preset, 'same_day')
where notification_timed_preset is null or notification_date_preset is null;
