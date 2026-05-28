-- Daily Surprise Build 1
-- Additive family events layered on top of Bible progress, Family Cup, honey,
-- push subscriptions, and auth. No Bible progress rows are decreased or moved.

alter table public.family_room_members
  add column if not exists last_seen_at timestamptz;

create table if not exists public.family_surprises (
  id uuid primary key default gen_random_uuid(),
  family_room_id uuid not null references public.family_rooms(id) on delete cascade,
  surprise_type text not null check (
    surprise_type in (
      'honey_storm',
      'flash_race',
      'mystery_box',
      'showdown',
      'crown_hunt',
      'wildcard_day',
      'swarm'
    )
  ),
  surprise_date date not null,
  start_at timestamptz not null,
  end_at timestamptz not null,
  payload jsonb not null default '{}'::jsonb,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (family_room_id, surprise_date)
);

create index if not exists family_surprises_room_active_idx
  on public.family_surprises(family_room_id, start_at, end_at)
  where resolved_at is null;

alter table public.family_surprises enable row level security;

drop policy if exists family_surprises_read_member on public.family_surprises;
create policy family_surprises_read_member on public.family_surprises
  for select to authenticated
  using (
    exists (
      select 1
      from public.family_room_members mine
      where mine.room_id = family_surprises.family_room_id
        and mine.user_id = auth.uid()
        and mine.active
        and mine.joined_at <= now() - interval '24 hours'
    )
  );

-- Backfill the new multi-source boost structure from the old single-field
-- client state. This preserves users who currently have a 2x boost active.
with boosted as (
  select
    up.user_id,
    up.state,
    nullif(up.state->>'honeyBoostUntil', '') as legacy_until
  from public.user_progress up
  where up.state ? 'honeyBoostUntil'
)
update public.user_progress up
set state = jsonb_set(
      coalesce(up.state, '{}'::jsonb),
      '{honeyBoosts}',
      coalesce(up.state->'honeyBoosts', '[]'::jsonb) ||
        jsonb_build_array(
          jsonb_build_object(
            'source', 'legacy',
            'multiplier', 2,
            'until', boosted.legacy_until
          )
        ),
      true
    ),
    updated_at = now()
from boosted
where boosted.user_id = up.user_id
  and boosted.legacy_until is not null
  and boosted.legacy_until::timestamptz > now()
  and not exists (
    select 1
    from jsonb_array_elements(coalesce(up.state->'honeyBoosts', '[]'::jsonb)) as existing(boost)
    where existing.boost->>'source' = 'legacy'
      and existing.boost->>'until' = boosted.legacy_until
  );

create or replace function public.surprise_cosmetic_pool()
returns text[]
language sql
immutable
as $$
  select array[
    'ark-cruiser',
    'desert-chariot',
    'royal-lion',
    'sea-split',
    'fire-path',
    'royal-confetti',
    'gold-ring',
    'royal-blue',
    'sunday-crown'
  ]::text[]
$$;

create or replace function public.surprise_hash_bucket(p_seed text, p_mod integer)
returns integer
language sql
immutable
as $$
  select (
    (('x' || substr(md5(coalesce(p_seed, '')), 1, 8))::bit(32)::bigint)
    % greatest(1, p_mod)
  )::integer
$$;

create or replace function public.surprise_add_user_honey(
  p_user_id uuid,
  p_delta integer
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_delta integer := greatest(0, coalesce(p_delta, 0));
  v_honey integer := 0;
begin
  insert into public.user_progress(user_id, state, total_chapters)
  values (p_user_id, jsonb_build_object('honey', v_delta), 0)
  on conflict (user_id) do update
    set state = jsonb_set(
          coalesce(public.user_progress.state, '{}'::jsonb),
          '{honey}',
          to_jsonb(
            greatest(
              0,
              coalesce((public.user_progress.state->>'honey')::integer, 0) + v_delta
            )
          ),
          true
        ),
        updated_at = now()
  returning coalesce((state->>'honey')::integer, 0) into v_honey;

  return coalesce(v_honey, 0);
end;
$$;

create or replace function public.surprise_transfer_honey(
  p_from_user_id uuid,
  p_to_user_id uuid,
  p_amount integer
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_amount integer := greatest(0, coalesce(p_amount, 0));
  v_from_honey integer := 0;
  v_to_honey integer := 0;
  v_transfer integer := 0;
begin
  if p_from_user_id is null or p_to_user_id is null or p_from_user_id = p_to_user_id then
    return 0;
  end if;

  insert into public.user_progress(user_id, state, total_chapters)
  values
    (p_from_user_id, jsonb_build_object('honey', 0), 0),
    (p_to_user_id, jsonb_build_object('honey', 0), 0)
  on conflict (user_id) do nothing;

  select coalesce((state->>'honey')::integer, 0)
    into v_from_honey
  from public.user_progress
  where user_id = p_from_user_id
  for update;

  select coalesce((state->>'honey')::integer, 0)
    into v_to_honey
  from public.user_progress
  where user_id = p_to_user_id
  for update;

  v_transfer := least(v_amount, greatest(0, coalesce(v_from_honey, 0)));

  update public.user_progress
     set state = jsonb_set(
           coalesce(state, '{}'::jsonb),
           '{honey}',
           to_jsonb(greatest(0, coalesce(v_from_honey, 0) - v_transfer)),
           true
         ),
         updated_at = now()
   where user_id = p_from_user_id;

  update public.user_progress
     set state = jsonb_set(
           coalesce(state, '{}'::jsonb),
           '{honey}',
           to_jsonb(greatest(0, coalesce(v_to_honey, 0) + v_transfer)),
           true
         ),
         updated_at = now()
   where user_id = p_to_user_id;

  return v_transfer;
end;
$$;

create or replace function public.surprise_grant_honey_boost(
  p_user_id uuid,
  p_source text,
  p_hours integer default 24
)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_state jsonb := '{}'::jsonb;
  v_active jsonb := '[]'::jsonb;
  v_until timestamptz := now() + make_interval(hours => greatest(1, coalesce(p_hours, 24)));
  v_source text := left(coalesce(nullif(trim(p_source), ''), 'surprise'), 60);
begin
  insert into public.user_progress(user_id, state, total_chapters)
  values (p_user_id, '{}'::jsonb, 0)
  on conflict (user_id) do nothing;

  select coalesce(state, '{}'::jsonb)
    into v_state
  from public.user_progress
  where user_id = p_user_id
  for update;

  select coalesce(jsonb_agg(boost), '[]'::jsonb)
    into v_active
  from jsonb_array_elements(coalesce(v_state->'honeyBoosts', '[]'::jsonb)) as b(boost)
  where nullif(b.boost->>'until', '')::timestamptz > now()
    and coalesce(b.boost->>'source', '') <> v_source;

  v_active := v_active || jsonb_build_array(
    jsonb_build_object(
      'source', v_source,
      'multiplier', 2,
      'until', v_until
    )
  );

  v_state := jsonb_set(v_state, '{honeyBoosts}', v_active, true);
  v_state := jsonb_set(v_state, '{honeyBoostUntil}', to_jsonb(v_until), true);

  update public.user_progress
     set state = v_state,
         updated_at = now()
   where user_id = p_user_id;

  return v_until;
end;
$$;

create or replace function public.surprise_award_cosmetic(
  p_user_id uuid,
  p_seed text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_state jsonb := '{}'::jsonb;
  v_owned jsonb := '[]'::jsonb;
  v_cosmetic text;
begin
  insert into public.user_progress(user_id, state, total_chapters)
  values (p_user_id, '{}'::jsonb, 0)
  on conflict (user_id) do nothing;

  select coalesce(state, '{}'::jsonb)
    into v_state
  from public.user_progress
  where user_id = p_user_id
  for update;

  v_owned := coalesce(v_state->'ownedCosmetics', '[]'::jsonb);

  select cosmetic_id
    into v_cosmetic
  from unnest(public.surprise_cosmetic_pool()) as pool(cosmetic_id)
  where not exists (
    select 1
    from jsonb_array_elements_text(v_owned) as owned(id)
    where owned.id = pool.cosmetic_id
  )
  order by md5(coalesce(p_seed, '') || ':' || cosmetic_id)
  limit 1;

  if v_cosmetic is null then
    return null;
  end if;

  v_state := jsonb_set(
    v_state,
    '{ownedCosmetics}',
    v_owned || to_jsonb(v_cosmetic),
    true
  );

  update public.user_progress
     set state = v_state,
         updated_at = now()
   where user_id = p_user_id;

  return v_cosmetic;
end;
$$;

create or replace function public.mark_family_presence(p_family_room_id uuid default null)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid := coalesce(p_family_room_id, public.current_family_room_id());
  v_row_count integer := 0;
begin
  if auth.uid() is null or v_room_id is null then
    return false;
  end if;

  update public.family_room_members
     set last_seen_at = now()
   where room_id = v_room_id
     and user_id = auth.uid()
     and active
     and (last_seen_at is null or last_seen_at < now() - interval '5 minutes');

  get diagnostics v_row_count = row_count;
  return v_row_count > 0;
end;
$$;

create or replace function public.current_active_surprise(p_family_room_id uuid default null)
returns table(
  id uuid,
  family_room_id uuid,
  surprise_type text,
  surprise_date date,
  start_at timestamptz,
  end_at timestamptz,
  payload jsonb,
  seconds_left integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid := coalesce(p_family_room_id, public.current_family_room_id());
begin
  if auth.uid() is null or v_room_id is null then
    return;
  end if;

  if not exists (
    select 1
    from public.family_room_members m
    where m.room_id = v_room_id
      and m.user_id = auth.uid()
      and m.active
      and m.joined_at <= now() - interval '24 hours'
  ) then
    return;
  end if;

  return query
  select
    fs.id,
    fs.family_room_id,
    fs.surprise_type,
    fs.surprise_date,
    fs.start_at,
    fs.end_at,
    case
      when fs.surprise_type = 'crown_hunt'
        then (fs.payload - 'crown_verse_ref')
      else fs.payload
    end as payload,
    greatest(0, extract(epoch from (fs.end_at - now()))::integer) as seconds_left
  from public.family_surprises fs
  where fs.family_room_id = v_room_id
    and fs.resolved_at is null
    and fs.start_at <= now()
    and fs.end_at > now()
    and coalesce(fs.payload->>'skipped', 'false') <> 'true'
  order by fs.start_at desc
  limit 1;
end;
$$;

create or replace function public.claim_surprise_chapter(
  p_surprise_id uuid,
  p_book text,
  p_chapter integer,
  p_chapter_honey integer default 0
)
returns table(
  surprise_type text,
  reward_kind text,
  reward_label text,
  honey_delta integer,
  cosmetic_id text,
  boost_until timestamptz,
  winner boolean,
  result_payload jsonb
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_surprise public.family_surprises%rowtype;
  v_user uuid := auth.uid();
  v_room_id uuid;
  v_payload jsonb;
  v_key text := left('chapter:' || coalesce(p_book, '') || ':' || coalesce(p_chapter::text, ''), 140);
  v_bonus integer := 0;
  v_kind text := 'none';
  v_label text := '';
  v_cosmetic text := null;
  v_boost_until timestamptz := null;
  v_winner boolean := false;
  v_roll integer := 0;
  v_user_chapters jsonb := '[]'::jsonb;
  v_count integer := 0;
  v_other uuid := null;
  v_transfer integer := 0;
  v_pot integer := null;
  v_payout_source text := 'system';
begin
  if v_user is null then
    return;
  end if;

  select * into v_surprise
  from public.family_surprises
  where id = p_surprise_id
  for update;

  if not found then
    return;
  end if;

  v_room_id := v_surprise.family_room_id;

  if v_surprise.resolved_at is not null
     or v_surprise.start_at > now()
     or v_surprise.end_at <= now()
     or coalesce(v_surprise.payload->>'skipped', 'false') = 'true' then
    return;
  end if;

  if not exists (
    select 1
    from public.family_room_members m
    where m.room_id = v_room_id
      and m.user_id = v_user
      and m.active
      and m.joined_at <= now() - interval '24 hours'
  ) then
    return;
  end if;

  v_payload := coalesce(v_surprise.payload, '{}'::jsonb);

  if v_surprise.surprise_type = 'honey_storm' then
    v_payload := jsonb_set(v_payload, '{honey_storm_claims}', coalesce(v_payload->'honey_storm_claims', '{}'::jsonb), true);
    v_payload := jsonb_set(v_payload, array['honey_storm_claims', v_user::text], coalesce(v_payload #> array['honey_storm_claims', v_user::text], '{}'::jsonb), true);
    if (v_payload #> array['honey_storm_claims', v_user::text, v_key]) is null then
      v_bonus := greatest(0, coalesce(p_chapter_honey, 0)) * 2;
      if v_bonus > 0 then
        perform public.surprise_add_user_honey(v_user, v_bonus);
      end if;
      v_payload := jsonb_set(v_payload, array['honey_storm_claims', v_user::text, v_key], to_jsonb(v_bonus), true);
      v_kind := 'honey';
      v_label := 'Honey Storm 3x chapter bonus';
    end if;

  elsif v_surprise.surprise_type = 'flash_race' then
    v_payload := jsonb_set(v_payload, '{flash_progress}', coalesce(v_payload->'flash_progress', '{}'::jsonb), true);
    v_user_chapters := coalesce(v_payload #> array['flash_progress', v_user::text], '[]'::jsonb);
    if not exists (select 1 from jsonb_array_elements_text(v_user_chapters) as ch(k) where ch.k = v_key) then
      v_user_chapters := v_user_chapters || to_jsonb(v_key);
      v_payload := jsonb_set(v_payload, array['flash_progress', v_user::text], v_user_chapters, true);
    end if;
    v_count := jsonb_array_length(v_user_chapters);
    if v_count >= 2 and nullif(v_payload->>'winner_user_id', '') is null then
      v_bonus := 200;
      select p.pot_honey
      into v_pot
      from public.family_weekly_pots p
      where p.room_id = v_room_id
        and p.week_start = public.current_family_week_start()
      for update;

      if coalesce(v_pot, 0) > 0 then
        v_payout_source := case
          when v_pot >= v_bonus then 'family_pot'
          else 'family_pot_plus_system'
        end;

        update public.family_weekly_pots
        set pot_honey = greatest(0, v_pot - v_bonus),
            updated_at = now()
        where room_id = v_room_id
          and week_start = public.current_family_week_start();
      end if;

      perform public.surprise_add_user_honey(v_user, v_bonus);
      v_payload := jsonb_set(v_payload, '{winner_user_id}', to_jsonb(v_user::text), true);
      v_payload := jsonb_set(v_payload, '{winner_at}', to_jsonb(now()), true);
      v_payload := jsonb_set(v_payload, '{payout_source}', to_jsonb(v_payout_source), true);
      v_kind := 'honey';
      v_label := 'Flash Race winner';
      v_winner := true;
      v_surprise.resolved_at := now();
    end if;

  elsif v_surprise.surprise_type = 'mystery_box' then
    v_payload := jsonb_set(v_payload, '{mystery_box_rolls}', coalesce(v_payload->'mystery_box_rolls', '{}'::jsonb), true);
    if (v_payload #> array['mystery_box_rolls', v_user::text]) is null then
      v_roll := public.surprise_hash_bucket(v_surprise.id::text || ':' || v_user::text || ':mystery', 100);
      if v_roll < 40 then
        v_bonus := 50;
        perform public.surprise_add_user_honey(v_user, v_bonus);
        v_kind := 'honey';
        v_label := 'Mystery Box: 50 honey';
      elsif v_roll < 70 then
        v_bonus := 200;
        perform public.surprise_add_user_honey(v_user, v_bonus);
        v_kind := 'honey';
        v_label := 'Mystery Box: 200 honey';
      elsif v_roll < 80 then
        v_bonus := 500;
        perform public.surprise_add_user_honey(v_user, v_bonus);
        v_kind := 'honey';
        v_label := 'Mystery Box: 500 honey';
      elsif v_roll < 90 then
        v_cosmetic := public.surprise_award_cosmetic(v_user, v_surprise.id::text || ':' || v_user::text || ':cosmetic');
        if v_cosmetic is null then
          v_bonus := 200;
          perform public.surprise_add_user_honey(v_user, v_bonus);
          v_kind := 'honey';
          v_label := 'Mystery Box: 200 honey';
        else
          v_kind := 'cosmetic';
          v_label := 'Mystery Box cosmetic';
        end if;
      elsif v_roll < 97 then
        v_boost_until := public.surprise_grant_honey_boost(v_user, 'mystery_box', 24);
        v_kind := 'boost';
        v_label := 'Mystery Box: 2x honey for 24h';
      else
        select m.user_id
          into v_other
        from public.family_room_members m
        left join public.user_progress up on up.user_id = m.user_id
        where m.room_id = v_room_id
          and m.user_id <> v_user
          and m.active
          and coalesce((up.state->>'honey')::integer, 0) > 0
        order by md5(v_surprise.id::text || ':' || v_user::text || ':' || m.user_id::text)
        limit 1;

        if v_other is null then
          v_bonus := 100;
          perform public.surprise_add_user_honey(v_user, v_bonus);
        else
          v_bonus := public.surprise_transfer_honey(v_other, v_user, 100);
        end if;
        v_kind := 'steal';
        v_label := case when v_other is null then 'Mystery Box: 100 honey' else 'Mystery Box: stole honey' end;
      end if;

      v_payload := jsonb_set(
        v_payload,
        array['mystery_box_rolls', v_user::text],
        jsonb_build_object(
          'claimed_at', now(),
          'roll', v_roll,
          'reward_kind', v_kind,
          'honey_delta', v_bonus,
          'cosmetic_id', v_cosmetic,
          'boost_until', v_boost_until,
          'label', v_label
        ),
        true
      );
    end if;

  elsif v_surprise.surprise_type = 'showdown' then
    if nullif(v_payload->>'winner_user_id', '') is null
       and exists (
         select 1
         from jsonb_array_elements_text(coalesce(v_payload->'participants', '[]'::jsonb)) as participant(id)
         where participant.id = v_user::text
       ) then
      select participant.id::uuid
        into v_other
      from jsonb_array_elements_text(coalesce(v_payload->'participants', '[]'::jsonb)) as participant(id)
      where participant.id <> v_user::text
      limit 1;

      v_transfer := public.surprise_transfer_honey(v_other, v_user, 150);
      v_bonus := v_transfer;
      v_kind := 'honey';
      v_label := 'Showdown winner';
      v_winner := true;
      v_payload := jsonb_set(v_payload, '{winner_user_id}', to_jsonb(v_user::text), true);
      v_payload := jsonb_set(v_payload, '{loser_user_id}', to_jsonb(v_other::text), true);
      v_payload := jsonb_set(v_payload, '{honey_transfer}', to_jsonb(v_transfer), true);
      v_payload := jsonb_set(v_payload, '{winner_at}', to_jsonb(now()), true);
      v_surprise.resolved_at := now();
    end if;

  elsif v_surprise.surprise_type = 'wildcard_day' then
    v_payload := jsonb_set(v_payload, '{wildcard_claims}', coalesce(v_payload->'wildcard_claims', '{}'::jsonb), true);
    if (v_payload #> array['wildcard_claims', v_user::text]) is null then
      v_cosmetic := public.surprise_award_cosmetic(v_user, v_surprise.id::text || ':' || v_user::text || ':wildcard');
      if v_cosmetic is null then
        v_bonus := 200;
        perform public.surprise_add_user_honey(v_user, v_bonus);
        v_kind := 'honey';
        v_label := 'Wildcard Day: 200 honey';
      else
        v_kind := 'cosmetic';
        v_label := 'Wildcard Day cosmetic';
      end if;
      v_payload := jsonb_set(
        v_payload,
        array['wildcard_claims', v_user::text],
        jsonb_build_object('claimed_at', now(), 'reward_kind', v_kind, 'cosmetic_id', v_cosmetic, 'honey_delta', v_bonus),
        true
      );
    end if;

  elsif v_surprise.surprise_type = 'swarm' then
    if nullif(v_payload->>'winner_user_id', '') is null then
      select count(distinct coalesce(source_key, id::text))::integer
        into v_count
      from public.family_weekly_activity
      where room_id = v_room_id
        and user_id = v_user
        and event_type = 'chapter_read'
        and created_at >= greatest(v_surprise.start_at, now() - interval '60 minutes')
        and created_at <= now();

      if v_count >= 3 then
        v_boost_until := public.surprise_grant_honey_boost(v_user, 'swarm', 24);
        v_kind := 'boost';
        v_label := 'Swarm winner: 2x honey for 24h';
        v_winner := true;
        v_payload := jsonb_set(v_payload, '{winner_user_id}', to_jsonb(v_user::text), true);
        v_payload := jsonb_set(v_payload, '{winner_at}', to_jsonb(now()), true);
        v_payload := jsonb_set(v_payload, '{chapters_in_window}', to_jsonb(v_count), true);
        v_surprise.resolved_at := now();
      end if;
    end if;
  end if;

  update public.family_surprises
     set payload = v_payload,
         resolved_at = v_surprise.resolved_at,
         updated_at = now()
   where id = v_surprise.id;

  return query select
    v_surprise.surprise_type,
    v_kind,
    v_label,
    v_bonus,
    v_cosmetic,
    v_boost_until,
    v_winner,
    jsonb_build_object(
      'label', v_label,
      'count', v_count
    );
end;
$$;

create or replace function public.touch_crown_verse(
  p_surprise_id uuid,
  p_book text,
  p_chapter integer,
  p_verse integer,
  p_action text default 'pass'
)
returns table(
  surprise_type text,
  reward_kind text,
  reward_label text,
  honey_delta integer,
  winner boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_surprise public.family_surprises%rowtype;
  v_user uuid := auth.uid();
  v_payload jsonb;
  v_bonus integer := 0;
  v_winner boolean := false;
begin
  if v_user is null then
    return;
  end if;

  select * into v_surprise
  from public.family_surprises
  where id = p_surprise_id
  for update;

  if not found
     or v_surprise.surprise_type <> 'crown_hunt'
     or v_surprise.resolved_at is not null
     or v_surprise.start_at > now()
     or v_surprise.end_at <= now() then
    return;
  end if;

  if not exists (
    select 1
    from public.family_room_members m
    where m.room_id = v_surprise.family_room_id
      and m.user_id = v_user
      and m.active
      and m.joined_at <= now() - interval '24 hours'
  ) then
    return;
  end if;

  v_payload := coalesce(v_surprise.payload, '{}'::jsonb);

  if coalesce(v_payload #>> '{crown_verse_ref,book}', '') = coalesce(p_book, '')
     and coalesce((v_payload #>> '{crown_verse_ref,chapter}')::integer, 0) = coalesce(p_chapter, 0)
     and coalesce((v_payload #>> '{crown_verse_ref,verse}')::integer, 0) = coalesce(p_verse, 0)
     and nullif(v_payload->>'winner_user_id', '') is null then
    v_bonus := 300;
    perform public.surprise_add_user_honey(v_user, v_bonus);
    v_winner := true;
    v_payload := jsonb_set(v_payload, '{winner_user_id}', to_jsonb(v_user::text), true);
    v_payload := jsonb_set(v_payload, '{winner_at}', to_jsonb(now()), true);
    v_payload := jsonb_set(v_payload, '{winning_action}', to_jsonb(left(coalesce(p_action, 'pass'), 30)), true);

    update public.family_surprises
       set payload = v_payload,
           resolved_at = now(),
           updated_at = now()
     where id = v_surprise.id;
  end if;

  if v_winner then
    return query select
      'crown_hunt'::text,
      'honey'::text,
      'Crown Hunt winner'::text,
      v_bonus,
      true;
  end if;
end;
$$;

grant select on table public.family_surprises to authenticated;
grant execute on function public.current_active_surprise(uuid) to authenticated;
grant execute on function public.mark_family_presence(uuid) to authenticated;
grant execute on function public.claim_surprise_chapter(uuid, text, integer, integer) to authenticated;
grant execute on function public.touch_crown_verse(uuid, text, integer, integer, text) to authenticated;
grant execute on function public.surprise_add_user_honey(uuid, integer) to service_role;
grant execute on function public.surprise_transfer_honey(uuid, uuid, integer) to service_role;
grant execute on function public.surprise_grant_honey_boost(uuid, text, integer) to service_role;
grant execute on function public.surprise_award_cosmetic(uuid, text) to service_role;
