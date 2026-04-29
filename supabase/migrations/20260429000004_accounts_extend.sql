-- ============================================================================
-- Centmond — Phase 5.1: Extend accounts table to match Swift Account model
-- ============================================================================
-- Adds: current_balance, institution_name, credit_limit, interest_rate,
--       include_in_net_worth
-- Renames: sort_order → display_order, color → color_tag
-- Replaces: archived_at (timestamptz) → is_archived (boolean)
-- Updates: type CHECK constraint to match Swift AccountType raw values
-- New: account_balance_snapshots table + RLS + owner-inheriting trigger
-- ============================================================================

-- 1. Drop dependent index, then drop archived_at
drop index if exists public.accounts_owner_active_idx;
alter table public.accounts drop column archived_at;

-- 2. Renames
alter table public.accounts rename column sort_order   to display_order;
alter table public.accounts rename column color        to color_tag;

-- 3. New columns
alter table public.accounts
  add column current_balance       numeric(14,2) not null default 0,
  add column institution_name      text,
  add column credit_limit          numeric(14,2),
  add column interest_rate         numeric(6,3),
  add column include_in_net_worth  boolean not null default true,
  add column is_archived           boolean not null default false;

-- 4. Update type CHECK to match Swift AccountType raw values
alter table public.accounts drop constraint accounts_type_check;
alter table public.accounts
  add constraint accounts_type_check
  check (type in ('cash','bank','credit_card','savings','investment','loan'));

-- 5. Recreate partial index on the new is_archived column
create index accounts_owner_active_idx
  on public.accounts(owner_id)
  where is_archived = false;

-- 6. account_balance_snapshots
create table public.account_balance_snapshots (
  id             uuid primary key default gen_random_uuid(),
  account_id     uuid not null references public.accounts(id) on delete cascade,
  owner_id       uuid not null references auth.users(id) on delete cascade,
  balance        numeric(14,2) not null,
  snapshot_date  timestamptz not null default now(),
  created_at     timestamptz not null default now()
);
create index abs_account_idx on public.account_balance_snapshots(account_id, snapshot_date desc);
create index abs_owner_idx   on public.account_balance_snapshots(owner_id);

alter table public.account_balance_snapshots enable row level security;
create policy "abs self select" on public.account_balance_snapshots
  for select using (owner_id = auth.uid());
create policy "abs self insert" on public.account_balance_snapshots
  for insert with check (owner_id = auth.uid());
create policy "abs self update" on public.account_balance_snapshots
  for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "abs self delete" on public.account_balance_snapshots
  for delete using (owner_id = auth.uid());

-- Trigger so the client only needs to send account_id + balance; owner_id is
-- inherited from the parent account row. Saves the Swift side from having to
-- pass auth.uid() on every snapshot insert.
create or replace function public.abs_inherit_owner()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if NEW.owner_id is null then
    select owner_id into NEW.owner_id from public.accounts where id = NEW.account_id;
  end if;
  return NEW;
end;
$$;
create trigger trg_abs_inherit_owner
  before insert on public.account_balance_snapshots
  for each row execute function public.abs_inherit_owner();
