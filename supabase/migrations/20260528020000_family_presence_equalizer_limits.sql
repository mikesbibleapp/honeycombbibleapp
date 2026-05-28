-- Family presence + safer Equalizer limits
-- Additive: does not change Bible progress, chapters, streaks, or existing race points.

create or replace function public.family_room_presence()
returns table(
  user_id uuid,
  display_name text,
  last_seen_at timestamptz,
  today_chapters integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid := public.current_family_room_id();
  v_week_start date := public.current_family_week_start();
  v_race_date date := public.family_central_today();
begin
  if auth.uid() is null or v_room_id is null then
    return;
  end if;

  return query
  select
    m.user_id,
    coalesce(p.display_name, 'Reader') as display_name,
    m.last_seen_at,
    coalesce(sum(a.chapters_delta) filter (
      where a.event_type = 'chapter_read'
        and (a.created_at at time zone 'America/Chicago')::date = v_race_date
    ), 0)::integer as today_chapters
  from public.family_room_members m
  left join public.profiles p on p.id = m.user_id
  left join public.family_weekly_activity a
    on a.room_id = m.room_id
   and a.user_id = m.user_id
   and a.week_start = v_week_start
  where m.room_id = v_room_id
    and m.active
    and exists (
      select 1
      from public.family_room_members mine
      where mine.room_id = m.room_id
        and mine.user_id = auth.uid()
        and mine.active
    )
  group by m.user_id, p.display_name, m.last_seen_at
  order by coalesce(m.last_seen_at, 'epoch'::timestamptz) desc, coalesce(p.display_name, 'Reader') asc;
end;
$$;

create or replace function public.use_family_race_powerup(
  p_target_id uuid default null,
  p_powerup text default 'honey_slick'
)
returns table(remaining_honey integer, my_race_points integer, target_race_points integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid;
  v_week_start date := public.current_family_week_start();
  v_race_date date := public.family_central_today();
  v_target_id uuid := coalesce(p_target_id, auth.uid());
  v_powerup text := lower(coalesce(p_powerup, 'honey_slick'));
  v_cost integer;
  v_delta integer;
  v_honey integer;
  v_my_points integer := 0;
  v_target_points integer := 0;
  v_floor_points integer := 0;
  v_gap integer := 0;
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;

  v_room_id := public.current_family_room_id();
  if v_room_id is null then
    raise exception 'join a family room first';
  end if;

  if not exists (
    select 1
    from public.family_room_members
    where room_id = v_room_id
      and user_id = v_target_id
      and active
  ) then
    raise exception 'target is not in your family room';
  end if;

  insert into public.family_daily_races(room_id, race_date)
  values (v_room_id, v_race_date)
  on conflict on constraint family_daily_races_pkey do nothing;

  select greatest(0, coalesce(sum(points_delta), 0)::integer) into v_my_points
  from public.family_race_events
  where room_id = v_room_id
    and race_date = v_race_date
    and user_id = auth.uid();

  select greatest(0, coalesce(sum(points_delta), 0)::integer) into v_target_points
  from public.family_race_events
  where room_id = v_room_id
    and race_date = v_race_date
    and user_id = v_target_id;

  if v_powerup = 'turbo' then
    v_target_id := auth.uid();
    v_cost := 125;
    v_delta := 180;
    v_target_points := v_my_points;
  elsif v_powerup = 'honey_slick' then
    if v_target_id = auth.uid() then
      raise exception 'pick someone else to slow down';
    end if;
    if v_target_points <= 0 then
      raise exception 'that racer is already at zero';
    end if;
    v_cost := 75;
    v_delta := -least(150, v_target_points);
  elsif v_powerup = 'mega_honey_trap' then
    if v_target_id = auth.uid() then
      raise exception 'pick someone ahead of you';
    end if;
    if exists (
      select 1
      from public.family_race_events
      where room_id = v_room_id
        and race_date = v_race_date
        and actor_id = auth.uid()
        and event_type = 'mega_honey_trap'
    ) then
      raise exception 'equalizer can only be used once per day';
    end if;
    if exists (
      select 1
      from public.family_race_events
      where room_id = v_room_id
        and race_date = v_race_date
        and user_id = v_target_id
        and event_type = 'mega_honey_trap'
    ) then
      raise exception 'that racer has already been equalized today';
    end if;
    if v_target_points <= v_my_points then
      raise exception 'equalizer only works on someone ahead of you';
    end if;

    select coalesce(max(points), 0)::integer into v_floor_points
    from (
      select
        m.user_id,
        greatest(0, coalesce(sum(re.points_delta), 0)::integer) as points
      from public.family_room_members m
      left join public.family_race_events re
        on re.room_id = m.room_id
       and re.user_id = m.user_id
       and re.race_date = v_race_date
      where m.room_id = v_room_id
        and m.active = true
        and m.user_id <> v_target_id
      group by m.user_id
    ) scores
    where scores.points < v_target_points;

    v_gap := v_target_points - greatest(0, coalesce(v_floor_points, 0));
    if v_gap <= 0 then
      raise exception 'equalizer cannot move that racer right now';
    end if;
    v_delta := -v_gap;
    v_cost := greatest(500, 300 + ceil(v_gap::numeric / 2.0)::integer);
  else
    raise exception 'unknown powerup';
  end if;

  select coalesce((state->>'honey')::integer, 0) into v_honey
  from public.user_progress
  where user_id = auth.uid()
  for update;

  if coalesce(v_honey, 0) < v_cost then
    raise exception 'not enough honey for that powerup';
  end if;

  update public.user_progress
    set state = jsonb_set(coalesce(state, '{}'::jsonb), '{honey}', to_jsonb(v_honey - v_cost), true),
        updated_at = now()
    where user_id = auth.uid();

  insert into public.family_weekly_pots(room_id, week_start)
  values (v_room_id, v_week_start)
  on conflict on constraint family_weekly_pots_pkey do nothing;

  insert into public.family_race_events(room_id, race_date, user_id, actor_id, event_type, points_delta, note)
  values (
    v_room_id,
    v_race_date,
    v_target_id,
    auth.uid(),
    v_powerup,
    v_delta,
    case
      when v_powerup = 'turbo' then 'Turbo boost'
      when v_powerup = 'mega_honey_trap' then 'Equalizer Trap to next place'
      else 'Honey Trap setback'
    end
  );

  insert into public.family_weekly_activity(room_id, week_start, user_id, event_type, honey_delta, chapters_delta, note)
  values (v_room_id, v_week_start, auth.uid(), 'powerup_spend', v_cost, 0, 'Race powerup fed the family pot');

  update public.family_weekly_pots fwp
    set pot_honey = fwp.pot_honey + v_cost,
        updated_at = now()
    where fwp.room_id = v_room_id
      and fwp.week_start = v_week_start;

  select greatest(0, coalesce(sum(points_delta), 0)::integer) into v_my_points
  from public.family_race_events
  where room_id = v_room_id
    and race_date = v_race_date
    and user_id = auth.uid();

  select greatest(0, coalesce(sum(points_delta), 0)::integer) into v_target_points
  from public.family_race_events
  where room_id = v_room_id
    and race_date = v_race_date
    and user_id = v_target_id;

  return query select v_honey - v_cost, v_my_points, v_target_points;
end;
$$;

grant execute on function public.family_room_presence() to authenticated;
grant execute on function public.use_family_race_powerup(uuid, text) to authenticated;
