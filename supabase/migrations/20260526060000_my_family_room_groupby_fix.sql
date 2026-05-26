-- Hotfix: my_family_room was throwing "subquery uses ungrouped column m.room_id"
-- because the morning_reads / evening_reads subqueries correlated on m.room_id
-- but m.room_id wasn't in the member_stats GROUP BY clause.
--
-- Side effect: my_family_room threw and the client treated the empty payload
-- as "not in a family room" -- showing the Create-a-Room empty state for
-- everyone in the Bell Family.
--
-- Fix: pull morning_reads / evening_reads up into the SUM(CASE ...) form
-- so no correlated subquery is needed, and add m.room_id to the GROUP BY
-- defensively. Function body redeployed via apply_migration with the
-- corrected aggregation.
--
-- This file documents the fix; the live function body matches the latest
-- apply_migration call.

-- (No-op marker.) The redefinition was applied directly via apply_migration
-- and lives in migration history under name 'my_family_room_groupby_fix'.
select 1;
