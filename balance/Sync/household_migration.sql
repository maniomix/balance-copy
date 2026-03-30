-- ============================================================
-- Centmond: Household Cloud Sync — Supabase Migration
-- ============================================================
-- Run this in the Supabase SQL editor to create all household
-- tables with Row-Level Security policies.
--
-- SOURCE-OF-TRUTH MODEL: Same as Store sync —
--   LOCAL-FIRST WRITE, CLOUD-AUTHORITATIVE READ.
--   Household data is scoped by household_id, not user_id.
--   RLS policies grant access to any authenticated member of
--   the household.
-- ============================================================

-- 1. Households
CREATE TABLE IF NOT EXISTS households (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL DEFAULT 'Our Household',
    created_by  TEXT NOT NULL,          -- userId of creator
    invite_code TEXT NOT NULL UNIQUE,   -- 6-char alphanumeric
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE households ENABLE ROW LEVEL SECURITY;

-- 2. Household Members
CREATE TABLE IF NOT EXISTS household_members (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id        UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    user_id             TEXT NOT NULL,
    display_name        TEXT NOT NULL,
    email               TEXT NOT NULL DEFAULT '',
    role                TEXT NOT NULL DEFAULT 'partner',  -- owner | partner | viewer
    joined_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    shared_account_ids  JSONB,          -- null = share all, [] = share none, ["id1","id2"] = specific
    share_transactions  BOOLEAN NOT NULL DEFAULT true,

    UNIQUE(household_id, user_id)
);

ALTER TABLE household_members ENABLE ROW LEVEL SECURITY;

-- 3. Split Expenses
CREATE TABLE IF NOT EXISTS split_expenses (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id    UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    transaction_id  UUID,               -- links to transactions table (nullable for standalone splits)
    amount          INTEGER NOT NULL,    -- cents
    paid_by         TEXT NOT NULL,       -- userId who paid
    split_rule      TEXT NOT NULL DEFAULT 'equal',  -- equal | custom | paidByMe | paidByPartner | percentage:60
    custom_splits   JSONB DEFAULT '[]',  -- [{"userId":"...","amount":500}]
    category        TEXT NOT NULL DEFAULT 'other',
    note            TEXT NOT NULL DEFAULT '',
    date            TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_settled      BOOLEAN NOT NULL DEFAULT false,
    settled_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE split_expenses ENABLE ROW LEVEL SECURITY;

-- 4. Settlements
CREATE TABLE IF NOT EXISTS settlements (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id        UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    from_user_id        TEXT NOT NULL,
    to_user_id          TEXT NOT NULL,
    amount              INTEGER NOT NULL,    -- cents
    note                TEXT NOT NULL DEFAULT 'Settlement',
    date                TIMESTAMPTZ NOT NULL DEFAULT now(),
    related_expense_ids JSONB DEFAULT '[]',  -- [UUID strings]
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE settlements ENABLE ROW LEVEL SECURITY;

-- 5. Shared Budgets
CREATE TABLE IF NOT EXISTS shared_budgets (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id        UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    month_key           TEXT NOT NULL,       -- YYYY-MM
    total_amount        INTEGER NOT NULL,    -- cents
    split_rule          TEXT NOT NULL DEFAULT 'equal',
    category_budgets    JSONB DEFAULT '{}',  -- {"groceries": 5000, "dining": 3000}
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE(household_id, month_key)
);

ALTER TABLE shared_budgets ENABLE ROW LEVEL SECURITY;

-- 6. Shared Goals
CREATE TABLE IF NOT EXISTS shared_goals (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id    UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    icon            TEXT NOT NULL DEFAULT 'star.fill',
    target_amount   INTEGER NOT NULL,    -- cents
    current_amount  INTEGER NOT NULL DEFAULT 0,
    created_by      TEXT NOT NULL,        -- userId
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE shared_goals ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- ROW-LEVEL SECURITY POLICIES
-- ============================================================
-- Pattern: A user can access household data IFF they are a member
-- of that household. We use a helper function for this check.
-- ============================================================

-- Helper: Check if the current authenticated user is a member of a household
CREATE OR REPLACE FUNCTION is_household_member(hh_id UUID)
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1 FROM household_members
        WHERE household_id = hh_id
          AND user_id = auth.uid()::text
    );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Households: members can read, creator can update/delete
CREATE POLICY "Members can view household"
    ON households FOR SELECT
    USING (is_household_member(id));

CREATE POLICY "Authenticated users can create household"
    ON households FOR INSERT
    WITH CHECK (auth.uid()::text = created_by);

CREATE POLICY "Creator can update household"
    ON households FOR UPDATE
    USING (auth.uid()::text = created_by);

CREATE POLICY "Creator can delete household"
    ON households FOR DELETE
    USING (auth.uid()::text = created_by);

-- Household Members: members can read all members, join via insert
CREATE POLICY "Members can view members"
    ON household_members FOR SELECT
    USING (is_household_member(household_id));

CREATE POLICY "Authenticated users can join"
    ON household_members FOR INSERT
    WITH CHECK (auth.uid()::text = user_id);

CREATE POLICY "Owner can manage members"
    ON household_members FOR UPDATE
    USING (is_household_member(household_id));

CREATE POLICY "Owner can remove members"
    ON household_members FOR DELETE
    USING (is_household_member(household_id));

-- Split Expenses: members can CRUD
CREATE POLICY "Members can view splits"
    ON split_expenses FOR SELECT
    USING (is_household_member(household_id));

CREATE POLICY "Members can add splits"
    ON split_expenses FOR INSERT
    WITH CHECK (is_household_member(household_id));

CREATE POLICY "Members can update splits"
    ON split_expenses FOR UPDATE
    USING (is_household_member(household_id));

CREATE POLICY "Members can delete splits"
    ON split_expenses FOR DELETE
    USING (is_household_member(household_id));

-- Settlements: members can CRUD
CREATE POLICY "Members can view settlements"
    ON settlements FOR SELECT
    USING (is_household_member(household_id));

CREATE POLICY "Members can add settlements"
    ON settlements FOR INSERT
    WITH CHECK (is_household_member(household_id));

CREATE POLICY "Members can update settlements"
    ON settlements FOR UPDATE
    USING (is_household_member(household_id));

-- Shared Budgets: members can CRUD
CREATE POLICY "Members can view shared budgets"
    ON shared_budgets FOR SELECT
    USING (is_household_member(household_id));

CREATE POLICY "Members can add shared budgets"
    ON shared_budgets FOR INSERT
    WITH CHECK (is_household_member(household_id));

CREATE POLICY "Members can update shared budgets"
    ON shared_budgets FOR UPDATE
    USING (is_household_member(household_id));

-- Shared Goals: members can CRUD
CREATE POLICY "Members can view shared goals"
    ON shared_goals FOR SELECT
    USING (is_household_member(household_id));

CREATE POLICY "Members can add shared goals"
    ON shared_goals FOR INSERT
    WITH CHECK (is_household_member(household_id));

CREATE POLICY "Members can update shared goals"
    ON shared_goals FOR UPDATE
    USING (is_household_member(household_id));

CREATE POLICY "Members can delete shared goals"
    ON shared_goals FOR DELETE
    USING (is_household_member(household_id));

-- ============================================================
-- INDEXES for performance
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_household_members_household ON household_members(household_id);
CREATE INDEX IF NOT EXISTS idx_household_members_user ON household_members(user_id);
CREATE INDEX IF NOT EXISTS idx_split_expenses_household ON split_expenses(household_id);
CREATE INDEX IF NOT EXISTS idx_split_expenses_date ON split_expenses(date);
CREATE INDEX IF NOT EXISTS idx_settlements_household ON settlements(household_id);
CREATE INDEX IF NOT EXISTS idx_shared_budgets_household_month ON shared_budgets(household_id, month_key);
CREATE INDEX IF NOT EXISTS idx_shared_goals_household ON shared_goals(household_id);
CREATE INDEX IF NOT EXISTS idx_households_invite_code ON households(invite_code);
