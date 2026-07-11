alter table public.companies
  drop constraint if exists companies_status_check;

alter table public.companies
  alter column status set default 'considering';

alter table public.companies
  add constraint companies_status_check
  check (status in ('considering', 'active', 'offer', 'rejected', 'withdrawn'));
