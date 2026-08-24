# CI-1 isolated Supabase Auth session completion

## Provenance

**USER-SUPPLIED MAC CI-1 COMPLETION REPORT** supplies tests, builds, lifetime,
reviews and preservation. **REMOTE COMMIT VERIFIED BY VPS** supplies the commit,
tree, changed paths and hashes. The VPS did not execute Xcode, simulator,
native tests, Docker, renderer, signing, archive, deploy or production actions.

## Verified identity

| Field | Value |
| --- | --- |
| Workstream | CI-1 — Isolated Supabase Auth, Keychain and Single Session Source |
| Branch | `codex/ci1-supabase-auth-session-v1` |
| Commit / parent / tree | `aba177d7cbb0d9cecb13c5f1099e6b99b6456c93` / `b9a51bc1a641895ef5323cb1085b3b5622bbb277` / `5ea465bcfbe3a52781e0afef597372a03fa5dbe0` |
| Subject | `feat(ios): add isolated Supabase authentication session` |
| Scope | 15 paths: 7 modified, 8 added; 2,629 additions, 61 deletions |
| Package | `Auth` only; 2.55.1 at `21d3aaf21ee98f41611f9f75070489fc8b23d882` |

The remote commit contains no asset, public strings/plist, documentation,
backend or migration path. VPS verified every supplied content hash:

```text
906d7b047b1cf861e6d808da4882c2fea99c401de9dd0409ddd0c0edd72ce683 project.pbxproj
b28b5314f8ff24b9bfd55aa8779603aec475ab82a7850007f41edff164822a79 Package.resolved
893bead4a0d93ab17eb5a96131c14d1ed6f0d48f84680aaa37a3da9e89e57b14 AppDependencies.swift
449b0fa78c87e3fb36f9fe679bd7ecdc5f516c3ab2f229560569ec4bc8ee00cc AuthenticationService.swift
8bae848618a30bc911f817a57884f51827faa22937604348f2a8ae5f4541e629 KeychainSecureStore.swift
e2b41900a198cf692821896647c6175e2844a7b48ba33491043937167fe6067b AppDependenciesTests.swift
64799f8452899b52a3010fa7698cefdc57eee7a3bb2ee55651d49d44000d3a67 SecureStorageTests.swift
9c3841ab180dcb3f0c2f97682df65108fcdf38c5ddfcca3a81977c876f99bcb7 AuthenticationSessionRecord.swift
335b00f92c87db196e1ffbac57612bde573d0fcc5368b185ff4b4bec35a8a730 AuthenticationSessionStore.swift
582791cf6cb7691583c371f238b2e7276fa04a85d12d3402c565d23c29abd72d DiscardingSupabaseAuthStorage.swift
519e725987aa952770f019341d2f06f6abd7b6e62fc9e3fe365472539171a086 SupabaseAuthConfiguration.swift
41bfe47b2646ce4a4ab092931862d10597775a76719c3b88adf5f4f8168161a2 SupabaseAuthService.swift
755576b9c8cf8617f9d7f7e85502366d7e891eed39c7abfc4c9a603536875742 AuthenticationSessionStoreTests.swift
9a313f0463a8268e40b37ad1753eba22f77aa0d57bdd94d8e3e1027eebf867ad SupabaseAuthConfigurationTests.swift
049a8a124a478d8cade74e9f5a7a840de08e8786e57c8f082a7bca118978723a SupabaseAuthServiceTests.swift
```

## Reported completion gates

- focused: 140 registrations, 182 executions, zero failures/skips, PASS;
  `/tmp/ci1-auth2551-focused-final.xcresult`;
- BodyFlowTests: 1,072 registrations, 1,261 executions, zero failures/skips,
  `TEST SUCCEEDED`, 46.196 seconds;
  `/tmp/ci1-auth2551-bodyflowtests-final.xcresult`;
- unsigned Debug and Release `generic/platform=iOS`: `BUILD SUCCEEDED` with
  only `CODE_SIGNING_ALLOWED=NO` and `CODE_SIGNING_REQUIRED=NO`; AppIntents
  inherited, no CI-1 warning attributed;
- lifetime: weak AuthClient nil by 3 seconds; 10 ms polling; 150 ms late
  window; zero late requests, refresh grants and SDK storage retention; no
  production `Task.yield()`;
- scans passed for diff, allowlist, package/product, forbidden APIs/listener/
  refresh, secrets/PII/real URL, Release mock, naming and CI-2;
- Reviews A and B: 0 Critical, 0 Important, 0 Minor.

CI-1 establishes isolated Auth, Keychain-backed app session/bearer ownership,
ephemeral client use and Release fail-closed behavior. It does not implement
refresh, rotation, remote revocation, user switching, cancellation, adapters,
staging E2E, signing or production. CI-1 was clean with empty staging; manager,
CI-0, diagnostics, orphan metadata and old worktree were preserved. No PR,
merge, deploy or production action occurred.
