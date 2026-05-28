-- Weekly season guard.
-- The weekly pot should close the week that just ended, not the week currently
-- in progress. This keeps the family race automatic and prevents mid-week
-- manual closeouts from freezing the live pot.

create or replace function public.settle_family_weekly_season()
returns table(award_count integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid;
  v_today date := public.family_central_today();
  v_current_week_start date := public.current_family_week_start();
  v_target_week date;
  v_count integer := 0;
  v_total integer := 0;
  v_dow integer;
  v_prev_status text;
  r record;
begin
  v_dow := extract(isodow from v_today)::integer;
  v_target_week := v_current_week_start - 7;

  -- No auth context (pg_cron) settles every room, but only on Monday after
  -- the previous week has actually ended.
  if auth.uid() is null then
    if v_dow <> 1 then
      return query select 0;
      return;
    end if;

    for r in
      select distinct id
      from public.family_rooms
    loop
      perform public._settle_family_weekly_season_for_room(r.id, v_target_week);
      v_total := v_total + 1;
    end loop;

    return query select v_total;
    return;
  end if;

  v_room_id := public.current_family_room_id();
  if v_room_id is null then
    raise exception 'join a family room first';
  end if;

  if v_dow <> 1 then
    raise exception 'Weekly season closes Monday morning after Sunday finishes';
  end if;

  select status into v_prev_status
  from public.family_weekly_pots
  where room_id = v_room_id
    and week_start = v_target_week;

  if v_prev_status is null then
    raise exception 'No completed weekly pot is ready yet';
  end if;

  if v_prev_status = 'settled' then
    select count(*)::integer into v_count
    from public.family_weekly_awards
    where room_id = v_room_id
      and week_start = v_target_week;
    return query select v_count;
    return;
  end if;

  v_count := public._settle_family_weekly_season_for_room(v_room_id, v_target_week);
  return query select v_count;
end;
$$;

grant execute on function public.settle_family_weekly_season() to authenticated;

-- Repair any pot that was accidentally closed before the current Central week
-- finished. Generated trophies can be recalculated at the real closeout.
with reopened as (
  update public.family_weekly_pots
  set status = 'active',
      winner_id = null,
      settled_at = null,
      updated_at = now()
  where week_start = public.current_family_week_start()
    and status = 'settled'
    and public.family_central_today() < (week_start + 7)
  returning room_id, week_start
)
delete from public.family_weekly_awards a
using reopened r
where a.room_id = r.room_id
  and a.week_start = r.week_start;
