begin;
set local plpgsql.check_asserts = on;
set local timezone = 'Pacific/Auckland';
create function public.test_private_function() returns integer language sql as 'select 1';

do $$
declare
  client text;
  relation text;
  uid uuid := gen_random_uuid();
  tid uuid;
begin
  foreach client in array array['anon', 'authenticated'] loop
    assert not has_table_privilege(client, 'public.account_deletion_requests', 'SELECT');
    assert not has_table_privilege(client, 'public.account_deletion_requests', 'INSERT');
    assert not has_table_privilege(client, 'public.account_deletion_requests', 'UPDATE');
    assert not has_table_privilege(client, 'public.account_deletion_requests', 'DELETE');
    assert not has_function_privilege(client, 'public.test_private_function()', 'EXECUTE');
    foreach relation in array array['companies','selection_steps','tasks','company_information_items'] loop
      assert not has_table_privilege(client, 'public.' || relation, 'TRUNCATE');
    end loop;
  end loop;
  insert into auth.users(id) values (uid);
  assert has_table_privilege('service_role', 'public.account_deletion_requests', 'SELECT,INSERT,UPDATE');
  insert into public.account_deletion_requests(user_id) values(uid);
  insert into public.tasks(user_id,title,version) values(uid,'Undated',9223372036854775807) returning id into tid;
  assert (select version = 1 and not notification_enabled and created_at = now() from public.tasks where id = tid);
  update public.tasks set due_at = '2027-01-01 22:00Z' where id = tid;
  assert (select version = 2 and due_on = '2027-01-02' and updated_at = now() from public.tasks where id = tid);
  begin
    update public.tasks set due_on = null where id = tid;
    raise exception 'Accepted missing date';
  exception when check_violation then null;
  end;
  delete from auth.users where id = uid;
  assert not exists (select from public.account_deletion_requests where user_id = uid);
end;
$$;
rollback;
