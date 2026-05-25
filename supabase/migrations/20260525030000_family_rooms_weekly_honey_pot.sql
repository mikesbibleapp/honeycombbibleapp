-- Family Rooms + Weekly Honey Pot
-- Additive schema: does not alter existing progress/challenge tables.

create table if not exists public.family_rooms (
  id uuid primary key default uuid_generate_v4(),
  name text not null check (char_length(trim(name)) between 2 and 60),
  invite_code text not null unique,
  owner_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.family_room_members (
  room_id uuid not null references public.family_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  active boolean not null default true,
  primary key (room_id, user_id)
);

create table if not exists public.family_weekly_pots (
  room_id uuid not null references public.family_rooms(id) on delete cascade,
  week_start date not null,
  week_end date not null generated always as (week_start + 6) stored,
  pot_honey integer not null default 0 check (pot_honey >= 0),
  status text not null default 'active' check (status in ('active', 'settled')),
  winner_id uuid references auth.users(id) on delete set null,
  settled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (room_id, week_start)
);

create table if not exists public.family_weekly_activity (
  id uuid primary key default uuid_generate_v4(),
  room_id uuid not null references public.family_rooms(id) on delete cascade,
  week_start date not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  event_type text not null,
  honey_delta integer not null default 0 check (honey_delta >= 0),
  chapters_delta integer not null default 0 check (chapters_delta >= 0),
  source_key text,
  note text,
  created_at timestamptz not null default now()
);

create unique index if not exists family_weekly_activity_source_key_idx
  on public.family_weekly_activity(room_id, user_id, source_key)
  where source_key is not null;

create index if not exists family_weekly_activity_room_week_idx
  on public.family_weekly_activity(room_id, week_start, user_id);

create table if not exists public.family_goals (
  id uuid primary key default uuid_generate_v4(),
  room_id uuid not null references public.family_rooms(id) on delete cascade,
  week_start date not null,
  challenger_id uuid not null references auth.users(id) on delete cascade,
  target_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  target_chapters integer not null default 4 check (target_chapters between 1 and 80),
  wager integer not null default 50 check (wager between 1 and 5000),
  deadline date not null,
  status text not null default 'active' check (status in ('active', 'settled', 'cancelled')),
  winner_id uuid references auth.users(id) on delete set null,
  payout_honey integer not null default 0,
  settled_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists family_goals_room_status_idx
  on public.family_goals(room_id, status, deadline);

create table if not exists public.family_daily_races (
  room_id uuid not null references public.family_rooms(id) on delete cascade,
  race_date date not null,
  jackpot_honey integer not null default 2000 check (jackpot_honey >= 0),
  status text not null default 'active' check (status in ('active', 'settled')),
  winner_id uuid references auth.users(id) on delete set null,
  settled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (room_id, race_date)
);

create table if not exists public.family_race_events (
  id uuid primary key default uuid_generate_v4(),
  room_id uuid not null references public.family_rooms(id) on delete cascade,
  race_date date not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  event_type text not null,
  points_delta integer not null default 0,
  source_key text,
  note text,
  created_at timestamptz not null default now()
);

create unique index if not exists family_race_events_source_key_idx
  on public.family_race_events(room_id, user_id, source_key)
  where source_key is not null;

create index if not exists family_race_events_room_date_idx
  on public.family_race_events(room_id, race_date, user_id);

create table if not exists public.family_mission_claims (
  room_id uuid not null references public.family_rooms(id) on delete cascade,
  mission_date date not null,
  mission_key text not null,
  claimed_by uuid not null references auth.users(id) on delete cascade,
  reward_honey integer not null default 0 check (reward_honey >= 0),
  claimed_at timestamptz not null default now(),
  primary key (room_id, mission_date, mission_key)
);

create table if not exists public.family_weekly_awards (
  room_id uuid not null references public.family_rooms(id) on delete cascade,
  week_start date not null,
  award_key text not null,
  winner_id uuid references auth.users(id) on delete set null,
  title text not null,
  metric_value integer not null default 0,
  created_at timestamptz not null default now(),
  primary key (room_id, week_start, award_key)
);

alter table public.family_rooms enable row level security;
alter table public.family_room_members enable row level security;
alter table public.family_weekly_pots enable row level security;
alter table public.family_weekly_activity enable row level security;
alter table public.family_goals enable row level security;
alter table public.family_daily_races enable row level security;
alter table public.family_race_events enable row level security;
alter table public.family_mission_claims enable row level security;
alter table public.family_weekly_awards enable row level security;

drop policy if exists family_rooms_read_member on public.family_rooms;
create policy family_rooms_read_member on public.family_rooms
  for select to authenticated
  using (
    exists (
      select 1 from public.family_room_members m
      where m.room_id = family_rooms.id
        and m.user_id = auth.uid()
        and m.active
    )
  );

drop policy if exists family_members_read_room on public.family_room_members;
create policy family_members_read_room on public.family_room_members
  for select to authenticated
  using (
    exists (
      select 1 from public.family_room_members mine
      where mine.room_id = family_room_members.room_id
        and mine.user_id = auth.uid()
        and mine.active
    )
  );

drop policy if exists family_pots_read_member on public.family_weekly_pots;
create policy family_pots_read_member on public.family_weekly_pots
  for select to authenticated
  using (
    exists (
      select 1 from public.family_room_members mine
      where mine.room_id = family_weekly_pots.room_id
        and mine.user_id = auth.uid()
        and mine.active
    )
  );

drop policy if exists family_activity_read_member on public.family_weekly_activity;
create policy family_activity_read_member on public.family_weekly_activity
  for select to authenticated
  using (
    exists (
      select 1 from public.family_room_members mine
      where mine.room_id = family_weekly_activity.room_id
        and mine.user_id = auth.uid()
        and mine.active
    )
  );

drop policy if exists family_goals_read_member on public.family_goals;
create policy family_goals_read_member on public.family_goals
  for select to authenticated
  using (
    exists (
      select 1 from public.family_room_members mine
      where mine.room_id = family_goals.room_id
        and mine.user_id = auth.uid()
        and mine.active
    )
  );

drop policy if exists family_daily_races_read_member on public.family_daily_races;
create policy family_daily_races_read_member on public.family_daily_races
  for select to authenticated
  using (
    exists (
      select 1 from public.family_room_members mine
      where mine.room_id = family_daily_races.room_id
        and mine.user_id = auth.uid()
        and mine.active
    )
  );

drop policy if exists family_race_events_read_member on public.family_race_events;
create policy family_race_events_read_member on public.family_race_events
  for select to authenticated
  using (
    exists (
      select 1 from public.family_room_members mine
      where mine.room_id = family_race_events.room_id
        and mine.user_id = auth.uid()
        and mine.active
    )
  );

drop policy if exists family_mission_claims_read_member on public.family_mission_claims;
create policy family_mission_claims_read_member on public.family_mission_claims
  for select to authenticated
  using (
    exists (
      select 1 from public.family_room_members mine
      where mine.room_id = family_mission_claims.room_id
        and mine.user_id = auth.uid()
        and mine.active
    )
  );

drop policy if exists family_weekly_awards_read_member on public.family_weekly_awards;
create policy family_weekly_awards_read_member on public.family_weekly_awards
  for select to authenticated
  using (
    exists (
      select 1 from public.family_room_members mine
      where mine.room_id = family_weekly_awards.room_id
        and mine.user_id = auth.uid()
        and mine.active
    )
  );

create or replace function public.current_family_week_start()
returns date
language sql
stable
as $$
  select date_trunc('week', now())::date
$$;

create or replace function public.current_family_room_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select m.room_id
  from public.family_room_members m
  where m.user_id = auth.uid()
    and m.active
  order by m.joined_at
  limit 1
$$;

drop function if exists public.my_family_room();
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
      coalesce(sum(a.honey_delta), 0)::integer as week_honey,
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

drop function if exists public.create_family_room(text);
create or replace function public.create_family_room(p_name text)
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
  v_code text;
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;

  if public.current_family_room_id() is not null then
    return query select * from public.my_family_room();
    return;
  end if;

  loop
    v_code := upper(substr(replace(uuid_generate_v4()::text, '-', ''), 1, 6));
    exit when not exists (select 1 from public.family_rooms where invite_code = v_code);
  end loop;

  insert into public.family_rooms(name, invite_code, owner_id)
  values (trim(p_name), v_code, auth.uid())
  returning id into v_room_id;

  insert into public.family_room_members(room_id, user_id, role)
  values (v_room_id, auth.uid(), 'owner');

  insert into public.family_weekly_pots(room_id, week_start)
  values (v_room_id, public.current_family_week_start())
  on conflict on constraint family_weekly_pots_pkey do nothing;

  insert into public.family_daily_races(room_id, race_date)
  values (v_room_id, current_date)
  on conflict on constraint family_daily_races_pkey do nothing;

  return query select * from public.my_family_room();
end;
$$;

drop function if exists public.join_family_room(text);
create or replace function public.join_family_room(p_code text)
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
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;

  select id into v_room_id
  from public.family_rooms
  where invite_code = upper(trim(p_code));

  if v_room_id is null then
    raise exception 'family room not found';
  end if;

  insert into public.family_room_members(room_id, user_id, role, active)
  values (v_room_id, auth.uid(), 'member', true)
  on conflict on constraint family_room_members_pkey
  do update set active = true;

  insert into public.family_weekly_pots(room_id, week_start)
  values (v_room_id, public.current_family_week_start())
  on conflict on constraint family_weekly_pots_pkey do nothing;

  insert into public.family_daily_races(room_id, race_date)
  values (v_room_id, current_date)
  on conflict on constraint family_daily_races_pkey do nothing;

  return query select * from public.my_family_room();
end;
$$;

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
  v_id uuid;
  v_honey integer := greatest(0, coalesce(p_honey_delta, 0));
  v_chapters integer := greatest(0, coalesce(p_chapters_delta, 0));
  v_race_points integer := 0;
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

  insert into public.family_weekly_pots(room_id, week_start)
  values (v_room_id, v_week_start)
  on conflict on constraint family_weekly_pots_pkey do nothing;

  insert into public.family_daily_races(room_id, race_date)
  values (v_room_id, current_date)
  on conflict on constraint family_daily_races_pkey do nothing;

  insert into public.family_weekly_activity(room_id, week_start, user_id, event_type, honey_delta, chapters_delta, source_key, note)
  values (v_room_id, v_week_start, auth.uid(), left(coalesce(p_event_type, 'activity'), 50), v_honey, v_chapters, p_source_key, left(coalesce(p_note, ''), 180))
  on conflict (room_id, user_id, source_key) where source_key is not null do nothing
  returning id into v_id;

  if v_id is not null then
	    v_race_points := case
	      when coalesce(p_event_type, '') = 'chapter_read' then (v_chapters * 100) + least(50, v_honey)
	      when coalesce(p_event_type, '') = 'double_next_bonus' then 120
	      when coalesce(p_event_type, '') = 'comeback_bonus' then 60
	      when coalesce(p_event_type, '') = 'sunday_strong' then 150
	      else 0
	    end;

    if v_race_points <> 0 then
      insert into public.family_race_events(room_id, race_date, user_id, actor_id, event_type, points_delta, source_key, note)
      values (
        v_room_id,
        current_date,
        auth.uid(),
        auth.uid(),
        left(coalesce(p_event_type, 'activity'), 50),
        v_race_points,
        case when p_source_key is null then null else 'race:' || p_source_key end,
        left(coalesce(p_note, ''), 180)
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

  perform * from public.record_family_activity(
    'goal_stake',
    v_wager,
    0,
    'goal-stake:' || v_goal_id::text,
    'Goal stake added to the weekly pot'
  );

  return query select v_goal_id, v_honey - v_wager;
end;
$$;

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

  if v_reward > 0 then
    update public.family_weekly_pots fwp
    set pot_honey = fwp.pot_honey + v_reward,
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

  return query select v_claimed, v_reward, coalesce(v_pot, 0);
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
  v_race_date date := current_date;
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
    select 1 from public.family_room_members
    where room_id = v_room_id
      and user_id = v_target_id
      and active
  ) then
    raise exception 'target is not in your family room';
  end if;

  if v_powerup = 'turbo' then
    v_target_id := auth.uid();
    v_cost := 125;
    v_delta := 180;
  elsif v_powerup = 'honey_slick' then
    if v_target_id = auth.uid() then
      raise exception 'pick someone else to slow down';
    end if;
    v_cost := 75;
    v_delta := -150;
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
  set state = jsonb_set(state, '{honey}', to_jsonb(v_honey - v_cost), true),
      updated_at = now()
  where user_id = auth.uid();

  insert into public.family_weekly_pots(room_id, week_start)
  values (v_room_id, v_week_start)
  on conflict on constraint family_weekly_pots_pkey do nothing;

  insert into public.family_daily_races(room_id, race_date)
  values (v_room_id, v_race_date)
  on conflict on constraint family_daily_races_pkey do nothing;

  insert into public.family_race_events(room_id, race_date, user_id, actor_id, event_type, points_delta, note)
  values (
    v_room_id,
    v_race_date,
    v_target_id,
    auth.uid(),
    v_powerup,
    v_delta,
    case when v_powerup = 'turbo' then 'Turbo boost' else 'Honey Trap setback' end
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
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;

  v_room_id := public.current_family_room_id();
  if v_room_id is null then
    raise exception 'join a family room first';
  end if;

  with stats as (
    select
      m.user_id,
      coalesce(p.display_name, 'Reader') as display_name,
      coalesce(up.best_streak, 0) as best_streak,
      coalesce(sum(a.chapters_delta), 0)::integer as week_chapters,
      coalesce(sum(a.honey_delta), 0)::integer as week_honey,
      coalesce(sum(a.honey_delta) filter (where a.event_type = 'comeback_bonus'), 0)::integer as comeback_honey
    from public.family_room_members m
    left join public.profiles p on p.id = m.user_id
    left join public.user_progress up on up.user_id = m.user_id
    left join public.family_weekly_activity a
      on a.room_id = m.room_id
     and a.user_id = m.user_id
     and a.week_start = v_week_start
    where m.room_id = v_room_id
      and m.active
    group by m.user_id, p.display_name, up.best_streak
  ),
  race_scores as (
    select user_id, coalesce(sum(points_delta), 0)::integer as race_points
    from public.family_race_events
    where room_id = v_room_id
      and race_date >= v_week_start
      and race_date <= (v_week_start + 6)
    group by user_id
  ),
  sunday_scores as (
    select user_id, coalesce(sum(honey_delta), 0)::integer as sunday_honey
    from public.family_weekly_activity
    where room_id = v_room_id
      and week_start = v_week_start
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
  select v_room_id, v_week_start, award_key, winner_id, title, greatest(0, coalesce(metric_value, 0))
  from all_awards
  where winner_id is not null
  on conflict (room_id, week_start, award_key)
  do update set
    winner_id = excluded.winner_id,
    title = excluded.title,
    metric_value = excluded.metric_value,
    created_at = now();

  select count(*)::integer into v_count
  from public.family_weekly_awards
  where room_id = v_room_id
    and week_start = v_week_start;

  return query select v_count;
end;
$$;

create or replace function public.prevent_user_progress_regression()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' then
    if new.total_chapters < old.total_chapters then
      raise exception 'refusing to reduce total_chapters from % to %', old.total_chapters, new.total_chapters;
    end if;

    if new.books_finished_count < old.books_finished_count then
      raise exception 'refusing to reduce books_finished_count from % to %', old.books_finished_count, new.books_finished_count;
    end if;

    if new.best_streak < old.best_streak then
      new.best_streak := old.best_streak;
    end if;
  end if;

  new.state := jsonb_set(coalesce(new.state, '{}'::jsonb), '{totalChapters}', to_jsonb(new.total_chapters), true);
  new.state := jsonb_set(new.state, '{booksFinishedCount}', to_jsonb(new.books_finished_count), true);
  new.state := jsonb_set(new.state, '{bestStreak}', to_jsonb(new.best_streak), true);

  return new;
end;
$$;

drop trigger if exists user_progress_no_regression on public.user_progress;
create trigger user_progress_no_regression
before update on public.user_progress
for each row
execute function public.prevent_user_progress_regression();

grant execute on function public.current_family_week_start() to authenticated;
grant execute on function public.current_family_room_id() to authenticated;
grant execute on function public.my_family_room() to authenticated;
grant execute on function public.create_family_room(text) to authenticated;
grant execute on function public.join_family_room(text) to authenticated;
grant execute on function public.record_family_activity(text, integer, integer, text, text) to authenticated;
grant execute on function public.create_family_goal(uuid, integer, integer, date, text) to authenticated;
grant execute on function public.settle_family_goal(uuid) to authenticated;
grant execute on function public.claim_family_missions() to authenticated;
grant execute on function public.use_family_race_powerup(uuid, text) to authenticated;
grant execute on function public.settle_family_daily_race() to authenticated;
grant execute on function public.settle_family_weekly_season() to authenticated;
