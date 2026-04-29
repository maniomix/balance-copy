-- ============================================================================
-- Centmond — Phase 5.3: Align transactions table with Swift Transaction model.
-- ============================================================================
-- Drops:    category_id (FK), transfer_pair_id (FK)
-- Replaces: amount numeric(14,2) → bigint (Swift uses cents-as-Int)
-- Adds:     category_key, transfer_group_id, payment_method, is_flagged,
--           linked_goal_id
-- Loosens:  account_id NOT NULL → nullable (Swift accountId is optional)
-- Tightens: type CHECK to ('income','expense') (transfer is encoded via
--           transfer_group_id; legs keep their normal income/expense type)
-- Trigger:  fill_owner_id on insert
-- ============================================================================

drop index if exists public.tx_category_idx;
drop index if exists public.tx_transfer_pair_idx;

alter table public.transactions drop column category_id;
alter table public.transactions drop column transfer_pair_id;

alter table public.transactions drop constraint transactions_type_check;
alter table public.transactions
  add constraint transactions_type_check check (type in ('income','expense'));

-- numeric → bigint (cents). Empty table so the cast is a no-op.
alter table public.transactions alter column amount type bigint using (amount)::bigint;

alter table public.transactions alter column account_id drop not null;

alter table public.transactions
  add column category_key      text,
  add column transfer_group_id uuid,
  add column payment_method    text not null default 'card'
                               check (payment_method in ('cash','card')),
  add column is_flagged        boolean not null default false,
  add column linked_goal_id    uuid references public.goals(id) on delete set null;

create index tx_category_key_idx   on public.transactions(category_key);
create index tx_transfer_group_idx on public.transactions(transfer_group_id);
create index tx_linked_goal_idx    on public.transactions(linked_goal_id);

create trigger trg_transactions_fill_owner
  before insert on public.transactions
  for each row execute function public.fill_owner_id();
