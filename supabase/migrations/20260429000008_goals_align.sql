-- ============================================================================
-- Centmond — Phase 5.5: Align goals + goal_contributions tables with the
-- post-Goals-Rebuild Swift models.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- goals
-- ---------------------------------------------------------------------------
-- numeric → bigint (cents)
alter table public.goals alter column target_amount  type bigint using (target_amount)::bigint;
alter table public.goals alter column current_amount type bigint using (current_amount)::bigint;

-- Renames to match Swift CodingKeys
alter table public.goals rename column color      to color_token;
alter table public.goals rename column account_id to linked_account_id;

-- Replace timestamp flags with booleans (Swift uses Bool)
alter table public.goals add column is_archived boolean not null default false;
alter table public.goals add column is_completed boolean not null default false;
update public.goals set is_archived = (archived_at is not null),
                        is_completed = (completed_at is not null);
alter table public.goals drop column archived_at;
alter table public.goals drop column completed_at;

-- New columns from Phase 1.5+ of the iOS Goals rebuild
alter table public.goals
  add column type                     text not null default 'custom'
                                      check (type in ('emergency_fund','vacation','tax','gadget','car','home','custom')),
  add column notes                    text,
  add column priority                 integer not null default 0,
  add column paused_at                timestamptz,
  add column category_storage_key     text,
  add column original_target_amount   bigint not null default 0,
  add column household_id             uuid;

-- Backfill original_target_amount = target_amount for any preexisting rows.
update public.goals set original_target_amount = target_amount
  where original_target_amount = 0 and target_amount > 0;

-- ---------------------------------------------------------------------------
-- goal_contributions
-- ---------------------------------------------------------------------------
-- numeric → bigint (cents). Negative values allowed (withdrawals).
alter table public.goal_contributions alter column amount type bigint using (amount)::bigint;

-- Drop currency (Swift contribution model has none)
alter table public.goal_contributions drop column currency;

-- Drop occurred_at (Swift only has createdAt; created_at is enough)
alter table public.goal_contributions drop column occurred_at;

-- Rename transaction_id → linked_transaction_id (Swift CodingKey)
alter table public.goal_contributions rename column transaction_id to linked_transaction_id;

-- Update source CHECK to Swift's ContributionSource enum raw values.
alter table public.goal_contributions drop constraint goal_contributions_source_check;
alter table public.goal_contributions
  add constraint goal_contributions_source_check
  check (source in ('manual','transaction','transfer','allocation_rule','ai_action','round_up'));

-- New columns
alter table public.goal_contributions
  add column linked_rule_id  uuid,
  add column is_reversed     boolean not null default false,
  add column reversed_at     timestamptz;

create index gc_linked_tx_idx on public.goal_contributions(linked_transaction_id);
create index gc_linked_rule_idx on public.goal_contributions(linked_rule_id);

-- ---------------------------------------------------------------------------
-- owner-fill triggers (Swift Goal carries userId, but contributions don't)
-- ---------------------------------------------------------------------------
create trigger trg_goals_fill_owner before insert on public.goals
  for each row execute function public.fill_owner_id();
create trigger trg_gc_fill_owner before insert on public.goal_contributions
  for each row execute function public.fill_owner_id();
