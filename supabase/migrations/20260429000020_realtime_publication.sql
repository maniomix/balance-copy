-- ============================================================================
-- Centmond — Phase 6: Realtime publication
-- ============================================================================
-- Publishes the cross-device-relevant tables to `supabase_realtime`. RLS
-- still applies — clients only receive events for rows they would be
-- allowed to SELECT, so each user only sees their own changes.
--
-- Skipped:
--   • app_events       (append-only analytics — noisy, not worth syncing back)
--   • device_sessions  (internal heartbeat)
--   • attachments      (rarely changes; the parent transaction event is enough)
-- ============================================================================

alter publication supabase_realtime add table public.profiles;
alter publication supabase_realtime add table public.accounts;
alter publication supabase_realtime add table public.categories;
alter publication supabase_realtime add table public.transactions;
alter publication supabase_realtime add table public.monthly_budgets;
alter publication supabase_realtime add table public.monthly_category_budgets;
alter publication supabase_realtime add table public.goals;
alter publication supabase_realtime add table public.goal_contributions;
alter publication supabase_realtime add table public.subscription_state;
alter publication supabase_realtime add table public.household_state;
alter publication supabase_realtime add table public.ai_memory;
alter publication supabase_realtime add table public.ai_chat_sessions;
alter publication supabase_realtime add table public.ai_chat_messages;
alter publication supabase_realtime add table public.saved_filter_presets;
