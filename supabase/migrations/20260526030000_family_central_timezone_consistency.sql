-- Family-race date math anchored to America/Chicago instead of UTC.
-- Without this, reading after 7pm Central gets bucketed into "tomorrow's"
-- race because Postgres current_date defaults to UTC. Symptom: late-evening
-- readers can each "win" their own personal race because the day boundary
-- moves before 9pm Central settle time.
--
-- Also includes a one-time data backfill that rewrites past
-- family_race_events.race_date to the Central calendar date.

create or replace function public.current_family_week_start()
returns date
language sql stable
as $$
  select date_trunc('week', (now() at time zone 'America/Chicago'))::date;
$$;

create or replace function public.family_central_today()
returns date
language sql stable
as $$
  select (now() at time zone 'America/Chicago')::date;
$$;

grant execute on function public.current_family_week_start() to authenticated;
grant execute on function public.family_central_today() to authenticated;

-- Backfill: re-bucket race events that were tagged with UTC race_date.
update public.family_race_events
set race_date = (created_at at time zone 'America/Chicago')::date
where race_date <> (created_at at time zone 'America/Chicago')::date;

-- The five RPCs that derive race_date or filter created_at::date are
-- redefined in the parallel apply_migration calls (record_family_activity,
-- use_family_race_powerup, my_family_room, claim_family_missions,
-- settle_family_daily_race). Each call public.family_central_today() in
-- place of current_date and uses (created_at at time zone 'America/Chicago')
-- when bucketing events by day.
