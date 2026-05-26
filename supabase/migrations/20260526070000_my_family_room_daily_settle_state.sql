-- Expose daily-race settle state via my_family_room so the UI can render a
-- clean "race over, NAME won +2000" banner instead of pretending the race
-- is still live after the 9pm Central cutoff.
--
-- Adds 5 new return columns: daily_race_status, daily_winner_id,
-- daily_winner_name, daily_winner_payout, daily_settled_at.
--
-- Function body redeployed via apply_migration (required DROP first
-- because changing the return type of a function isn't allowed otherwise).

-- (No-op marker; the live function body matches the apply_migration call
-- named 'my_family_room_expose_daily_settle_state'.)
select 1;
