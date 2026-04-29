-- ============================================================================
-- Centmond — P13: pg_cron retention jobs
-- ============================================================================
-- Keeps tables that grow unbounded under control.
--   • app_events older than 90 days      → daily delete
--   • device_sessions inactive > 6 months → daily delete
--
-- Anything user-owned (transactions, goals, etc.) is NEVER touched by cron —
-- those are user data and only get removed via explicit user action or the
-- `delete_account()` cascade.
-- ============================================================================

create extension if not exists pg_cron with schema extensions;

-- Schedule lives on the postgres database. Re-running this migration is safe
-- because cron.schedule replaces an existing job with the same name.

select cron.schedule(
  'centmond_cleanup_app_events',
  '0 3 * * *',  -- daily at 03:00 UTC
  $$ delete from public.app_events where occurred_at < now() - interval '90 days' $$
);

select cron.schedule(
  'centmond_cleanup_device_sessions',
  '15 3 * * *', -- daily at 03:15 UTC
  $$ delete from public.device_sessions where last_seen_at < now() - interval '180 days' $$
);

-- Inspect / unschedule via the dashboard or:
--   select * from cron.job;
--   select cron.unschedule('centmond_cleanup_app_events');
