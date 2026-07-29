# BodyFlow iOS auth and onboarding — local simulator evidence

Captured on 2026-07-28/29 (`America/Sao_Paulo`) for Prompt 12 Task 8.

## Source and toolchain

- Branch: `codex/bodyflow-ios-auth-onboarding-v1`
- Product/test HEAD before this evidence-only commit:
  `5475e4f0d7a9f815ca7cb4eb9cb0825b349225c9`
- Base branch: `codex/bodyflow-ios-scaffold-v1`
- Xcode: `26.6` (`17F113`)
- Swift: `6.3.3` (`swiftlang-6.3.3.1.3`, `clang-2100.1.1.101`)
- Simulator: iPhone 17 Pro, iOS 26.5 (`23F77`), arm64
- Device ID: `27291590-659D-4A29-8F45-CA5CA2D154F9`
- Final simulator settings restored after capture: Light appearance, Large
  content size

## Build and test gates

Debug compile gate:

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -derivedDataPath /tmp/bodyflow-task8-final6-debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Result: `** BUILD SUCCEEDED **`.

Release compile gate:

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -configuration Release \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath /tmp/bodyflow-task8-final6-release \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Result: `** BUILD SUCCEEDED **`.

Full runtime test gate:

```bash
xcodebuild test \
  -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -derivedDataPath /tmp/bodyflow-task8-final6-signed \
  -resultBundlePath /tmp/BodyFlowTask8-Final6-Signed.xcresult
```

`xcresulttool` reported:

- result: passed;
- 191 logical tests passed: 175 unit tests and 16 UI tests;
- 210 executions passed after parameter expansion (194 unit and 16 UI);
- 0 failures, 0 skipped and 0 expected failures;
- 12 parameterized tests produced 31 test runs.

The runtime test command intentionally used local ad-hoc signing. Demo persistence
uses the Keychain, so unsigned builds are compile gates only and are not valid
substitutes for the signed runtime suite.

The signed suite covers the explicit root state machine, fresh sign-up,
development email confirmation, all seven onboarding steps, Today, Profile
persona editing, relaunch persistence, validation, cancellation and recoverable
errors. Release-policy tests prove that the development confirmation UI is not
available in Release and that synthetic development consent is rejected without
mutation.

## Curated screenshots

Every PNG is 1206×2622, was visually inspected, shows visible BodyFlow product
identity, and contains no real user information.

| File | Evidence |
| --- | --- |
| `01-sign-in.png` | Fresh signed-out entry and auth actions |
| `02-onboarding-body-data.png` | Body-data step with unclipped commands |
| `03-onboarding-persona.png` | Focus, Impulse and Zen choices; no balanced option |
| `04-onboarding-synthetic-consent.png` | Explicit development-only synthetic consent notice |
| `05-today.png` | Today after completing onboarding |
| `06-profile-persona-editor.png` | Persona editing from Profile |
| `07-accessibility-dynamic-type-welcome.png` | Welcome at Accessibility Dynamic Type without overlap |
| `08-dark-appearance-today.png` | Today in dark appearance |

## Static repository checks

```bash
git diff --check codex/bodyflow-ios-scaffold-v1...HEAD
rg -n "https?://|service_role|sb_secret_|SUPABASE|Authorization: Bearer|WhatsApp|whatsapp" apps/ios/BodyFlow
rg -n "email|password|birth_date|height_cm|weight_kg|body_fat_percent|token|raw_error" apps/ios/BodyFlow/BodyFlow/Core/Telemetry
```

Results:

- diff check exited 0;
- endpoint, secret, provider and channel scan returned no matches;
- telemetry scan found only the bounded auth-screen enum cases
  `passwordRecovery = "password_recovery"` and
  `emailConfirmation = "email_confirmation"`;
- no event construction contains email addresses, passwords, birth dates,
  height, weight, body-fat values, tokens, free text or raw errors.

## Boundaries and limitations

This is a deterministic local demonstration. Supabase/BFF calls and legal
consent documents are not live. A live integration still requires an approved
authentication provider/session strategy, reviewed backend endpoints,
production legal-document identifiers and the later `/me` profile contract.

No merge, deployment, migration, production change, real account, real email,
secret, TestFlight upload or external provider was used. No live Supabase/BFF
request was made.
