# Supabase Auth 2.55.1 refresh and logout authority

## Official sources verified on 2026-08-24

Only official material was used: `supabase-swift` tag `v2.55.1`, the official
Supabase Auth OpenAPI/server repository and official Supabase documentation.
The SDK tag resolves to `21d3aaf21ee98f41611f9f75070489fc8b23d882`; product is
`Auth` only. Relevant tag blobs are AuthClient
`86cadf092f9551077cb8223ab6330524a44e16c9`, SessionManager
`e711c35f6377746836043779cf53d02f39aa91d3`, SessionStorage
`c922bbd8a693a7e725b660fa066fa912af262ad6`, APIClient
`830f41ed620d2a115387ec15a426590d3903f1ab`, Types
`847c4edb10d83cade87f42067509ae5333901bd2`, and AuthError
`65ead932ca979614b3e016d4ab142b79e6b40a99`.

`AuthClient.refreshSession(refreshToken: String? = nil) async throws -> Session`
uses the current SDK session when no token is supplied. SessionManager sends
`POST /auth/v1/token?grant_type=refresh_token`, body containing only the
refresh token, updates configured storage and emits an internal refreshed event.
`AuthClient.signOut(scope: SignOutScope = .global)` defaults to global and is
therefore prohibited for CI-2. Official scopes are `global`, `local` and
`others`; local means current session only, while the server returns HTTP 204
after successful revocation. Access JWTs remain potentially valid until expiry.

## Chosen implementation

CI-2 uses the existing origin-locked `SupabaseAuthFetch` directly for both
operations; it uses no long-lived AuthClient, SDK session storage or listener.

| Operation | Request | Success |
| --- | --- | --- |
| Refresh | `POST /auth/v1/token?grant_type=refresh_token`, apikey + anon authorization + JSON headers, JSON body only `refresh_token` | Decode/validate Session, then atomically persist rotated app record. |
| Current-session logout | `POST /auth/v1/logout?scope=local`, apikey + current access-token authorization, empty body | HTTP 204 is confirmed remote revocation. |

Refresh response must contain a non-empty refresh token. It may equal the
request token only when that behavior is officially compatible and explicitly
tested. 400/401 official invalid-grant,
session-missing and refresh-token-reuse outcomes invalidate local session.
403 rejects without a synthetic success. 429, 5xx, timeout and network errors
are transient: no loop and no automatic logout. Logout maps 204 to confirmed;
401/403/404/429/5xx/timeout/network to remote-unconfirmed after local invalidation.

The app actor/Keychain record is the sole durable authority. App-level
single-flight belongs to CI-2, not SDK internals. SDK restore/currentSession,
setSession, automatic refresh, listeners and global/others logout are forbidden.
This proves API semantics, not a configured environment or staging E2E.
