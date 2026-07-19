alter table public.selection_steps
  add column starts_on date,
  add column deadline_on date;

alter table public.tasks
  add column due_on date;

comment on column public.selection_steps.starts_on is
  'Calendar date for a start without a user-specified time. starts_at remains as a legacy-client compatibility mirror.';

comment on column public.selection_steps.deadline_on is
  'Calendar date for a deadline without a user-specified time. deadline_at remains as a legacy-client compatibility mirror.';

comment on column public.tasks.due_on is
  'Calendar date for a due date without a user-specified time. due_at remains as a legacy-client compatibility mirror.';

-- Backfilling compatibility columns is a schema migration, not a user edit.
-- Temporarily disable only the updated_at triggers so existing timestamps remain intact.
do $$
begin
  execute 'alter table public.selection_steps disable trigger selection_steps_set_updated_at';
  execute 'alter table public.tasks disable trigger tasks_set_updated_at';

  update public.selection_steps
  set starts_on = (starts_at at time zone 'Asia/Tokyo')::date
  where starts_at is not null
    and starts_has_time = false;

  update public.selection_steps
  set deadline_on = (deadline_at at time zone 'Asia/Tokyo')::date
  where deadline_at is not null
    and deadline_has_time = false;

  update public.tasks
  set due_on = (due_at at time zone 'Asia/Tokyo')::date
  where due_at is not null
    and due_has_time = false;

  execute 'alter table public.selection_steps enable trigger selection_steps_set_updated_at';
  execute 'alter table public.tasks enable trigger tasks_set_updated_at';
end;
$$;

-- Dates decoded by current Apple/Supabase formatters lose sub-millisecond precision,
-- so updated_at cannot safely double as an optimistic-lock token. A dedicated
-- server-controlled integer version is exact, additive, and remains compatible
-- with legacy clients that do not send the column.
alter table public.companies
  add column version bigint not null default 1
    constraint companies_version_positive check (version > 0);

alter table public.selection_steps
  add column version bigint not null default 1
    constraint selection_steps_version_positive check (version > 0);

alter table public.tasks
  add column version bigint not null default 1
    constraint tasks_version_positive check (version > 0);

create or replace function public.increment_record_version()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.version = old.version + 1;
  return new;
end;
$$;

create trigger companies_increment_version
before update on public.companies
for each row execute function public.increment_record_version();

create trigger selection_steps_increment_version
before update on public.selection_steps
for each row execute function public.increment_record_version();

create trigger tasks_increment_version
before update on public.tasks
for each row execute function public.increment_record_version();

create or replace function public.sync_date_only_columns()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if tg_table_name = 'selection_steps' then
    if new.starts_at is null or new.starts_has_time then
      new.starts_on = null;
    elsif tg_op = 'INSERT' then
      new.starts_on = coalesce(new.starts_on, (new.starts_at at time zone 'Asia/Tokyo')::date);
    elsif new.starts_on is not distinct from old.starts_on
      and (
        new.starts_at is distinct from old.starts_at
        or new.starts_has_time is distinct from old.starts_has_time
      ) then
      new.starts_on = (new.starts_at at time zone 'Asia/Tokyo')::date;
    end if;

    if new.deadline_at is null or new.deadline_has_time then
      new.deadline_on = null;
    elsif tg_op = 'INSERT' then
      new.deadline_on = coalesce(new.deadline_on, (new.deadline_at at time zone 'Asia/Tokyo')::date);
    elsif new.deadline_on is not distinct from old.deadline_on
      and (
        new.deadline_at is distinct from old.deadline_at
        or new.deadline_has_time is distinct from old.deadline_has_time
      ) then
      new.deadline_on = (new.deadline_at at time zone 'Asia/Tokyo')::date;
    end if;
  elsif tg_table_name = 'tasks' then
    if new.due_at is null or new.due_has_time then
      new.due_on = null;
    elsif tg_op = 'INSERT' then
      new.due_on = coalesce(new.due_on, (new.due_at at time zone 'Asia/Tokyo')::date);
    elsif new.due_on is not distinct from old.due_on
      and (
        new.due_at is distinct from old.due_at
        or new.due_has_time is distinct from old.due_has_time
      ) then
      new.due_on = (new.due_at at time zone 'Asia/Tokyo')::date;
    end if;
  end if;

  return new;
end;
$$;

create trigger selection_steps_sync_date_only_columns
before insert or update on public.selection_steps
for each row execute function public.sync_date_only_columns();

create trigger tasks_sync_date_only_columns
before insert or update on public.tasks
for each row execute function public.sync_date_only_columns();

alter table public.selection_steps
  add constraint selection_steps_start_date_consistency check (
    (starts_at is null and starts_on is null)
    or (starts_at is not null and starts_has_time and starts_on is null)
    or (
      starts_at is not null
      and starts_has_time = false
      and starts_on = (starts_at at time zone 'Asia/Tokyo')::date
    )
  ),
  add constraint selection_steps_deadline_date_consistency check (
    (deadline_at is null and deadline_on is null)
    or (deadline_at is not null and deadline_has_time and deadline_on is null)
    or (
      deadline_at is not null
      and deadline_has_time = false
      and deadline_on = (deadline_at at time zone 'Asia/Tokyo')::date
    )
  ),
  add constraint selection_steps_custom_title_length check (
    custom_title is null or char_length(custom_title) <= 120
  ) not valid,
  add constraint selection_steps_memo_length check (
    memo is null or char_length(memo) <= 10000
  ) not valid;

alter table public.companies
  add constraint companies_url_length check (
    url is null or char_length(url) <= 2048
  ) not valid,
  add constraint companies_memo_length check (
    memo is null or char_length(memo) <= 10000
  ) not valid;

alter table public.tasks
  add constraint tasks_due_date_consistency check (
    (due_at is null and due_on is null)
    or (due_at is not null and due_has_time and due_on is null)
    or (
      due_at is not null
      and due_has_time = false
      and due_on = (due_at at time zone 'Asia/Tokyo')::date
    )
  ),
  add constraint tasks_memo_length check (
    memo is null or char_length(memo) <= 10000
  ) not valid;

-- NOT VALID keeps the initial lock brief; validation below confirms that the
-- complete pre-existing data set also satisfies every new length constraint.
alter table public.selection_steps
  validate constraint selection_steps_custom_title_length,
  validate constraint selection_steps_memo_length;

alter table public.companies
  validate constraint companies_url_length,
  validate constraint companies_memo_length;

alter table public.tasks
  validate constraint tasks_memo_length;

create index selection_steps_user_starts_on_idx
  on public.selection_steps(user_id, starts_on);

create index selection_steps_user_deadline_on_idx
  on public.selection_steps(user_id, deadline_on);

create index tasks_user_due_on_idx
  on public.tasks(user_id, due_on);
