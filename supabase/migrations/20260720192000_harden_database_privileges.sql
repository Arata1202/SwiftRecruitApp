-- The RLS auto-enable function is an internal event-trigger implementation.
-- Keep the event trigger active, but prevent direct calls through the Data API.
-- It is an optional Supabase setup, so fresh environments may not have it.
do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    execute 'revoke execute on function public.rls_auto_enable() from public, anon, authenticated';
  end if;
end;
$$;

-- Application clients only need row-level CRUD. RLS continues to decide which
-- rows each authenticated user can access; service_role privileges are unchanged.
revoke all privileges on table
  public.companies,
  public.company_information_items,
  public.selection_steps,
  public.tasks
from anon, authenticated;

grant select, insert, update, delete on table
  public.companies,
  public.company_information_items,
  public.selection_steps,
  public.tasks
to authenticated;

-- Fail closed for future public tables/functions created by postgres.
-- Migrations must explicitly grant only the access each API object requires.
alter default privileges for role postgres in schema public
  revoke all privileges on tables from anon, authenticated;

alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;
