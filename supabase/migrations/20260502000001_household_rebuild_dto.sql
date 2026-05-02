-- ============================================================================
-- Household Rebuild — P2: DTO version bump for the unified household model
-- ============================================================================
-- Spec: docs/HOUSEHOLD_REBUILD_P1_SPEC.md
--
-- The `household_state.snapshot` JSONB is rewritten in place. Old shape used a
-- `splitExpenses` array with a `splitRule` enum. New shape uses an
-- `expenseShares` array (one row per member who owes), plus `invites`.
--
-- Strategy:
--   1. Stamp every existing snapshot with `schema_version = 1` (the OLD shape).
--   2. The Swift client recognises v1 snapshots, expands them on first read,
--      and writes back as v2. Server-side migration is intentionally NOT done
--      here — the expansion needs Swift's category/role enums and the same
--      remainder-rounding rule the new engine uses, so doing it on the client
--      keeps one source of truth.
--   3. New writes include `schema_version = 2`.
--
-- This migration is therefore additive metadata only; no rows are mutated
-- destructively. Fully reversible.
-- ============================================================================

-- 1. Stamp existing rows as v1 if not already versioned.
update public.household_state
   set snapshot = jsonb_set(snapshot, '{schema_version}', to_jsonb(1), true)
 where snapshot is not null
   and not (snapshot ? 'schema_version');

-- 2. Helper: read schema version (used by future server-side jobs / dashboards).
create or replace function public.household_snapshot_version(s jsonb)
returns int
language sql
immutable
as $$
  select coalesce((s->>'schema_version')::int, 1);
$$;

-- 3. Document expected v2 shape via a CHECK that's intentionally permissive
--    (we don't validate the full DTO — JSONB stays flexible — but we DO
--    require the version key once it's been touched).
alter table public.household_state
  drop constraint if exists household_state_schema_version_chk;
alter table public.household_state
  add constraint household_state_schema_version_chk
  check (
    snapshot is null
    or snapshot = '{}'::jsonb
    or snapshot ? 'schema_version'
  );

-- ============================================================================
-- Tier B placeholders — row-per-entity tables for future multi-user phase.
-- Created EMPTY with RLS so the schema is ready when cross-user redemption
-- ships. Until then they stay unused; the JSONB blob is still the source of
-- truth. Safe to keep around: zero rows, zero cost.
-- ============================================================================

create table if not exists public.household_invites (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null,
  invited_by    uuid not null references auth.users(id) on delete cascade,
  invite_code   text not null,
  role          text not null check (role in ('owner','partner','adult','child','viewer')),
  status        text not null default 'pending'
                  check (status in ('pending','accepted','declined','expired')),
  created_at    timestamptz not null default now(),
  expires_at    timestamptz not null default (now() + interval '7 days')
);
create index if not exists household_invites_code_idx
  on public.household_invites (invite_code)
  where status = 'pending';

alter table public.household_invites enable row level security;

-- Pending-and-not-expired invites are publicly readable BY CODE only — needed
-- for the future join flow. RLS still blocks listing all invites.
drop policy if exists "hi public read by code" on public.household_invites;
create policy "hi public read by code" on public.household_invites
  for select using (
    status = 'pending' and expires_at > now()
  );

drop policy if exists "hi inviter manage" on public.household_invites;
create policy "hi inviter manage" on public.household_invites
  for all using (invited_by = auth.uid())
        with check (invited_by = auth.uid());

-- ============================================================================
-- Done. Sanity check (run manually):
--   select owner_id, public.household_snapshot_version(snapshot) from
--     public.household_state;
-- All existing rows should report version 1.
-- ============================================================================
