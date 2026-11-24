begin;
set local plpgsql.check_asserts = on;
insert into auth.users(id) values ('00000000-0000-0000-0000-000000000081');
insert into public.companies(id,user_id,name) values ('00000000-0000-0000-0000-000000000082','00000000-0000-0000-0000-000000000081','Internship test');
do $$
declare row_id uuid; stored text; t text;
begin
  foreach t in array array['briefing','internship','document','aptitude','interview','offer','other'] loop
    insert into public.selection_steps(user_id,company_id,type,custom_title,starts_at,deadline_has_time,notification_enabled)
    values ('00000000-0000-0000-0000-000000000081','00000000-0000-0000-0000-000000000082',t,'Test selection','2030-08-01 09:00Z',false,false)
    returning id into row_id;
    select type into stored from public.selection_steps where id=row_id;
    assert stored=t;
    update public.selection_steps set type='internship',memo='Updated' where id=row_id;
    select type into stored from public.selection_steps where id=row_id;
    assert stored='internship';
    begin
      update public.selection_steps set type='invalid_type' where id=row_id;
      raise exception 'Unknown type accepted';
    exception when check_violation then null;
    end;
  end loop;
end $$;
rollback;
