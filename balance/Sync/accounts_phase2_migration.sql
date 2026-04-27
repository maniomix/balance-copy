-- ============================================================
-- Accounts rebuild — Phase 2 schema migration
-- ============================================================
-- Adds three columns consumed by the rebuilt Accounts surface.
-- Existing rows decode fine without the columns (the Swift
-- decoder defaults them), but inserts/updates from the new
-- client will write these fields, so the columns must exist.
-- ============================================================

ALTER TABLE accounts
    ADD COLUMN IF NOT EXISTS display_order        INTEGER  NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS color_tag            TEXT,
    ADD COLUMN IF NOT EXISTS include_in_net_worth BOOLEAN  NOT NULL DEFAULT TRUE;

-- Initial display_order: preserve current "newest first" ordering as the
-- starting custom order. Older accounts get higher indices.
WITH ranked AS (
    SELECT id,
           ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at DESC) - 1 AS rn
    FROM accounts
)
UPDATE accounts a
SET    display_order = r.rn
FROM   ranked r
WHERE  a.id = r.id
AND    a.display_order = 0;

CREATE INDEX IF NOT EXISTS accounts_user_display_order_idx
    ON accounts (user_id, display_order);
