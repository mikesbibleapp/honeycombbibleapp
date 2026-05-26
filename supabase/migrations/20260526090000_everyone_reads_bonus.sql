-- "Everyone reads" jackpot bonus: +500 honey added to today's daily race
-- pot the first time every active family member has read at least one
-- chapter that Central day. Capped at the existing 5000 jackpot ceiling.
-- Paid once per day per room via the new everyone_read_bonus_paid flag.
--
-- Implementation lives inside record_family_activity (redeployed via
-- apply_migration name 'everyone_reads_bonus_jackpot'). The atomic
-- UPDATE on family_daily_races prevents double-payment under concurrent
-- chapter_read events from multiple members finishing simultaneously.

alter table public.family_daily_races
  add column if not exists everyone_read_bonus_paid boolean not null default false;

select 1;
