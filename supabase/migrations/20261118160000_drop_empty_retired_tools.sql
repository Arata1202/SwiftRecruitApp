-- Retired Tools clients must no longer access this database before applying.
-- One DO statement is atomic even when run without an outer transaction.
-- Keep all historical migrations and shared trigger functions.
do $migration$
begin
  perform set_config('lock_timeout', '5s', true);
  perform set_config('statement_timeout', '30s', true);
  -- Fail closed rather than accidentally seeing an RLS-filtered empty table.
  perform set_config('row_security', 'off', true);

  lock table public.self_analysis_answers, public.motivation_points,
    public.es_templates in access exclusive mode;

  if exists (select 1 from public.self_analysis_answers)
    or exists (select 1 from public.motivation_points)
    or exists (select 1 from public.es_templates) then
    raise exception 'Retired Tools tables are not empty; no tables were dropped';
  end if;

  drop table public.self_analysis_answers, public.motivation_points,
    public.es_templates restrict;
end
$migration$;
