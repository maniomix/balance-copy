-- ============================================================================
-- Centmond — Phase 1: Initial schema
-- ============================================================================
-- Conventions:
--   * snake_case columns
--   * uuid PK with gen_random_uuid()
--   * owner_id uuid references auth.users on delete cascade  (HARD DELETE)
--   * money: numeric(14,2) + currency char(3)
--   * timestamps: created_at, updated_at (auto-maintained via moddatetime)
--   * "archive" (hide-but-keep) uses archived_at; UI delete = real DELETE row
-- ============================================================================

create extension if not exists moddatetime;
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Helper: updated_at trigger applied to most tables
-- ---------------------------------------------------------------------------
-- moddatetime is provided by the extension; we use it directly per table.

-- ---------------------------------------------------------------------------
-- profiles  (1:1 with auth.users)
-- ---------------------------------------------------------------------------
create table public.profiles (
  id                    uuid primary key references auth.users(id) on delete cascade,
  display_name          text,
  default_currency      char(3) not null default 'EUR',
  locale                text    not null default 'en',
  theme                 text    not null default 'system'
                                check (theme in ('light','dark','system')),
  ai_mode               text    not null default 'assistant'
                                check (ai_mode in ('advisor','assistant','autopilot','cfo')),
  onboarding_completed  boolean not null default false,
  onboarding_data       jsonb,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create trigger trg_profiles_updated before update on public.profiles
  for each row execute procedure moddatetime(updated_at);

-- Auto-create a profile row whenever a new auth user signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email,'@',1)));
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ---------------------------------------------------------------------------
-- accounts
-- ---------------------------------------------------------------------------
create table public.accounts (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null references auth.users(id) on delete cascade,
  name            text not null,
  type            text not null check (type in ('checking','savings','credit','cash','investment','other')),
  currency        char(3) not null default 'EUR',
  initial_balance numeric(14,2) not null default 0,
  icon            text,
  color           text,
  sort_order      integer not null default 0,
  archived_at     timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index accounts_owner_idx on public.accounts(owner_id);
create index accounts_owner_active_idx on public.accounts(owner_id) where archived_at is null;
create trigger trg_accounts_updated before update on public.accounts
  for each row execute procedure moddatetime(updated_at);

-- ---------------------------------------------------------------------------
-- categories  (built-ins seeded per user on first sign-in by the app)
-- ---------------------------------------------------------------------------
create table public.categories (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references auth.users(id) on delete cascade,
  name        text not null,
  kind        text not null check (kind in ('income','expense','both')) default 'expense',
  icon        text,
  color       text,
  is_custom   boolean not null default true,
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (owner_id, name)
);
create index categories_owner_idx on public.categories(owner_id);
create trigger trg_categories_updated before update on public.categories
  for each row execute procedure moddatetime(updated_at);

-- ---------------------------------------------------------------------------
-- transactions
-- ---------------------------------------------------------------------------
create table public.transactions (
  id                uuid primary key default gen_random_uuid(),
  owner_id          uuid not null references auth.users(id) on delete cascade,
  account_id        uuid not null references public.accounts(id) on delete cascade,
  category_id       uuid references public.categories(id) on delete set null,
  amount            numeric(14,2) not null,
  currency          char(3) not null default 'EUR',
  occurred_at       timestamptz not null default now(),
  note              text,
  merchant          text,
  type              text not null check (type in ('income','expense','transfer')),
  transfer_pair_id  uuid references public.transactions(id) on delete set null,
  source            text not null default 'manual'
                    check (source in ('manual','ai','import','recurring','subscription')),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index tx_owner_date_idx    on public.transactions(owner_id, occurred_at desc);
create index tx_account_date_idx  on public.transactions(account_id, occurred_at desc);
create index tx_category_idx      on public.transactions(category_id);
create index tx_transfer_pair_idx on public.transactions(transfer_pair_id);
create index tx_merchant_trgm_idx on public.transactions using gin (merchant gin_trgm_ops);
create extension if not exists pg_trgm;
create trigger trg_tx_updated before update on public.transactions
  for each row execute procedure moddatetime(updated_at);

-- ---------------------------------------------------------------------------
-- budgets
-- ---------------------------------------------------------------------------
create table public.budgets (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null references auth.users(id) on delete cascade,
  category_id  uuid not null references public.categories(id) on delete cascade,
  period       text not null check (period in ('weekly','monthly','yearly')),
  amount       numeric(14,2) not null,
  currency     char(3) not null default 'EUR',
  rollover     boolean not null default false,
  start_date   date not null default current_date,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (owner_id, category_id, period)
);
create index budgets_owner_idx on public.budgets(owner_id);
create trigger trg_budgets_updated before update on public.budgets
  for each row execute procedure moddatetime(updated_at);

-- ---------------------------------------------------------------------------
-- goals + contributions
-- ---------------------------------------------------------------------------
create table public.goals (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null references auth.users(id) on delete cascade,
  name            text not null,
  target_amount   numeric(14,2) not null,
  current_amount  numeric(14,2) not null default 0,
  currency        char(3) not null default 'EUR',
  target_date     date,
  account_id      uuid references public.accounts(id) on delete set null,
  icon            text,
  color           text,
  archived_at     timestamptz,
  completed_at    timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index goals_owner_idx on public.goals(owner_id);
create trigger trg_goals_updated before update on public.goals
  for each row execute procedure moddatetime(updated_at);

create table public.goal_contributions (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null references auth.users(id) on delete cascade,
  goal_id         uuid not null references public.goals(id) on delete cascade,
  amount          numeric(14,2) not null,
  currency        char(3) not null default 'EUR',
  occurred_at     timestamptz not null default now(),
  note            text,
  source          text not null default 'manual'
                  check (source in ('manual','auto','allocation','ai')),
  transaction_id  uuid references public.transactions(id) on delete set null,
  created_at      timestamptz not null default now()
);
create index goal_contrib_goal_idx  on public.goal_contributions(goal_id);
create index goal_contrib_owner_idx on public.goal_contributions(owner_id);

-- ---------------------------------------------------------------------------
-- subscriptions  (manual; recurring stays derived in-app)
-- ---------------------------------------------------------------------------
create table public.subscriptions (
  id                uuid primary key default gen_random_uuid(),
  owner_id          uuid not null references auth.users(id) on delete cascade,
  name              text not null,
  amount            numeric(14,2) not null,
  currency          char(3) not null default 'EUR',
  cadence           text not null check (cadence in ('weekly','monthly','quarterly','yearly','custom')),
  cadence_days      integer,
  next_charge_date  date,
  account_id        uuid references public.accounts(id) on delete set null,
  category_id       uuid references public.categories(id) on delete set null,
  hidden            boolean not null default false,
  archived_at       timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index subs_owner_idx on public.subscriptions(owner_id);
create trigger trg_subs_updated before update on public.subscriptions
  for each row execute procedure moddatetime(updated_at);

-- ---------------------------------------------------------------------------
-- saved filter presets
-- ---------------------------------------------------------------------------
create table public.saved_filter_presets (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references auth.users(id) on delete cascade,
  name        text not null,
  filter      jsonb not null,
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index presets_owner_idx on public.saved_filter_presets(owner_id);
create trigger trg_presets_updated before update on public.saved_filter_presets
  for each row execute procedure moddatetime(updated_at);

-- ---------------------------------------------------------------------------
-- attachments  (Storage bucket "receipts" is created in a follow-up migration
-- via the storage API; here we only model the metadata table.)
-- ---------------------------------------------------------------------------
create table public.attachments (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null references auth.users(id) on delete cascade,
  transaction_id  uuid not null references public.transactions(id) on delete cascade,
  storage_path    text not null,
  mime_type       text,
  size_bytes      bigint,
  created_at      timestamptz not null default now()
);
create index attachments_tx_idx    on public.attachments(transaction_id);
create index attachments_owner_idx on public.attachments(owner_id);

-- ---------------------------------------------------------------------------
-- Household  (per-user data; group is a coordination layer for settlements)
-- ---------------------------------------------------------------------------
create table public.household_groups (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references auth.users(id) on delete cascade,
  name        text not null,
  currency    char(3) not null default 'EUR',
  archived_at timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index hh_groups_owner_idx on public.household_groups(owner_id);
create trigger trg_hh_groups_updated before update on public.household_groups
  for each row execute procedure moddatetime(updated_at);

create table public.household_members (
  id              uuid primary key default gen_random_uuid(),
  group_id        uuid not null references public.household_groups(id) on delete cascade,
  user_id         uuid references auth.users(id) on delete cascade,
  invitee_email   text,
  display_name    text,
  role            text not null default 'member'
                  check (role in ('owner','admin','member','viewer','child')),
  share_pct       numeric(5,2) not null default 0,
  joined_at       timestamptz,
  created_at      timestamptz not null default now(),
  check (user_id is not null or invitee_email is not null)
);
create unique index hh_members_group_user_uidx
  on public.household_members(group_id, user_id) where user_id is not null;
create index hh_members_group_idx on public.household_members(group_id);

create table public.household_settlements (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.household_groups(id) on delete cascade,
  from_user    uuid references auth.users(id) on delete set null,
  to_user      uuid references auth.users(id) on delete set null,
  amount       numeric(14,2) not null,
  currency     char(3) not null default 'EUR',
  occurred_at  timestamptz not null default now(),
  status       text not null default 'pending' check (status in ('pending','settled')),
  note         text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index hh_settle_group_idx on public.household_settlements(group_id);
create trigger trg_hh_settle_updated before update on public.household_settlements
  for each row execute procedure moddatetime(updated_at);

-- ---------------------------------------------------------------------------
-- AI: chat sessions + messages
-- ---------------------------------------------------------------------------
create table public.ai_chat_sessions (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null references auth.users(id) on delete cascade,
  title        text,
  archived_at  timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index ai_chat_owner_idx on public.ai_chat_sessions(owner_id, updated_at desc);
create trigger trg_ai_chat_updated before update on public.ai_chat_sessions
  for each row execute procedure moddatetime(updated_at);

create table public.ai_chat_messages (
  id          uuid primary key default gen_random_uuid(),
  session_id  uuid not null references public.ai_chat_sessions(id) on delete cascade,
  owner_id    uuid not null references auth.users(id) on delete cascade,
  role        text not null check (role in ('user','assistant','system','tool')),
  content     text not null default '',
  action      jsonb,
  created_at  timestamptz not null default now()
);
create index ai_chat_msg_session_idx on public.ai_chat_messages(session_id, created_at);

-- ---------------------------------------------------------------------------
-- AI: action history (audit + undo)
-- ---------------------------------------------------------------------------
create table public.ai_action_history (
  id                uuid primary key default gen_random_uuid(),
  owner_id          uuid not null references auth.users(id) on delete cascade,
  action_type       text not null,
  params            jsonb not null default '{}'::jsonb,
  status            text not null default 'success'
                    check (status in ('success','failed','pending','undone')),
  snapshot_before   jsonb,
  snapshot_after    jsonb,
  group_id          uuid,
  error_message     text,
  created_at        timestamptz not null default now()
);
create index ai_hist_owner_idx on public.ai_action_history(owner_id, created_at desc);
create index ai_hist_group_idx on public.ai_action_history(group_id);

-- ---------------------------------------------------------------------------
-- AI: kv memory (prefs, approval patterns, tone, automation level, etc.)
-- ---------------------------------------------------------------------------
create table public.ai_memory (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references auth.users(id) on delete cascade,
  key         text not null,
  value       jsonb not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (owner_id, key)
);
create trigger trg_ai_mem_updated before update on public.ai_memory
  for each row execute procedure moddatetime(updated_at);

-- ---------------------------------------------------------------------------
-- AI: few-shot examples
-- ---------------------------------------------------------------------------
create table public.ai_fewshot_examples (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null references auth.users(id) on delete cascade,
  intent         text not null,
  input          text not null,
  output         jsonb not null,
  success_count  integer not null default 0,
  last_used_at   timestamptz,
  created_at     timestamptz not null default now()
);
create index ai_fewshot_owner_intent_idx on public.ai_fewshot_examples(owner_id, intent);

-- ---------------------------------------------------------------------------
-- AI: merchant aliases (normalization memory)
-- ---------------------------------------------------------------------------
create table public.ai_merchant_aliases (
  id                  uuid primary key default gen_random_uuid(),
  owner_id            uuid not null references auth.users(id) on delete cascade,
  raw_name            text not null,
  normalized_name     text not null,
  default_category_id uuid references public.categories(id) on delete set null,
  usage_count         integer not null default 1,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (owner_id, raw_name)
);
create trigger trg_ai_merchant_updated before update on public.ai_merchant_aliases
  for each row execute procedure moddatetime(updated_at);

-- ---------------------------------------------------------------------------
-- AI: proactive insight dismissals
-- ---------------------------------------------------------------------------
create table public.ai_proactive_dismissals (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references auth.users(id) on delete cascade,
  kind          text not null,
  target_id     text not null,
  dismissed_at  timestamptz not null default now(),
  expires_at    timestamptz
);
create index ai_dismiss_owner_idx on public.ai_proactive_dismissals(owner_id);

-- ---------------------------------------------------------------------------
-- device_sessions  (per-device last-seen, push tokens)
-- ---------------------------------------------------------------------------
create table public.device_sessions (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references auth.users(id) on delete cascade,
  device_id     text not null,
  platform      text not null check (platform in ('ios','macos','web','admin')),
  device_name   text,
  app_version   text,
  push_token    text,
  last_seen_at  timestamptz not null default now(),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (owner_id, device_id)
);
create index device_owner_idx on public.device_sessions(owner_id);
create trigger trg_device_updated before update on public.device_sessions
  for each row execute procedure moddatetime(updated_at);

-- ---------------------------------------------------------------------------
-- app_events  (lightweight analytics, opt-in)
-- ---------------------------------------------------------------------------
create table public.app_events (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid references auth.users(id) on delete cascade,
  device_id    text,
  event_name   text not null,
  properties   jsonb not null default '{}'::jsonb,
  occurred_at  timestamptz not null default now(),
  created_at   timestamptz not null default now()
);
create index app_events_owner_time_idx on public.app_events(owner_id, occurred_at desc);
create index app_events_name_idx       on public.app_events(event_name);

-- ---------------------------------------------------------------------------
-- delete_account RPC  (user calls this from the app to wipe themselves)
-- ---------------------------------------------------------------------------
create or replace function public.delete_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;
revoke all on function public.delete_account() from public;
grant execute on function public.delete_account() to authenticated;
