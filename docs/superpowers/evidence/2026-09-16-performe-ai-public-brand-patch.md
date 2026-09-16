# Performe AI public brand patch — local validation evidence

Date: 2026-09-16

## Scope and provenance

- Operation: `IMPLEMENT_PERFORME_AI_PUBLIC_BRAND_PATCH_V1`
- Repository: `/Users/eduardohenrique/Developer/performe-ai-client-beta-flow-v1`
- Branch: `codex/performe-ai-client-beta-flow-v1`
- Required starting HEAD: `48e3bbe091d1511605fbb5a629f18e25c56c26d5`
- Host classification: `LOCAL_DEVELOPMENT`
- Deployment required: no
- Remote resources changed: none

The patch is intentionally limited to the confirmed public brand leaks. Technical
identifiers, module names, bundle identifiers, asset names, API contracts, routing,
models, tools, clinical policy, and legacy non-mobile behavior remain unchanged.

## Root cause and correction

The iOS views still contained eight user-visible `BodyFlow` strings. Separately,
the authenticated mobile pipeline inherited the legacy Dr. Robert/Roberto identity
from both the stable prompt and the variable user context.

The correction:

- changes only the eight confirmed iOS public strings to `Performe AI` / `Flow`;
- uses `Flow` in the `mobile_flow` user context;
- neutralizes only the observed `Dr. Robert` / `Dr. Roberto` identity variants in
  the stable prompt when `historyProvider === 'mobile_flow'`;
- preserves the stable prompt structure and all non-identity instructions;
- preserves the representative `whatsapp_cloud` legacy identity.

## Files changed

Production allowlist:

- `apps/ios/BodyFlow/BodyFlow/DesignSystem/Components/ScreenStateView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Auth/SplashView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Library/PublishedContentCard.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Mascot/MascotCardView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Mascot/MascotDetailView.swift`
- `packages/agent/src/pipeline.ts`

Directly related tests:

- `apps/ios/BodyFlow/BodyFlowTests/LibraryPresentationTests.swift`
- `apps/ios/BodyFlow/BodyFlowTests/MascotAccessibilityModelTests.swift`
- `apps/ios/BodyFlow/BodyFlowUITests/BodyFlowUITests.swift`
- `packages/agent/src/mobile-authenticated-pipeline.test.ts`

No asset, app icon, SVG, generic coach copy, generator prompt, migration, or
unrelated documentation file was changed.

## TDD evidence

Initial Agent RED:

```text
COREPACK_ENABLE_NETWORK=0 corepack pnpm --filter @mpp/agent exec vitest run src/mobile-authenticated-pipeline.test.ts
```

- The real authenticated mobile entrypoint reached `llm.complete`.
- The captured prompt contained `Persona: Dr. Roberto Menescal.` instead of
  `Persona: Flow.`.
- The representative WhatsApp compatibility assertion passed.

iOS RED:

```text
xcodebuild test -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow \
  -destination 'platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9' \
  -only-testing:BodyFlowTests/LibraryPresentationTests \
  -only-testing:BodyFlowTests/MascotAccessibilityModelTests
```

- Assertions failed on the old library category and mascot accessibility copy.

Review B exposed a second, distinct RED case: a realistic active stable prompt
containing both `Dr. Roberto Menescal` and `Dr. Robert Menescal` still reached the
mobile LLM even after the variable context was corrected. The fixture was updated
first, and the focused test failed on the captured final prompt before the
channel-specific neutralization was implemented.

Final focused Agent GREEN:

```text
Test Files  1 passed (1)
Tests       6 passed (6)
```

The tests traverse `processAuthenticatedMessage` and `processMessage`, capture the
actual `systemPrompt` passed to `llm.complete`, prove both legacy variants absent
from `mobile_flow`, and prove the WhatsApp identity remains present.

## Regression verification

Agent suite:

```text
COREPACK_ENABLE_NETWORK=0 corepack pnpm --filter @mpp/agent exec vitest run
Test Files  70 passed (70)
Tests       1059 passed (1059)
```

Agent typecheck:

```text
COREPACK_ENABLE_NETWORK=0 corepack pnpm --filter @mpp/agent typecheck
PASS
```

Biome:

- `mobile-authenticated-pipeline.test.ts`: PASS.
- `pipeline.ts`: the repository's existing whole-file Biome debt remains: three
  errors and four warnings (import ordering, legacy formatting, explicit `any`,
  and non-null assertions). The new focused code introduced no `git diff --check`
  failure. The legacy file was not mass-formatted because that would exceed the
  authorized patch.

Relevant iOS test battery:

```text
BrandIdentityTests
LibraryPresentationTests
MascotAccessibilityModelTests
LocalizationContractTests
ScreenStateTests
MascotPresentationTests

Result: 59 tests passed, 0 failed, 0 skipped
```

Complete iOS unit suite:

```text
xcodebuild test ... -only-testing:BodyFlowTests
Result: 1145 tests passed, 0 failed, 0 skipped
```

UI verification:

- `BodyFlowUITests/testBrandIdentityIsVisibleOnAuthSurface`: PASS, with the actual
  accessibility label `Performe AI`.
- The existing Prompt 14 authenticated-shell fixture restored
  `screen.onboarding.welcome` instead of Today, so the mascot surface was not
  claimed as directly UI-verified. Mascot title and announcement behavior are
  covered by `MascotAccessibilityModelTests`; the compiled Release copy is also
  verified below. No out-of-scope fixture repair was made.

Release Simulator build:

```text
xcodebuild build ... -configuration Release ... CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
BUILD SUCCEEDED
```

Compiled `Info.plist`:

```text
CFBundleDisplayName = Performe AI
CFBundleName = Performe AI
CFBundleIdentifier = com.bodyflow.app
```

The bundle identifier remains an authorized internal technical identifier.

Compiled artifact copy scan:

```text
Performe AI = present
Uso do Performe AI = present
Mascote do Performe AI = present
O estado e a personalidade vêm do Flow. = present

Uso do BodyFlow = 0
Mascote BodyFlow = 0
coach BodyFlow = 0
Dr. Roberto = 0
Dr. Robert = 0
```

Remaining `BodyFlow` occurrences in the Release artifact are internal module,
symbol, source-path, bundle identifier, and asset identifiers. They are classified
`INTERNAL_REQUIRED`, not public copy.

## Static and independent review

- `git diff --check`: PASS.
- Public source scan across the five iOS production files: PASS.
- Out-of-scope path scan: PASS.
- Secret-pattern scan of the diff: PASS.
- Review A: Critical 0, Important 0, Minor 0, Ready Yes.
- Review B final: Critical 0, Important 0, Minor 0, Ready Yes.

## Deferred scope

The following remain deliberately `NEEDS_REVIEW` and were not changed:

- brand assets, SVGs, app icon, and `BodyFlowBrandAsset.swift`;
- generic coach terminology;
- WhatsApp-only and generator prompts;
- broader staging configuration and UI/UX rebrand coverage.

No deployment, Supabase, OpenRouter, CI-3, E2E, or other remote operation was
performed.

`REBRAND STATUS: PARTIAL`
