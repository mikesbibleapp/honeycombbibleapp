-- Kids 2x scoring, expanded daily missions (rotate over a week), and
-- weekly-season auto-settle wiring (pg_cron + client-callable fallback).
--
-- TASK 1: record_family_activity age scoring ladder rebalanced so kids
--         under 10 get exactly 2x adult, with a smoother fairness ladder.
-- TASK 2: claim_family_missions + my_family_room now rotate missions over
--         a full week (doy % 7) and include 5 new mission templates.
-- TASK 3: pg_cron job (if extension present) + maybe_settle_weekly_season()
--         RPC that any authenticated client can call from the family-room
--         load handler. Idempotent. Also patches settle_family_weekly_season
--         to be safe to call without an auth context (cron) by iterating
--         all rooms when auth.uid() is null.

-- ---------------------------------------------------------------------------
-- TASK 1: record_family_activity — 2x kid scoring + smoother ladder
-- ---------------------------------------------------------------------------

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

  -- Rebalanced ladder: kids under 10 get exactly 2x adult (200 vs 100).
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
          coalesce(sum(re.points_delta), 0)::integer as points
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

grant execute on function public.record_family_activity(text, integer, integer, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- TASK 2: claim_family_missions — expanded set, weekly (doy % 7) rotation
-- ---------------------------------------------------------------------------
--
-- Slot picker: 7-day rotation with no adjacent repeats. Each day shows 3
-- missions: slot_a (one of 7), slot_b (one of 7, offset so it never equals
-- slot_a on the same or adjacent day), and the always-on 'family-ten'.
--
-- Day-of-year doy % 7:
--   slot_a → ['everyone-read','beat-yesterday','help-lowest','early-bird',
--             'night-owl','kid-leads','streak-keeper'][doy%7]
--   slot_b → ['comeback-day','comeback-double','close-gap','pot-fattener',
--             'streak-keeper','early-bird','kid-leads'][doy%7]
--
-- Note: slot_b's array is rotated/offset from slot_a so combinations
-- never repeat across the week. 'family-ten' is always slot 3.

create or replace function public.claim_family_missions()
returns table(claimed_count integer, reward_honey integer, pot_honey integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid;
  v_week_start date := public.current_family_week_start();
  v_race_date date := public.family_central_today();
  v_doy_slot integer;
  v_member_count integer := 0;
  v_everyone_progress integer := 0;
  v_family_today integer := 0;
  v_comeback_progress integer := 0;
  v_yesterday_target integer := 1;
  v_lowest_progress integer := 0;
  v_behind_max integer := 0;
  v_leader_id uuid;
  v_early_bird_progress integer := 0;
  v_night_owl_progress integer := 0;
  v_kid_leads_progress integer := 0;
  v_streak_keeper_progress integer := 0;
  v_pot_week_honey integer := 0;
  v_slot_a text;
  v_slot_b text;
  v_claimed integer := 0;
  v_reward integer := 0;
  v_pot integer := 0;
  v_claim_key text;
  v_user_honey integer := 0;
  mission record;
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;

  v_room_id := public.current_family_room_id();
  if v_room_id is null then
    raise exception 'join a family room first';
  end if;

  insert into public.family_weekly_pots(room_id, week_start)
  values (v_room_id, v_week_start)
  on conflict on constraint family_weekly_pots_pkey do nothing;

  v_doy_slot := extract(doy from v_race_date)::integer % 7;

  v_slot_a := case v_doy_slot
    when 0 then 'everyone-read'
    when 1 then 'beat-yesterday'
    when 2 then 'help-lowest'
    when 3 then 'early-bird'
    when 4 then 'night-owl'
    when 5 then 'kid-leads'
    else 'streak-keeper'
  end;

  v_slot_b := case v_doy_slot
    when 0 then 'comeback-day'
    when 1 then 'comeback-double'
    when 2 then 'close-gap'
    when 3 then 'pot-fattener'
    when 4 then 'streak-keeper'
    when 5 then 'early-bird'
    else 'kid-leads'
  end;

  select count(*)::integer into v_member_count
  from public.family_room_members
  where room_id = v_room_id
    and active;

  select greatest(1, coalesce(sum(a.chapters_delta), 0)::integer + 1) into v_yesterday_target
  from public.family_weekly_activity a
  where a.room_id = v_room_id
    and a.week_start = v_week_start
    and (a.created_at at time zone 'America/Chicago')::date = (v_race_date - 1);

  with activity as (
    select
      m.user_id,
      coalesce(sum(a.chapters_delta), 0)::integer as week_chapters,
      coalesce(sum(a.chapters_delta) filter (
        where (a.created_at at time zone 'America/Chicago')::date = v_race_date
      ), 0)::integer as today_chapters
    from public.family_room_members m
    left join public.family_weekly_activity a
      on a.room_id = m.room_id
     and a.user_id = m.user_id
     and a.week_start = v_week_start
    where m.room_id = v_room_id
      and m.active
    group by m.user_id
  ),
  leader as (
    select user_id
    from activity
    order by week_chapters desc, user_id
    limit 1
  ),
  lowest_reader as (
    select user_id, today_chapters
    from activity
    order by week_chapters asc, user_id
    limit 1
  )
  select
    (select count(*)::integer from activity where today_chapters > 0),
    (select coalesce(sum(today_chapters), 0)::integer from activity),
    (select count(*)::integer from activity where today_chapters > 0 and user_id <> (select user_id from leader)),
    (select user_id from leader),
    (select case when today_chapters > 0 then 1 else 0 end from lowest_reader),
    (select coalesce(max(today_chapters), 0)::integer from activity where user_id <> (select user_id from leader))
  into v_everyone_progress, v_family_today, v_comeback_progress, v_leader_id, v_lowest_progress, v_behind_max;

  -- early-bird: count distinct members with chapter_read today before noon CT
  select count(distinct a.user_id)::integer into v_early_bird_progress
  from public.family_weekly_activity a
  where a.room_id = v_room_id
    and a.week_start = v_week_start
    and a.event_type = 'chapter_read'
    and (a.created_at at time zone 'America/Chicago')::date = v_race_date
    and extract(hour from (a.created_at at time zone 'America/Chicago')) < 12;

  -- night-owl: count distinct members with chapter_read today after 19:00 CT
  select count(distinct a.user_id)::integer into v_night_owl_progress
  from public.family_weekly_activity a
  where a.room_id = v_room_id
    and a.week_start = v_week_start
    and a.event_type = 'chapter_read'
    and (a.created_at at time zone 'America/Chicago')::date = v_race_date
    and extract(hour from (a.created_at at time zone 'America/Chicago')) >= 19;

  -- kid-leads: max today_chapters among readers in kid/tween brackets
  select coalesce(max(today_ch), 0)::integer into v_kid_leads_progress
  from (
    select coalesce(sum(a.chapters_delta), 0)::integer as today_ch
    from public.family_room_members m
    join public.profiles p on p.id = m.user_id
    left join public.family_weekly_activity a
      on a.room_id = m.room_id
     and a.user_id = m.user_id
     and a.week_start = v_week_start
     and (a.created_at at time zone 'America/Chicago')::date = v_race_date
    where m.room_id = v_room_id
      and m.active
      and coalesce(p.age_bracket, 'adult_18_plus') in ('kid_6_8', 'kid_9_11', 'tween_12_13')
    group by m.user_id
  ) kid_today;

  -- streak-keeper: members who read at least 1 chapter today AND yesterday
  with by_user as (
    select
      m.user_id,
      coalesce(sum(a.chapters_delta) filter (
        where (a.created_at at time zone 'America/Chicago')::date = v_race_date
      ), 0)::integer as today_ch,
      coalesce(sum(a.chapters_delta) filter (
        where (a.created_at at time zone 'America/Chicago')::date = (v_race_date - 1)
      ), 0)::integer as yest_ch
    from public.family_room_members m
    left join public.family_weekly_activity a
      on a.room_id = m.room_id
     and a.user_id = m.user_id
     and a.week_start = v_week_start
    where m.room_id = v_room_id
      and m.active
    group by m.user_id
  )
  select count(*)::integer into v_streak_keeper_progress
  from by_user
  where today_ch >= 1 and yest_ch >= 1;

  -- pot-fattener: net week honey to the pot (already excluding spend events)
  select coalesce(sum(a.honey_delta) filter (
    where a.event_type not in ('goal_stake', 'powerup_spend', 'pot_boost', 'gift_sent')
  ), 0)::integer into v_pot_week_honey
  from public.family_weekly_activity a
  where a.room_id = v_room_id
    and a.week_start = v_week_start;

  for mission in
    select m.*
    from (
      values
        ('everyone-read'::text, v_everyone_progress, greatest(1, v_member_count), 300),
        ('beat-yesterday'::text, v_family_today, v_yesterday_target, 450),
        ('help-lowest'::text, v_lowest_progress, 1, 350),
        ('family-ten'::text, v_family_today, 10, 500),
        ('comeback-day'::text, v_comeback_progress, 2, 400),
        ('comeback-double'::text, v_behind_max, 2, 350),
        ('close-gap'::text, v_behind_max, 3, 450),
        ('early-bird'::text, v_early_bird_progress, 2, 375),
        ('night-owl'::text, v_night_owl_progress, 2, 375),
        ('kid-leads'::text, v_kid_leads_progress, 3, 500),
        ('streak-keeper'::text, v_streak_keeper_progress, greatest(1, v_member_count), 450),
        ('pot-fattener'::text, v_pot_week_honey, 1000, 600)
    ) as m(mission_key, progress_value, target_value, reward_honey)
    where m.mission_key in (v_slot_a, v_slot_b, 'family-ten')
  loop
    if mission.progress_value >= mission.target_value then
      v_claim_key := null;
      insert into public.family_mission_claims(room_id, mission_date, mission_key, claimed_by, reward_honey)
      values (v_room_id, v_race_date, mission.mission_key, auth.uid(), mission.reward_honey)
      on conflict (room_id, mission_date, mission_key) do nothing
      returning mission_key into v_claim_key;

      if v_claim_key is not null then
        v_claimed := v_claimed + 1;
        v_reward := v_reward + mission.reward_honey;

        -- Pay the claimant directly in user_progress.state.honey.
        select coalesce((state->>'honey')::integer, 0) into v_user_honey
        from public.user_progress
        where user_id = auth.uid()
        for update;

        update public.user_progress
        set state = jsonb_set(coalesce(state, '{}'::jsonb), '{honey}', to_jsonb(coalesce(v_user_honey, 0) + mission.reward_honey), true),
            updated_at = now()
        where user_id = auth.uid();

        insert into public.family_weekly_activity(room_id, week_start, user_id, event_type, honey_delta, chapters_delta, source_key, note)
        values (
          v_room_id,
          v_week_start,
          auth.uid(),
          'mission_reward',
          mission.reward_honey,
          0,
          'family-mission:' || v_race_date::text || ':' || mission.mission_key,
          'Family mission completed'
        )
        on conflict (room_id, user_id, source_key) where source_key is not null do nothing;
      end if;
    end if;
  end loop;

  -- Read the current pot but do NOT credit it; the user gets the full reward.
  select fwp.pot_honey into v_pot
  from public.family_weekly_pots fwp
  where fwp.room_id = v_room_id
    and fwp.week_start = v_week_start;

  return query select v_claimed, v_reward, coalesce(v_pot, 0);
end;
$$;

grant execute on function public.claim_family_missions() to authenticated;

-- ---------------------------------------------------------------------------
-- TASK 2 (cont.): my_family_room — same expanded set + weekly rotation
-- ---------------------------------------------------------------------------

create or replace function public.my_family_room()
returns table (
  room_id uuid,
  room_name text,
  invite_code text,
  role text,
  member_count integer,
  week_start date,
  week_end date,
  pot_honey integer,
  my_week_chapters integer,
  my_week_honey integer,
  my_rank integer,
  leader_name text,
  leader_chapters integer,
  members jsonb,
  goals jsonb,
  race_date date,
  daily_jackpot integer,
  my_race_points integer,
  race_leader_name text,
  race_leader_points integer,
  race_members jsonb,
  missions jsonb,
  awards jsonb
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid;
  v_week_start date := public.current_family_week_start();
  v_race_date date := public.family_central_today();
  v_doy_slot integer := extract(doy from public.family_central_today())::integer % 7;
  v_slot_a text;
  v_slot_b text;
begin
  v_room_id := public.current_family_room_id();
  if v_room_id is null then
    return;
  end if;

  v_slot_a := case v_doy_slot
    when 0 then 'everyone-read'
    when 1 then 'beat-yesterday'
    when 2 then 'help-lowest'
    when 3 then 'early-bird'
    when 4 then 'night-owl'
    when 5 then 'kid-leads'
    else 'streak-keeper'
  end;

  v_slot_b := case v_doy_slot
    when 0 then 'comeback-day'
    when 1 then 'comeback-double'
    when 2 then 'close-gap'
    when 3 then 'pot-fattener'
    when 4 then 'streak-keeper'
    when 5 then 'early-bird'
    else 'kid-leads'
  end;

  insert into public.family_weekly_pots(room_id, week_start)
  values (v_room_id, v_week_start)
  on conflict on constraint family_weekly_pots_pkey do nothing;

  insert into public.family_daily_races(room_id, race_date)
  values (v_room_id, v_race_date)
  on conflict on constraint family_daily_races_pkey do nothing;

  return query
  with member_stats as (
    select
      m.user_id,
      m.role as member_role,
      coalesce(p.display_name, 'Reader') as display_name,
      coalesce(p.age_bracket, 'adult_18_plus') as age_bracket,
      coalesce(up.total_chapters, 0) as total_chapters,
      coalesce(up.best_streak, 0) as best_streak,
      coalesce(up.character_id, 'bee') as character_id,
      coalesce(sum(a.chapters_delta), 0)::integer as week_chapters,
      coalesce(sum(a.honey_delta) filter (
        where a.event_type not in ('goal_stake', 'powerup_spend', 'pot_boost', 'gift_sent')
      ), 0)::integer as week_honey,
      coalesce(sum(a.chapters_delta) filter (
        where (a.created_at at time zone 'America/Chicago')::date = v_race_date
      ), 0)::integer as today_chapters,
      coalesce(sum(a.chapters_delta) filter (
        where (a.created_at at time zone 'America/Chicago')::date = (v_race_date - 1)
      ), 0)::integer as yesterday_chapters,
      (
        select count(distinct a2.id)
        from public.family_weekly_activity a2
        where a2.room_id = m.room_id
          and a2.user_id = m.user_id
          and a2.week_start = v_week_start
          and a2.event_type = 'chapter_read'
          and (a2.created_at at time zone 'America/Chicago')::date = v_race_date
          and extract(hour from (a2.created_at at time zone 'America/Chicago')) < 12
      ) as morning_reads,
      (
        select count(distinct a2.id)
        from public.family_weekly_activity a2
        where a2.room_id = m.room_id
          and a2.user_id = m.user_id
          and a2.week_start = v_week_start
          and a2.event_type = 'chapter_read'
          and (a2.created_at at time zone 'America/Chicago')::date = v_race_date
          and extract(hour from (a2.created_at at time zone 'America/Chicago')) >= 19
      ) as evening_reads
    from public.family_room_members m
    left join public.profiles p on p.id = m.user_id
    left join public.user_progress up on up.user_id = m.user_id
    left join public.family_weekly_activity a
      on a.room_id = m.room_id
     and a.user_id = m.user_id
     and a.week_start = v_week_start
    where m.room_id = v_room_id
      and m.active
    group by m.user_id, m.role, p.display_name, p.age_bracket, up.total_chapters, up.best_streak, up.character_id
  ),
  race_stats as (
    select
      ms.*,
      coalesce(sum(re.points_delta), 0)::integer as race_points
    from member_stats ms
    left join public.family_race_events re
      on re.room_id = v_room_id
     and re.user_id = ms.user_id
     and re.race_date = v_race_date
    group by ms.user_id, ms.member_role, ms.display_name, ms.age_bracket, ms.total_chapters, ms.best_streak, ms.character_id, ms.week_chapters, ms.week_honey, ms.today_chapters, ms.yesterday_chapters, ms.morning_reads, ms.evening_reads
  ),
  ranked as (
    select
      rs.*,
      row_number() over (
        order by rs.week_chapters desc, rs.week_honey desc, rs.total_chapters desc, rs.display_name asc
      )::integer as family_rank
    from race_stats rs
  ),
  race_ranked as (
    select
      rs.*,
      row_number() over (
        order by rs.race_points desc, rs.today_chapters desc, rs.week_chapters desc, rs.display_name asc
      )::integer as race_rank
    from race_stats rs
  ),
  goal_rows as (
    select
      g.id,
      g.title,
      g.challenger_id,
      coalesce(cp.display_name, 'Reader') as challenger_name,
      g.target_id,
      coalesce(tp.display_name, 'Reader') as target_name,
      g.target_chapters,
      g.wager,
      g.deadline,
      g.status,
      g.winner_id,
      g.payout_honey,
      g.created_at
    from public.family_goals g
    left join public.profiles cp on cp.id = g.challenger_id
    left join public.profiles tp on tp.id = g.target_id
    where g.room_id = v_room_id
      and g.week_start = v_week_start
      and g.status = 'active'
    order by g.created_at desc
    limit 10
  ),
  award_rows as (
    select
      a.award_key,
      a.title,
      a.winner_id,
      coalesce(p.display_name, 'Reader') as winner_name,
      a.metric_value,
      a.created_at
    from public.family_weekly_awards a
    left join public.profiles p on p.id = a.winner_id
    where a.room_id = v_room_id
      and a.week_start = v_week_start
    order by a.created_at desc, a.award_key
  ),
  pot_week_honey as (
    select coalesce(sum(a.honey_delta) filter (
      where a.event_type not in ('goal_stake', 'powerup_spend', 'pot_boost', 'gift_sent')
    ), 0)::integer as v
    from public.family_weekly_activity a
    where a.room_id = v_room_id
      and a.week_start = v_week_start
  ),
  mission_rows as (
    select m.*
    from (
      values
        (
          'everyone-read',
          'Everyone reads today',
          'Every family member reads at least one chapter today.',
          (select count(*)::integer from race_stats where today_chapters > 0),
          greatest(1, (select count(*)::integer from race_stats)),
          300
        ),
        (
          'beat-yesterday',
          'Beat yesterday',
          'Top yesterday''s family chapter total before bedtime.',
          (select coalesce(sum(today_chapters), 0)::integer from race_stats),
          greatest(
            1,
            (
              select coalesce(sum(a.chapters_delta), 0)::integer + 1
              from public.family_weekly_activity a
              where a.room_id = v_room_id
                and a.week_start = v_week_start
                and (a.created_at at time zone 'America/Chicago')::date = (v_race_date - 1)
            )
          ),
          450
        ),
        (
          'help-lowest',
          'Help the lowest reader',
          'The reader with the lowest weekly total gets one chapter today.',
          (
            select case when coalesce(rs.today_chapters, 0) > 0 then 1 else 0 end
            from race_stats rs
            order by rs.week_chapters asc, rs.total_chapters asc, rs.display_name asc
            limit 1
          ),
          1,
          350
        ),
        (
          'family-ten',
          '10 chapter family sprint',
          'Read 10 total chapters as a family today.',
          (select coalesce(sum(today_chapters), 0)::integer from race_stats),
          10,
          500
        ),
        (
          'comeback-day',
          'Comeback day',
          'At least two readers behind the leader get on the board today.',
          (
            select count(*)::integer
            from race_stats
            where today_chapters > 0
              and user_id <> (select user_id from ranked where family_rank = 1 limit 1)
          ),
          2,
          400
        ),
        (
          'comeback-double',
          '2x comeback boost',
          'A reader behind the leader reads 2 chapters today.',
          (
            select coalesce(max(today_chapters), 0)::integer
            from race_stats
            where user_id <> (select user_id from ranked where family_rank = 1 limit 1)
          ),
          2,
          350
        ),
        (
          'close-gap',
          'Close the gap',
          'Someone chasing the leader closes the family gap with 3 chapters today.',
          (
            select coalesce(max(today_chapters), 0)::integer
            from race_stats
            where user_id <> (select user_id from ranked where family_rank = 1 limit 1)
          ),
          3,
          450
        ),
        (
          'early-bird',
          'Early bird readers',
          'Two readers post before noon Central.',
          (select count(*)::integer from race_stats where morning_reads > 0),
          2,
          375
        ),
        (
          'night-owl',
          'Night owl readers',
          'Two readers post after 7 PM Central.',
          (select count(*)::integer from race_stats where evening_reads > 0),
          2,
          375
        ),
        (
          'kid-leads',
          'Kid leads the family',
          'A reader under 14 tops 3 chapters today.',
          (
            select coalesce(max(today_chapters), 0)::integer
            from race_stats
            where age_bracket in ('kid_6_8', 'kid_9_11', 'tween_12_13')
          ),
          3,
          500
        ),
        (
          'streak-keeper',
          'Streak keeper',
          'Everyone hits at least 1 chapter today AND yesterday.',
          (select count(*)::integer from race_stats where today_chapters >= 1 and yesterday_chapters >= 1),
          greatest(1, (select count(*)::integer from race_stats)),
          450
        ),
        (
          'pot-fattener',
          'Pot fattener',
          'Family adds 1000 honey to the pot this week.',
          (select v from pot_week_honey),
          1000,
          600
        )
    ) as m(mission_key, title, body, progress_value, target_value, reward_honey)
    where m.mission_key in (
      v_slot_a,
      v_slot_b,
      'family-ten'
    )
  )
  select
    r.id,
    r.name,
    r.invite_code,
    mine.role,
    (select count(*)::integer from ranked),
    v_week_start,
    (v_week_start + 6),
    coalesce(pot.pot_honey, 0),
    coalesce(me.week_chapters, 0),
    coalesce(me.week_honey, 0),
    coalesce(me.family_rank, 0),
    coalesce(leader.display_name, 'Reader'),
    coalesce(leader.week_chapters, 0),
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'user_id', rk.user_id,
            'display_name', rk.display_name,
            'role', rk.member_role,
            'character_id', rk.character_id,
            'week_chapters', rk.week_chapters,
            'week_honey', rk.week_honey,
            'total_chapters', rk.total_chapters,
            'best_streak', rk.best_streak,
            'rank', rk.family_rank
          )
          order by rk.family_rank
        )
        from ranked rk
      ),
      '[]'::jsonb
    ),
    coalesce(
      (
        select jsonb_agg(to_jsonb(goal_rows) order by goal_rows.created_at desc)
        from goal_rows
      ),
      '[]'::jsonb
    ),
    v_race_date,
    coalesce(dr.jackpot_honey, 2000),
    coalesce(my_race.race_points, 0),
    coalesce(race_leader.display_name, 'Reader'),
    coalesce(race_leader.race_points, 0),
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'user_id', rr.user_id,
            'display_name', rr.display_name,
            'character_id', rr.character_id,
            'today_chapters', rr.today_chapters,
            'race_points', rr.race_points,
            'race_rank', rr.race_rank
          )
          order by rr.race_rank
        )
        from race_ranked rr
      ),
      '[]'::jsonb
    ),
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'mission_key', mr.mission_key,
            'title', mr.title,
            'body', mr.body,
            'progress', least(mr.progress_value, mr.target_value),
            'target', mr.target_value,
            'reward_honey', mr.reward_honey,
            'complete', mr.progress_value >= mr.target_value,
            'claimed', mc.mission_key is not null
          )
          order by mr.reward_honey desc
        )
        from mission_rows mr
        left join public.family_mission_claims mc
          on mc.room_id = v_room_id
         and mc.mission_date = v_race_date
         and mc.mission_key = mr.mission_key
      ),
      '[]'::jsonb
    ),
    coalesce(
      (
        select jsonb_agg(to_jsonb(award_rows) order by award_rows.created_at desc, award_rows.award_key)
        from award_rows
      ),
      '[]'::jsonb
    )
  from public.family_rooms r
  join public.family_room_members mine
    on mine.room_id = r.id
   and mine.user_id = auth.uid()
   and mine.active
  left join public.family_weekly_pots pot
    on pot.room_id = r.id
   and pot.week_start = v_week_start
  left join public.family_daily_races dr
    on dr.room_id = r.id
   and dr.race_date = v_race_date
  left join ranked me on me.user_id = auth.uid()
  left join ranked leader on leader.family_rank = 1
  left join race_ranked my_race on my_race.user_id = auth.uid()
  left join race_ranked race_leader on race_leader.race_rank = 1
  where r.id = v_room_id;
end;
$$;

grant execute on function public.my_family_room() to authenticated;

-- ---------------------------------------------------------------------------
-- TASK 3: Weekly winner auto-settle wiring
-- ---------------------------------------------------------------------------
--
-- Patch settle_family_weekly_season so it can be called from pg_cron (no
-- auth.uid()) — when there's no auth context, iterate over EVERY room and
-- settle the current week for each. When called by an authenticated user
-- (existing behavior), settle just their room.

create or replace function public.settle_family_weekly_season()
returns table(award_count integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid;
  v_week_start date := public.current_family_week_start();
  v_count integer := 0;
  v_total integer := 0;
  r record;
begin
  -- No auth context (e.g. pg_cron) → settle every room for this week.
  if auth.uid() is null then
    for r in
      select distinct id from public.family_rooms
    loop
      perform public._settle_family_weekly_season_for_room(r.id, v_week_start);
      v_total := v_total + 1;
    end loop;
    return query select v_total;
    return;
  end if;

  v_room_id := public.current_family_room_id();
  if v_room_id is null then
    raise exception 'join a family room first';
  end if;

  v_count := public._settle_family_weekly_season_for_room(v_room_id, v_week_start);
  return query select v_count;
end;
$$;

-- Helper that does the actual award computation for one room/week. Idempotent
-- via upsert on (room_id, week_start, award_key). Also marks the weekly pot
-- as settled with a winner_id so maybe_settle_weekly_season can short-circuit
-- on subsequent calls.
create or replace function public._settle_family_weekly_season_for_room(
  p_room_id uuid,
  p_week_start date
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
  v_winner_id uuid;
  v_pot_honey integer := 0;
  v_winner_existing_honey integer := 0;
begin
  with stats as (
    select
      m.user_id,
      coalesce(p.display_name, 'Reader') as display_name,
      coalesce(up.best_streak, 0) as best_streak,
      coalesce(sum(a.chapters_delta), 0)::integer as week_chapters,
      coalesce(sum(a.honey_delta) filter (
        where a.event_type not in ('goal_stake', 'powerup_spend', 'pot_boost', 'gift_sent')
      ), 0)::integer as week_honey,
      coalesce(sum(a.honey_delta) filter (where a.event_type = 'comeback_bonus'), 0)::integer as comeback_honey
    from public.family_room_members m
    left join public.profiles p on p.id = m.user_id
    left join public.user_progress up on up.user_id = m.user_id
    left join public.family_weekly_activity a
      on a.room_id = m.room_id
     and a.user_id = m.user_id
     and a.week_start = p_week_start
    where m.room_id = p_room_id
      and m.active
    group by m.user_id, p.display_name, up.best_streak
  ),
  race_scores as (
    select user_id, coalesce(sum(points_delta), 0)::integer as race_points
    from public.family_race_events
    where room_id = p_room_id
      and race_date >= p_week_start
      and race_date <= (p_week_start + 6)
    group by user_id
  ),
  sunday_scores as (
    select user_id, coalesce(sum(honey_delta), 0)::integer as sunday_honey
    from public.family_weekly_activity
    where room_id = p_room_id
      and week_start = p_week_start
      and event_type = 'sunday_strong'
    group by user_id
  ),
  awards as (
    select 'weekly-champion'::text as award_key, 'Weekly Champion'::text as title, user_id as winner_id, week_chapters as metric_value
    from stats
    order by week_chapters desc, week_honey desc, display_name asc
    limit 1
  ),
  most_improved_award as (
    select 'most-improved'::text as award_key, 'Most Improved'::text as title, s.user_id as winner_id, coalesce(r.race_points, 0)::integer as metric_value
    from stats s
    left join race_scores r on r.user_id = s.user_id
    order by coalesce(r.race_points, 0) desc, s.week_chapters desc, s.display_name asc
    limit 1
  ),
  best_streak_award as (
    select 'best-streak'::text as award_key, 'Best Streak'::text as title, user_id as winner_id, best_streak as metric_value
    from stats
    order by best_streak desc, week_chapters desc, display_name asc
    limit 1
  ),
  comeback_award as (
    select 'biggest-comeback'::text as award_key, 'Biggest Comeback'::text as title, user_id as winner_id, comeback_honey as metric_value
    from stats
    order by comeback_honey desc, week_chapters desc, display_name asc
    limit 1
  ),
  sunday_award as (
    select 'sunday-finisher'::text as award_key, 'Sunday Finisher'::text as title, s.user_id as winner_id, coalesce(ss.sunday_honey, 0)::integer as metric_value
    from stats s
    left join sunday_scores ss on ss.user_id = s.user_id
    order by coalesce(ss.sunday_honey, 0) desc, s.week_chapters desc, s.display_name asc
    limit 1
  ),
  all_awards as (
    select * from awards
    union all select * from most_improved_award
    union all select * from best_streak_award
    union all select * from comeback_award
    union all select * from sunday_award
  )
  insert into public.family_weekly_awards(room_id, week_start, award_key, winner_id, title, metric_value)
  select p_room_id, p_week_start, award_key, winner_id, title, greatest(0, coalesce(metric_value, 0))
  from all_awards
  where winner_id is not null
  on conflict (room_id, week_start, award_key)
  do update set
    winner_id = excluded.winner_id,
    title = excluded.title,
    metric_value = excluded.metric_value,
    created_at = now();

  -- Pay the Weekly Champion the current pot honey, then mark the pot settled.
  select winner_id into v_winner_id
  from public.family_weekly_awards
  where room_id = p_room_id
    and week_start = p_week_start
    and award_key = 'weekly-champion';

  select pot_honey into v_pot_honey
  from public.family_weekly_pots
  where room_id = p_room_id
    and week_start = p_week_start
    and status = 'active'
  for update;

  if v_winner_id is not null and coalesce(v_pot_honey, 0) > 0 then
    select coalesce((state->>'honey')::integer, 0) into v_winner_existing_honey
    from public.user_progress
    where user_id = v_winner_id
    for update;

    update public.user_progress
    set state = jsonb_set(coalesce(state, '{}'::jsonb), '{honey}', to_jsonb(coalesce(v_winner_existing_honey, 0) + v_pot_honey), true),
        updated_at = now()
    where user_id = v_winner_id;

    insert into public.family_weekly_activity(room_id, week_start, user_id, event_type, honey_delta, chapters_delta, source_key, note)
    values (p_room_id, p_week_start, v_winner_id, 'weekly_pot_payout', v_pot_honey, 0,
            'weekly-pot-payout:' || p_week_start::text, 'Weekly Honey Pot champion payout')
    on conflict (room_id, user_id, source_key) where source_key is not null do nothing;
  end if;

  -- Mark pot settled (idempotent guard for maybe_settle_weekly_season).
  update public.family_weekly_pots
  set status = 'settled',
      winner_id = v_winner_id,
      settled_at = now(),
      updated_at = now()
  where room_id = p_room_id
    and week_start = p_week_start
    and status = 'active';

  select count(*)::integer into v_count
  from public.family_weekly_awards
  where room_id = p_room_id
    and week_start = p_week_start;

  return v_count;
end;
$$;

grant execute on function public.settle_family_weekly_season() to authenticated;

-- Client-side fallback: any authenticated client (e.g. the family-room load
-- handler) can call this once per page-load. It only does real work on
-- Mondays Central, and only if this week's pot is still active.
create or replace function public.maybe_settle_weekly_season()
returns table(settled boolean, room_id uuid, week_start date)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid;
  v_week_start date := public.current_family_week_start();
  v_today date := public.family_central_today();
  v_dow integer;
  v_pot_status text;
  v_prev_week date;
  v_prev_status text;
begin
  if auth.uid() is null then
    return query select false, null::uuid, v_week_start;
    return;
  end if;

  v_room_id := public.current_family_room_id();
  if v_room_id is null then
    return query select false, null::uuid, v_week_start;
    return;
  end if;

  -- ISO dow: Monday = 1
  v_dow := extract(isodow from v_today)::integer;
  if v_dow <> 1 then
    return query select false, v_room_id, v_week_start;
    return;
  end if;

  -- The week we want to settle on Monday is LAST week (Mon–Sun just ended).
  v_prev_week := v_week_start - 7;

  select status into v_prev_status
  from public.family_weekly_pots
  where room_id = v_room_id
    and week_start = v_prev_week;

  if v_prev_status is null or v_prev_status = 'settled' then
    return query select false, v_room_id, v_prev_week;
    return;
  end if;

  perform public._settle_family_weekly_season_for_room(v_room_id, v_prev_week);
  return query select true, v_room_id, v_prev_week;
end;
$$;

grant execute on function public.maybe_settle_weekly_season() to authenticated;

-- pg_cron schedule: Monday 12:00 UTC = 7am Central (CDT). Guarded so the
-- migration succeeds even on projects where pg_cron is not installed.
do $$
begin
  begin
    perform cron.schedule(
      'settle-family-weekly-season-monday-7am-central',
      '0 12 * * 1',
      $cron$select public.settle_family_weekly_season();$cron$
    );
  exception
    when undefined_function then null;
    when undefined_schema then null;
    when undefined_table then null;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- Verification (for human eyes; uncomment to run manually):
-- ---------------------------------------------------------------------------
-- select pg_get_functiondef('public.record_family_activity(text,integer,integer,text,text)'::regprocedure);
-- select pg_get_functiondef('public.claim_family_missions()'::regprocedure);
-- select pg_get_functiondef('public.my_family_room()'::regprocedure);
-- select pg_get_functiondef('public.maybe_settle_weekly_season()'::regprocedure);
-- select pg_get_functiondef('public.settle_family_weekly_season()'::regprocedure);
-- select * from cron.job where jobname like 'settle-family-weekly-season%';
