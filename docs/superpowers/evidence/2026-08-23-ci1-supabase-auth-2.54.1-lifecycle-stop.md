# CI-1 Supabase Auth 2.54.1 lifecycle STOP

## Provenance

**Source:** `USER-SUPPLIED MAC CI-1 SUPABASE AUTH 2.54.1 LIFECYCLE REVIEW STOP`.
This VPS records the supplied report; it did not run Xcode, a simulator, tests,
Docker, a renderer, or implementation code.

| Field | Value |
| --- | --- |
| Worktree | `/Users/eduardohenrique/Developer/bodyflow-ci1-supabase-auth-session-v1` |
| Branch | `codex/ci1-supabase-auth-session-v1` |
| Base HEAD / parent | `b9a51bc1a641895ef5323cb1085b3b5622bbb277` / `4f635ad2b5802239575ef2b6ec04b0aed50db740` |
| Upstream / staging | absent / empty |
| Dirty paths | 15: 7 modified and 8 untracked |
| Porcelain SHA-256 | `49d7a7bd2b1860225a7a0b7ba564b85f52ea7d2877a4ef93c926bf843f8f1539` |
| Tracked diff SHA-256 | `c282deed21d3d3f197e9c54e68e981bf3854e7b59ef2fb0f9d35c01b17d29fe4` |
| Full patch SHA-256 | `bedcfde4fe4c32e87414f1c7f250890ff4ccba836d6d5e752d7461459a03a021` |

The exact frozen inventory is: modified
`apps/ios/BodyFlow/BodyFlow.xcodeproj/project.pbxproj`,
`apps/ios/BodyFlow/BodyFlow.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`,
`apps/ios/BodyFlow/BodyFlow/App/AppDependencies.swift`,
`apps/ios/BodyFlow/BodyFlow/Core/Auth/AuthenticationService.swift`,
`apps/ios/BodyFlow/BodyFlow/Core/Storage/KeychainSecureStore.swift`,
`apps/ios/BodyFlow/BodyFlowTests/AppDependenciesTests.swift`, and
`apps/ios/BodyFlow/BodyFlowTests/SecureStorageTests.swift`; new
`apps/ios/BodyFlow/BodyFlow/Core/Auth/AuthenticationSessionRecord.swift`,
`apps/ios/BodyFlow/BodyFlow/Core/Auth/AuthenticationSessionStore.swift`,
`apps/ios/BodyFlow/BodyFlow/Core/Auth/DiscardingSupabaseAuthStorage.swift`,
`apps/ios/BodyFlow/BodyFlow/Core/Auth/SupabaseAuthConfiguration.swift`,
`apps/ios/BodyFlow/BodyFlow/Core/Auth/SupabaseAuthService.swift`,
`apps/ios/BodyFlow/BodyFlowTests/AuthenticationSessionStoreTests.swift`,
`apps/ios/BodyFlow/BodyFlowTests/SupabaseAuthConfigurationTests.swift`, and
`apps/ios/BodyFlow/BodyFlowTests/SupabaseAuthServiceTests.swift`.

## Reported gates before STOP

- focused suite: 154 passing, zero failures/skips;
- full `BodyFlowTests`: 1,071 passing, zero failures/skips;
- package: Auth 2.54.1 at `b118484ae0eb4a6b6ce1b216711d660baf6ec1aa`;
- Debug and Release generic iOS Simulator builds were reported passing; exact
  `generic/platform=iOS` unsigned verification remained pending;
- no staging, commit, push, pull request, merge, deployment, renderer or
  production configuration action occurred.

## Blocking finding

Review A reported 0 Critical / 1 Important / 0 Minor: AuthClient 2.54.1 had
internal lifecycle observation and a static dependencies registry without a
public cleanup path adequate for the CI-1 short-lived-client pattern. A client
per operation could therefore accumulate lifecycle/registry state. Review B
reported 0 Critical / 0 Important / 1 Minor: a `Task.yield()` polling approach
was not deterministic enough for lifecycle proof.

The frozen worktree must be preserved. This evidence authorizes neither a
repair of its Git state nor implementation on the VPS. CI-1 may resume only
under the 2.55.1 authority and its bounded deallocation proof.
