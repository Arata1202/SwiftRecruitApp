-- Existing appointments remain start-only. No backfill or timestamp mirror for ends_on.
alter table public.selection_steps
  add column ends_at timestamptz,
  add column ends_on date,
  add constraint selection_steps_end_consistency check (
    (ends_at is null and ends_on is null)
    or (
      starts_at is not null and deadline_at is null
      and (
        (starts_has_time and ends_at is not null and ends_on is null and ends_at >= starts_at)
        or (not starts_has_time and ends_at is null and ends_on is not null
            and starts_on is not null and ends_on >= starts_on)
      )
    )
  );

comment on column public.selection_steps.ends_at is
  'Optional end of a timed schedule; same precision as its start. Midnight is exclusive in calendar coverage.';
comment on column public.selection_steps.ends_on is
  'Optional inclusive last calendar date of a date-only schedule. Never converted to a timestamp.';
