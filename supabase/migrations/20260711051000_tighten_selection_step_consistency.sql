update public.selection_steps
set starts_has_time = false
where starts_at is null;

update public.selection_steps
set deadline_has_time = false
where deadline_at is null;

update public.selection_steps
set notification_enabled = false
where status <> 'scheduled';

alter table public.selection_steps
  add constraint selection_steps_start_time_requires_date
    check (starts_has_time = false or starts_at is not null),
  add constraint selection_steps_deadline_time_requires_date
    check (deadline_has_time = false or deadline_at is not null),
  add constraint selection_steps_notification_requires_scheduled_status
    check (notification_enabled = false or status = 'scheduled');
