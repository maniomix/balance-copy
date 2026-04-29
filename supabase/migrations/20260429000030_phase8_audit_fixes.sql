-- ============================================================================
-- Centmond — Phase 8: Pre-launch audit fixes
-- ============================================================================
-- Addresses Supabase security + performance advisor warnings:
--   • 71× auth_rls_initplan         → rewrite all RLS policies with (select auth.uid())
--   • 2×  unindexed_foreign_keys    → ai_chat_messages.owner_id, goals.linked_account_id
--   • 2×  extension_in_public       → move moddatetime + pg_trgm to extensions schema
--   • 4×  *_security_definer_executable → revoke EXECUTE on trigger functions
--
-- Skipped (deferred until real traffic):
--   • unused_index (9)              → wait for production queries before dropping
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- 1. RLS rewrite — wrap auth.uid() in (select auth.uid())
-- ────────────────────────────────────────────────────────────────────────────
-- Postgres only re-evaluates `auth.uid()` for each row when called inline; the
-- subquery form is hoisted to an InitPlan and runs once per query. For tables
-- with thousands of rows this is the difference between O(n) and O(1) on the
-- auth lookup.
--
-- Strategy: drop and recreate every owner-keyed policy with the new shape.
-- Generated mechanically — same predicates, just wrapped.

-- Helper DO block: regenerate the standard 4-policy set on owner_id tables
do $$
declare
  t text;
  owner_tables text[] := array[
    'accounts','categories','transactions','monthly_budgets','monthly_category_budgets',
    'goals','goal_contributions','subscription_state','household_state',
    'ai_memory','ai_chat_sessions','ai_chat_messages',
    'attachments','saved_filter_presets','device_sessions','app_events'
  ];
begin
  foreach t in array owner_tables loop
    -- Drop existing policies (names match the patterns from earlier migrations).
    execute format('drop policy if exists "%s self select" on public.%I', t, t);
    execute format('drop policy if exists "%s self insert" on public.%I', t, t);
    execute format('drop policy if exists "%s self update" on public.%I', t, t);
    execute format('drop policy if exists "%s self delete" on public.%I', t, t);
    -- Also drop the abbreviated "ss"/"hs"/"mb"/"mcb" variants used by some tables.
    -- (Idempotent — drop-if-exists.)
    execute format('drop policy if exists "ss self select" on public.%I', t);
    execute format('drop policy if exists "ss self upsert insert" on public.%I', t);
    execute format('drop policy if exists "ss self upsert update" on public.%I', t);
    execute format('drop policy if exists "ss self delete" on public.%I', t);
    execute format('drop policy if exists "hs self select" on public.%I', t);
    execute format('drop policy if exists "hs self insert" on public.%I', t);
    execute format('drop policy if exists "hs self update" on public.%I', t);
    execute format('drop policy if exists "hs self delete" on public.%I', t);
    execute format('drop policy if exists "mb self select" on public.%I', t);
    execute format('drop policy if exists "mb self insert" on public.%I', t);
    execute format('drop policy if exists "mb self update" on public.%I', t);
    execute format('drop policy if exists "mb self delete" on public.%I', t);
    execute format('drop policy if exists "mcb self select" on public.%I', t);
    execute format('drop policy if exists "mcb self insert" on public.%I', t);
    execute format('drop policy if exists "mcb self update" on public.%I', t);
    execute format('drop policy if exists "mcb self delete" on public.%I', t);

    execute format('create policy "%s self select" on public.%I for select using (owner_id = (select auth.uid()))', t, t);
    execute format('create policy "%s self insert" on public.%I for insert with check (owner_id = (select auth.uid()))', t, t);
    execute format('create policy "%s self update" on public.%I for update using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()))', t, t);
    execute format('create policy "%s self delete" on public.%I for delete using (owner_id = (select auth.uid()))', t, t);
  end loop;
end $$;

-- profiles uses `id` (= auth.users.id) instead of `owner_id`
drop policy if exists "profiles self select" on public.profiles;
drop policy if exists "profiles self update" on public.profiles;
drop policy if exists "profiles self delete" on public.profiles;
create policy "profiles self select" on public.profiles for select using (id = (select auth.uid()));
create policy "profiles self update" on public.profiles for update using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy "profiles self delete" on public.profiles for delete using (id = (select auth.uid()));

-- account_balance_snapshots wasn't in the array above (left over from prior schema?) — also fix if present.
do $$ begin
  if exists (select 1 from pg_tables where schemaname='public' and tablename='account_balance_snapshots') then
    execute 'drop policy if exists "account_balance_snapshots self select" on public.account_balance_snapshots';
    execute 'drop policy if exists "account_balance_snapshots self insert" on public.account_balance_snapshots';
    execute 'drop policy if exists "account_balance_snapshots self update" on public.account_balance_snapshots';
    execute 'drop policy if exists "account_balance_snapshots self delete" on public.account_balance_snapshots';
    execute 'create policy "account_balance_snapshots self select" on public.account_balance_snapshots for select using (owner_id = (select auth.uid()))';
    execute 'create policy "account_balance_snapshots self insert" on public.account_balance_snapshots for insert with check (owner_id = (select auth.uid()))';
    execute 'create policy "account_balance_snapshots self update" on public.account_balance_snapshots for update using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()))';
    execute 'create policy "account_balance_snapshots self delete" on public.account_balance_snapshots for delete using (owner_id = (select auth.uid()))';
  end if;
end $$;

-- ────────────────────────────────────────────────────────────────────────────
-- 2. Add missing FK indexes
-- ────────────────────────────────────────────────────────────────────────────
create index if not exists ai_chat_messages_owner_idx on public.ai_chat_messages(owner_id);
create index if not exists goals_linked_account_idx   on public.goals(linked_account_id);

-- ────────────────────────────────────────────────────────────────────────────
-- 3. Move extensions out of public
-- ────────────────────────────────────────────────────────────────────────────
create schema if not exists extensions;
alter extension moddatetime set schema extensions;
alter extension pg_trgm     set schema extensions;
-- pgcrypto stays where Supabase placed it (extensions schema already).

-- ────────────────────────────────────────────────────────────────────────────
-- 4. Revoke RPC access on trigger-only functions
-- ────────────────────────────────────────────────────────────────────────────
-- These functions are wired to triggers (BEFORE INSERT / AFTER INSERT) and
-- should never be exposed via the REST API.
revoke execute on function public.handle_new_user() from anon, authenticated, public;
revoke execute on function public.fill_owner_id()   from anon, authenticated, public;
