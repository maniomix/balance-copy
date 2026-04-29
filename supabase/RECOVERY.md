# Centmond Database — Backup & Recovery

Project ID: `ymxrrvmpqblgewspzxwq` (Centmodn, eu-west-1)

## ⚠️ Backup status

**You are on the Supabase Free tier — there are no automated backups.**

| Plan | Daily backups | Retention | PITR |
|---|---|---|---|
| Free *(current)* | ❌ | n/a | ❌ |
| Pro ($25/mo) | ✅ | 7 days | ✅ |

**Action required before public launch:** upgrade to Pro. A finance app
without backups is one bad migration / accidental drop away from losing
every user's data with no recovery path.

Until then: **take a manual dump before every risky operation** (large
migration, RLS rewrite, table drop, etc.). The commands below take ~10 s
and produce a `.sql` file you can keep in iCloud / git-ignored folder.

---

## Manual backup (5 lines)

### One-time setup

1. Install `psql` + `pg_dump` if you don't have them:
   ```bash
   brew install postgresql@17
   ```

2. Get your **DB password** from Supabase Dashboard:
   Project Settings → Database → Connection string → Database password
   (`[YOUR-PASSWORD]` placeholder; click "Reset" if you don't remember it).
   Save to env var:
   ```bash
   export CENTMOND_DB_PASSWORD='paste-here'
   ```

3. The connection URL is:
   ```
   postgresql://postgres.ymxrrvmpqblgewspzxwq:$CENTMOND_DB_PASSWORD@aws-0-eu-west-1.pooler.supabase.com:5432/postgres
   ```

### Take a backup

```bash
mkdir -p ~/CentmondBackups
pg_dump \
  "postgresql://postgres.ymxrrvmpqblgewspzxwq:$CENTMOND_DB_PASSWORD@aws-0-eu-west-1.pooler.supabase.com:5432/postgres" \
  --schema=public --schema=auth \
  --no-owner --no-privileges \
  -f ~/CentmondBackups/centmond_$(date +%Y%m%d_%H%M%S).sql
```

Result: `~/CentmondBackups/centmond_20260429_142359.sql` — full dump of
`public` schema (your data) and `auth` schema (users + sessions).

### Restore from a backup

⚠️ **This wipes the existing database.** Only do it on a fresh project
or after confirming you really want to discard current state.

```bash
psql \
  "postgresql://postgres.ymxrrvmpqblgewspzxwq:$CENTMOND_DB_PASSWORD@aws-0-eu-west-1.pooler.supabase.com:5432/postgres" \
  -f ~/CentmondBackups/centmond_20260429_142359.sql
```

---

## When to back up manually (until you're on Pro)

- Before applying any migration that touches existing data (renames,
  drops, type changes)
- Before a Supabase dashboard operation (RLS edits, role changes)
- Before any SQL run from `execute_sql` that includes `delete`, `update`,
  `drop`, `truncate`
- Weekly, just for peace of mind

---

## Schema as code

Every DDL change in this project is captured as a numbered SQL file in
`supabase/migrations/`. If the database is ever wiped:

1. Create a fresh Supabase project
2. Apply all migration files in chronological order:
   ```bash
   for f in supabase/migrations/*.sql; do
     psql "$NEW_DB_URL" -f "$f"
   done
   ```
3. Restore user data from a `pg_dump` snapshot if you have one.

Migrations are the source of truth for schema; data lives in dumps.

---

## When to upgrade to Pro

- **Hard requirement:** before opening signups to anyone outside your
  test account.
- A single hour of customer data is worth more than $25/mo.
- Pro also lifts the rate limits on email auth (see SMTP — though
  Resend covers that separately).
