-- Support 200 weeks in the existing elapsed/calendar wire format.
-- Only widen numeric validation; existing values, columns and write guards stay intact.
create or replace function public.valid_custom_notification_timing(value jsonb, allows_elapsed boolean)
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
      and ((value->>'unit' = 'minutes' and (value->>'value')::numeric between 1 and 2016000)
        or (value->>'unit' = 'hours' and (value->>'value')::numeric between 1 and 33600)), false);
  elsif value->>'mode' = 'calendar' then
    return coalesce(value ?& array['mode', 'value', 'hour', 'minute']
      and (value - array['mode', 'value', 'hour', 'minute']) = '{}'::jsonb
      and (value->>'value')::numeric between 0 and 1400
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

