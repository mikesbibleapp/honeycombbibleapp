-- Family Cup comeback mechanics:
-- - Equalizer Trap affects only race points, never Bible progress.
-- - Race-stakes mini-game challenges move Cup points instead of honey.
-- - Race event feed exposes recent shared race moments.

alter table public.challenges
  add column if not exists prize_mode text not null default 'honey',
  add column if not exists race_points_delta integer not null default 0,
  add column if not exists parent_challenge_id uuid references public.challenges(id) on delete set null,
  add column if not exists double_or_nothing_used boolean not null default false;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'challenges_prize_mode_check'
      and conrelid = 'public.challenges'::regclass
  ) then
    alter table public.challenges
      add constraint challenges_prize_mode_check
      check (prize_mode in ('honey', 'race'));
  end if;
end;
$$;

create unique index if not exists challenges_one_double_or_nothing_per_parent
  on public.challenges(parent_challenge_id)
  where parent_challenge_id is not null;

create or replace function public.settle_challenge(p_challenge_id uuid)
returns table(winner_id uuid, honey_transfer integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.challenges%rowtype;
  win uuid;
  los uuid;
  win_honey integer;
  los_honey integer;
  transfer integer;
  v_room_id uuid;
  v_race_date date := public.family_central_today();
  v_race_delta integer;
begin
  select * into c
  from public.challenges
  where id = p_challenge_id
  for update;

  if not found then
    raise exception 'challenge not found';
  end if;
  if c.status <> 'awaiting_opp' then
    raise exception 'challenge not awaiting settlement';
  end if;
  if c.challenger_score is null or c.opponent_score is null then
    raise exception 'both scores required';
  end if;
  if auth.uid() <> c.challenger_id and auth.uid() <> c.opponent_id then
    raise exception 'not a participant';
  end if;

  if c.challenger_score > c.opponent_score then
    win := c.challenger_id;
    los := c.opponent_id;
  elsif c.opponent_score > c.challenger_score then
    win := c.opponent_id;
    los := c.challenger_id;
  else
    update public.challenges
      set status = 'settled',
          winner_id = null,
          honey_transfer = 0,
          race_points_delta = 0,
          settled_at = now()
      where id = p_challenge_id;

    if c.parent_challenge_id is not null then
      update public.challenges
        set double_or_nothing_used = true
        where id = c.parent_challenge_id;
    end if;

    return query select null::uuid, 0;
    return;
  end if;

  if coalesce(c.prize_mode, 'honey') = 'race' then
    select m1.room_id into v_room_id
    from public.family_room_members m1
    join public.family_room_members m2
      on m2.room_id = m1.room_id
     and m2.user_id = los
     and m2.active
    where m1.user_id = win
      and m1.active
    order by m1.joined_at
    limit 1;

    if v_room_id is null then
      raise exception 'race duels require both players in the same family room';
    end if;

    if exists (
      select 1
      from public.family_daily_races dr
      where dr.room_id = v_room_id
        and dr.race_date = v_race_date
        and dr.status = 'settled'
    ) then
      raise exception 'today''s Family Cup race already settled';
    end if;

    insert into public.family_daily_races(room_id, race_date)
    values (v_room_id, v_race_date)
    on conflict on constraint family_daily_races_pkey do nothing;

    v_race_delta := greatest(
      1,
      coalesce(
        nullif(c.race_points_delta, 0),
        greatest(0, c.wager) * 3 * case when c.parent_challenge_id is not null then 2 else 1 end
      )
    );

    insert into public.family_race_events(
      room_id,
      race_date,
      user_id,
      actor_id,
      event_type,
      points_delta,
      source_key,
      note
    )
    values (
      v_room_id,
      v_race_date,
      win,
      win,
      case when c.parent_challenge_id is null then 'race_duel_win' else 'double_or_nothing_win' end,
      v_race_delta,
      'challenge:' || p_challenge_id::text || ':win',
      case when c.parent_challenge_id is null then 'Race Duel win' else 'Double-or-Nothing win' end
    )
    on conflict (room_id, user_id, source_key) where source_key is not null do nothing;

    insert into public.family_race_events(
      room_id,
      race_date,
      user_id,
      actor_id,
      event_type,
      points_delta,
      source_key,
      note
    )
    values (
      v_room_id,
      v_race_date,
      los,
      win,
      case when c.parent_challenge_id is null then 'race_duel_loss' else 'double_or_nothing_loss' end,
      -v_race_delta,
      'challenge:' || p_challenge_id::text || ':loss',
      case when c.parent_challenge_id is null then 'Race Duel loss' else 'Double-or-Nothing loss' end
    )
    on conflict (room_id, user_id, source_key) where source_key is not null do nothing;

    update public.challenges
      set status = 'settled',
          winner_id = win,
          honey_transfer = 0,
          race_points_delta = v_race_delta,
          settled_at = now()
      where id = p_challenge_id;

    if c.parent_challenge_id is not null then
      update public.challenges
        set double_or_nothing_used = true
        where id = c.parent_challenge_id;
    end if;

    return query select win, 0;
    return;
  end if;

  -- Honey mode keeps the original wager behavior.
  if c.challenger_used_token and los = c.challenger_id then
    update public.challenges
      set status = 'settled',
          winner_id = win,
          honey_transfer = 0,
          settled_at = now()
      where id = p_challenge_id;
    return query select win, 0;
    return;
  end if;

  select coalesce((up.state->>'honey')::integer, 0) into los_honey
  from public.user_progress up
  where user_id = los
  for update;

  select coalesce((up.state->>'honey')::integer, 0) into win_honey
  from public.user_progress up
  where user_id = win
  for update;

  transfer := least(c.wager, greatest(0, los_honey));

  update public.user_progress
    set state = jsonb_set(
          coalesce(state, '{}'::jsonb),
          '{honey}',
          to_jsonb(greatest(0, los_honey - transfer)),
          true
        ),
        updated_at = now()
    where user_id = los;

  update public.user_progress
    set state = jsonb_set(
          coalesce(state, '{}'::jsonb),
          '{honey}',
          to_jsonb(win_honey + transfer),
          true
        ),
        updated_at = now()
    where user_id = win;

  update public.challenges
    set status = 'settled',
        winner_id = win,
        honey_transfer = transfer,
        settled_at = now()
    where id = p_challenge_id;

  return query select win, transfer;
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

  select coalesce(sum(points_delta), 0)::integer into v_my_points
  from public.family_race_events
  where room_id = v_room_id
    and race_date = v_race_date
    and user_id = auth.uid();

  select coalesce(sum(points_delta), 0)::integer into v_target_points
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
    v_cost := 75;
    v_delta := -150;
  elsif v_powerup = 'mega_honey_trap' then
    if v_target_id = auth.uid() then
      raise exception 'pick someone ahead of you';
    end if;
    if v_target_points <= v_my_points then
      raise exception 'equalizer only works on someone ahead of you';
    end if;
    v_delta := -(v_target_points - v_my_points);
    v_cost := greatest(500, 300 + ceil((v_target_points - v_my_points)::numeric / 2.0)::integer);
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
    set state = jsonb_set(
          coalesce(state, '{}'::jsonb),
          '{honey}',
          to_jsonb(v_honey - v_cost),
          true
        ),
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
      when v_powerup = 'mega_honey_trap' then 'Equalizer Trap'
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

  select coalesce(sum(points_delta), 0)::integer into v_my_points
  from public.family_race_events
  where room_id = v_room_id
    and race_date = v_race_date
    and user_id = auth.uid();

  select coalesce(sum(points_delta), 0)::integer into v_target_points
  from public.family_race_events
  where room_id = v_room_id
    and race_date = v_race_date
    and user_id = v_target_id;

  return query select v_honey - v_cost, v_my_points, v_target_points;
end;
$$;

create or replace function public.family_race_feed()
returns table(
  id uuid,
  event_type text,
  points_delta integer,
  actor_id uuid,
  actor_name text,
  target_id uuid,
  target_name text,
  note text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid;
  v_race_date date := public.family_central_today();
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;

  v_room_id := public.current_family_room_id();
  if v_room_id is null then
    raise exception 'join a family room first';
  end if;

  return query
  with race_events as (
    select
      re.id,
      re.event_type,
      re.points_delta,
      re.actor_id,
      coalesce(actor_profile.display_name, 'Reader') as actor_name,
      re.user_id as target_id,
      coalesce(target_profile.display_name, 'Reader') as target_name,
      re.note,
      re.created_at
    from public.family_race_events re
    left join public.profiles actor_profile
      on actor_profile.id = re.actor_id
    left join public.profiles target_profile
      on target_profile.id = re.user_id
    where re.room_id = v_room_id
      and re.race_date = v_race_date
  ),
  rematch_requests as (
    select
      c.id,
      'double_or_nothing_request'::text as event_type,
      coalesce(nullif(c.race_points_delta, 0), greatest(0, c.wager) * 6)::integer as points_delta,
      c.challenger_id as actor_id,
      c.challenger_name as actor_name,
      c.opponent_id as target_id,
      c.opponent_name as target_name,
      'Double-or-Nothing requested'::text as note,
      c.created_at
    from public.challenges c
    join public.family_room_members cm
      on cm.room_id = v_room_id
     and cm.user_id = c.challenger_id
     and cm.active
    join public.family_room_members om
      on om.room_id = v_room_id
     and om.user_id = c.opponent_id
     and om.active
    where c.prize_mode = 'race'
      and c.parent_challenge_id is not null
      and c.status = 'awaiting_opp'
      and c.created_at >= (now() - interval '1 day')
  )
  select * from race_events
  union all
  select * from rematch_requests
  order by created_at desc
  limit 30;
end;
$$;

grant execute on function public.settle_challenge(uuid) to authenticated;
grant execute on function public.use_family_race_powerup(uuid, text) to authenticated;
grant execute on function public.family_race_feed() to authenticated;
