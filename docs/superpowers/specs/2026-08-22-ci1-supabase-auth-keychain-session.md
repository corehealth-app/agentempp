# CI-1 — Isolated Supabase Auth, Keychain and Single Session Source

## Goal

Add real, injected Supabase authentication while retaining one process-local
app session authority and no automatic refresh. CI-1 uses only `Auth` from
`supabase-swift` exact 2.55.1/revision
`21d3aaf21ee98f41611f9f75070489fc8b23d882`.

## Architecture

`AuthenticationSessionStore` is an actor, is the sole real
`SessionTokenProviding`, hydrates/persists through existing `SecureStoring` and
`KeychainSecureStore`, serializes transitions, and returns a bearer only for an
unexpired record. The version-1 internal record holds user ID, email,
confirmation, onboarding flag, access token, refresh token and expiry; tokens
never appear in public session models, descriptions or logs.

The remote adapter imports `Auth` only. Each sign-in, sign-up or recovery
operation creates a short-lived AuthClient with `autoRefreshToken: false`,
`emitLocalSessionAsInitialSession: true`, injected ephemeral no-cache network,
and `DiscardingSupabaseAuthStorage` (retrieve nil; store retains nothing;
remove idempotent). No application auth or session listener is permitted: the
app must not subscribe to `authStateChanges`/`onAuthStateChange`, nor persist
or restore a session from a listener. The SDK's internal lifecycle observation
in Auth 2.55.1 is permitted only because the client is ephemeral, refresh is
disabled, storage is discarding, and the client must deallocate after each
operation. SDK restore, SDK session/currentSession, refresh API, long-lived
client or SDK storage remains prohibited.

The operation tests must prove a weak AuthClient reference becomes nil within a
bounded deadline, with bounded polling, cancellation and an actionable timeout
message. They must also prove no late request or refresh grant occurs after the
operation and that discarding SDK storage retains nothing. A single
`Task.yield()` is not sufficient proof. `AuthenticationSessionStore` remains
the sole durable, app-actor-owned session and bearer authority.

Configuration is injected and fail-closed: HTTPS root URL only and an anon or
publishable key. Empty, service-role, secret, unknown `sb_` keys and legacy JWT
whose role is not `anon` are rejected. No real URL/key, fallback, payload host
or production configuration is allowed.

Keychain uses generic-password, `WhenUnlockedThisDeviceOnly`, explicit
synchronizable false, no access group, typed add/update/read/delete errors and
corrupt/unknown-version fail-closed behavior. No UserDefaults, file or iCloud
storage is permitted.

The existing operations are restore, sign-in, sign-up, development
confirmation, recovery and sign-out. Restore is local only; development
confirmation is unavailable; sign-out clears only local actor/Keychain state
and does not claim remote revocation. Refresh, rotation, remote logout, user
switching, patient cancellation, domain adapters, staging E2E and CI-2 are out
of scope.

## Required proof

Tests cover configuration validation, package/product pin, no application
listener, no refresh or persistent SDK storage, deterministic client lifetime,
secure network redirects/cancellation, every
Keychain status, record corruption/version, hydration/expiry/concurrency,
password lifetime, each auth result, Release fail-closed wiring and CI-0 bearer
replacement. Scans prove no secret, URL, naming expansion, mock Release path or
CI-2 behavior. Two independent reviews require zero Critical/Important.
