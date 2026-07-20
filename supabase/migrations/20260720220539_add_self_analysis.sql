create table public.self_analysis_answers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category text not null check (
    category in ('values', 'strengths', 'interests', 'work_style', 'future', 'custom')
  ),
  question text not null check (char_length(trim(question)) between 1 and 300),
  answer text not null check (char_length(trim(answer)) between 1 and 10000),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  version bigint not null default 1 check (version > 0)
);

create table public.motivation_points (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  age smallint not null check (age between 0 and 100),
  happiness smallint not null check (happiness between 0 and 10),
  reason text not null check (char_length(trim(reason)) between 1 and 1000),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  version bigint not null default 1 check (version > 0),
  constraint motivation_points_user_age_key unique (user_id, age)
);

create index self_analysis_answers_user_id_idx
  on public.self_analysis_answers(user_id, id);
create index self_analysis_answers_user_category_idx
  on public.self_analysis_answers(user_id, category, updated_at desc);
create index motivation_points_user_id_idx
  on public.motivation_points(user_id, id);

create trigger self_analysis_answers_set_updated_at
before update on public.self_analysis_answers
for each row execute function public.set_updated_at();
create trigger self_analysis_answers_increment_version
before update on public.self_analysis_answers
for each row execute function public.increment_record_version();

create trigger motivation_points_set_updated_at
before update on public.motivation_points
for each row execute function public.set_updated_at();
create trigger motivation_points_increment_version
before update on public.motivation_points
for each row execute function public.increment_record_version();

alter table public.self_analysis_answers enable row level security;
alter table public.motivation_points enable row level security;

create policy "Users manage their self analysis answers"
on public.self_analysis_answers for all to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "Users manage their motivation points"
on public.motivation_points for all to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

revoke all on public.self_analysis_answers, public.motivation_points from anon;
grant select, insert, update, delete
  on public.self_analysis_answers, public.motivation_points to authenticated;
grant all on public.self_analysis_answers, public.motivation_points to service_role;
