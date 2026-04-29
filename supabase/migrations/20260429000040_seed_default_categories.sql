-- ============================================================================
-- Centmond — P12: Seed default categories per user
-- ============================================================================
-- Up to now, the 9 built-in categories (groceries, rent, bills, …) lived only
-- in the Swift `Category` enum and never hit the DB. That worked fine for the
-- iOS/macOS apps but means future web admin queries can't enumerate categories
-- without embedding the Swift constants.
--
-- Adds a nullable `storage_key` column for joining `transactions.category_key`
-- back to a `categories` row. Built-ins fill it; customs leave it null
-- (a custom category's `name` is its identity).
--
-- The `handle_new_user` trigger now seeds the 9 built-ins on signup. Existing
-- users get the rows backfilled at the bottom of this migration.
-- ============================================================================

alter table public.categories
  add column if not exists storage_key text;

-- Built-ins identified by storage_key; customs identified by name.
create unique index if not exists categories_owner_storage_key_uidx
  on public.categories(owner_id, storage_key)
  where storage_key is not null;

-- ----------------------------------------------------------------------------
-- handle_new_user: keep the existing profile insert + add categories seeding.
-- ----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email,'@',1)))
  on conflict (id) do nothing;

  -- Seed 9 built-in categories. Each user owns their own copies so they can
  -- rename or recolor them without affecting other users; the `storage_key`
  -- stays stable so transactions.category_key keeps joining correctly.
  insert into public.categories (owner_id, name, kind, icon, color_hex, sort_order, is_custom, storage_key)
  values
    (new.id, 'Groceries',  'expense', 'basket',           '2ECC71', 0, false, 'groceries'),
    (new.id, 'Rent',       'expense', 'house',            '3498DB', 1, false, 'rent'),
    (new.id, 'Bills',      'expense', 'doc.text',         'F39C12', 2, false, 'bills'),
    (new.id, 'Transport',  'expense', 'car',              '9B59B6', 3, false, 'transport'),
    (new.id, 'Health',     'expense', 'cross.case',       'E74C3C', 4, false, 'health'),
    (new.id, 'Education',  'expense', 'book',             '1ABC9C', 5, false, 'education'),
    (new.id, 'Dining',     'expense', 'fork.knife',       'E91E63', 6, false, 'dining'),
    (new.id, 'Shopping',   'expense', 'bag',              'FF5722', 7, false, 'shopping'),
    (new.id, 'Other',      'expense', 'square.grid.2x2',  '607D8B', 8, false, 'other')
  on conflict (owner_id, name) do nothing;

  return new;
end;
$$;

-- ----------------------------------------------------------------------------
-- Backfill: existing users get the rows now.
-- ----------------------------------------------------------------------------
insert into public.categories (owner_id, name, kind, icon, color_hex, sort_order, is_custom, storage_key)
select u.id, defaults.name, 'expense', defaults.icon, defaults.color_hex,
       defaults.sort_order, false, defaults.storage_key
from auth.users u
cross join (values
  ('Groceries',  'basket',          '2ECC71', 0, 'groceries'),
  ('Rent',       'house',           '3498DB', 1, 'rent'),
  ('Bills',      'doc.text',        'F39C12', 2, 'bills'),
  ('Transport',  'car',             '9B59B6', 3, 'transport'),
  ('Health',     'cross.case',      'E74C3C', 4, 'health'),
  ('Education',  'book',            '1ABC9C', 5, 'education'),
  ('Dining',     'fork.knife',      'E91E63', 6, 'dining'),
  ('Shopping',   'bag',             'FF5722', 7, 'shopping'),
  ('Other',      'square.grid.2x2', '607D8B', 8, 'other')
) as defaults(name, icon, color_hex, sort_order, storage_key)
on conflict (owner_id, name) do nothing;
