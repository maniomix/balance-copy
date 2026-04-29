-- ============================================================================
-- Centmond — Phase 5.9a: Consolidate AI persistence into `ai_memory` kv.
-- ============================================================================
-- AIActionRecord, MerchantProfile, FewShotExample, etc. all have complex
-- nested types (associated-value enums, snapshots, structured rationale)
-- that map poorly to Postgres columns. The app's access pattern is
-- "load-all-on-launch, save-all-on-edit" — never server-side query.
--
-- One row per (owner_id, key) in `ai_memory` keeps the schema flat and
-- mirrors what we did for subscription_state and household_state.
--
-- Used keys (one row each):
--   ai.action_history          [AIActionRecord]
--   ai.memory_entries          [AIMemoryEntry]
--   ai.merchant_profiles       [MerchantProfile]
--   ai.fewshot_examples        [FewShotExample]
--   ai.user_preferences        AIUserPreferences (object)
--   ai.proactive_dismissals    [String]
-- ============================================================================

drop table if exists public.ai_action_history       cascade;
drop table if exists public.ai_fewshot_examples     cascade;
drop table if exists public.ai_merchant_aliases     cascade;
drop table if exists public.ai_proactive_dismissals cascade;

-- Owner-fill trigger so Swift doesn't have to send owner_id explicitly.
create trigger trg_ai_memory_fill_owner
  before insert on public.ai_memory
  for each row execute function public.fill_owner_id();
