-- Keep Edge Function cron jobs using the same private cron secret that is
-- also installed as the CRON_SECRET Edge Function secret.

do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'cron')
     and exists (select 1 from pg_namespace where nspname = 'net') then
    begin
      perform cron.unschedule('process-daily-surprises-every-minute');
    exception when others then
      null;
    end;

    perform cron.schedule(
      'process-daily-surprises-every-minute',
      '* * * * *',
      $cron$
        select net.http_post(
          url := 'https://dqlbnpqyoblfsaasydkr.supabase.co/functions/v1/process-daily-surprises',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'x-honeycomb-cron-secret', (select value from private.cron_config where key = 'cron_secret')
          ),
          body := '{}'::jsonb,
          timeout_milliseconds := 30000
        );
      $cron$
    );

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
