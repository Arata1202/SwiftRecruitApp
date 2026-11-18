-- Run after migrations in an isolated test database, never against production.
begin;
insert into auth.users (id) values ('00000000-0000-0000-0000-000000000001');
insert into public.companies (id, user_id, name) values
 ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'Range test');

do $$
declare
  row_id uuid;
  old_version bigint;
  stored_end timestamptz;
begin
  insert into public.selection_steps (user_id, company_id, type, starts_at, starts_has_time, deadline_has_time)
  values ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'interview', '2026-12-31 10:00Z', true, false)
  returning id, version into row_id, old_version;
  assert (select ends_at is null and ends_on is null from public.selection_steps where id = row_id), 'Legacy insert invented an end';

  update public.selection_steps set ends_at = '2027-01-02 00:00Z' where id = row_id and version = old_version;
  assert (select version = old_version + 1 from public.selection_steps where id = row_id), 'Version guard changed';
  update public.selection_steps set memo = 'stale' where id = row_id and version = old_version;
  assert not found, 'Stale write succeeded';
  update public.selection_steps set status = 'completed' where id = row_id;
  select ends_at into stored_end from public.selection_steps where id = row_id;
  assert stored_end = '2027-01-02 00:00Z'::timestamptz, 'Status update lost end';

  begin
    update public.selection_steps set ends_at = '2026-12-31 09:59Z' where id = row_id;
    raise exception 'Accepted timed end before start';
  exception when check_violation then null;
  end;
  begin
    update public.selection_steps set ends_on = '2027-01-02' where id = row_id;
    raise exception 'Accepted mixed end precision';
  exception when check_violation then null;
  end;
  -- Old clients must not silently discard an end they cannot edit.
  begin
    update public.selection_steps set starts_at = '2027-02-01 10:00Z' where id = row_id;
    raise exception 'Accepted incompatible legacy edit';
  exception when check_violation then null;
  end;
  update public.selection_steps set ends_at = starts_at where id = row_id;
  update public.selection_steps set starts_at = '2026-12-31 12:00Z', starts_on = '2026-12-31',
    starts_has_time = false, ends_at = null, ends_on = '2027-01-02' where id = row_id;
  assert (select ends_at is null and ends_on = '2027-01-02' from public.selection_steps where id = row_id), 'Date-only round trip failed';
  begin
    update public.selection_steps set ends_on = '2026-12-30' where id = row_id;
    raise exception 'Accepted date-only end before start';
  exception when check_violation then null;
  end;
  update public.selection_steps set ends_on = starts_on where id = row_id;
  update public.selection_steps set ends_on = null, starts_at = null, starts_on = null,
    deadline_at = '2027-01-03 10:00Z', deadline_has_time = true where id = row_id;
  begin
    update public.selection_steps set ends_at = '2027-01-04 10:00Z' where id = row_id;
    raise exception 'Accepted deadline with end';
  exception when check_violation then null;
  end;
  assert (select deadline_at = '2027-01-03 10:00Z'::timestamptz and ends_at is null and ends_on is null from public.selection_steps where id = row_id), 'Deadline changed';
end;
$$;

insert into public.tasks (user_id, title, notification_enabled)
values ('00000000-0000-0000-0000-000000000001', 'Undated ToDo', false);
rollback;
