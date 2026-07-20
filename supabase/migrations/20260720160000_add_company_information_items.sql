create table public.company_information_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  company_id uuid not null,
  category text not null check (
    category in ('research', 'motivation', 'interview', 'questions', 'custom')
  ),
  title text not null check (char_length(trim(title)) between 1 and 120),
  body text not null check (char_length(trim(body)) between 1 and 10000),
  occurred_on date,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  version bigint not null default 1 check (version > 0),
  constraint company_information_items_company_owner_fkey
    foreign key (company_id, user_id)
    references public.companies(id, user_id)
    on delete cascade
);

create index company_information_items_user_id_idx
  on public.company_information_items(user_id, id);

create index company_information_items_company_category_idx
  on public.company_information_items(company_id, category, occurred_on desc, updated_at desc);

create trigger company_information_items_set_updated_at
before update on public.company_information_items
for each row execute function public.set_updated_at();

create trigger company_information_items_increment_version
before update on public.company_information_items
for each row execute function public.increment_record_version();

alter table public.company_information_items enable row level security;

create policy "Users manage their company information items"
on public.company_information_items
for all
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

revoke all on public.company_information_items from anon;
grant select, insert, update, delete on public.company_information_items to authenticated;
grant all on public.company_information_items to service_role;
