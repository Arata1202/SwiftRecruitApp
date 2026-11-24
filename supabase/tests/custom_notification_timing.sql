-- Run after all migrations in an isolated test database only.
begin;
set local plpgsql.check_asserts = on;
insert into auth.users(id) values ('00000000-0000-0000-0000-000000000091');
insert into public.companies(id,user_id,name) values
('00000000-0000-0000-0000-000000000092','00000000-0000-0000-0000-000000000091','Notification test');
do $$
declare
  value jsonb;
  relation text;
  row_id uuid;
  stored jsonb;
begin
  assert public.valid_custom_notification_timing(null, true);
  foreach value in array array[
    'null','{}','[]','{"mode":"elapsed","value":0,"unit":"minutes"}',
    '{"mode":"elapsed","value":2016001,"unit":"minutes"}',
    '{"mode":"elapsed","value":33601,"unit":"hours"}',
    '{"mode":"elapsed","value":1.5,"unit":"hours"}',
    '{"mode":"elapsed","value":1,"unit":null}',
    '{"mode":"elapsed","value":1,"unit":"hours","hour":9}',
    '{"mode":"calendar","value":0,"hour":9}',
    '{"mode":"calendar","value":0,"hour":null,"minute":0}',
    '{"mode":"calendar","value":0,"hour":"9","minute":0}',
    '{"mode":"calendar","value":1401,"hour":9,"minute":0}',
    '{"mode":"calendar","value":-1,"hour":9,"minute":0}',
    '{"mode":"calendar","value":0,"hour":24,"minute":0}',
    '{"mode":"calendar","value":0,"hour":9,"minute":60}',
    '{"mode":"calendar","value":0,"hour":9,"minute":0,"unit":"hours"}'
  ]::jsonb[] loop
    assert not public.valid_custom_notification_timing(value, true), 'Invalid JSON accepted';
  end loop;
  foreach value in array array[
    '{"mode":"elapsed","value":1,"unit":"minutes"}',
    '{"mode":"elapsed","value":525600,"unit":"minutes"}',
    '{"mode":"elapsed","value":8760,"unit":"hours"}',
    '{"mode":"elapsed","value":2016000,"unit":"minutes"}',
    '{"mode":"elapsed","value":33600,"unit":"hours"}'
  ]::jsonb[] loop
    assert public.valid_custom_notification_timing(value, true);
    assert not public.valid_custom_notification_timing(value, false);
  end loop;
  assert public.valid_custom_notification_timing('{"mode":"calendar","value":365,"hour":23,"minute":59}', false);

  assert public.valid_custom_notification_timing('{"mode":"calendar","value":1400,"hour":9,"minute":0}', false);

  foreach relation in array array['selection_steps','tasks'] loop
    if relation = 'selection_steps' then
      insert into public.selection_steps(user_id,company_id,type,starts_at,starts_has_time,deadline_has_time,notification_enabled)
      values ('00000000-0000-0000-0000-000000000091','00000000-0000-0000-0000-000000000092','interview','2030-01-02 00:00Z',false,false,false)
      returning id into row_id;
    else
      insert into public.tasks(user_id,title,due_at,notification_enabled)
      values ('00000000-0000-0000-0000-000000000091','Custom test','2030-01-02 00:00Z',false) returning id into row_id;
    end if;
    execute format('select notification_timed_custom from public.%I where id=$1',relation) into stored using row_id;
    assert stored is null, 'Legacy insert invented a custom setting';
    execute format('update public.%I set notification_timed_preset=''one_hour'', notification_date_preset=''same_day'', notification_timed_custom=$1, notification_date_custom=$2 where id=$3',relation)
      using '{"mode":"elapsed","value":17,"unit":"minutes"}'::jsonb,
            '{"mode":"calendar","value":2,"hour":18,"minute":23}'::jsonb,row_id;
    execute format('update public.%I set memo=''unrelated edit'', notification_timed_preset=''one_hour'' where id=$1',relation) using row_id;
    execute format('select notification_timed_custom from public.%I where id=$1 and notification_enabled=false',relation) into stored using row_id;
    assert stored = '{"mode":"elapsed","value":17,"unit":"minutes"}'::jsonb, 'Round trip or disabled preference lost';
    begin
      execute format('update public.%I set notification_timed_preset=''three_days'' where id=$1',relation) using row_id;
      raise exception 'Legacy preset write bypassed custom override guard';
    exception when check_violation then null; end;
    begin
      execute format('update public.%I set notification_date_custom=$1 where id=$2',relation)
        using '{"mode":"elapsed","value":1,"unit":"minutes"}'::jsonb,row_id;
      raise exception 'Date-only column accepted elapsed preference';
    exception when check_violation then null; end;
    begin
      execute format('update public.%I set notification_timed_custom=''null''::jsonb where id=$1',relation) using row_id;
      raise exception 'JSON null accepted';
    exception when check_violation then null; end;
    -- Expanded range round-trips through both actual table constraints unchanged.
    execute format('update public.%I set notification_timed_custom=$1, notification_date_custom=$2 where id=$3',relation)
      using '{"mode":"elapsed","value":33600,"unit":"hours"}'::jsonb,
            '{"mode":"calendar","value":1400,"hour":9,"minute":0}'::jsonb,row_id;
    execute format('update public.%I set memo=''unrelated edit after 200 weeks'' where id=$1',relation) using row_id;
    execute format('select notification_timed_custom from public.%I where id=$1',relation) into stored using row_id;
    assert stored = '{"mode":"elapsed","value":33600,"unit":"hours"}'::jsonb;
    execute format('select notification_date_custom from public.%I where id=$1',relation) into stored using row_id;
    assert stored = '{"mode":"calendar","value":1400,"hour":9,"minute":0}'::jsonb;
    begin
      execute format('update public.%I set notification_date_custom=$1 where id=$2',relation)
        using '{"mode":"calendar","value":1401,"hour":9,"minute":0}'::jsonb,row_id;
      raise exception 'Out-of-range calendar preference accepted';
    exception when check_violation then null; end;
    begin
      execute format('update public.%I set notification_timed_custom=$1 where id=$2',relation)
        using '{"mode":"elapsed","value":33601,"unit":"hours"}'::jsonb,row_id;
      raise exception 'Out-of-range elapsed preference accepted';
    exception when check_violation then null; end;
    execute format('update public.%I set notification_date_custom=$1 where id=$2',relation)
      using '{"mode":"calendar","value":2,"hour":18,"minute":23}'::jsonb,row_id;
    execute format('update public.%I set notification_timed_preset=''three_days'', notification_timed_custom=null where id=$1',relation) using row_id;
    execute format('select notification_date_custom from public.%I where id=$1 and notification_timed_custom is null',relation) into stored using row_id;
    assert stored = '{"mode":"calendar","value":2,"hour":18,"minute":23}'::jsonb, 'Clearing timed preference lost date preference';
  end loop;
end $$;
rollback;
