-- Apply after 20261119030000_add_custom_notification_timing.sql, before updated clients.
-- One fixed instant overrides both precision-specific relative preferences.
-- Past values remain valid storage: expiry must not prevent unrelated edits.
alter table public.selection_steps
  add column notification_absolute_at timestamptz
    check (notification_absolute_at is null or isfinite(notification_absolute_at));
alter table public.tasks
  add column notification_absolute_at timestamptz
    check (notification_absolute_at is null or isfinite(notification_absolute_at));

-- Old clients cannot intentionally replace an absolute preference with a preset.
-- Same-value/unrelated writes preserve it; active devices still need upgrading
-- because their local notification schedulers do not understand this column.
create function public.guard_absolute_notification_preset_write()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.notification_absolute_at is not null
     and new.notification_absolute_at is not distinct from old.notification_absolute_at
     and (new.notification_timed_preset is distinct from old.notification_timed_preset
       or new.notification_date_preset is distinct from old.notification_date_preset) then
    raise exception 'Absolute notification timing is active. Upgrade the client or explicitly clear the absolute preference.'
      using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger guard_absolute_notification_preset_write before update on public.selection_steps
  for each row execute function public.guard_absolute_notification_preset_write();
create trigger guard_absolute_notification_preset_write before update on public.tasks
  for each row execute function public.guard_absolute_notification_preset_write();
