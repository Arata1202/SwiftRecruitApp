-- Forward-only corrections. Existing rows and their optimistic-lock tokens stay intact.
set local lock_timeout = '5s';
set local statement_timeout = '30s';

alter default privileges for role postgres revoke execute on functions from public;

alter table public.tasks alter column notification_enabled set default false;
alter table public.selection_steps
  alter column starts_has_time set default false,
  alter column deadline_has_time set default false;

create or replace function public.set_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.increment_record_version() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then new.version = 1;
  else new.version = old.version + 1;
  end if;
  return new;
end;
$$;

alter table public.companies
  alter column created_at set default now(),
  alter column updated_at set default now();
create trigger companies_initial_version before insert on public.companies
  for each row execute function public.increment_record_version();

alter table public.selection_steps
  alter column created_at set default now(),
  alter column updated_at set default now();
create trigger selection_steps_initial_version before insert on public.selection_steps
  for each row execute function public.increment_record_version();

alter table public.tasks
  alter column created_at set default now(),
  alter column updated_at set default now();
create trigger tasks_initial_version before insert on public.tasks
  for each row execute function public.increment_record_version();

alter table public.company_information_items
  alter column created_at set default now(),
  alter column updated_at set default now();
create trigger company_information_items_initial_version before insert on public.company_information_items
  for each row execute function public.increment_record_version();

alter table public.selection_steps add constraint starts_on_required
  check (starts_at is null or starts_has_time or starts_on is not null) not valid;
alter table public.selection_steps add constraint deadline_on_required
  check (deadline_at is null or deadline_has_time or deadline_on is not null) not valid;
alter table public.tasks add constraint due_on_required
  check (due_at is null or due_has_time or due_on is not null) not valid;

alter table public.company_information_items
  add constraint information_title_storage_limit check (char_length(title) <= 120 and title ~ '[^[:space:]]') not valid,
  add constraint information_body_storage_limit check (char_length(body) <= 10000 and body ~ '[^[:space:]]') not valid;

create or replace function public.guard_absolute_notification_preset_write()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.notification_absolute_at is not null
     and new.notification_absolute_at is not distinct from old.notification_absolute_at
     and (new.notification_timed_preset is distinct from old.notification_timed_preset
       or new.notification_date_preset is distinct from old.notification_date_preset
       or new.notification_timed_custom is distinct from old.notification_timed_custom
       or new.notification_date_custom is distinct from old.notification_date_custom) then
    raise exception 'Absolute notification timing is active. Upgrade the client or explicitly clear the absolute preference.'
      using errcode = '23514';
  end if;
  return new;
end;
$$;
