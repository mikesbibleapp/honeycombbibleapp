-- Rotate Game of the Day through casual skill games only. The older Bible
-- question games remain playable for existing challenge records, but the
-- featured daily game and daily push must be fair for people who do not know
-- Bible trivia yet.

create or replace function public.daily_game_ids()
returns text[]
language sql
immutable
security definer
set search_path = public
as $$
  select array[
    'honey_drop',
    'manna_mover',
    'shepherd_dash',
    'ark_match',
    'bible_memory'
  ]::text[];
$$;

grant execute on function public.daily_game_ids() to authenticated;
