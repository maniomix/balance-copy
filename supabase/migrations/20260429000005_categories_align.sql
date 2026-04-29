-- ============================================================================
-- Centmond — Phase 5.2: Align categories table with CustomCategoryModel,
-- plus a generic owner-id auto-fill trigger.
-- ============================================================================

-- 1. Rename color → color_hex to match CustomCategoryModel.colorHex
alter table public.categories rename column color to color_hex;

-- 2. Generic helper: fill owner_id from auth.uid() if the client didn't send
--    it. Lets Swift models that don't include owner_id still satisfy the RLS
--    WITH CHECK (since auth.uid() is what RLS checks against anyway).
create or replace function public.fill_owner_id()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if NEW.owner_id is null then
    NEW.owner_id := auth.uid();
  end if;
  return NEW;
end;
$$;

create trigger trg_categories_fill_owner
  before insert on public.categories
  for each row execute function public.fill_owner_id();
