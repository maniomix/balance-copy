-- ============================================================================
-- Centmond — Phase 5.10: owner-fill trigger on app_events.
-- ============================================================================
-- owner_id is nullable on `app_events` so anon events (pre-signin) can land,
-- but for signed-in users we want auth.uid() to fill in automatically.
-- ============================================================================

create trigger trg_app_events_fill_owner
  before insert on public.app_events
  for each row execute function public.fill_owner_id();
