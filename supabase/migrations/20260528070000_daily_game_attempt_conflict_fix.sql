-- Fix claim_daily_game_attempt ambiguity between the output column named
-- game_date and the daily_game_attempts.game_date conflict target.

create or replace function public.claim_daily_game_attempt(
  p_game_id text,
  p_seed integer,
  p_score integer
)
returns table(
  inserted boolean,
  game_date date,
  game_id text,
  seed integer,
  score integer,
  points_awarded integer,
  read_deadline_at timestamptz,
  doubled_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid := public.current_family_room_id();
  v_game record;
  v_attempt public.daily_game_attempts%rowtype;
  v_inserted boolean := false;
  v_score integer := greatest(0, least(100000, coalesce(p_score, 0)));
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  if v_room_id is null then
    raise exception 'join a family room first';
  end if;

  select * into v_game
  from public.daily_game_for_room(v_room_id, public.family_central_today())
  limit 1;

  if v_game.game_id <> p_game_id or v_game.seed <> p_seed then
    raise exception 'today''s game has changed; refresh and try again';
  end if;

  insert into public.daily_game_attempts(
    family_room_id,
    user_id,
    game_date,
    game_id,
    seed,
    score,
    base_points,
    points_awarded,
    read_deadline_at
  )
  values (
    v_room_id,
    auth.uid(),
    v_game.game_date,
    v_game.game_id,
    v_game.seed,
    v_score,
    v_game.base_points,
    v_game.base_points,
    now() + interval '10 minutes'
  )
  on conflict on constraint daily_game_attempts_family_room_id_user_id_game_date_key do nothing
  returning * into v_attempt;

  v_inserted := v_attempt.id is not null;

  if v_inserted then
    insert into public.family_daily_races(room_id, race_date)
    values (v_room_id, v_game.game_date)
    on conflict on constraint family_daily_races_pkey do nothing;

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
      v_game.game_date,
      auth.uid(),
      auth.uid(),
      'daily_game',
      v_game.base_points,
      'daily-game:' || v_game.game_date::text || ':' || auth.uid()::text,
      'Game of the Day base Cup points'
    )
    on conflict (room_id, user_id, source_key) where source_key is not null do nothing;
  else
    select * into v_attempt
    from public.daily_game_attempts a
    where a.family_room_id = v_room_id
      and a.user_id = auth.uid()
      and a.game_date = v_game.game_date
    limit 1;
  end if;

  return query
  select
    v_inserted,
    v_attempt.game_date,
    v_attempt.game_id,
    v_attempt.seed,
    v_attempt.score,
    v_attempt.points_awarded,
    v_attempt.read_deadline_at,
    v_attempt.doubled_at;
end;
$$;

grant execute on function public.claim_daily_game_attempt(text, integer, integer) to authenticated;
