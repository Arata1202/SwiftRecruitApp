-- Isolated database only; all rows are rolled back.
begin;
insert into auth.users(id) values ('00000000-0000-0000-0000-000000000081');
insert into public.companies(id,user_id,name) values
('00000000-0000-0000-0000-000000000082','00000000-0000-0000-0000-000000000081','Absolute test');
do $$
declare
  relation text;
  row_id uuid;
  stored timestamptz;
  legacy jsonb;
  old_version integer;
  new_version integer;
begin
  foreach relation in array array['selection_steps','tasks'] loop
    if relation = 'selection_steps' then
      insert into public.selection_steps(user_id,company_id,type,starts_at,starts_has_time,deadline_has_time,notification_enabled)
      values ('00000000-0000-0000-0000-000000000081','00000000-0000-0000-0000-000000000082','interview','2030-01-02 00:00Z',true,false,true)
      returning id into row_id;
    else
      insert into public.tasks(user_id,title,due_at,due_has_time,notification_enabled)
      values ('00000000-0000-0000-0000-000000000081','Absolute test','2030-01-02 00:00Z',true,true) returning id into row_id;
    end if;
    execute format('select notification_absolute_at from public.%I where id=$1',relation) into stored using row_id;
    assert stored is null;
    execute format('update public.%I set notification_timed_custom=$1, notification_absolute_at=$2 where id=$3',relation)
      using '{"mode":"elapsed","value":97,"unit":"minutes"}'::jsonb,'2030-01-01 10:23+09'::timestamptz,row_id;
    execute format('select notification_absolute_at, notification_timed_custom, version from public.%I where id=$1',relation)
      into stored,legacy,old_version using row_id;
    assert stored = '2030-01-01 01:23Z'::timestamptz;
    assert legacy->>'value' = '97';
    execute format('update public.%I set memo=''unrelated'' where id=$1',relation) using row_id;
    execute format('select notification_absolute_at,version from public.%I where id=$1',relation) into stored,new_version using row_id;
    assert stored = '2030-01-01 01:23Z'::timestamptz;
    assert new_version = old_version + 1;
    begin
      execute format('update public.%I set notification_absolute_at=''infinity'' where id=$1',relation) using row_id;
      raise exception 'infinity accepted';
    exception when check_violation then null;
    end;
    begin
      execute format('update public.%I set notification_date_preset=''three_days'' where id=$1',relation) using row_id;
      raise exception 'legacy preset overwrite accepted';
    exception when check_violation then null;
    end;
    -- A preset detour is only editor state. Restoring the snapshot sends original
    -- presets/custom/absolute together, and must pass both compatibility guards.
    execute format('update public.%I set notification_timed_preset=null, notification_date_preset=null, notification_timed_custom=$1, notification_absolute_at=$2 where id=$3',relation)
      using '{"mode":"elapsed","value":97,"unit":"minutes"}'::jsonb,'2030-01-01 01:23Z'::timestamptz,row_id;
    execute format('update public.%I set notification_absolute_at=null where id=$1',relation) using row_id;
    execute format('update public.%I set notification_timed_preset=null, notification_timed_custom=$1 where id=$2',relation)
      using '{"mode":"elapsed","value":97,"unit":"minutes"}'::jsonb,row_id;
    execute format('update public.%I set notification_absolute_at=''2000-01-01Z'', notification_enabled=false where id=$1',relation) using row_id;
    execute format('update public.%I set memo=''expired unrelated'' where id=$1',relation) using row_id;
    execute format('update public.%I set notification_absolute_at=null where id=$1',relation) using row_id;
    execute format('select notification_absolute_at,notification_timed_custom from public.%I where id=$1',relation) into stored,legacy using row_id;
    assert stored is null;
    assert legacy->>'value' = '97';
    assert (select relrowsecurity from pg_class where oid = format('public.%I',relation)::regclass);
  end loop;
end;
$$;
insert into auth.users(id) values ('00000000-0000-0000-0000-000000000083');
insert into public.tasks(id,user_id,title,due_at,due_has_time,notification_absolute_at)
values ('00000000-0000-0000-0000-000000000084','00000000-0000-0000-0000-000000000081','Owner only','2030-01-02Z',true,'2030-01-01Z');
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000083"}';
do $$
declare affected integer;
begin
  update public.tasks set notification_absolute_at='2030-01-01 10:00Z'
    where id='00000000-0000-0000-0000-000000000084';
  get diagnostics affected = row_count;
  assert affected = 0, 'Cross-user update escaped RLS';
end;
$$;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000081"}';
do $$
declare affected integer;
begin
  update public.tasks set notification_absolute_at=null
    where id='00000000-0000-0000-0000-000000000084' and version=1;
  get diagnostics affected = row_count;
  assert affected = 1, 'Owner update failed';
  update public.tasks set notification_absolute_at='2030-01-01Z'
    where id='00000000-0000-0000-0000-000000000084' and version=1;
  get diagnostics affected = row_count;
  assert affected = 0, 'Stale version matched';
  begin
    update public.tasks set user_id='00000000-0000-0000-0000-000000000083'
      where id='00000000-0000-0000-0000-000000000084';
    raise exception 'Ownership transfer escaped RLS';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;
rollback;
