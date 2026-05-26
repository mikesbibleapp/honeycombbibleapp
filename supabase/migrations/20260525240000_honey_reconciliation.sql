-- One-time honey reconciliation pass.
-- Refunds unpaid mission claims (claim_family_missions previously credited
-- the pot but not the claimant), removes the goal-stake double-count from
-- past pots, and grants every user a flat 500-honey apology credit for the
-- recent economy bugs. Safe to run once; subsequent runs would re-apply
-- credits, so do not run again after deploy.

do $$
begin
  -- A. Refund unpaid mission claims. Each row in family_mission_claims is one
  -- mission the user "won" but never actually received honey for.
  update public.user_progress up
  set state = jsonb_set(
        coalesce(up.state, '{}'::jsonb),
        '{honey}',
        to_jsonb(coalesce((up.state->>'honey')::int, 0) + claims.total_reward),
        true
      ),
      updated_at = now()
  from (
    select claimed_by, coalesce(sum(reward_honey), 0)::int as total_reward
    from public.family_mission_claims
    where claimed_at is not null
    group by claimed_by
  ) as claims
  where up.user_id = claims.claimed_by
    and claims.total_reward > 0;
end $$;

do $$
begin
  -- B. De-double the pot for past goal stakes: subtract any goal_stake
  -- honey_delta from the matching weekly pot, clamped to >= 0.
  update public.family_weekly_pots p
  set pot_honey = greatest(0, p.pot_honey - stakes.total_stake),
      updated_at = now()
  from (
    select room_id, week_start, coalesce(sum(honey_delta), 0)::int as total_stake
    from public.family_weekly_activity
    where event_type = 'goal_stake'
    group by room_id, week_start
  ) as stakes
  where p.room_id = stakes.room_id
    and p.week_start = stakes.week_start
    and stakes.total_stake > 0;
end $$;

do $$
begin
  -- C. Flat 500-honey "sorry for the bugs" apology credit for every existing user.
  update public.user_progress
  set state = jsonb_set(
        coalesce(state, '{}'::jsonb),
        '{honey}',
        to_jsonb(coalesce((state->>'honey')::int, 0) + 500),
        true
      ),
      updated_at = now();
end $$;
