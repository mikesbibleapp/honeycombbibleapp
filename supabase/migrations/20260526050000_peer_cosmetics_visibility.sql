-- Add user_progress.cosmetics column so other family members can render
-- each other's equipped vehicle / trail / aura in the family race lane.
-- Until now cosmetics lived only inside state jsonb, which my_family_room
-- never exposed -- so siblings always saw each other on the default cart.

alter table public.user_progress
  add column if not exists cosmetics jsonb default '{}'::jsonb not null;

-- Backfill from state.equippedCosmetics so today's racers immediately have
-- the right vehicle/trail/aura visible to siblings.
update public.user_progress
set cosmetics = coalesce(state->'equippedCosmetics', '{}'::jsonb)
where cosmetics = '{}'::jsonb
  and state ? 'equippedCosmetics';

-- my_family_room now returns each member's cosmetics in both the members
-- and race_members jsonb arrays. Redefinition deployed via direct apply.
