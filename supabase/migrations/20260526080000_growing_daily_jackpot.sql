-- The family daily race jackpot now grows as members read. Each chapter_read
-- event bumps family_daily_races.jackpot_honey by +50, capped at 5000.
-- Starts at the 2000 baseline so a quiet day still pays the floor; a heavy
-- reading day juices the pot to keep the race exciting.
--
-- settle_family_daily_race already reads v_race.jackpot_honey at payout time,
-- so the grown pot is awarded automatically -- no settle-side change needed.
--
-- record_family_activity body redeployed via apply_migration named
-- 'growing_daily_jackpot'. This file is the version-control marker.

select 1;
