# Balance — Security Architecture

## Phase 9 + Hardening Pass

### Secrets Removed from Client Code

| Secret | Was in | Status |
|--------|--------|--------|
| Gemini API key `AIzaSy...` | `AIInsightsManager_Gemini.swift:17` | **REMOVED** — moved to backend proxy |
| Supabase anon key | `Supabase.plist` | Loaded via `AppConfig` from gitignored plist |
| Supabase URL | `Supabase.plist` | Loaded via `AppConfig` from gitignored plist |

> **ACTION REQUIRED:** Rotate the Gemini key immediately in Google Cloud Console. It was committed to source history.

### Note on Supabase Anon Key

The Supabase **anon key** is designed to be used in clients — it is NOT a secret. It only grants access allowed by Row-Level Security (RLS) policies. However, it should still be in a gitignored config file (not committed to source) to prevent casual misuse.

---

## Security Files

| File | Purpose |
|------|---------|
| `Security/AppConfig.swift` | Environment-aware config reader with HTTPS validation |
| `Security/SecureLogger.swift` | Production-safe logger (redacts JWTs, keys, emails, UUIDs, paths, URLs) |
| `Security/AIProxyService.swift` | Rate-limited, validated proxy client for AI calls |
| `Security/RequestGuard.swift` | Input validation, injection detection, field sanitization, SQL injection checks |
| `.gitignore` | Prevents Config.plist, Supabase.plist, GoogleService-Info.plist from being committed |

---

## Hardening Pass Changes

### 1. `.gitignore` Added
- Blocks `Config.plist`, `Supabase.plist`, `GoogleService-Info.plist`, `.env*`, `*.xcconfig`
- Prevents accidental commit of secrets going forward

### 2. AppConfig Hardened
- Added `enforcesSecurity`, `allowsDirectAICalls`, `showsDetailedErrors` environment flags
- Added HTTPS URL validation for Supabase and AI proxy URLs in non-dev environments
- Added `safeErrorMessage()` helper — masks internal error details in production
- Added `appVersion` and `buildNumber` computed properties for request headers

### 3. SecureLogger Hardened
- Added UUID redaction pattern (prevents user/transaction ID leaks)
- Added Bearer token redaction pattern
- Added URL redaction in error descriptions (prevents endpoint leaks)
- Added error message truncation (max 300 chars) to prevent stack trace leaks
- Added `security()` log level for auth failures and injection attempts

### 4. AuthManager Hardened
- Client-side rate limiting: 5 failed sign-in attempts triggers 5-minute lockout
- Input validation: Email format, password length (8–128 chars), display name (XSS check)
- Session cleanup on sign-out: Clears all profile caches from UserDefaults
- Access token accessor: Safe async getter for authenticated API calls
- All `print()` calls replaced with SecureLogger (no PII in production logs)

### 5. SupabaseManager Hardened
- 60+ `print()` calls replaced with SecureLogger
- Sensitive data removed from logs: No user IDs, emails, transaction details, or JSON payloads
- Debug-only verbose logging via SecureLogger.debug (suppressed in production)

### 6. AccountManager Hardened
- Ownership validation on hard delete: Checks `account.userId == currentUserId`
- Error messages sanitized via `AppConfig.safeErrorMessage()`
- All `print()` calls replaced with SecureLogger

### 7. GoalManager Hardened
- Error messages sanitized for user-facing display
- All `print()` calls replaced with SecureLogger
- No financial amounts or goal names in production logs
- **Ownership validation on delete**: `deleteGoal()` now filters by `user_id` to prevent cross-user deletion

### 8. AnalyticsManager Hardened
- Replaced `#if DEBUG print()` with `SecureLogger.debug()` (auto-suppressed in production)
- Event properties no longer logged (only event names)

### 9. AIProxyService Hardened
- Auth token validation before any request
- Prompt validation via RequestGuard before sending to proxy
- Standard secure headers via `RequestGuard.requestHeaders()` (version, platform, request ID)
- Response validation via `RequestGuard.validateResponse()` with proper error mapping
- Error messages sanitized via `AppConfig.safeErrorMessage()`

### 10. SupabaseManager Delete Operations Hardened
- `deleteTransaction()` now requires authenticated user and filters by `user_id`
- `deleteMonthData()` now validates that the `userId` parameter matches the authenticated user
- Both throw explicit errors on auth/permission failures instead of silently proceeding

### 11. ProfileView Hardened
- Replaced all `print()` calls with SecureLogger
- Sign-out sync now routes through `SyncCoordinator.pushToCloud()` instead of direct `supabaseManager.saveStore()`

### 12. ContentView Sync Consistency
- Month deletion cloud push routed through `SyncCoordinator.pushToCloud()`
- CSV import cloud push routed through `SyncCoordinator.pushToCloud()`
- No remaining direct `supabaseManager.saveStore()` calls outside the sync layer

### 13. SyncStatusView Updated
- Migrated from `SupabaseManager` to `SyncCoordinator` for sync status, error state, and last-sync time
- Manual sync now uses `SyncCoordinator.fullReconcile()` instead of direct `supabaseManager.syncStore()`
- Shows offline status when network is unavailable

### 14. SupabaseTestView Hardened
- Error display uses `AppConfig.safeErrorMessage()` instead of raw `error.localizedDescription`
- Auth state reads from `AuthManager` instead of removed `SupabaseManager.isAuthenticated`

### 15. RequestGuard Enhanced
- Added field sanitization (`sanitizeField`) — strips control characters, enforces length limits
- Added amount validation (`validateAmount`) — bounds-checked monetary input
- Added SQL injection detection (`containsSQLInjection`)
- Added URL validation (`validateURL`) — HTTPS/HTTP scheme check
- Expanded injection patterns list (26 patterns including `<system>` tags)
- Added 403 Forbidden error case

---

## Configuration

### Config.plist (gitignored)

Create `Config.plist` in the app bundle with these keys:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>SUPABASE_URL</key>
    <string>https://your-project.supabase.co</string>
    <key>SUPABASE_ANON_KEY</key>
    <string>eyJ...</string>
    <key>AI_PROXY_BASE_URL</key>
    <string>https://your-project.supabase.co/functions/v1</string>
    <key>ENVIRONMENT</key>
    <string>production</string>
    <key>GEMINI_API_KEY_DEV</key>
    <string></string>
</dict>
</plist>
```

### Environments

| Key | development | staging | production |
|-----|------------|---------|------------|
| `AI_PROXY_BASE_URL` | optional (falls back to direct) | required | required |
| `GEMINI_API_KEY_DEV` | allowed | blocked | blocked |
| Verbose logging | yes | yes | no |
| Error details in UI | full | sanitized | sanitized |
| HTTPS enforcement | no | yes | yes |
| Rate limiting | relaxed | enforced | enforced |
| Direct AI calls | allowed | blocked | blocked |

---

## AI Proxy Architecture

```
iOS App  →  AIProxyService  →  Supabase Edge Function  →  Gemini API
                                      ↑
                            Validates JWT
                            Appends API key
                            Rate-limits per user
```

### Setting Up the Edge Function

Deploy a Supabase Edge Function (Deno) at `ai/generate-insights` and `ai/chat`:

```typescript
// supabase/functions/ai/generate-insights/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

serve(async (req) => {
  // 1. Validate JWT from Authorization header
  const jwt = req.headers.get("Authorization")?.replace("Bearer ", "")
  if (!jwt) return new Response("Unauthorized", { status: 401 })

  // 2. Read prompt from body
  const { prompt } = await req.json()

  // 3. Call Gemini with server-side key
  const GEMINI_KEY = Deno.env.get("GEMINI_API_KEY")
  const resp = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=${GEMINI_KEY}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.7, maxOutputTokens: 1024 }
      })
    }
  )

  const data = await resp.json()
  const text = data.candidates?.[0]?.content?.parts?.[0]?.text ?? ""

  return new Response(JSON.stringify({ text }), {
    headers: { "Content-Type": "application/json" }
  })
})
```

---

## Protections Summary

### Client-Side
- **AI rate limiting**: 10 requests/minute, 60/hour (AIProxyService)
- **Auth rate limiting**: 5 failed attempts → 5-minute lockout (AuthManager)
- **Input validation**: Email, password, display name, amount, prompt (AuthManager, RequestGuard)
- **Prompt sanitization**: Max 4000 chars, 26 injection patterns (RequestGuard)
- **SQL injection detection**: Common patterns blocked (RequestGuard)
- **Field sanitization**: Control character stripping, length limits (RequestGuard)
- **Log sanitization**: JWTs, API keys, emails, UUIDs, URLs, Bearer tokens (SecureLogger)
- **Error sanitization**: Internal errors masked, truncated to 300 chars (SecureLogger, AppConfig)
- **Ownership validation**: Account deletion checks userId (AccountManager), goal deletion filters by user_id (GoalManager), transaction deletion filters by user_id (SupabaseManager), month data deletion validates authenticated user (SupabaseManager)
- **Session cleanup**: All local caches cleared on sign-out (AuthManager)
- **HTTPS enforcement**: Non-dev environments require HTTPS (AppConfig)

### Server-Side (to implement)
- JWT validation on every AI request
- Per-user rate limiting (Redis or Supabase)
- Request logging (without prompt contents)
- Cost monitoring and alerting
- RLS policies on all tables

---

## Migration Steps

1. Ensure `.gitignore` is committed (blocks config files)
2. Create `Config.plist` with your keys (see template above)
3. Rotate the exposed Gemini API key in Google Cloud Console
4. Deploy the Supabase Edge Function
5. Set `AI_PROXY_BASE_URL` in Config.plist
6. For dev: put a test Gemini key in `GEMINI_API_KEY_DEV`
7. For prod: leave `GEMINI_API_KEY_DEV` empty (it's blocked anyway)
8. Consider purging git history with BFG Repo-Cleaner to remove old secrets
