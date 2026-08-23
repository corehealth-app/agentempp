# CI-1 execution plan — isolated Supabase authentication

Base `b9a51bc1a641895ef5323cb1085b3b5622bbb277`; branch
`codex/ci1-supabase-auth-session-v1`; worktree
`/Users/eduardohenrique/Developer/bodyflow-ci1-supabase-auth-session-v1`; final
commit `feat(ios): add isolated Supabase authentication session`.

Resume the existing frozen worktree; do not recreate the branch or worktree.
Task 0 validates its 15 listed paths, preflight hashes and empty staging. Task
1 changes only the existing package pin to `Auth` exact 2.55.1/revision
`21d3aaf21ee98f41611f9f75070489fc8b23d882`, never product or import
`Supabase`. Task 2 TDDs injected configuration. Task 3 TDDs discarding SDK
storage, short-lived adapter, safe fetch/no-refresh proof and deterministic
lifetime proof. Task 4 TDDs versioned Keychain record. Task 5 TDDs actor
session ownership/hydration/bearer. Task 6 TDDs existing authentication
operations. Task 7 TDDs AppDependencies wiring. Task 8 runs CI-1, CI-0,
Authentication, Storage and dependency tests, unsigned Debug/Release builds,
scans, two reviews, selective commit and one non-force push without upstream.

Each task requires expected RED, minimal implementation and focused GREEN; no
unapproved skipped case or assertion reduction. The final allowlist must enumerate exact
files after Task 0; it may only name necessary Auth/Storage/test files,
`AppDependencies.swift`, `project.pbxproj` and `Package.resolved`, never a
wildcard, asset, strings, plist, renderer, backend or documentation.

The existing 15-path allowlist is final: no sixteenth path may be changed.
Task 0 must compare exatamente this inventory and its frozen preflight before a
write:

1. `apps/ios/BodyFlow/BodyFlow.xcodeproj/project.pbxproj`
2. `apps/ios/BodyFlow/BodyFlow.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
3. `apps/ios/BodyFlow/BodyFlow/App/AppDependencies.swift`
4. `apps/ios/BodyFlow/BodyFlow/Core/Auth/AuthenticationService.swift`
5. `apps/ios/BodyFlow/BodyFlow/Core/Storage/KeychainSecureStore.swift`
6. `apps/ios/BodyFlow/BodyFlowTests/AppDependenciesTests.swift`
7. `apps/ios/BodyFlow/BodyFlowTests/SecureStorageTests.swift`
8. `apps/ios/BodyFlow/BodyFlow/Core/Auth/AuthenticationSessionRecord.swift`
9. `apps/ios/BodyFlow/BodyFlow/Core/Auth/AuthenticationSessionStore.swift`
10. `apps/ios/BodyFlow/BodyFlow/Core/Auth/DiscardingSupabaseAuthStorage.swift`
11. `apps/ios/BodyFlow/BodyFlow/Core/Auth/SupabaseAuthConfiguration.swift`
12. `apps/ios/BodyFlow/BodyFlow/Core/Auth/SupabaseAuthService.swift`
13. `apps/ios/BodyFlow/BodyFlowTests/AuthenticationSessionStoreTests.swift`
14. `apps/ios/BodyFlow/BodyFlowTests/SupabaseAuthConfigurationTests.swift`
15. `apps/ios/BodyFlow/BodyFlowTests/SupabaseAuthServiceTests.swift`

The preflight must observe 7 modified + 8 untracked paths, empty staging,
porcelain SHA-256
`49d7a7bd2b1860225a7a0b7ba564b85f52ea7d2877a4ef93c926bf843f8f1539`,
tracked diff SHA-256
`c282deed21d3d3f197e9c54e68e981bf3854e7b59ef2fb0f9d35c01b17d29fe4`,
and full patch SHA-256
`bedcfde4fe4c32e87414f1c7f250890ff4ccba836d6d5e752d7461459a03a021`.
Within it, add deterministic lifetime proof: a weak client reference becomes
nil by a finite deadline; polling has a finite interval and cancellation; the
failure reports the deadline; no late request/refresh grant can occur; and the
discarding SDK storage retains no session. The minor reported for `Task.yield()`
must be either removed with an in-allowlist deterministic alternative or
justified objectively and accepted by final Review B with zero Critical or
Important findings.

Use only the established unsigned build overrides and exact destination
`generic/platform=iOS` for both Debug and Release. Review A covers
SDK/Auth/Keychain and AuthClient lifecycle. Review B covers actor/session/
concurrency and bounded lifetime proof. Stop for package/API mismatch, refresh,
persistent SDK storage, durable SDK ownership, application auth/session
listener, failed client deallocation, double authority, forbidden naming,
secret, real URL/key, Release mock, failed build/test or Critical/Important
finding.
