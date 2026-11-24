-- Exercise the released migration against partially populated legacy rows.
begin;
set local plpgsql.check_asserts = on;
insert into auth.users(id) values ('00000000-0000-0000-0000-000000000066');
insert into public.companies(id,user_id,name) values
 ('00000000-0000-0000-0000-000000000067','00000000-0000-0000-0000-000000000066','Test');
insert into public.tasks(user_id,title,notification_timed_preset,notification_date_preset,notification_enabled)
values ('00000000-0000-0000-0000-000000000066','timed','ten_minutes',null,false),
       ('00000000-0000-0000-0000-000000000066','date',null,'three_days',false);
insert into public.selection_steps(user_id,company_id,type,starts_at,starts_has_time,deadline_has_time,
 notification_timed_preset,notification_date_preset,notification_enabled)
select id,'00000000-0000-0000-0000-000000000067','interview',now(),true,false,t,d,false
from auth.users cross join (values ('ten_minutes',null),(null,'three_days')) prefs(t,d)
where id = '00000000-0000-0000-0000-000000000066';

\ir ../migrations/20261119020000_normalize_notification_timing_defaults.sql

do $$
declare owner_id uuid := '00000000-0000-0000-0000-000000000066';
begin
  assert (select count(distinct (notification_timed_preset, notification_date_preset)) = 2 from public.tasks where user_id = owner_id and not notification_enabled
    and (notification_timed_preset, notification_date_preset) in (('ten_minutes','same_day'),('at_time','three_days')));
  assert (select count(distinct (notification_timed_preset, notification_date_preset)) = 2 from public.selection_steps where user_id = owner_id and not notification_enabled
    and (notification_timed_preset, notification_date_preset) in (('ten_minutes','same_day'),('one_hour','three_days')));
end $$;
rollback;
