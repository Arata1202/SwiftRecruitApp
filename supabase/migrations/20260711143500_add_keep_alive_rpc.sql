create or replace function public.keep_alive()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select true;
$$;

revoke all on function public.keep_alive() from public;
grant execute on function public.keep_alive() to anon;

comment on function public.keep_alive() is
  'Returns a constant value so scheduled health checks can generate harmless database activity.';
