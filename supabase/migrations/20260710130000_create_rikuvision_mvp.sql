create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

create table public.companies (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 120),
  priority smallint not null default 3 check (priority between 1 and 5),
  status text not null default 'active' check (status in ('active', 'offer', 'rejected', 'withdrawn')),
  url text,
  memo text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (id, user_id)
);

create table public.selection_steps (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  company_id uuid not null,
  type text not null check (type in ('briefing', 'document', 'aptitude', 'interview', 'offer', 'other')),
  custom_title text,
  starts_at timestamptz,
  deadline_at timestamptz,
  status text not null default 'scheduled' check (status in ('scheduled', 'completed', 'cancelled')),
  memo text,
  notification_enabled boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint selection_steps_company_owner_fkey
    foreign key (company_id, user_id) references public.companies(id, user_id) on delete cascade,
  constraint selection_steps_has_date check (starts_at is not null or deadline_at is not null),
  constraint selection_steps_custom_title check (
    type <> 'other' or char_length(trim(coalesce(custom_title, ''))) > 0
  )
);

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  company_id uuid,
  title text not null check (char_length(trim(title)) between 1 and 200),
  memo text,
  due_at timestamptz,
  due_has_time boolean not null default false,
  completed_at timestamptz,
  notification_enabled boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint tasks_company_owner_fkey
    foreign key (company_id, user_id) references public.companies(id, user_id) on delete cascade,
  constraint tasks_notification_requires_due_date check (
    notification_enabled = false or due_at is not null
  ),
  constraint tasks_time_requires_due_date check (
    due_has_time = false or due_at is not null
  )
);

create index companies_user_status_idx on public.companies(user_id, status);
create index companies_user_updated_idx on public.companies(user_id, updated_at desc);
create index selection_steps_user_starts_idx on public.selection_steps(user_id, starts_at);
create index selection_steps_user_deadline_idx on public.selection_steps(user_id, deadline_at);
create index selection_steps_company_idx on public.selection_steps(company_id);
create index tasks_user_due_idx on public.tasks(user_id, due_at);
create index tasks_company_idx on public.tasks(company_id);

create trigger companies_set_updated_at
before update on public.companies
for each row execute function public.set_updated_at();

create trigger selection_steps_set_updated_at
before update on public.selection_steps
for each row execute function public.set_updated_at();

create trigger tasks_set_updated_at
before update on public.tasks
for each row execute function public.set_updated_at();

alter table public.companies enable row level security;
alter table public.selection_steps enable row level security;
alter table public.tasks enable row level security;

create policy "Users manage their companies"
on public.companies
for all
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "Users manage their selection steps"
on public.selection_steps
for all
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "Users manage their tasks"
on public.tasks
for all
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

revoke all on public.companies, public.selection_steps, public.tasks from anon;
grant select, insert, update, delete on public.companies, public.selection_steps, public.tasks to authenticated;
grant all on public.companies, public.selection_steps, public.tasks to service_role;

