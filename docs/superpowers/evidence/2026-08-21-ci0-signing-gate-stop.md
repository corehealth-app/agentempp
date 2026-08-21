# CI-0 signing gate STOP — evidence from the Mac execution

**Classification:** `CI0_SIGNING_GATE_STOP`  
**Source:** `USER-SUPPLIED MAC CI-0 EXECUTION REPORT`  
**Documentation authority:** `bf2236ce9ddee8861556e25670f8b6ade11e6e7f` —
`docs(project): pause naming and open neutral integration`  
**Date recorded:** 2026-08-21

This is a documentary record of an execution performed on the Mac/Xcode
machine. The VPS did not execute Xcode, a simulator, an iOS build, or any
signing operation.

## Mac environment reported by the local session

| Item | Reported value |
| --- | --- |
| macOS | 26.5.2 (25F84) |
| Xcode | 26.6 (17F113) |
| Swift | 6.3.3 |
| Simulator | iPhone 17 Pro, iOS 26.5 |

## Preserved integration state

The local session created the durable naming-neutral integration worktree
`bodyflow-naming-neutral-core-integration-v1` on branch
`codex/naming-neutral-core-integration-v1`, at committed Task 2 base
`4f635ad2b5802239575ef2b6ec04b0aed50db740` (parent
`701c272030ead0061e76e3ee69801d7dbf763917`). It had no upstream, an empty
staging area, final porcelain SHA-256
`97ed936286fe80aca2d0aea6737b48315d1781cc3703380115be48efb6b0a731`, and
tracked binary-diff SHA-256
`3f7f91d80a7b1833e0b1ec4ff5302cfe007ddd8e07aa05387980171ddca42c72`.

The reported implementation remains unstaged and uncommitted. It created:

- `apps/ios/BodyFlow/BodyFlow/Core/Networking/MobileAPIConfiguration.swift`
- `apps/ios/BodyFlow/BodyFlow/Core/Networking/MobileAPIEnvelope.swift`
- `apps/ios/BodyFlow/BodyFlow/Core/Networking/MobileAPITransport.swift`
- `apps/ios/BodyFlow/BodyFlow/Core/Networking/MobileAPITransportError.swift`
- `apps/ios/BodyFlow/BodyFlow/Core/Networking/SessionTokenProviding.swift`
- `apps/ios/BodyFlow/BodyFlowTests/MobileAPIConfigurationTests.swift`
- `apps/ios/BodyFlow/BodyFlowTests/MobileAPITransportTests.swift`

It modified:

- `apps/ios/BodyFlow/BodyFlow/App/AppDependencies.swift`
- `apps/ios/BodyFlow/BodyFlow/Core/Networking/APIClient.swift`
- `apps/ios/BodyFlow/BodyFlowTests/AppDependenciesTests.swift`

No path outside that reported allowlist was observed.

The Mac Git manager remained clean at
`0ce7f20f22b0e66a6de0544d4a46345181f2fccb`. The diagnostic repository
remained with its nine historical paths, empty staging, and unchanged hashes.
The orphan `worktree1` metadata remains preserved at
`ad9869c0d6b11222263ea40c7b72e329092aeef5`, with index SHA-256
`2e4cef4ed2f2bfe7e7e4cb2825001401ff80ef1252227f07f13ae36fcd545dd0`.
The old Better Ahead worktree remains
`PHYSICALLY_INCOMPLETE_WORKTREE`; it was not repaired, reused, or pruned.

## Focused test result — RED/GREEN record

The local session reports this focused test command:

```text
xcodebuild test \
  -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BodyFlowTests/MobileAPIConfigurationTests \
  -only-testing:BodyFlowTests/MobileAPITransportTests \
  -only-testing:BodyFlowTests/AppDependenciesTests
```

The supplied report records the final GREEN result, not a separate retained RED
invocation: the official result bundle reported `Passed`, with 63 registered
tests, 83 expanded passed executions, zero failures, zero skips, zero expected
failures, zero warnings, and 29.630 seconds of execution. This evidence does
not infer an unreported RED phase and does not claim that the VPS ran or
independently verified the GREEN result.

## Build STOP

The Mac session then ran the original Debug build command:

```text
xcodebuild build \
  -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -configuration Debug \
  -destination 'generic/platform=iOS'
```

It stopped with exit code 65 in `GatherProvisioningInputs`, before compilation
of the CI-0 implementation:

```text
Signing for "BodyFlow" requires a development team.
Select a development team in the Signing & Capabilities editor.
```

No signing configuration was changed. Release was not executed. Final
`git diff --check`, naming and secret scans, independent review, staging, and
commit were not executed. This is not a conclusion that CI-0 is complete and
not evidence that the application is integrated, signed, installable, or
distributable.

No real login, renderer, Docker, brand pnpm work, push, pull request, merge,
deploy, TestFlight, or App Store action was performed by that execution.

## Narrow reconciliation required for the next Mac gate

The CI-0 Debug and Release checks are compilation gates, not signing,
installation, archive, or distribution gates. The only authorized change for
their command lines is the pair:

```text
CODE_SIGNING_ALLOWED=NO
CODE_SIGNING_REQUIRED=NO
```

This allows compilation proof only. It does not authorize a simulator
substitution, `project.pbxproj` changes, a Development Team, provisioning
updates, a provisioning profile, certificates, bundle-ID changes, persistent
signing settings, archive, device installation, TestFlight, App Store, or any
claim that the resulting build is signed or distributable. A failure after
this narrow override must be reported as the real compilation, linking, Swift
6, test-target, resource, or configuration failure without adding flags.
