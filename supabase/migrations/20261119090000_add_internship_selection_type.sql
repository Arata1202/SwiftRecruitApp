-- Extend the existing type constraint without rewriting stored records.
alter table public.selection_steps drop constraint selection_steps_type_check;
alter table public.selection_steps add constraint selection_steps_type_check
  check (type in ('briefing', 'internship', 'document', 'aptitude', 'interview', 'offer', 'other'));
