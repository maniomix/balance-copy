-- ============================================================================
-- Centmond — Phase 5.7: Replace household_* row-per-entity tables with a
-- per-user JSONB blob, matching the existing iOS HouseholdManager local-first
-- design and the locked decision that household stays per-user.
-- ============================================================================
-- The Swift household domain has 7+ inter-linked entity types (Household,
-- HouseholdGroup, HouseholdMember, SplitExpense, Settlement, SharedBudget,
-- SharedGoal, HouseholdInvite). Modelling each as a row table required ~640
-- lines of bespoke mapping in HouseholdSyncManager and didn't unlock any
-- server-side query the app actually performs.
--
-- One JSONB blob per user matches the access pattern (load all on launch,
-- save all on edit) and mirrors what we did for subscription_state.
--
-- Cross-user invite-code lookup is deferred until a future "household linking"
-- phase. For now joinHouseholdViaCloud always returns nil.
-- ============================================================================

drop table if exists public.household_settlements cascade;
drop table if exists public.household_members cascade;
drop table if exists public.household_groups cascade;

create table public.household_state (
  owner_id    uuid primary key references auth.users(id) on delete cascade,
  snapshot    jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now()
);
create trigger trg_household_state_updated before update on public.household_state
  for each row execute procedure moddatetime(updated_at);

alter table public.household_state enable row level security;
create policy "hs self select" on public.household_state
  for select using (owner_id = auth.uid());
create policy "hs self insert" on public.household_state
  for insert with check (owner_id = auth.uid());
create policy "hs self update" on public.household_state
  for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "hs self delete" on public.household_state
  for delete using (owner_id = auth.uid());
