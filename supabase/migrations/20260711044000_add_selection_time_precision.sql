alter table public.selection_steps
  add column starts_has_time boolean not null default true,
  add column deadline_has_time boolean not null default true;

comment on column public.selection_steps.starts_has_time is
  'Whether starts_at includes a user-specified time.';

comment on column public.selection_steps.deadline_has_time is
  'Whether deadline_at includes a user-specified time.';
