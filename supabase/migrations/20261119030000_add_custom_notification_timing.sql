-- Custom preferences override the unchanged, old-client-readable preset columns.
-- SQL NULL means use the preset/default. JSON null and malformed shapes are rejected.
create function public.valid_custom_notification_timing(value jsonb, allows_elapsed boolean)
returns boolean language plpgsql immutable set search_path = '' as $$
begin
  if value is null then return true; end if;
  if jsonb_typeof(value) is distinct from 'object'
     or jsonb_typeof(value->'mode') is distinct from 'string'
     or jsonb_typeof(value->'value') is distinct from 'number'
     or (value->>'value') !~ '^[0-9]+$' then return false; end if;
  if value->>'mode' = 'elapsed' then
    return coalesce(allows_elapsed
      and value ?& array['mode', 'value', 'unit']
      and (value - array['mode', 'value', 'unit']) = '{}'::jsonb
      and jsonb_typeof(value->'unit') = 'string'
      and ((value->>'unit' = 'minutes' and (value->>'value')::numeric between 1 and 525600)
        or (value->>'unit' = 'hours' and (value->>'value')::numeric between 1 and 8760)), false);
  elsif value->>'mode' = 'calendar' then
    return coalesce(value ?& array['mode', 'value', 'hour', 'minute']
      and (value - array['mode', 'value', 'hour', 'minute']) = '{}'::jsonb
      and (value->>'value')::numeric between 0 and 365
      and jsonb_typeof(value->'hour') = 'number'
      and jsonb_typeof(value->'minute') = 'number'
      and (value->>'hour') ~ '^[0-9]+$'
      and (value->>'minute') ~ '^[0-9]+$'
      and (value->>'hour')::numeric between 0 and 23
      and (value->>'minute')::numeric between 0 and 59, false);
  end if;
  return false;
exception when invalid_text_representation or numeric_value_out_of_range then
  return false;
end;
$$;

alter table public.selection_steps
  add column notification_timed_custom jsonb
    check (public.valid_custom_notification_timing(notification_timed_custom, true)),
  add column notification_date_custom jsonb
    check (public.valid_custom_notification_timing(notification_date_custom, false));
alter table public.tasks
  add column notification_timed_custom jsonb
    check (public.valid_custom_notification_timing(notification_timed_custom, true)),
  add column notification_date_custom jsonb
    check (public.valid_custom_notification_timing(notification_date_custom, false));

-- Reject legacy preset changes that would silently leave a custom override active.
-- New clients clear the corresponding JSON column explicitly when choosing a preset.
-- Same-value legacy writes cannot be distinguished from unrelated edits: they preserve
-- the custom setting. Old clients cannot display/schedule custom settings; upgrade all
-- active devices before using this feature (their local scheduler still uses presets).
create function public.guard_custom_notification_preset_write()
returns trigger language plpgsql set search_path = '' as $$
begin
  if (new.notification_timed_preset is distinct from old.notification_timed_preset
      and old.notification_timed_custom is not null and new.notification_timed_custom = old.notification_timed_custom)
    or (new.notification_date_preset is distinct from old.notification_date_preset
      and old.notification_date_custom is not null and new.notification_date_custom = old.notification_date_custom) then
    raise exception 'Custom notification timing is active. Upgrade the client or explicitly clear the custom preference.'
      using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger guard_custom_notification_preset_write before update on public.selection_steps
  for each row execute function public.guard_custom_notification_preset_write();
create trigger guard_custom_notification_preset_write before update on public.tasks
  for each row execute function public.guard_custom_notification_preset_write();
