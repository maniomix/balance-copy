-- ============================================================================
-- Centmond — Phase 5.8: owner-fill trigger on saved_filter_presets so
-- Swift's SavedFilterPreset (no userId field) can insert.
-- ============================================================================

create trigger trg_filter_presets_fill_owner
  before insert on public.saved_filter_presets
  for each row execute function public.fill_owner_id();
