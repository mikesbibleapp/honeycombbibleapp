-- Keep Family Cup race scores from going below zero.
-- Bible progress remains untouched; this only changes race-point events.

create or replace function public.record_family_activity(
  p_event_type text,
  p_honey_delta integer default 0,
  p_chapters_delta integer default 0,
  p_source_key text default null,
  p_note text default null
)
returns table(inserted boolean, pot_honey integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid;
  v_week_start date := public.current_family_week_start();
  v_today date := public.family_central_today();
  v_id uuid;
  v_honey integer := greatest(0, coalesce(p_honey_delta, 0));
  v_chapters integer := greatest(0, coalesce(p_chapters_delta, 0));
  v_race_points integer := 0;
  v_age_bracket text := 'adult_18_plus';
  v_age_points integer := 100;
  v_member_count integer := 0;
  v_my_points integer := 0;
  v_min_points integer := 0;
  v_leader_points integer := 0;
  v_gap integer := 0;
  v_catchup_points integer := 0;
  v_pot integer := 0;
begin
  if auth.uid() is null then
    return query select false, 0;
    return;
  end if;

  v_room_id := public.current_family_room_id();
  if v_room_id is null then
    return query select false, 0;
    return;
  end if;

  select coalesce(p.age_bracket, 'adult_18_plus')
    into v_age_bracket
  from public.profiles p
  where p.id = auth.uid();

  v_age_points := case v_age_bracket
    when 'kid_6_8' then 200
    when 'kid_9_11' then 200
    when 'tween_12_13' then 140
    when 'teen_14_17' then 115
    else 100
  end;

  insert into public.family_weekly_pots(room_id, week_start)
  values (v_room_id, v_week_start)
  on conflict on constraint family_weekly_pots_pkey do nothing;

  insert into public.family_daily_races(room_id, race_date)
  values (v_room_id, v_today)
  on conflict on constraint family_daily_races_pkey do nothing;

  insert into public.family_weekly_activity(room_id, week_start, user_id, event_type, honey_delta, chapters_delta, source_key, note)
  values (v_room_id, v_week_start, auth.uid(), left(coalesce(p_event_type, 'activity'), 50), v_honey, v_chapters, p_source_key, left(coalesce(p_note, ''), 180))
  on conflict (room_id, user_id, source_key) where source_key is not null do nothing
  returning id into v_id;

  if v_id is not null then
    v_race_points := case
      when coalesce(p_event_type, '') = 'chapter_read' then (v_chapters * v_age_points) + least(50, v_honey)
      when coalesce(p_event_type, '') = 'double_next_bonus' then 120
      when coalesce(p_event_type, '') = 'comeback_bonus' then 60
      when coalesce(p_event_type, '') = 'sunday_strong' then 150
      else 0
    end;

    if coalesce(p_event_type, '') = 'chapter_read' then
      select
        count(*)::integer,
        coalesce(max(points), 0)::integer,
        coalesce(min(points), 0)::integer,
        coalesce(max(points) filter (where user_id = auth.uid()), 0)::integer
      into v_member_count, v_leader_points, v_min_points, v_my_points
      from (
        select
          m.user_id,
          greatest(0, coalesce(sum(re.points_delta), 0)::integer) as points
        from public.family_room_members m
        left join public.family_race_events re
          on re.room_id = m.room_id
         and re.user_id = m.user_id
         and re.race_date = v_today
        where m.room_id = v_room_id
          and m.active = true
        group by m.user_id
      ) scores;

      v_gap := greatest(0, coalesce(v_leader_points, 0) - coalesce(v_my_points, 0));
      if v_member_count >= 2 and v_gap >= 100 and coalesce(v_my_points, 0) <= coalesce(v_min_points, 0) then
        v_catchup_points := 150;
      elsif v_member_count >= 2 and v_gap >= 300 then
        v_catchup_points := 75;
      end if;

      v_race_points := v_race_points + v_catchup_points;
    end if;

    if v_race_points <> 0 then
      insert into public.family_race_events(room_id, race_date, user_id, actor_id, event_type, points_delta, source_key, note)
      values (
        v_room_id,
        v_today,
        auth.uid(),
        auth.uid(),
        left(coalesce(p_event_type, 'activity'), 50),
        v_race_points,
        case when p_source_key is null then null else 'race:' || p_source_key end,
        left(
          trim(both ' ' from concat(
            coalesce(p_note, ''),
            case when coalesce(p_event_type, '') = 'chapter_read' then ' · age fair +' || v_age_points || ' pts/chapter' else '' end,
            case when v_catchup_points > 0 then ' · last-place boost +' || v_catchup_points else '' end
          )),
          180
        )
      )
      on conflict (room_id, user_id, source_key) where source_key is not null do nothing;
    end if;

    update public.family_weekly_pots fwp
    set pot_honey = fwp.pot_honey + v_honey,
        updated_at = now()
    where fwp.room_id = v_room_id
      and fwp.week_start = v_week_start
    returning fwp.pot_honey into v_pot;
  else
    select fwp.pot_honey into v_pot
    from public.family_weekly_pots fwp
    where fwp.room_id = v_room_id
      and fwp.week_start = v_week_start;
  end if;

  return query select (v_id is not null), coalesce(v_pot, 0);
end;
$$;

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
  v_loser_points integer := 0;
  v_loss_delta integer := 0;
begin
  select * into c
  from public.challenges
  where id = p_challenge_id
  for update;

  if not found then raise exception 'challenge not found'; end if;
  if c.status <> 'awaiting_opp' then raise exception 'challenge not awaiting settlement'; end if;
  if c.challenger_score is null or c.opponent_score is null then raise exception 'both scores required'; end if;
  if auth.uid() <> c.challenger_id and auth.uid() <> c.opponent_id then raise exception 'not a participant'; end if;

  if c.challenger_score > c.opponent_score then
    win := c.challenger_id;
    los := c.opponent_id;
  elsif c.opponent_score > c.challenger_score then
    win := c.opponent_id;
    los := c.challenger_id;
  else
    update public.challenges
      set status = 'settled', winner_id = null, honey_transfer = 0, race_points_delta = 0, settled_at = now()
      where id = p_challenge_id;
    if c.parent_challenge_id is not null then
      update public.challenges set double_or_nothing_used = true where id = c.parent_challenge_id;
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

    select greatest(0, coalesce(sum(points_delta), 0)::integer)
      into v_loser_points
    from public.family_race_events
    where room_id = v_room_id
      and race_date = v_race_date
      and user_id = los;

    v_loss_delta := -least(v_race_delta, greatest(0, coalesce(v_loser_points, 0)));

    insert into public.family_race_events(room_id, race_date, user_id, actor_id, event_type, points_delta, source_key, note)
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

    if v_loss_delta <> 0 then
      insert into public.family_race_events(room_id, race_date, user_id, actor_id, event_type, points_delta, source_key, note)
      values (
        v_room_id,
        v_race_date,
        los,
        win,
        case when c.parent_challenge_id is null then 'race_duel_loss' else 'double_or_nothing_loss' end,
        v_loss_delta,
        'challenge:' || p_challenge_id::text || ':loss',
        case when c.parent_challenge_id is null then 'Race Duel loss' else 'Double-or-Nothing loss' end
      )
      on conflict (room_id, user_id, source_key) where source_key is not null do nothing;
    end if;

    update public.challenges
      set status = 'settled', winner_id = win, honey_transfer = 0, race_points_delta = v_race_delta, settled_at = now()
      where id = p_challenge_id;

    if c.parent_challenge_id is not null then
      update public.challenges set double_or_nothing_used = true where id = c.parent_challenge_id;
    end if;

    return query select win, 0;
    return;
  end if;

  if c.challenger_used_token and los = c.challenger_id then
    update public.challenges
      set status = 'settled', winner_id = win, honey_transfer = 0, settled_at = now()
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
    set state = jsonb_set(coalesce(state, '{}'::jsonb), '{honey}', to_jsonb(greatest(0, los_honey - transfer)), true),
        updated_at = now()
    where user_id = los;

  update public.user_progress
    set state = jsonb_set(coalesce(state, '{}'::jsonb), '{honey}', to_jsonb(win_honey + transfer), true),
        updated_at = now()
    where user_id = win;

  update public.challenges
    set status = 'settled', winner_id = win, honey_transfer = transfer, settled_at = now()
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
    if v_target_points <= v_my_points then
      raise exception 'equalizer only works on someone ahead of you';
    end if;
    v_gap := v_target_points - v_my_points;
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

-- Repair today's Bell Family race debt caused before the no-negative guard.
with current_scores as (
  select
    fr.id as room_id,
    public.family_central_today() as race_date,
    m.user_id,
    coalesce(sum(re.points_delta), 0)::integer as race_points
  from public.family_rooms fr
  join public.family_room_members m
    on m.room_id = fr.id
   and m.active
  left join public.family_race_events re
    on re.room_id = fr.id
   and re.user_id = m.user_id
   and re.race_date = public.family_central_today()
  where fr.invite_code = 'BELL25'
  group by fr.id, m.user_id
)
insert into public.family_race_events(room_id, race_date, user_id, actor_id, event_type, points_delta, source_key, note)
select
  room_id,
  race_date,
  user_id,
  user_id,
  'score_floor_repair',
  -race_points,
  'score-floor-repair:' || race_date::text || ':' || user_id::text,
  'Repair pre-clamp negative Cup score debt'
from current_scores
where race_points < 0
on conflict (room_id, user_id, source_key) where source_key is not null do nothing;

insert into public.family_race_events(room_id, race_date, user_id, actor_id, event_type, points_delta, source_key, note)
select
  fr.id,
  public.family_central_today(),
  p.id,
  p.id,
  'score_floor_repair',
  340,
  'score-floor-repair:2026-05-27:mike-equalizer-debt',
  'Restore post-Equalizer points swallowed by pre-clamp negative score debt'
from public.family_rooms fr
join public.profiles p
  on p.display_name = 'mikebell'
where fr.invite_code = 'BELL25'
  and public.family_central_today() = date '2026-05-27'
on conflict (room_id, user_id, source_key) where source_key is not null do nothing;

grant execute on function public.record_family_activity(text, integer, integer, text, text) to authenticated;
grant execute on function public.settle_challenge(uuid) to authenticated;
grant execute on function public.use_family_race_powerup(uuid, text) to authenticated;
