-- ============================================================
-- Centmond: Goals Rebuild — Phase 1.5 Migration
-- ============================================================
-- Run in the Supabase SQL editor. Additive only — safe to run
-- on production data with existing goals/contributions.
--
-- Adds:
--   goals.priority, is_archived, paused_at, category_storage_key,
--     original_target_amount, household_id
--   goal_contributions.linked_transaction_id, linked_rule_id,
--     is_reversed, reversed_at
-- ============================================================

-- 1. Goals
ALTER TABLE goals
    ADD COLUMN IF NOT EXISTS priority INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS paused_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS category_storage_key TEXT,
    ADD COLUMN IF NOT EXISTS original_target_amount INTEGER,
    ADD COLUMN IF NOT EXISTS household_id UUID;

-- Backfill original_target_amount from current target for existing rows.
UPDATE goals
   SET original_target_amount = target_amount
 WHERE original_target_amount IS NULL;

ALTER TABLE goals
    ALTER COLUMN original_target_amount SET NOT NULL,
    ALTER COLUMN original_target_amount SET DEFAULT 0;

-- 2. Goal Contributions
ALTER TABLE goal_contributions
    ADD COLUMN IF NOT EXISTS linked_transaction_id UUID,
    ADD COLUMN IF NOT EXISTS linked_rule_id UUID,
    ADD COLUMN IF NOT EXISTS is_reversed BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS reversed_at TIMESTAMPTZ;

-- 3. Indexes for new query patterns
CREATE INDEX IF NOT EXISTS idx_goals_user_priority
    ON goals(user_id, priority DESC, target_date ASC NULLS LAST);

CREATE INDEX IF NOT EXISTS idx_goals_household
    ON goals(household_id)
    WHERE household_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_goal_contributions_active
    ON goal_contributions(goal_id, created_at DESC)
    WHERE is_reversed = false;

CREATE INDEX IF NOT EXISTS idx_goal_contributions_linked_tx
    ON goal_contributions(linked_transaction_id)
    WHERE linked_transaction_id IS NOT NULL;
