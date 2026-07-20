create table public.es_templates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category text not null check (
    category in (
      'student_experience',
      'self_promotion',
      'motivation',
      'strengths',
      'weaknesses',
      'custom'
    )
  ),
  title text not null check (char_length(trim(title)) between 1 and 120),
  body text not null check (char_length(trim(body)) between 1 and 10000),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  version bigint not null default 1 check (version > 0)
);

create index es_templates_user_id_idx on public.es_templates(user_id, id);
create index es_templates_user_category_updated_idx
  on public.es_templates(user_id, category, updated_at desc);

create trigger es_templates_set_updated_at
before update on public.es_templates
for each row execute function public.set_updated_at();

create trigger es_templates_increment_version
before update on public.es_templates
for each row execute function public.increment_record_version();

alter table public.es_templates enable row level security;

create policy "Users manage their ES templates"
on public.es_templates
for all
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

revoke all on public.es_templates from anon;
grant select, insert, update, delete on public.es_templates to authenticated;
grant all on public.es_templates to service_role;
