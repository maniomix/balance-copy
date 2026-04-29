# Shared layout notes

All 5 templates share the same skeleton so they look like one product.

## Brand tokens

| Token | Value |
|---|---|
| Accent | `#338CFF` |
| Text | `#0E1116` |
| Subtext | `#5A6066` |
| BG | `#FFFFFF` |
| Card | `#F5F7FB` |
| Border | `#E5E8EE` |

## Supabase template variables (always lowercase, double-curlied)

| Var | Where it appears |
|---|---|
| `{{ .ConfirmationURL }}` | Confirm signup, Magic Link, Reset Password, Change Email, Invite |
| `{{ .Email }}` | Confirm signup, Magic Link, Reset, Change Email |
| `{{ .NewEmail }}` | Change Email |
| `{{ .Token }}` | OTP-style flows (currently unused) |
| `{{ .SiteURL }}` | Footer back-link |

## Where to paste

Supabase Dashboard →
[Auth → Email Templates](https://supabase.com/dashboard/project/ymxrrvmpqblgewspzxwq/auth/templates)

For each template:
1. Click the template (Confirm signup, Magic Link, Change Email, Reset Password, Invite User)
2. Replace **Subject** with the value from the corresponding `.html` file's first line comment
3. Replace **Message body** with the HTML from the `.html` file (everything after the `<!-- HTML -->` line)
4. Save

## Testing

After saving, Supabase has a "Send test email" button per template — paste your email, click, and confirm rendering looks right in Apple Mail + Gmail.
