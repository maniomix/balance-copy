-- ============================================================================
-- Centmond — Phase 5.6.5: Membership tier columns on profiles.
-- ============================================================================
-- The app's *own* paid plan ("Centmond Membership") gates Pro features. This
-- is distinct from the user-tracked services feature (Netflix/Spotify/etc.)
-- which now lives in `subscription_state`.
--
-- Tiers: free | pro_trial | pro. StoreKit is the source of truth — these
-- columns are a cloud cache so other devices know the user's tier without
-- re-querying Apple.
-- ============================================================================

alter table public.profiles
  add column membership_tier   text not null default 'free'
                               check (membership_tier in ('free','pro_trial','pro')),
  add column trial_started_at  timestamptz,
  add column trial_ends_at     timestamptz,
  add column pro_period_end    timestamptz,
  add column pro_platform      text check (pro_platform in ('apple','web','manual'));
