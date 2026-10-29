# Mobile password recovery

## Scope and activation

`/api/mobile/v1/auth/password-recovery` is a public, session-independent web
endpoint mirrored into the dedicated mobile BFF. It has GET, HEAD and POST only.
The dedicated Next wrapper declares `maxDuration = 45` locally; the existing
Flow route retains 300 seconds. The original 74 mobile route contracts remain
unchanged; recovery is the single approved 75th route.

This implementation is restricted to staging project `xitugspwfxkcluxvrdeg` and
canonical origin `https://performe-ai-staging-bff.vercel.app`. It is disabled
unless `MOBILE_PASSWORD_RECOVERY_PROJECT_REF` equals that project reference,
`NEXT_PUBLIC_SUPABASE_URL` points to the same project, and the configured public
key is an anon or publishable key. Never use a service-role key for recovery.

**Code integration is not proof of e-mail delivery.** Before activation, qualify
the actual SMTP sender, recovery template, provider limits and complete synthetic
request → received e-mail → changed password → app sign-in flow. On 2026-10-29,
the staging dashboard still showed custom SMTP disabled and a recovery template
using `{{ .ConfirmationURL }}`. These settings were observed, not modified.

## E-mail link contract

The reviewed page expects this fixed link, with the template's hash in its URL
fragment, not its query string:

```text
https://performe-ai-staging-bff.vercel.app/api/mobile/v1/auth/password-recovery#token_hash={{ .TokenHash }}&type=recovery
```

The native app already requests recovery without relying on a persisted PKCE
verifier. Opening this page must not verify or consume a recovery token. The
browser reads the fragment into memory and immediately removes it from the
visible URL. It does not persist a session, token or password. Link tracking in
the sending service must not rewrite this contract. The mailer's real behavior,
including prefetching, must be tested before claiming the flow works.

## Submission and security boundaries

- Only an explicit, locally valid submission sends a request. Duplicate submits
  are suppressed. Password strength remains the Auth provider's responsibility,
  consistent with the native app; the web endpoint adds a 1024-character
  technical bound, not a new minimum password policy.
- POST requires the fixed canonical request origin, exact route and matching
  `Origin`; cross-site Fetch Metadata is rejected. JSON is bounded to 8 KiB and
  rejects invalid UTF-8, duplicate keys and unexpected fields.
- The server verifies only `type=recovery`, updates only the user returned by
  that verification, and attempts logout of that temporary local session. It
  never reuses an administrative cookie, caller-supplied bearer or user ID.
- GET and HEAD never contact Auth. HEAD has no body. The page uses a nonce CSP,
  `no-store`, `no-referrer`, frame denial and no external assets. The admin
  middleware bypasses cookie restoration only for the exact recovery path.
- Auth calls have bounded timeouts; the browser aborts after 60 seconds. A lost
  response reports an uncertain outcome and clears the form. It never retries
  token verification or claims rollback/success without confirmation.
- Logout is best effort and local. Do not promise instant global invalidation
  of previously issued access tokens.

## Verification and remaining release gates

Local evidence on 2026-10-29: 5,013 admin tests, 53 dedicated BFF tests, both
typechecks, a fresh BFF build and route/import/build-surface checks passed. The
127 selected native tests include recovery with the button and keyboard, English
copy, existing-account errors, login/logout and session restoration. Native
changes in this increment are Debug fixtures and tests only, not Release
behavior changes or a new TestFlight delivery.

Actual local HTTP checks covered Portuguese/English content, empty HEAD,
per-response CSP nonces and security headers. Chrome covered Portuguese dark
desktop/mobile layout, mismatch focus, keyboard submit, an explicitly rejected
local-origin request, cleared fields, removed fragment and invalid-link reload.
No real password was changed or e-mail sent. Full SMTP/real Auth/replay/history
preservation QA and distributed-app verification remain release gates.

Rollback must preserve the prior canonical deployment and e-mail configuration.
Removing the activation flag disables this endpoint; it does not undo a password
change already confirmed by Auth. Never retry an uncertain change automatically.
