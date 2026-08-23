# Supabase Swift 2.55.1 AuthClient lifecycle authority

**Verified on:** 2026-08-23, from official repository
`https://github.com/supabase/supabase-swift.git`, tag `v2.55.1`.

| Field | Verified value |
| --- | --- |
| Version / tag | `2.55.1` / `v2.55.1` |
| Release commit | `21d3aaf21ee98f41611f9f75070489fc8b23d882` |
| Release date | 2026-08-13 |
| Product | `Auth` only |
| Ancestors present | `a71f55a8d522aa38e2cecd314b64c6b24d518f8c`, `0826b287b85ee7999cc25bb5b07ba5637984a439`, `c6a5d99a204c17da2f4db8555edcc27f46b8f2cd` |

| Tag path | Blob |
| --- | --- |
| `Package.swift` | `e74b5d1ea025fefbd46bcc343fda4853a9a73c13` |
| `Sources/Auth/AuthClientConfiguration.swift` | `c4eea4a15c7239c5df3d2f12f12805fc7692d72e` |
| `Sources/Auth/AuthClient.swift` | `86cadf092f9551077cb8223ab6330524a44e16c9` |
| `Sources/Auth/Internal/Dependencies.swift` | `01a1f2afa87d9cc484586e88b94ea800bee40281` |
| `Tests/AuthTests/AuthClientMultipleInstancesTests.swift` | `c8bdc92b110be0d646aba1f589c6c8705ba61933` |

## Lifecycle facts

The independent `Auth` product remains available, Swift tools version remains
6.1 and the package remains iOS-compatible. AuthClient initialization installs
its own internal lifecycle observation; lifecycle handling starts or stops
refresh only when `autoRefreshToken` is true. This is not an application
session source.

The 2.55.0 ancestry contains `fix(auth): remove AuthClient from Dependencies
registry on deinit` and `fix(auth): stop auto-refresh task on AuthClient deinit`.
At 2.55.1, `AuthClient.deinit` removes its `clientID` entry from
`Dependencies.instances`, captures only the session manager for cleanup, and
ends its refresh work. The official multiple-instances tests poll for registry
entry disappearance after deallocation and verify that auto-refresh stops after
deallocation.

## CI-1 decision

CI-1 may use exactly `Auth` at this tag/revision with ephemeral clients,
`autoRefreshToken: false`, discarding storage and no durable SDK ownership. It
may not import the `Supabase` product, use an application auth/session listener,
restore SDK state, read SDK session/currentSession, call refresh/setSession, or
use SDK persistent storage. The app actor plus its Keychain record is the only
durable session and bearer authority.

The Mac implementation must independently prove its client becomes unreachable
within a bounded deadline, cannot issue a late request or refresh grant after
the operation, and leaves no SDK storage retained. Upstream behavior is a
necessary authority, not a substitute for those application-level tests.
