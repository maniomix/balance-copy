-- ============================================================================
-- Centmond — Phase 5.6: Subscription state store.
-- ============================================================================
-- The original `public.subscriptions` table modeled subscriptions as per-row
-- entities, but the iOS/macOS apps already keep a much richer in-memory model
-- (DetectedSubscription with charge history, detection rationale, status
-- overrides, etc.) that is JSON-encoded into a single SubscriptionStoreSnapshot.
--
-- Mapping every field to columns is bloat with no upside. Instead store the
-- snapshot as a single JSONB blob per user.
-- ============================================================================

drop table if exists public.subscriptions cascade;

create table public.subscription_state (
  owner_id    uuid primary key references auth.users(id) on delete cascade,
  snapshot    jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now()
);
create trigger trg_subscription_state_updated before update on public.subscription_state
  for each row execute procedure moddatetime(updated_at);

alter table public.subscription_state enable row level security;
create policy "ss self select" on public.subscription_state
  for select using (owner_id = auth.uid());
create policy "ss self upsert insert" on public.subscription_state
  for insert with check (owner_id = auth.uid());
create policy "ss self upsert update" on public.subscription_state
  for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "ss self delete" on public.subscription_state
  for delete using (owner_id = auth.uid());
