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

alter table public.family_rooms enable row level security;
alter table public.family_room_members enable row level security;
alter table public.family_weekly_pots enable row level security;
alter table public.family_weekly_activity enable row level security;
alter table public.family_goals enable row level security;

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
  goals jsonb
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid;
  v_week_start date := public.current_family_week_start();
begin
  v_room_id := public.current_family_room_id();
  if v_room_id is null then
    return;
  end if;

  insert into public.family_weekly_pots(room_id, week_start)
  values (v_room_id, v_week_start)
  on conflict on constraint family_weekly_pots_pkey do nothing;

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
      coalesce(sum(a.honey_delta), 0)::integer as week_honey
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
  ranked as (
    select
      ms.*,
      row_number() over (
        order by ms.week_chapters desc, ms.week_honey desc, ms.total_chapters desc, ms.display_name asc
      )::integer as family_rank
    from member_stats ms
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
    )
  from public.family_rooms r
  join public.family_room_members mine
    on mine.room_id = r.id
   and mine.user_id = auth.uid()
   and mine.active
  left join public.family_weekly_pots pot
    on pot.room_id = r.id
   and pot.week_start = v_week_start
  left join ranked me on me.user_id = auth.uid()
  left join ranked leader on leader.family_rank = 1
  where r.id = v_room_id;
end;
$$;

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
  goals jsonb
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

  return query select * from public.my_family_room();
end;
$$;

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
  goals jsonb
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
  on conflict (room_id, week_start) do nothing;

  insert into public.family_weekly_activity(room_id, week_start, user_id, event_type, honey_delta, chapters_delta, source_key, note)
  values (v_room_id, v_week_start, auth.uid(), left(coalesce(p_event_type, 'activity'), 50), v_honey, v_chapters, p_source_key, left(coalesce(p_note, ''), 180))
  on conflict (room_id, user_id, source_key) where source_key is not null do nothing
  returning id into v_id;

  if v_id is not null then
    update public.family_weekly_pots
    set pot_honey = pot_honey + v_honey,
        updated_at = now()
    where room_id = v_room_id
      and week_start = v_week_start
    returning family_weekly_pots.pot_honey into v_pot;
  else
    select family_weekly_pots.pot_honey into v_pot
    from public.family_weekly_pots
    where room_id = v_room_id
      and week_start = v_week_start;
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

grant execute on function public.current_family_week_start() to authenticated;
grant execute on function public.current_family_room_id() to authenticated;
grant execute on function public.my_family_room() to authenticated;
grant execute on function public.create_family_room(text) to authenticated;
grant execute on function public.join_family_room(text) to authenticated;
grant execute on function public.record_family_activity(text, integer, integer, text, text) to authenticated;
grant execute on function public.create_family_goal(uuid, integer, integer, date, text) to authenticated;
grant execute on function public.settle_family_goal(uuid) to authenticated;
