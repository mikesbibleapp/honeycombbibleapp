alter table public.profiles
  add column if not exists age_bracket text;

alter table public.profiles
  drop constraint if exists profiles_age_bracket_check;

alter table public.profiles
  add constraint profiles_age_bracket_check
  check (
    age_bracket is null or age_bracket in (
      'kid_6_8',
      'kid_9_11',
      'tween_12_13',
      'teen_14_17',
      'adult_18_plus'
    )
  );

comment on column public.profiles.age_bracket is
  'Optional broad age bracket used to balance Family Cup race points. It never changes Bible progress.';

update public.profiles
set age_bracket = 'kid_9_11'
where age_bracket is null
  and lower(coalesce(display_name, '')) like '%gage%';

update public.profiles
set age_bracket = 'tween_12_13'
where age_bracket is null
  and (
    lower(coalesce(display_name, '')) like '%brod%'
    or lower(coalesce(display_name, '')) like '%jett%'
    or lower(coalesce(display_name, '')) like '%jet%'
  );

update public.profiles
set age_bracket = 'adult_18_plus'
where age_bracket is null
  and (
    lower(coalesce(display_name, '')) like '%mike%'
    or lower(coalesce(display_name, '')) like '%dave%'
  );

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
    when 'kid_6_8' then 175
    when 'kid_9_11' then 160
    when 'tween_12_13' then 130
    when 'teen_14_17' then 115
    else 100
  end;

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
         and re.race_date = current_date
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
        current_date,
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
