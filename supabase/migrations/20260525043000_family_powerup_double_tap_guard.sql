-- Prevent accidental double taps from spending Honey Trap/Turbo multiple times.
-- The RPC deducts honey and inserts the race event in one transaction, so this
-- trigger error rolls the whole spend back.

create or replace function public.prevent_family_powerup_double_tap()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.event_type in ('turbo', 'honey_slick') and exists (
    select 1
    from public.family_race_events e
    where e.room_id = new.room_id
      and e.race_date = new.race_date
      and e.user_id = new.user_id
      and coalesce(e.actor_id, '00000000-0000-0000-0000-000000000000'::uuid) =
        coalesce(new.actor_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and e.event_type = new.event_type
      and e.created_at > now() - interval '15 seconds'
  ) then
    raise exception 'powerup already fired. Wait a moment before using it again.';
  end if;

  return new;
end;
$$;

drop trigger if exists family_powerup_double_tap_guard on public.family_race_events;

create trigger family_powerup_double_tap_guard
before insert on public.family_race_events
for each row
execute function public.prevent_family_powerup_double_tap();
