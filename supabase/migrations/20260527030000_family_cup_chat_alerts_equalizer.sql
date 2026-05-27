-- Family Cup chat, push-alert support, and softer Equalizer behavior.
-- This keeps Bible progress untouched; only Family Cup messages and race events change.

create table if not exists public.push_subscriptions (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null,
  p256dh text not null,
  auth text not null,
  user_agent text,
  last_notified_date date,
  created_at timestamptz not null default now(),
  notifications_today jsonb default '{}'::jsonb
);

create unique index if not exists push_subscriptions_endpoint_key
  on public.push_subscriptions(endpoint);

alter table public.push_subscriptions enable row level security;

drop policy if exists push_subscriptions_all_own on public.push_subscriptions;
create policy push_subscriptions_all_own on public.push_subscriptions
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create table if not exists public.family_messages (
  id uuid primary key default uuid_generate_v4(),
  room_id uuid not null references public.family_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  body text not null,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  constraint family_messages_body_len
    check (char_length(trim(body)) between 1 and 280)
);

create index if not exists family_messages_room_created_idx
  on public.family_messages(room_id, created_at desc);

create index if not exists family_messages_user_idx
  on public.family_messages(user_id);

alter table public.family_messages enable row level security;

drop policy if exists family_messages_read_member on public.family_messages;
create policy family_messages_read_member on public.family_messages
  for select to authenticated
  using (
    exists (
      select 1
      from public.family_room_members mine
      where mine.room_id = family_messages.room_id
        and mine.user_id = auth.uid()
        and mine.active
    )
  );

drop policy if exists family_messages_insert_member on public.family_messages;
create policy family_messages_insert_member on public.family_messages
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1
      from public.family_room_members mine
      where mine.room_id = family_messages.room_id
        and mine.user_id = auth.uid()
        and mine.active
    )
  );

drop policy if exists family_messages_update_own on public.family_messages;
-- Updates happen through delete_family_message() so clients cannot edit sent text.

create or replace function public.send_family_message(p_body text)
returns table(id uuid, created_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid;
  v_body text;
  v_id uuid;
  v_created_at timestamptz;
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;

  v_room_id := public.current_family_room_id();
  if v_room_id is null then
    raise exception 'join a family room first';
  end if;

  v_body := trim(regexp_replace(coalesce(p_body, ''), '[\r\n\t]+', ' ', 'g'));
  v_body := regexp_replace(v_body, '\s+', ' ', 'g');

  if char_length(v_body) < 1 then
    raise exception 'message cannot be empty';
  end if;
  if char_length(v_body) > 280 then
    raise exception 'message is too long';
  end if;

  insert into public.family_messages(room_id, user_id, body)
  values (v_room_id, auth.uid(), v_body)
  returning family_messages.id, family_messages.created_at
    into v_id, v_created_at;

  return query select v_id, v_created_at;
end;
$$;

create or replace function public.family_message_board(p_limit integer default 30)
returns table(
  id uuid,
  user_id uuid,
  display_name text,
  body text,
  created_at timestamptz,
  is_mine boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid;
  v_limit integer := least(50, greatest(1, coalesce(p_limit, 30)));
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;

  v_room_id := public.current_family_room_id();
  if v_room_id is null then
    raise exception 'join a family room first';
  end if;

  return query
  with recent as (
    select
      fm.id,
      fm.user_id,
      coalesce(p.display_name, 'Reader') as display_name,
      fm.body,
      fm.created_at,
      (fm.user_id = auth.uid()) as is_mine
    from public.family_messages fm
    left join public.profiles p
      on p.id = fm.user_id
    where fm.room_id = v_room_id
      and fm.deleted_at is null
    order by fm.created_at desc
    limit v_limit
  )
  select
    recent.id,
    recent.user_id,
    recent.display_name,
    recent.body,
    recent.created_at,
    recent.is_mine
  from recent
  order by recent.created_at asc;
end;
$$;

create or replace function public.delete_family_message(p_message_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid;
  v_count integer := 0;
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;

  v_room_id := public.current_family_room_id();
  if v_room_id is null then
    raise exception 'join a family room first';
  end if;

  update public.family_messages fm
     set deleted_at = now()
   where fm.id = p_message_id
     and fm.room_id = v_room_id
     and fm.user_id = auth.uid()
     and fm.deleted_at is null;

  get diagnostics v_count = row_count;
  return v_count > 0;
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

grant execute on function public.send_family_message(text) to authenticated;
grant execute on function public.family_message_board(integer) to authenticated;
grant execute on function public.delete_family_message(uuid) to authenticated;
grant execute on function public.use_family_race_powerup(uuid, text) to authenticated;
