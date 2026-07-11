update public.selection_steps
set starts_at = null,
    starts_has_time = false
where starts_at is not null
  and deadline_at is not null
  and type in ('document', 'aptitude');

update public.selection_steps
set deadline_at = null,
    deadline_has_time = false
where starts_at is not null
  and deadline_at is not null;

alter table public.selection_steps
  drop constraint selection_steps_has_date;

alter table public.selection_steps
  add constraint selection_steps_has_exactly_one_date
  check ((starts_at is null) <> (deadline_at is null));
