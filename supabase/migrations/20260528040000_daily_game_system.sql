-- Daily Game system + encouragement cache repair
--
-- Additive only: solo Daily Game points feed the Family Cup through
-- family_race_events. Bible progress, streaks, chapters, challenges, duels,
-- and Daily Surprises remain separate.

create table if not exists public.daily_game_attempts (
  id uuid primary key default gen_random_uuid(),
  family_room_id uuid not null references public.family_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  game_date date not null,
  game_id text not null,
  seed integer not null,
  score integer,
  base_points integer not null default 25 check (base_points >= 0 and base_points <= 100),
  points_awarded integer not null default 25 check (points_awarded >= 0 and points_awarded <= 200),
  read_deadline_at timestamptz,
  doubled_at timestamptz,
  chapter_source_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (family_room_id, user_id, game_date)
);

create index if not exists daily_game_attempts_room_date_idx
  on public.daily_game_attempts(family_room_id, game_date);

create table if not exists public.daily_game_pushes (
  id uuid primary key default gen_random_uuid(),
  family_room_id uuid not null references public.family_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  game_date date not null,
  game_id text not null,
  sent_at timestamptz not null default now(),
  unique (user_id, game_date)
);

alter table public.daily_game_attempts enable row level security;
alter table public.daily_game_pushes enable row level security;

drop policy if exists daily_game_attempts_read_member on public.daily_game_attempts;
create policy daily_game_attempts_read_member
on public.daily_game_attempts
for select
to authenticated
using (
  exists (
    select 1
    from public.family_room_members mine
    where mine.room_id = daily_game_attempts.family_room_id
      and mine.user_id = auth.uid()
      and mine.active
  )
);

drop policy if exists daily_game_pushes_read_own on public.daily_game_pushes;
create policy daily_game_pushes_read_own
on public.daily_game_pushes
for select
to authenticated
using (user_id = auth.uid());

create or replace function public.daily_game_ids()
returns text[]
language sql
immutable
security definer
set search_path = public
as $$
  select array['bible_memory','finish_verse','match_book','who_said']::text[];
$$;

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

create or replace function public.current_daily_game(
  p_family_room_id uuid default null
)
returns table(
  family_room_id uuid,
  game_date date,
  game_id text,
  seed integer,
  base_points integer,
  doubled_points integer,
  has_attempt boolean,
  score integer,
  points_awarded integer,
  read_deadline_at timestamptz,
  doubled_at timestamptz,
  seconds_to_double integer,
  practice_only boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid := coalesce(p_family_room_id, public.current_family_room_id());
  v_game record;
  v_attempt public.daily_game_attempts%rowtype;
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  if v_room_id is null then
    raise exception 'join a family room first';
  end if;
  if not exists (
    select 1
    from public.family_room_members mine
    where mine.room_id = v_room_id
      and mine.user_id = auth.uid()
      and mine.active
  ) then
    raise exception 'not a member of that family room';
  end if;

  select * into v_game
  from public.daily_game_for_room(v_room_id, public.family_central_today())
  limit 1;

  select * into v_attempt
  from public.daily_game_attempts a
  where a.family_room_id = v_room_id
    and a.user_id = auth.uid()
    and a.game_date = v_game.game_date
  limit 1;

  return query
  select
    v_room_id,
    v_game.game_date,
    v_game.game_id,
    v_game.seed,
    v_game.base_points,
    v_game.doubled_points,
    v_attempt.id is not null,
    v_attempt.score,
    coalesce(v_attempt.points_awarded, 0),
    v_attempt.read_deadline_at,
    v_attempt.doubled_at,
    case
      when v_attempt.id is not null
       and v_attempt.doubled_at is null
       and v_attempt.read_deadline_at > now()
      then greatest(0, extract(epoch from (v_attempt.read_deadline_at - now()))::integer)
      else 0
    end,
    v_attempt.id is not null;
end;
$$;

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

create or replace function public.claim_daily_game_read_bonus(
  p_book text,
  p_chapter integer
)
returns table(
  doubled boolean,
  added_points integer,
  game_date date,
  game_id text,
  reason text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid := public.current_family_room_id();
  v_today date := public.family_central_today();
  v_attempt public.daily_game_attempts%rowtype;
  v_source_key text := 'chapter:' || trim(coalesce(p_book, '')) || ':' || coalesce(p_chapter, 0)::text;
  v_activity_id uuid;
  v_added integer;
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  if v_room_id is null then
    return query select false, 0, v_today, null::text, 'no family room';
    return;
  end if;

  select * into v_attempt
  from public.daily_game_attempts a
  where a.family_room_id = v_room_id
    and a.user_id = auth.uid()
    and a.game_date = v_today
    and a.doubled_at is null
    and a.read_deadline_at >= now()
  order by a.created_at desc
  limit 1
  for update;

  if v_attempt.id is null then
    return query select false, 0, v_today, null::text, 'no active game double window';
    return;
  end if;

  select a.id into v_activity_id
  from public.family_weekly_activity a
  where a.room_id = v_room_id
    and a.user_id = auth.uid()
    and a.event_type = 'chapter_read'
    and a.source_key = v_source_key
    and a.created_at >= v_attempt.created_at
    and a.created_at <= v_attempt.read_deadline_at
  order by a.created_at desc
  limit 1;

  if v_activity_id is null then
    return query select false, 0, v_attempt.game_date, v_attempt.game_id, 'no verified chapter in double window';
    return;
  end if;

  v_added := greatest(0, v_attempt.base_points);

  update public.daily_game_attempts
     set points_awarded = points_awarded + v_added,
         doubled_at = now(),
         chapter_source_key = v_source_key,
         updated_at = now()
   where id = v_attempt.id;

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
    v_attempt.game_date,
    auth.uid(),
    auth.uid(),
    'daily_game_double',
    v_added,
    'daily-game-double:' || v_attempt.game_date::text || ':' || auth.uid()::text,
    'Read within 10 minutes to double Game of the Day points'
  )
  on conflict (room_id, user_id, source_key) where source_key is not null do nothing;

  return query select true, v_added, v_attempt.game_date, v_attempt.game_id, 'doubled';
end;
$$;

-- get_daily_encouragement used to insert fallback rows before the Edge
-- Function could generate with OpenAI. Return a temporary fallback without
-- caching it so fallback does not block fresh daily generation.
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
  return query
  select de.encouragement_date, de.payload, de.source, de.created_at
  from public.daily_encouragements de
  where de.encouragement_date = v_date;

  if found then
    return;
  end if;

  return query
  select
    v_date,
    public.daily_encouragement_fallback(v_date),
    'fallback'::text,
    now();
end;
$$;

-- A larger fallback pool keeps the home screen fresh even if OPENAI_API_KEY is
-- not configured in the Edge Function secrets yet.
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
  v_index integer := mod(extract(doy from coalesce(p_date, current_date))::integer, 14);
begin
  return case v_index
    when 0 then jsonb_build_object('title','Sweeter Than Honey','opening_line','God''s voice was never meant to feel far away.','reflection','The Bible is not just a book to finish. It is a quiet place to meet with God. Even one chapter today can steady your heart and remind you that He is near.','scripture',jsonb_build_object('reference','Psalm 119:103','text','How sweet are your promises to my taste, more than honey to my mouth!'),'prayer_or_prompt','God, help me love Your words today.')
    when 1 then jsonb_build_object('title','Near In The Word','opening_line','A small moment with Scripture can become a deep breath for your soul.','reflection','You do not have to rush. Open God''s Word and let one true thing stay with you today. The Lord is patient, kind, and near.','scripture',jsonb_build_object('reference','Psalm 119:105','text','Your word is a lamp to my feet, and a light for my path.'),'prayer_or_prompt','Jesus, walk with me as I listen.')
    when 2 then jsonb_build_object('title','Quiet Hunger','opening_line','Your heart was made to be fed by more than noise.','reflection','God''s Word gives your soul something real to hold. Read slowly today. Let the sweetness of Scripture pull your thoughts back toward Him.','scripture',jsonb_build_object('reference','Matthew 4:4','text','Man shall not live by bread alone, but by every word that proceeds out of God''s mouth.'),'prayer_or_prompt','Lord, give me hunger for what is true.')
    when 3 then jsonb_build_object('title','Day And Night','opening_line','One verse can travel with you longer than you think.','reflection','Let God''s Word be something you return to through the day. Not as pressure, but as peace. He is willing to meet you in ordinary moments.','scripture',jsonb_build_object('reference','Psalm 1:2','text','But his delight is in Yahweh''s law. On his law he meditates day and night.'),'prayer_or_prompt','Father, keep Your Word close to my mind today.')
    when 4 then jsonb_build_object('title','Rest In His Voice','opening_line','God is not asking you to impress Him today.','reflection','Come to Scripture as someone loved. Read to remember who He is, not to prove yourself. His nearness is better than hurry.','scripture',jsonb_build_object('reference','Matthew 11:28','text','Come to me, all you who labor and are heavily burdened, and I will give you rest.'),'prayer_or_prompt','Jesus, help me receive Your rest.')
    when 5 then jsonb_build_object('title','Abide Today','opening_line','The branch lives by staying close to the vine.','reflection','Reading today is not just progress on a plan. It is a way to stay near Jesus. Let His words settle into you and bear fruit quietly.','scripture',jsonb_build_object('reference','John 15:5','text','I am the vine. You are the branches. He who remains in me, and I in him, bears much fruit.'),'prayer_or_prompt','Jesus, teach me to abide in You.')
    when 6 then jsonb_build_object('title','A Word For Today','opening_line','God can meet you in one honest chapter.','reflection','Before the day gets loud, give your heart a place to listen. The Lord speaks through His Word with patience, mercy, and light for the next step.','scripture',jsonb_build_object('reference','Psalm 119:18','text','Open my eyes, that I may see wondrous things out of your law.'),'prayer_or_prompt','God, open my eyes to Your Word.')
    when 7 then jsonb_build_object('title','Still Near','opening_line','You do not have to feel strong to open Scripture.','reflection','Bring God the heart you actually have today. His Word is steady when your thoughts are not. Let one chapter remind you that He has not stepped away.','scripture',jsonb_build_object('reference','Psalm 73:28','text','But it is good for me to come close to God. I have made the Lord Yahweh my refuge.'),'prayer_or_prompt','Lord, meet me with Your nearness.')
    when 8 then jsonb_build_object('title','Taste And See','opening_line','The sweetness of God''s Word grows as you return to it.','reflection','Some days the Bible feels like a feast. Some days it feels like one small bite. Both can nourish you when you come to the Lord with an open heart.','scripture',jsonb_build_object('reference','Psalm 34:8','text','Oh taste and see that Yahweh is good. Blessed is the man who takes refuge in him.'),'prayer_or_prompt','God, help me taste Your goodness today.')
    when 9 then jsonb_build_object('title','One Lamp Step','opening_line','You do not need the whole path lit to take the next step.','reflection','God often gives light one step at a time. Open His Word and receive enough for today. The Shepherd knows where He is leading you.','scripture',jsonb_build_object('reference','Psalm 119:105','text','Your word is a lamp to my feet, and a light for my path.'),'prayer_or_prompt','Lord, guide my next step.')
    when 10 then jsonb_build_object('title','Words That Stay','opening_line','Let one true sentence from God stay with you today.','reflection','Read slowly enough to carry something with you. A verse remembered in the middle of the day can become peace, courage, and worship.','scripture',jsonb_build_object('reference','Colossians 3:16','text','Let the word of Christ dwell in you richly.'),'prayer_or_prompt','Jesus, let Your Word dwell in me.')
    when 11 then jsonb_build_object('title','A Quiet Door','opening_line','Opening Scripture can be a quiet door back to peace.','reflection','The world pulls your attention in a hundred directions. God invites you to come close and listen. His voice is not hurried, harsh, or far away.','scripture',jsonb_build_object('reference','Isaiah 26:3','text','You will keep whoever''s mind is steadfast in perfect peace, because he trusts in you.'),'prayer_or_prompt','Father, settle my mind in You.')
    when 12 then jsonb_build_object('title','Hungry For God','opening_line','Spiritual hunger is not a weakness; it is an invitation.','reflection','If your soul feels empty, do not shame it. Bring it to the Lord. His Word can feed places that noise only distracts.','scripture',jsonb_build_object('reference','Jeremiah 15:16','text','Your words were found, and I ate them. Your words were to me a joy and the rejoicing of my heart.'),'prayer_or_prompt','God, feed my heart with Your truth.')
    else jsonb_build_object('title','Walk With Jesus','opening_line','Today''s chapter is part of walking with Someone, not just finishing something.','reflection','Jesus is not only waiting at the end of the plan. He is near in the reading, near in the questions, and near in the ordinary minutes after.','scripture',jsonb_build_object('reference','Luke 24:32','text','Weren''t our hearts burning within us, while he spoke to us along the way, and while he opened the Scriptures to us?'),'prayer_or_prompt','Jesus, walk with me in Your Word.')
  end;
end;
$$;

grant select on table public.daily_game_attempts to authenticated;
grant select on table public.daily_game_pushes to authenticated;
grant execute on function public.daily_game_ids() to authenticated;
grant execute on function public.daily_game_for_room(uuid, date) to authenticated;
grant execute on function public.current_daily_game(uuid) to authenticated;
grant execute on function public.claim_daily_game_attempt(text, integer, integer) to authenticated;
grant execute on function public.claim_daily_game_read_bonus(text, integer) to authenticated;
grant execute on function public.get_daily_encouragement() to anon, authenticated;
grant execute on function public.daily_encouragement_fallback(date) to anon, authenticated;

do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'cron')
     and exists (select 1 from pg_namespace where nspname = 'net') then
    begin
      perform cron.unschedule('process-daily-games-every-15-minutes');
    exception when others then
      null;
    end;

    perform cron.schedule(
      'process-daily-games-every-15-minutes',
      '*/15 * * * *',
      $cron$
        select net.http_post(
          url := 'https://dqlbnpqyoblfsaasydkr.supabase.co/functions/v1/process-daily-games',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'x-honeycomb-cron-secret', (select value from private.cron_config where key = 'cron_secret')
          ),
          body := '{}'::jsonb,
          timeout_milliseconds := 30000
        );
      $cron$
    );
  end if;
end $$;
