-- A verified revocation can be reused only for the same account until deletion completes.
create table public.account_deletion_requests (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.account_deletion_requests enable row level security;
revoke all on public.account_deletion_requests from public, anon, authenticated, service_role;
grant select, insert, update on public.account_deletion_requests to service_role;
