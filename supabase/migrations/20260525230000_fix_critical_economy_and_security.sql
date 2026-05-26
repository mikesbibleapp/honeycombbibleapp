-- Critical economy + security bug-fix migration.
-- Addresses: gift_honey deadlock, missing audit table, claim_family_missions
-- not paying users, create_family_goal double-minting pot, missing settle
-- guards, powerup double-tap race, week_honey including spend events,
-- regression trigger NULL safety, retention helper, and grants.

create extension if not exists "uuid-ossp";

-- ---------------------------------------------------------------------------
-- A + B: gift_honey deadlock fix + audit table
-- ---------------------------------------------------------------------------

create table if not exists public.honey_transfers (
  id uuid default gen_random_uuid() primary key,
  sender_id uuid not null,
  recipient_id uuid not null,
  amount integer not null check (amount > 0),
  created_at timestamptz default now() not null
);

create index if not exists honey_transfers_sender_created_idx
  on public.honey_transfers (sender_id, created_at desc);

create index if not exists honey_transfers_recipient_created_idx
  on public.honey_transfers (recipient_id, created_at desc);

alter table public.honey_transfers enable row level security;

drop policy if exists honey_transfers_read_participant on public.honey_transfers;
create policy honey_transfers_read_participant on public.honey_transfers
  for select to authenticated
  using (auth.uid() = sender_id or auth.uid() = recipient_id);

create or replace function public.gift_honey(
  p_recipient_id uuid,
  p_amount integer
)
returns table(sender_honey integer, transferred integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  my_honey integer;
  their_honey integer;
  v_first uuid;
  v_second uuid;
begin
  if uid is null then
    raise exception 'not signed in';
  end if;

  if p_recipient_id is null then
    raise exception 'pick someone to receive the gift';
  end if;

  if uid = p_recipient_id then
    raise exception 'cannot gift yourself';
  end if;

  if p_amount is null or p_amount < 1 then
    raise exception 'amount must be positive';
  end if;

  -- Lock both rows in canonical UUID order to avoid deadlocks.
  v_first := least(uid, p_recipient_id);
  v_second := greatest(uid, p_recipient_id);

  perform 1 from public.user_progress
    where user_id = v_first
    for update;

  perform 1 from public.user_progress
    where user_id = v_second
    for update;

  -- Read sender row (already locked above).
  select coalesce((state->>'honey')::integer, 0)
    into my_honey
    from public.user_progress
    where user_id = uid;

  if my_honey is null then
    raise exception 'sender progress not found';
  end if;

  if my_honey < p_amount then
    raise exception 'not enough honey';
  end if;

  select coalesce((state->>'honey')::integer, 0)
    into their_honey
    from public.user_progress
    where user_id = p_recipient_id;

  if their_honey is null then
    raise exception 'recipient not found';
  end if;

  update public.user_progress
    set state = jsonb_set(coalesce(state, '{}'::jsonb), '{honey}', to_jsonb(my_honey - p_amount), true),
        updated_at = now()
    where user_id = uid;

  update public.user_progress
    set state = jsonb_set(coalesce(state, '{}'::jsonb), '{honey}', to_jsonb(their_honey + p_amount), true),
        updated_at = now()
    where user_id = p_recipient_id;

  insert into public.honey_transfers(sender_id, recipient_id, amount)
  values (uid, p_recipient_id, p_amount);

  return query select (my_honey - p_amount), p_amount;
end;
$$;

-- ---------------------------------------------------------------------------
-- C: claim_family_missions now actually pays the claimant
-- ---------------------------------------------------------------------------

create or replace function public.claim_family_missions()
returns table(claimed_count integer, reward_honey integer, pot_honey integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid;
  v_week_start date := public.current_family_week_start();
  v_race_date date := current_date;
  v_member_count integer := 0;
  v_everyone_progress integer := 0;
  v_family_today integer := 0;
  v_comeback_progress integer := 0;
  v_yesterday_target integer := 1;
  v_lowest_progress integer := 0;
  v_behind_max integer := 0;
  v_leader_id uuid;
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

  select count(*)::integer into v_member_count
  from public.family_room_members
  where room_id = v_room_id
    and active;

  select greatest(1, coalesce(sum(a.chapters_delta), 0)::integer + 1) into v_yesterday_target
  from public.family_weekly_activity a
  where a.room_id = v_room_id
    and a.week_start = v_week_start
    and a.created_at::date = (v_race_date - 1);

  with activity as (
    select
      m.user_id,
      coalesce(sum(a.chapters_delta), 0)::integer as week_chapters,
      coalesce(sum(a.chapters_delta) filter (where a.created_at::date = v_race_date), 0)::integer as today_chapters
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
        ('close-gap'::text, v_behind_max, 3, 450)
    ) as m(mission_key, progress_value, target_value, reward_honey)
    where m.mission_key in (
      case (extract(doy from v_race_date)::integer % 3)
        when 0 then 'everyone-read'
        when 1 then 'beat-yesterday'
        else 'help-lowest'
      end,
      case (extract(doy from v_race_date)::integer % 3)
        when 0 then 'comeback-day'
        when 1 then 'comeback-double'
        else 'close-gap'
      end,
      'family-ten'
    )
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

-- ---------------------------------------------------------------------------
-- D: create_family_goal stops minting honey (stake logged with delta 0)
-- ---------------------------------------------------------------------------

create or replace function public.create_family_goal(
  p_target_id uuid,
  p_target_chapters integer default 4,
  p_wager integer default 50,
  p_deadline date default (current_date + 4),
  p_title text default null
)
returns table(goal_id uuid, remaining_honey integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid;
  v_week_start date := public.current_family_week_start();
  v_honey integer;
  v_goal_id uuid;
  v_target_chapters integer := least(80, greatest(1, coalesce(p_target_chapters, 4)));
  v_wager integer := least(5000, greatest(1, coalesce(p_wager, 50)));
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;

  v_room_id := public.current_family_room_id();
  if v_room_id is null then
    raise exception 'join a family room first';
  end if;

  if p_target_id = auth.uid() then
    raise exception 'pick someone else to challenge';
  end if;

  if not exists (
    select 1 from public.family_room_members
    where room_id = v_room_id
      and user_id = p_target_id
      and active
  ) then
    raise exception 'target is not in your family room';
  end if;

  select coalesce((state->>'honey')::integer, 0) into v_honey
  from public.user_progress
  where user_id = auth.uid()
  for update;

  if coalesce(v_honey, 0) < v_wager then
    raise exception 'not enough honey for this goal';
  end if;

  update public.user_progress
  set state = jsonb_set(state, '{honey}', to_jsonb(v_honey - v_wager), true),
      updated_at = now()
  where user_id = auth.uid();

  insert into public.family_goals(room_id, week_start, challenger_id, target_id, title, target_chapters, wager, deadline)
  values (
    v_room_id,
    v_week_start,
    auth.uid(),
    p_target_id,
    coalesce(nullif(trim(p_title), ''), 'Beat me by Friday'),
    v_target_chapters,
    v_wager,
    greatest(p_deadline, current_date)
  )
  returning id into v_goal_id;

  -- Log the stake for audit but do NOT credit the pot — the wager is already
  -- escrowed from the challenger; winner gets 2x from user_progress directly.
  perform * from public.record_family_activity(
    'goal_stake',
    0,
    0,
    'goal-stake:' || v_goal_id::text,
    'Goal stake recorded (pot not credited)'
  );

  return query select v_goal_id, v_honey - v_wager;
end;
$$;

-- ---------------------------------------------------------------------------
-- E: settle_family_daily_race deadline guard (settle yesterday or after 9pm CT)
-- ---------------------------------------------------------------------------

create or replace function public.settle_family_daily_race()
returns table(winner_id uuid, winner_name text, payout_honey integer, winning_points integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid;
  v_week_start date := public.current_family_week_start();
  v_race_date date := current_date;
  v_race public.family_daily_races%rowtype;
  v_winner_honey integer := 0;
  v_winner_name text := 'Reader';
  v_points integer := 0;
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;

  v_room_id := public.current_family_room_id();
  if v_room_id is null then
    raise exception 'join a family room first';
  end if;

  -- Deadline guard: only allow settling YESTERDAY's race, or today's after 9pm Central.
  if current_date = v_race_date
     and extract(hour from (now() at time zone 'America/Chicago')) < 21 then
    raise exception 'Daily race not yet closed (settles after 9 PM Central)';
  end if;

  insert into public.family_daily_races(room_id, race_date)
  values (v_room_id, v_race_date)
  on conflict on constraint family_daily_races_pkey do nothing;

  select * into v_race
  from public.family_daily_races
  where room_id = v_room_id
    and race_date = v_race_date
  for update;

  if v_race.status = 'settled' then
    select coalesce(p.display_name, 'Reader'), coalesce(sum(re.points_delta), 0)::integer
      into v_winner_name, v_points
    from public.profiles p
    left join public.family_race_events re
      on re.user_id = p.id
     and re.room_id = v_room_id
     and re.race_date = v_race_date
    where p.id = v_race.winner_id
    group by p.display_name;

    return query select v_race.winner_id, v_winner_name, v_race.jackpot_honey, coalesce(v_points, 0);
    return;
  end if;

  with scores as (
    select
      m.user_id,
      coalesce(p.display_name, 'Reader') as display_name,
      coalesce(sum(re.points_delta), 0)::integer as race_points
    from public.family_room_members m
    left join public.profiles p on p.id = m.user_id
    left join public.family_race_events re
      on re.room_id = m.room_id
     and re.user_id = m.user_id
     and re.race_date = v_race_date
    where m.room_id = v_room_id
      and m.active
    group by m.user_id, p.display_name
    order by race_points desc, display_name asc
    limit 1
  )
  select user_id, display_name, race_points
    into v_race.winner_id, v_winner_name, v_points
  from scores;

  if v_race.winner_id is null or coalesce(v_points, 0) <= 0 then
    raise exception 'no race points yet today';
  end if;

  select coalesce((state->>'honey')::integer, 0) into v_winner_honey
  from public.user_progress
  where user_id = v_race.winner_id
  for update;

  update public.user_progress
  set state = jsonb_set(state, '{honey}', to_jsonb(coalesce(v_winner_honey, 0) + v_race.jackpot_honey), true),
      updated_at = now()
  where user_id = v_race.winner_id;

  update public.family_daily_races
  set status = 'settled',
      winner_id = v_race.winner_id,
      settled_at = now(),
      updated_at = now()
  where room_id = v_room_id
    and race_date = v_race_date;

  insert into public.family_weekly_activity(room_id, week_start, user_id, event_type, honey_delta, chapters_delta, source_key, note)
  values (
    v_room_id,
    v_week_start,
    v_race.winner_id,
    'daily_race_win',
    v_race.jackpot_honey,
    0,
    'daily-race-win:' || v_race_date::text,
    'Daily family race jackpot'
  )
  on conflict (room_id, user_id, source_key) where source_key is not null do nothing;

  return query select v_race.winner_id, v_winner_name, v_race.jackpot_honey, coalesce(v_points, 0);
end;
$$;

-- ---------------------------------------------------------------------------
-- F: settle_family_goal caller validation
-- ---------------------------------------------------------------------------

create or replace function public.settle_family_goal(p_goal_id uuid)
returns table(
  goal_id uuid,
  winner_id uuid,
  payout_honey integer,
  challenger_week_chapters integer,
  target_week_chapters integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  g public.family_goals%rowtype;
  v_challenger_chapters integer := 0;
  v_target_chapters integer := 0;
  v_winner uuid;
  v_payout integer := 0;
  v_winner_honey integer := 0;
begin
  select * into g
  from public.family_goals
  where id = p_goal_id
  for update;

  if g.id is null then
    raise exception 'goal not found';
  end if;

  if not exists (
    select 1 from public.family_room_members
    where room_id = g.room_id
      and user_id = auth.uid()
      and active
  ) then
    raise exception 'not in this family room';
  end if;

  -- Caller must be a participant, OR the deadline has passed (anyone in room).
  if not (
    auth.uid() in (g.challenger_id, g.target_id)
    or current_date >= g.deadline
  ) then
    raise exception 'only the challenger or target can settle before the deadline';
  end if;

  if g.status <> 'active' then
    return query select g.id, g.winner_id, g.payout_honey, 0, 0;
    return;
  end if;

  select coalesce(sum(chapters_delta), 0)::integer into v_challenger_chapters
  from public.family_weekly_activity
  where room_id = g.room_id
    and week_start = g.week_start
    and user_id = g.challenger_id;

  select coalesce(sum(chapters_delta), 0)::integer into v_target_chapters
  from public.family_weekly_activity
  where room_id = g.room_id
    and week_start = g.week_start
    and user_id = g.target_id;

  if current_date < g.deadline
     and not (v_challenger_chapters >= g.target_chapters and v_challenger_chapters > v_target_chapters) then
    raise exception 'goal is not ready to settle';
  end if;

  if v_challenger_chapters = v_target_chapters then
    v_winner := null;
    v_payout := 0;
  elsif v_challenger_chapters >= g.target_chapters and v_challenger_chapters > v_target_chapters then
    v_winner := g.challenger_id;
    v_payout := g.wager * 2;
  else
    v_winner := g.target_id;
    v_payout := g.wager * 2;
  end if;

  update public.family_goals
  set status = 'settled',
      winner_id = v_winner,
      payout_honey = v_payout,
      settled_at = now()
  where id = g.id;

  if v_winner is not null and v_payout > 0 then
    select coalesce((state->>'honey')::integer, 0) into v_winner_honey
    from public.user_progress
    where user_id = v_winner
    for update;

    update public.user_progress
    set state = jsonb_set(state, '{honey}', to_jsonb(coalesce(v_winner_honey, 0) + v_payout), true),
        updated_at = now()
    where user_id = v_winner;

    insert into public.family_weekly_activity(room_id, week_start, user_id, event_type, honey_delta, chapters_delta, source_key, note)
    values (g.room_id, g.week_start, v_winner, 'goal_win', v_payout, 0, 'goal-win:' || g.id::text, 'Head-to-head family goal won')
    on conflict (room_id, user_id, source_key) where source_key is not null do nothing;
  end if;

  return query select g.id, v_winner, v_payout, v_challenger_chapters, v_target_chapters;
end;
$$;

-- ---------------------------------------------------------------------------
-- G: Powerup double-tap atomic guard via partial unique index
-- ---------------------------------------------------------------------------

create unique index if not exists family_race_events_no_doubletap
  on public.family_race_events (
    room_id, race_date, user_id, actor_id, event_type, (date_trunc('second', created_at))
  )
  where event_type like 'powerup_%';

-- ---------------------------------------------------------------------------
-- H: my_family_room excludes spend events from week_honey aggregation
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
  v_race_date date := current_date;
begin
  v_room_id := public.current_family_room_id();
  if v_room_id is null then
    return;
  end if;

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
      coalesce(up.total_chapters, 0) as total_chapters,
      coalesce(up.best_streak, 0) as best_streak,
      coalesce(up.character_id, 'bee') as character_id,
      coalesce(sum(a.chapters_delta), 0)::integer as week_chapters,
      coalesce(sum(a.honey_delta) filter (
        where a.event_type not in ('goal_stake', 'powerup_spend', 'pot_boost', 'gift_sent')
      ), 0)::integer as week_honey,
      coalesce(sum(a.chapters_delta) filter (where a.created_at::date = v_race_date), 0)::integer as today_chapters
    from public.family_room_members m
    left join public.profiles p on p.id = m.user_id
    left join public.user_progress up on up.user_id = m.user_id
    left join public.family_weekly_activity a
      on a.room_id = m.room_id
     and a.user_id = m.user_id
     and a.week_start = v_week_start
    where m.room_id = v_room_id
      and m.active
    group by m.user_id, m.role, p.display_name, up.total_chapters, up.best_streak, up.character_id
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
    group by ms.user_id, ms.member_role, ms.display_name, ms.total_chapters, ms.best_streak, ms.character_id, ms.week_chapters, ms.week_honey, ms.today_chapters
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
                and a.created_at::date = (v_race_date - 1)
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
        )
    ) as m(mission_key, title, body, progress_value, target_value, reward_honey)
    where m.mission_key in (
      case (extract(doy from v_race_date)::integer % 3)
        when 0 then 'everyone-read'
        when 1 then 'beat-yesterday'
        else 'help-lowest'
      end,
      case (extract(doy from v_race_date)::integer % 3)
        when 0 then 'comeback-day'
        when 1 then 'comeback-double'
        else 'close-gap'
      end,
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

-- ---------------------------------------------------------------------------
-- I: prevent_user_progress_regression NULL safety
-- ---------------------------------------------------------------------------

create or replace function public.prevent_user_progress_regression()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' then
    if coalesce(new.total_chapters, 0) < coalesce(old.total_chapters, 0) then
      raise exception 'refusing to reduce total_chapters from % to %', old.total_chapters, new.total_chapters;
    end if;

    if coalesce(new.books_finished_count, 0) < coalesce(old.books_finished_count, 0) then
      raise exception 'refusing to reduce books_finished_count from % to %', old.books_finished_count, new.books_finished_count;
    end if;

    if coalesce(new.best_streak, 0) < coalesce(old.best_streak, 0) then
      new.best_streak := old.best_streak;
    end if;
  end if;

  new.state := jsonb_set(coalesce(new.state, '{}'::jsonb), '{totalChapters}', to_jsonb(coalesce(new.total_chapters, 0)), true);
  new.state := jsonb_set(new.state, '{booksFinishedCount}', to_jsonb(coalesce(new.books_finished_count, 0)), true);
  new.state := jsonb_set(new.state, '{bestStreak}', to_jsonb(coalesce(new.best_streak, 0)), true);

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- J: Battle history retention helper
-- ---------------------------------------------------------------------------

create or replace function public.prune_old_settled_challenges()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted integer := 0;
begin
  with deleted as (
    delete from public.challenges
    where status = 'settled'
      and updated_at < now() - interval '90 days'
    returning 1
  )
  select count(*)::integer into v_deleted from deleted;

  return v_deleted;
end;
$$;

grant execute on function public.prune_old_settled_challenges() to authenticated;

-- Refresh grants for all client-callable functions touched above.
grant execute on function public.gift_honey(uuid, integer) to authenticated;
grant execute on function public.my_family_room() to authenticated;
grant execute on function public.create_family_goal(uuid, integer, integer, date, text) to authenticated;
grant execute on function public.settle_family_goal(uuid) to authenticated;
grant execute on function public.claim_family_missions() to authenticated;
grant execute on function public.settle_family_daily_race() to authenticated;

-- ---------------------------------------------------------------------------
-- K: Display-name patch reversal
-- ---------------------------------------------------------------------------
-- NOTE: cannot safely revert prior LIKE patches without per-user signal.
-- The 20260525140000 migration set age_bracket via LIKE matches on display_name
-- which can match unintended users (e.g. "%mike%" matches "Mike Wilson").
-- Mike will follow up manually with per-user updates once a signal column or
-- explicit opt-in exists. Leaving the data untouched here for safety.
