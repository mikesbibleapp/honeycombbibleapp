-- The original no-repeat guard compared today's raw bucket to yesterday's raw
-- bucket. If yesterday was itself advanced by the guard, the same displayed
-- game could still repeat. Compare against yesterday's displayed game instead.

create or replace function public.daily_game_for_room(
  p_family_room_id uuid default null,
  p_game_date date default public.family_central_today()
)
returns table(
  game_date date,
  game_id text,
  seed integer,
  base_points integer,
  doubled_points integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_room_id uuid := coalesce(p_family_room_id, public.current_family_room_id());
  v_game_date date := coalesce(p_game_date, public.family_central_today());
  v_games text[] := public.daily_game_ids();
  v_count integer := array_length(v_games, 1);
  v_index integer;
  v_yesterday_index integer;
  v_day_before_index integer;
begin
  if v_room_id is null then
    raise exception 'join a family room first';
  end if;

  if auth.uid() is not null and not exists (
    select 1
    from public.family_room_members mine
    where mine.room_id = v_room_id
      and mine.user_id = auth.uid()
      and mine.active
  ) then
    raise exception 'not a member of that family room';
  end if;

  v_index := public.surprise_hash_bucket(
    v_room_id::text || ':' || v_game_date::text || ':daily-game-v1',
    v_count
  ) + 1;
  v_yesterday_index := public.surprise_hash_bucket(
    v_room_id::text || ':' || (v_game_date - 1)::text || ':daily-game-v1',
    v_count
  ) + 1;
  v_day_before_index := public.surprise_hash_bucket(
    v_room_id::text || ':' || (v_game_date - 2)::text || ':daily-game-v1',
    v_count
  ) + 1;

  if v_yesterday_index = v_day_before_index then
    v_yesterday_index := (v_yesterday_index % v_count) + 1;
  end if;

  if v_index = v_yesterday_index then
    v_index := (v_index % v_count) + 1;
  end if;

  return query
  select
    v_game_date,
    v_games[v_index],
    public.surprise_hash_bucket(
      v_room_id::text || ':' || v_game_date::text || ':daily-game-seed-v1',
      2147483000
    ) + 1,
    25,
    50;
end;
$$;

grant execute on function public.daily_game_for_room(uuid, date) to authenticated;
