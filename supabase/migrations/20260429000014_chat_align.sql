-- ============================================================================
-- Centmond — Phase 5.9b: Align ai_chat_messages with Swift ChatMessageRecord.
-- ============================================================================
-- Swift stores `actionsJSON: Data?` representing a `[AIAction]` array. The
-- schema column was singular `action jsonb`. Renaming for clarity.
-- ============================================================================

alter table public.ai_chat_messages rename column action to actions;

-- owner-fill triggers so Swift doesn't have to send owner_id on insert
create trigger trg_chat_sessions_fill_owner before insert on public.ai_chat_sessions
  for each row execute function public.fill_owner_id();
create trigger trg_chat_messages_fill_owner before insert on public.ai_chat_messages
  for each row execute function public.fill_owner_id();
