-- ============================================================================
-- Centmond — Phase 2: Row Level Security policies
-- Rule: every row keyed to auth.uid() via owner_id (or via parent for
-- household_members / household_settlements).
-- ============================================================================

-- profiles: a user sees and edits only their own row. No insert (trigger does it).
create policy "profiles self select" on public.profiles
  for select using (id = auth.uid());
create policy "profiles self update" on public.profiles
  for update using (id = auth.uid()) with check (id = auth.uid());
create policy "profiles self delete" on public.profiles
  for delete using (id = auth.uid());

-- Helper macro pattern: owner_id = auth.uid() on all four ops.
do $$
declare
  t text;
  owner_tables text[] := array[
    'accounts','categories','transactions','budgets','goals','goal_contributions',
    'subscriptions','saved_filter_presets','attachments',
    'household_groups',
    'ai_chat_sessions','ai_chat_messages','ai_action_history','ai_memory',
    'ai_fewshot_examples','ai_merchant_aliases','ai_proactive_dismissals',
    'device_sessions','app_events'
  ];
begin
  foreach t in array owner_tables loop
    execute format('create policy "%s self select" on public.%I for select using (owner_id = auth.uid())', t, t);
    execute format('create policy "%s self insert" on public.%I for insert with check (owner_id = auth.uid())', t, t);
    execute format('create policy "%s self update" on public.%I for update using (owner_id = auth.uid()) with check (owner_id = auth.uid())', t, t);
    execute format('create policy "%s self delete" on public.%I for delete using (owner_id = auth.uid())', t, t);
  end loop;
end $$;

-- household_members: visible to the group owner; managed by the group owner.
create policy "hh_members select" on public.household_members
  for select using (
    exists (select 1 from public.household_groups g
            where g.id = household_members.group_id and g.owner_id = auth.uid())
  );
create policy "hh_members insert" on public.household_members
  for insert with check (
    exists (select 1 from public.household_groups g
            where g.id = household_members.group_id and g.owner_id = auth.uid())
  );
create policy "hh_members update" on public.household_members
  for update using (
    exists (select 1 from public.household_groups g
            where g.id = household_members.group_id and g.owner_id = auth.uid())
  ) with check (
    exists (select 1 from public.household_groups g
            where g.id = household_members.group_id and g.owner_id = auth.uid())
  );
create policy "hh_members delete" on public.household_members
  for delete using (
    exists (select 1 from public.household_groups g
            where g.id = household_members.group_id and g.owner_id = auth.uid())
  );

-- household_settlements: same — only the group owner.
create policy "hh_settle select" on public.household_settlements
  for select using (
    exists (select 1 from public.household_groups g
            where g.id = household_settlements.group_id and g.owner_id = auth.uid())
  );
create policy "hh_settle insert" on public.household_settlements
  for insert with check (
    exists (select 1 from public.household_groups g
            where g.id = household_settlements.group_id and g.owner_id = auth.uid())
  );
create policy "hh_settle update" on public.household_settlements
  for update using (
    exists (select 1 from public.household_groups g
            where g.id = household_settlements.group_id and g.owner_id = auth.uid())
  ) with check (
    exists (select 1 from public.household_groups g
            where g.id = household_settlements.group_id and g.owner_id = auth.uid())
  );
create policy "hh_settle delete" on public.household_settlements
  for delete using (
    exists (select 1 from public.household_groups g
            where g.id = household_settlements.group_id and g.owner_id = auth.uid())
  );
