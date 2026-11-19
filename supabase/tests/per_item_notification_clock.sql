begin;
insert into auth.users(id) values ('00000000-0000-0000-0000-000000000081');
insert into public.companies(id,user_id,name) values ('00000000-0000-0000-0000-000000000082','00000000-0000-0000-0000-000000000081','Relative notification test');
do $$
declare u text; n integer; v jsonb; relation text; row_id uuid; stored jsonb;
begin
  foreach u in array array['minutes','hours','days','weeks','months'] loop
    foreach n in array array[1,200] loop
      v := jsonb_build_object('mode','relative','unit',u,'value',n,'hour',18,'minute',30);
      assert public.valid_custom_notification_timing(v,true) = (u in ('days','weeks','months'));
      assert public.valid_custom_notification_timing(v,false);
    end loop;
    foreach n in array array[-1,0,201] loop
      v := jsonb_build_object('mode','relative','unit',u,'value',n,'hour',18,'minute',30);
      assert not public.valid_custom_notification_timing(v,true);
      assert not public.valid_custom_notification_timing(v,false);
    end loop;
  end loop;
  assert not public.valid_custom_notification_timing('{"mode":"relative","unit":"years","value":1}',true);
  assert not public.valid_custom_notification_timing('{"mode":"relative","unit":"months","value":1,"hour":9}',true);
  assert not public.valid_custom_notification_timing('{"mode":"elapsed","unit":"months","value":1}',true);
  assert not public.valid_custom_notification_timing('{"mode":"relative","unit":"months","value":1.5}',true);
  foreach n in array array[-1,24,200] loop
    v := jsonb_build_object('mode','relative','unit','days','value',1,'hour',n,'minute',0);
    assert not public.valid_custom_notification_timing(v,false);
  end loop;
  v := jsonb_build_object('mode','relative','unit','days','value',1,'hour',0,'minute',0);
  assert public.valid_custom_notification_timing(v,false);
  v := jsonb_build_object('mode','relative','unit','months','value',200,'hour',23,'minute',59);
  assert public.valid_custom_notification_timing(v,false);
  v := jsonb_build_object('mode','relative','unit','months','value',200,'hour',23,'minute',60);
  assert not public.valid_custom_notification_timing(v,false);
  foreach relation in array array['tasks','selection_steps'] loop
    if relation='tasks' then
      insert into public.tasks(user_id,title,due_at,notification_enabled) values
      ('00000000-0000-0000-0000-000000000081','Month test','2050-03-31 09:00Z',false) returning id into row_id;
    else
      insert into public.selection_steps(user_id,company_id,type,starts_at,deadline_has_time,notification_enabled) values
      ('00000000-0000-0000-0000-000000000081','00000000-0000-0000-0000-000000000082','interview','2050-03-31 09:00Z',false,false) returning id into row_id;
    end if;
    foreach u in array array['minutes','hours','days','weeks','months'] loop
      v := jsonb_build_object('mode','relative','unit',u,'value',200,'hour',18,'minute',30);
      execute format('update public.%I set notification_date_custom=$1 where id=$2',relation) using v,row_id;
      execute format('update public.%I set memo=''Unrelated'' where id=$1',relation) using row_id;
      execute format('select notification_date_custom from public.%I where id=$1',relation) into stored using row_id;
      assert stored=v;
      if u in ('days','weeks','months') then
        execute format('update public.%I set notification_timed_custom=$1 where id=$2',relation) using v,row_id;
        execute format('update public.%I set memo=''Timed clock unchanged'' where id=$1',relation) using row_id;
        execute format('select notification_timed_custom from public.%I where id=$1',relation) into stored using row_id;
        assert stored=v;
      end if;
    end loop;
  end loop;
end $$;
rollback;
