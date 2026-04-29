-- ============================================================================
-- Centmond — Phase 5.4: Replace recurring-period `budgets` table with two
-- month-keyed tables matching the Swift `Store.budgetsByMonth` /
-- `Store.categoryBudgetsByMonth` shape.
-- ============================================================================
-- The original `public.budgets(period, start_date, ...)` table was a
-- recurring-period model. Swift uses per-month overrides keyed on
-- "YYYY-MM" strings. Two new tables reflect that shape directly.
--
-- monthly_budgets         — total budget per month (cents)
-- monthly_category_budgets — per-category budget per month (cents)
-- ============================================================================

drop table if exists public.budgets cascade;

create table public.monthly_budgets (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references auth.users(id) on delete cascade,
  month         text not null,           -- YYYY-MM
  total_amount  bigint not null default 0,
  currency      char(3) not null default 'EUR',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (owner_id, month)
);
create index mb_owner_month_idx on public.monthly_budgets(owner_id, month);
create trigger trg_mb_updated before update on public.monthly_budgets
  for each row execute procedure moddatetime(updated_at);
create trigger trg_mb_fill_owner before insert on public.monthly_budgets
  for each row execute function public.fill_owner_id();

alter table public.monthly_budgets enable row level security;
create policy "mb self select" on public.monthly_budgets for select using (owner_id = auth.uid());
create policy "mb self insert" on public.monthly_budgets for insert with check (owner_id = auth.uid());
create policy "mb self update" on public.monthly_budgets for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "mb self delete" on public.monthly_budgets for delete using (owner_id = auth.uid());

create table public.monthly_category_budgets (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references auth.users(id) on delete cascade,
  month         text not null,           -- YYYY-MM
  category_key  text not null,           -- "groceries", "custom:Coffee", …
  amount        bigint not null default 0,
  currency      char(3) not null default 'EUR',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (owner_id, month, category_key)
);
create index mcb_owner_month_idx on public.monthly_category_budgets(owner_id, month);
create trigger trg_mcb_updated before update on public.monthly_category_budgets
  for each row execute procedure moddatetime(updated_at);
create trigger trg_mcb_fill_owner before insert on public.monthly_category_budgets
  for each row execute function public.fill_owner_id();

alter table public.monthly_category_budgets enable row level security;
create policy "mcb self select" on public.monthly_category_budgets for select using (owner_id = auth.uid());
create policy "mcb self insert" on public.monthly_category_budgets for insert with check (owner_id = auth.uid());
create policy "mcb self update" on public.monthly_category_budgets for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "mcb self delete" on public.monthly_category_budgets for delete using (owner_id = auth.uid());
