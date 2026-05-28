-- Refresh cached fallback encouragement rows after expanding the fallback
-- rotation. This keeps today's Home card from staying stuck on the older
-- seven-day fallback if the Edge Function has no OPENAI_API_KEY yet.

update public.daily_encouragements de
set payload = public.daily_encouragement_fallback(de.encouragement_date),
    source = 'fallback'
where de.source = 'fallback';
