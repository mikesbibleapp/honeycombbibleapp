-- Family Cup daily race server-side closeout.
-- Keeps the client fallback, but also lets pg_cron award the daily jackpot
-- automatically after 9 PM Central without anyone pressing a button.

create or replace function public._settle_family_daily_race_for_room(
  p_room_id uuid,
  p_race_date date default public.family_central_today(),
  p_skip_empty boolean default false
)
returns table(winner_id uuid, winner_name text, payout_honey integer, winning_points integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_week_start date := public.current_family_week_start();
  v_race public.family_daily_races%rowtype;
  v_winner_honey integer := 0;
  v_winner_name text := 'Reader';
  v_winner_id uuid;
  v_points integer := 0;
begin
  if p_room_id is null then
    raise exception 'room_id required';
  end if;

  -- Deadline guard: only settle the current Central date after 9 PM Central.
  if p_race_date >= public.family_central_today()
     and extract(hour from (now() at time zone 'America/Chicago')) < 21 then
    raise exception 'Daily race not yet closed (settles after 9 PM Central)';
  end if;

  insert into public.family_daily_races(room_id, race_date)
  values (p_room_id, p_race_date)
  on conflict on constraint family_daily_races_pkey do nothing;

  select * into v_race
  from public.family_daily_races
  where room_id = p_room_id
    and race_date = p_race_date
  for update;

  if v_race.status = 'settled' then
    select
      coalesce(p.display_name, 'Reader'),
      coalesce(sum(re.points_delta), 0)::integer
    into v_winner_name, v_points
    from public.profiles p
    left join public.family_race_events re
      on re.user_id = p.id
     and re.room_id = p_room_id
     and re.race_date = p_race_date
    where p.id = v_race.winner_id
    group by p.display_name;

    return query select
      v_race.winner_id,
      v_winner_name,
      v_race.jackpot_honey,
      greatest(0, coalesce(v_points, 0));
    return;
  end if;

  with scores as (
    select
      m.user_id,
      coalesce(p.display_name, 'Reader') as display_name,
      greatest(0, coalesce(sum(re.points_delta), 0)::integer) as race_points
    from public.family_room_members m
    left join public.profiles p
      on p.id = m.user_id
    left join public.family_race_events re
      on re.room_id = m.room_id
     and re.user_id = m.user_id
     and re.race_date = p_race_date
    where m.room_id = p_room_id
      and m.active
    group by m.user_id, p.display_name
    order by race_points desc, display_name asc
    limit 1
  )
  select user_id, display_name, race_points
    into v_winner_id, v_winner_name, v_points
  from scores;

  if v_winner_id is null or coalesce(v_points, 0) <= 0 then
    if p_skip_empty then
      return;
    end if;
    raise exception 'no race points yet today';
  end if;

  select coalesce((state->>'honey')::integer, 0) into v_winner_honey
  from public.user_progress
  where user_id = v_winner_id
  for update;

  update public.user_progress
  set state = jsonb_set(
        coalesce(state, '{}'::jsonb),
        '{honey}',
        to_jsonb(coalesce(v_winner_honey, 0) + v_race.jackpot_honey),
        true
      ),
      updated_at = now()
  where user_id = v_winner_id;

  update public.family_daily_races
  set status = 'settled',
      winner_id = v_winner_id,
      settled_at = now(),
      updated_at = now()
  where room_id = p_room_id
    and race_date = p_race_date;

  insert into public.family_weekly_activity(
    room_id,
    week_start,
    user_id,
    event_type,
    honey_delta,
    chapters_delta,
    source_key,
    note
  )
  values (
    p_room_id,
    v_week_start,
    v_winner_id,
    'daily_race_win',
    v_race.jackpot_honey,
    0,
    'daily-race-win:' || p_race_date::text,
    'Daily family race jackpot'
  )
  on conflict (room_id, user_id, source_key) where source_key is not null do nothing;

  return query select
    v_winner_id,
    v_winner_name,
    v_race.jackpot_honey,
    greatest(0, coalesce(v_points, 0));
end;
$$;

create or replace function public.settle_family_daily_race()
returns table(winner_id uuid, winner_name text, payout_honey integer, winning_points integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid;
  v_race_date date := public.family_central_today();
  r record;
begin
  -- No auth context (pg_cron) settles every room. Empty rooms are skipped.
  if auth.uid() is null then
    if extract(hour from (now() at time zone 'America/Chicago')) < 21 then
      return;
    end if;

    for r in
      select id
      from public.family_rooms
      order by created_at
    loop
      return query
        select *
        from public._settle_family_daily_race_for_room(r.id, v_race_date, true);
    end loop;
    return;
  end if;

  v_room_id := public.current_family_room_id();
  if v_room_id is null then
    raise exception 'join a family room first';
  end if;

  return query
    select *
    from public._settle_family_daily_race_for_room(v_room_id, v_race_date, false);
end;
$$;

grant execute on function public.settle_family_daily_race() to authenticated;

-- Run every 10 minutes from 2-4 AM UTC. The function itself guards Central
-- time, so this settles shortly after 9 PM during both daylight and standard
-- time, and repeated runs are idempotent.
do $$
begin
  begin
    perform cron.schedule(
      'settle-family-daily-race-after-9pm-central',
      '*/10 2-4 * * *',
      $cron$select public.settle_family_daily_race();$cron$
    );
  exception
    when undefined_function then null;
    when invalid_schema_name then null;
    when undefined_table then null;
  end;
end $$;
