# Supabase Swift 2.54.1 refresh-isolation authority

**Verified:** 2026-08-23 from the official `supabase-swift` tag `v2.54.1`.

The official repository is `https://github.com/supabase/supabase-swift.git`.
Tag `v2.54.1`, release date 2026-07-29, resolves to
`b118484ae0eb4a6b6ce1b216711d660baf6ec1aa`. The verified blobs are:

| Path | Blob |
| --- | --- |
| `Package.swift` | `e74b5d1ea025fefbd46bcc343fda4853a9a73c13` |
| `Sources/Auth/AuthClientConfiguration.swift` | `3edcc76ba0daa24834876e3ed0d01e2ea16fb3e3` |
| `Sources/Auth/AuthClient.swift` | `26aa36ca025284311a08cc00b43894f7e44636a5` |
| `Sources/Auth/Storage/AuthLocalStorage.swift` | `45dd515152e1c4d9204a67b2121a24821a823616` |
| `Sources/Auth/Types.swift` | `847c4edb10d83cade87f42067509ae5333901bd2` |
| `Sources/Supabase/Types.swift` | `cb110d2c531e5f3094ca04d4bf00974c6ff9c40c` |
| `Sources/Supabase/SupabaseClient.swift` | `f6fdfdba939b4022e328fcafcf90f6f108e3a588` |

The package uses Swift tools 6.1, supports iOS 16+, and exposes independent
product `Auth`. `AuthClient.Configuration` supports `autoRefreshToken` and
`emitLocalSessionAsInitialSession`; `AuthLocalStorage` is customizable; Session
contains access/refresh tokens, expiry and user; User contains UUID, email and
email-confirmation state. The SDK also exposes refresh and listener APIs.

`autoRefreshToken: false` prevents the lifecycle auto-refresh loop but alone is
not proof of refresh isolation: initial-session/session lifecycle paths can
still reach refresh. CI-1 therefore uses only `import Auth`, exact 2.54.1, a
fresh `AuthClient` per remote operation, `autoRefreshToken: false`,
`emitLocalSessionAsInitialSession: true`, and a Sendable discarding storage.
The client has no listener, no SDK restore, no session/currentSession access and
is released after mapping an operation result.

CI-1 prohibits `SupabaseClient`, listeners, `refreshSession`,
`startAutoRefresh`, `stopAutoRefresh`, `setSession`, SDK default/Keychain
storage, and durable SDK ownership. The app actor and its own Keychain record
are the only durable session authority. No real URL or key is recorded here.
