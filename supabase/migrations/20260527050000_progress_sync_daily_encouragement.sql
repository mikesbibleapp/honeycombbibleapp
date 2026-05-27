-- Progress sync + daily encouragement
--
-- Repairs server progress from verified family chapter activity and keeps
-- future chapter reads reconciled immediately. Bible progress only moves up.
-- Also adds one cached daily encouragement per Central date.

create or replace function public.daily_encouragement_fallback(
  p_date date default public.family_central_today()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_index integer := mod(extract(doy from coalesce(p_date, current_date))::integer, 7);
begin
  return case v_index
    when 0 then jsonb_build_object(
      'title', 'Sweeter Than Honey',
      'opening_line', 'God''s voice was never meant to feel far away.',
      'reflection', 'The Bible is not just a book to finish. It is a quiet place to meet with God. Even one chapter today can steady your heart and remind you that He is near.',
      'scripture', jsonb_build_object(
        'reference', 'Psalm 119:103',
        'text', 'How sweet are your promises to my taste, more than honey to my mouth!'
      ),
      'prayer_or_prompt', 'God, help me love Your words today.'
    )
    when 1 then jsonb_build_object(
      'title', 'Near In The Word',
      'opening_line', 'A small moment with Scripture can become a deep breath for your soul.',
      'reflection', 'You do not have to rush. Open God''s Word and let one true thing stay with you today. The Lord is patient, kind, and near.',
      'scripture', jsonb_build_object(
        'reference', 'Psalm 119:105',
        'text', 'Your word is a lamp to my feet, and a light for my path.'
      ),
      'prayer_or_prompt', 'Jesus, walk with me as I listen.'
    )
    when 2 then jsonb_build_object(
      'title', 'Quiet Hunger',
      'opening_line', 'Your heart was made to be fed by more than noise.',
      'reflection', 'God''s Word gives your soul something real to hold. Read slowly today. Let the sweetness of Scripture pull your thoughts back toward Him.',
      'scripture', jsonb_build_object(
        'reference', 'Matthew 4:4',
        'text', 'Man shall not live by bread alone, but by every word that proceeds out of God''s mouth.'
      ),
      'prayer_or_prompt', 'Lord, give me hunger for what is true.'
    )
    when 3 then jsonb_build_object(
      'title', 'Day And Night',
      'opening_line', 'One verse can travel with you longer than you think.',
      'reflection', 'Let God''s Word be something you return to through the day. Not as pressure, but as peace. He is willing to meet you in ordinary moments.',
      'scripture', jsonb_build_object(
        'reference', 'Psalm 1:2',
        'text', 'But his delight is in Yahweh''s law. On his law he meditates day and night.'
      ),
      'prayer_or_prompt', 'Father, keep Your Word close to my mind today.'
    )
    when 4 then jsonb_build_object(
      'title', 'Rest In His Voice',
      'opening_line', 'God is not asking you to impress Him today.',
      'reflection', 'Come to Scripture as someone loved. Read to remember who He is, not to prove yourself. His nearness is better than hurry.',
      'scripture', jsonb_build_object(
        'reference', 'Matthew 11:28',
        'text', 'Come to me, all you who labor and are heavily burdened, and I will give you rest.'
      ),
      'prayer_or_prompt', 'Jesus, help me receive Your rest.'
    )
    when 5 then jsonb_build_object(
      'title', 'Abide Today',
      'opening_line', 'The branch lives by staying close to the vine.',
      'reflection', 'Reading today is not just progress on a plan. It is a way to stay near Jesus. Let His words settle into you and bear fruit quietly.',
      'scripture', jsonb_build_object(
        'reference', 'John 15:5',
        'text', 'I am the vine. You are the branches. He who remains in me, and I in him, bears much fruit.'
      ),
      'prayer_or_prompt', 'Jesus, teach me to abide in You.'
    )
    else jsonb_build_object(
      'title', 'A Word For Today',
      'opening_line', 'God can meet you in one honest chapter.',
      'reflection', 'Before the day gets loud, give your heart a place to listen. The Lord speaks through His Word with patience, mercy, and light for the next step.',
      'scripture', jsonb_build_object(
        'reference', 'Psalm 119:18',
        'text', 'Open my eyes, that I may see wondrous things out of your law.'
      ),
      'prayer_or_prompt', 'God, open my eyes to Your Word.'
    )
  end;
end;
$$;

create table if not exists public.daily_encouragements (
  encouragement_date date primary key,
  payload jsonb not null,
  source text not null default 'fallback',
  created_at timestamptz not null default now()
);

alter table public.daily_encouragements enable row level security;

drop policy if exists "daily_encouragements readable" on public.daily_encouragements;
create policy "daily_encouragements readable"
on public.daily_encouragements
for select
to anon, authenticated
using (true);

create or replace function public.get_daily_encouragement()
returns table(
  encouragement_date date,
  payload jsonb,
  source text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_date date := public.family_central_today();
begin
  insert into public.daily_encouragements(encouragement_date, payload, source)
  values (v_date, public.daily_encouragement_fallback(v_date), 'fallback')
  on conflict on constraint daily_encouragements_pkey do nothing;

  return query
  select de.encouragement_date, de.payload, de.source, de.created_at
  from public.daily_encouragements de
  where de.encouragement_date = v_date;
end;
$$;

create or replace function public.family_activity_verified_progress(
  p_target_user_id uuid
)
returns table(
  baseline_progress integer,
  unique_chapters integer,
  verified_total integer,
  done_patch jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  with activity as (
    select a.event_type, a.chapters_delta, a.source_key
    from public.family_weekly_activity a
    where a.user_id = p_target_user_id
  ),
  baseline as (
    select coalesce(max(chapters_delta), 0)::integer as chapters
    from activity
    where event_type = 'baseline_progress'
  ),
  chapter_sources as (
    select distinct source_key
    from activity
    where event_type = 'chapter_read'
      and source_key is not null
      and source_key ~ '^chapter:.+:[0-9]+$'
  ),
  parsed as (
    select
      (regexp_match(source_key, '^chapter:(.*):([0-9]+)$'))[1] as book_name,
      (regexp_match(source_key, '^chapter:(.*):([0-9]+)$'))[2] as chapter_num
    from chapter_sources
  ),
  patch as (
    select coalesce(jsonb_object_agg(book_name || '|' || chapter_num, true), '{}'::jsonb) as done_patch
    from parsed
    where book_name is not null
      and chapter_num is not null
  ),
  counts as (
    select count(*)::integer as unique_chapters
    from chapter_sources
  )
  select
    baseline.chapters,
    counts.unique_chapters,
    (baseline.chapters + counts.unique_chapters)::integer,
    patch.done_patch
  from baseline, counts, patch;
$$;

create or replace function public.reconcile_user_progress_from_family_activity(
  p_target_user_id uuid
)
returns table(
  user_id uuid,
  old_total integer,
  repaired_total integer,
  done_keys_added integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_baseline integer := 0;
  v_unique integer := 0;
  v_verified integer := 0;
  v_done_patch jsonb := '{}'::jsonb;
  v_state jsonb := '{}'::jsonb;
  v_state_done jsonb := '{}'::jsonb;
  v_merged_done jsonb := '{}'::jsonb;
  v_current_total integer := 0;
  v_state_total integer := 0;
  v_repaired_total integer := 0;
  v_done_added integer := 0;
  v_has_progress boolean := false;
begin
  if p_target_user_id is null then
    return;
  end if;

  select f.baseline_progress, f.unique_chapters, f.verified_total, f.done_patch
    into v_baseline, v_unique, v_verified, v_done_patch
  from public.family_activity_verified_progress(p_target_user_id) f;

  v_verified := coalesce(v_verified, 0);
  v_done_patch := coalesce(v_done_patch, '{}'::jsonb);
  if v_verified <= 0 and v_done_patch = '{}'::jsonb then
    return;
  end if;

  select up.state, up.total_chapters
    into v_state, v_current_total
  from public.user_progress up
  where up.user_id = p_target_user_id
  for update;

  v_has_progress := found;
  v_state := coalesce(v_state, '{}'::jsonb);
  v_current_total := coalesce(v_current_total, 0);

  if (v_state->>'totalChapters') ~ '^[0-9]+$' then
    v_state_total := (v_state->>'totalChapters')::integer;
  end if;

  v_repaired_total := greatest(v_current_total, v_state_total, v_verified);
  v_state_done := case
    when jsonb_typeof(v_state->'done') = 'object' then v_state->'done'
    else '{}'::jsonb
  end;

  select count(*)::integer
    into v_done_added
  from jsonb_object_keys(v_done_patch) k(key)
  where not (v_state_done ? k.key);

  v_merged_done := v_state_done || v_done_patch;
  v_state := jsonb_set(v_state, '{done}', v_merged_done, true);
  v_state := jsonb_set(v_state, '{totalChapters}', to_jsonb(v_repaired_total), true);
  v_state := jsonb_set(
    v_state,
    '{cursor}',
    to_jsonb(greatest(
      least(1189, v_repaired_total),
      case when (v_state->>'cursor') ~ '^[0-9]+$' then least(1189, (v_state->>'cursor')::integer) else 0 end
    )),
    true
  );

  if v_has_progress then
    update public.user_progress up
    set
      state = v_state,
      total_chapters = v_repaired_total,
      updated_at = now()
    where up.user_id = p_target_user_id;
  else
    insert into public.user_progress(user_id, state, total_chapters)
    values (p_target_user_id, v_state, v_repaired_total);
  end if;

  return query select p_target_user_id, v_current_total, v_repaired_total, v_done_added;
end;
$$;

create or replace function public.reconcile_family_progress_from_activity()
returns table(
  user_id uuid,
  display_name text,
  old_total integer,
  repaired_total integer,
  done_keys_added integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member record;
  v_row record;
begin
  for v_member in
    select distinct m.user_id, coalesce(p.display_name, 'Reader') as display_name
    from public.family_room_members m
    left join public.profiles p on p.id = m.user_id
    where m.active = true
    order by coalesce(p.display_name, 'Reader')
  loop
    for v_row in
      select *
      from public.reconcile_user_progress_from_family_activity(v_member.user_id)
    loop
      user_id := v_row.user_id;
      display_name := v_member.display_name;
      old_total := v_row.old_total;
      repaired_total := v_row.repaired_total;
      done_keys_added := v_row.done_keys_added;
      return next;
    end loop;
  end loop;
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
    if coalesce(p_event_type, '') = 'chapter_read' then
      perform public.reconcile_user_progress_from_family_activity(auth.uid());
    end if;

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
          greatest(0, coalesce(sum(re.points_delta), 0)::integer) as points
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

grant select on table public.daily_encouragements to anon, authenticated;
grant execute on function public.daily_encouragement_fallback(date) to anon, authenticated;
grant execute on function public.get_daily_encouragement() to anon, authenticated;
grant execute on function public.family_activity_verified_progress(uuid) to authenticated;
grant execute on function public.reconcile_family_progress_from_activity() to authenticated;
grant execute on function public.record_family_activity(text, integer, integer, text, text) to authenticated;
