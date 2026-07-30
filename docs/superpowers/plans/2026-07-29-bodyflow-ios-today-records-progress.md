# BodyFlow iOS Today, Records And Progress Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the approved Prompt 13 native iOS experience for Today, meal and workout proposals, weight, hydration, supplement and medication occurrences, Plan, Progress, the persisted 7,700 kcal block, and the first bounded page of confirmed meal-log and workout History.

**Architecture:** SwiftUI feature models depend on small `Sendable` capability protocols. Debug, previews and tests use one actor-backed deterministic repository with complete pre-authored snapshots and an idempotency replay ledger. Release resolves unavailable adapters and fails closed with `operationUnavailable`. Official values are rendered exactly from server-shaped responses and are never recalculated or patched in iOS. Main-History detail resolves an individual `meal_logs` row synchronously from the already-loaded first-page snapshot; it has no detail request, grouping logic or second-page path.

**Tech Stack:** Xcode 26.6, Swift 6 with complete concurrency checking, SwiftUI, Observation, Foundation, Swift Testing, XCTest/XCUIAutomation, iOS 18.0, and the iPhone 17 Pro simulator on iOS 26.5 (`27291590-659D-4A29-8F45-CA5CA2D154F9`).

## Approval And Execution Boundary

- The approved specification is `docs/superpowers/specs/2026-07-29-bodyflow-ios-today-records-progress-design.md`.
- The user approved the architecture and this TDD plan. This mandatory
  documentary revision does not start Task 1; implementation remains paused
  until a later explicit instruction.
- Execute implementation only in `/Users/eduardohenrique/Developer/bodyflow`.
- Execute implementation only on `codex/bodyflow-ios-today-records-progress-v1`, stacked on `codex/bodyflow-ios-auth-onboarding-v1`.
- Preserve the visible name `BodyFlow`, bundle ID `com.bodyflow.app`, Swift 6 language mode and iOS 18.0 deployment target.
- Keep the existing five tabs and independent navigation stacks.
- Use Swift Testing for unit/component tests and XCTest/XCUIAutomation for UI tests.
- Start every production behavior with a focused failing test, run it, and record the expected RED reason before adding production code.
- Every task ends green, passes `git diff --check`, and creates one Conventional Commit. Do not combine task checkpoints.
- Do not edit `BodyFlow.xcodeproj/project.pbxproj`; the project uses file-system-synchronized groups, so new Swift files are discovered automatically.
- Do not add packages, live URLs, bearer tokens, Supabase clients, provider SDKs, real authentication material, secrets or production configuration.
- Do not create a real parser, photo picker, camera flow, microphone flow, transcription, media upload or weight endpoint.
- Do not add any architecture based on WhatsApp or another messaging transport.
- Do not run migrations, deploy, merge, archive, sign for a physical device or upload to TestFlight.
- Do not push application commits or create the stacked draft PR until the final local gate is green.

## Non-Negotiable Contract Invariants

- `TodayResponse.data` is the sole source for official daily values and `block_7700`.
- `ProgressResponse.data.deficitBlock` never reconstructs or repairs the 7,700 kcal block.
- iOS never calculates official calories, macros, targets, hydration progress, remaining food, net balance, streak, level, weight trend or block credit.
- Proposal create, edit and cancel invalidate Today only.
- Proposal confirm invalidates Today and main History.
- Hydration invalidates Today only.
- A routine action invalidates Today, the matching routine list and the matching item-specific history.
- Weight's Debug-only receipt invalidates no official read.
- Hydration accepts only integer amounts in the inclusive `1...5000` ml range.
- Weight reuses the approved inclusive `30...300` kg app-domain limit and remains non-transport.
- Demonstration meal text accepts `1...1000` Swift `String.count` characters only in Debug, previews and UI tests; this is not a current or future API contract.
- Telemetry emits `calculation_version` only at `1...64` ASCII characters matching `[A-Za-z0-9._:-]`, without truncation or normalization.
- `FeatureInvalidationCenter` is an `@MainActor @Observable final class` that carries revision signals only; refresh replaces the whole provider response.
- Each read owner observes only its revision with `.task(id:)`; a read model deduplicates an already active/completed revision, a newer revision cancels the prior task, and at most one complete response publishes per revision.
- A cancelled or superseded async task never publishes a late result, error, receipt or navigation.
- Every mutation owns an immutable payload, operation kind, validated idempotency key and `TimeProviding` timestamp. Retry reuses that exact attempt.
- Text, Photo and Audio always produce a detected draft and pending proposal before confirmation.
- Pending meal/workout proposals may be edited; confirmed records are read-only.
- `snoozed_until` is present only for `snoozed`, is later than `occurred_at`, and remains on the original occurrence's patient-local date. Presets are 15, 30 and 60 minutes; a custom local time is also supported. Crossing-date choices are unavailable and never clamped.
- Main History calls the current `GET /history` capability once per load or retry with `before=nil` and `limit=30`.
- Main History never derives `next_before`, never loads another page and exposes no “Load more”.
- Each History meal element is one individual `meal_logs` row identified by its row `id`. There is no `meal_id`, synthesized occurrence identifier or grouping by `consumed_at`/`meal_type`.
- An individual History meal detail must resolve only from the immutable snapshot already held by the same `HistoryViewModel`. Opening detail must not call `HistoryProviding`.
- Supplement and medication detail histories are separate and may reuse only the exact opaque `next_cursor` returned by their documented contract.
- New mock behavior is compiled/constructed only in Debug, previews and tests. Release installs unavailable adapters, ignores feature scenario arguments, and presents exactly `Indisponível nesta versão`.

## Stable Interfaces To Produce

These signatures establish task boundaries. Later tasks may add private helpers but must not broaden the public capability surface.

```swift
enum BodyFlowCapabilityError: Error, Equatable, Sendable {
    case operationUnavailable
    case offline
    case serviceUnavailable
    case invalidInput
    case idempotencyConflict
    case registrationNotPending
    case registrationExpired
    case routineTransitionInvalid
    case routineSnoozeInvalid
}

protocol TimeProviding: Sendable {
    func now() -> Date
}

protocol IdempotencyKeyProviding: Sendable {
    func nextKey() async throws -> IdempotencyKey
}

struct MutationAttempt<Payload: Hashable & Sendable>: Hashable, Sendable {
    let operation: MutationOperation
    let key: IdempotencyKey
    let payload: Payload
    let createdAt: Date
}
```

```swift
enum FeatureReadState<Value: Equatable & Sendable>: Equatable, Sendable {
    case idle
    case loading
    case loaded(Value)
    case empty
    case offline(previousValue: Value?)
    case failed(previousValue: Value?, error: BodyFlowCapabilityError)
    case unavailable
}

enum FeatureMutationState<
    Attempt: Equatable & Sendable,
    Receipt: Equatable & Sendable
>: Equatable, Sendable {
    case idle
    case submitting(Attempt)
    case succeeded(Receipt)
    case failed(Attempt, BodyFlowCapabilityError)
    case unavailable
}
```

Every documented BFF result keeps its response envelope:

```swift
struct MobileResponse<
    Payload: Codable & Equatable & Sendable
>: Codable, Equatable, Sendable {
    let data: Payload
    let meta: MobileResponseMetadata
}

typealias TodayResponse = MobileResponse<TodaySnapshot>
typealias PlanResponse = MobileResponse<PlanSnapshot>
typealias ProgressResponse = MobileResponse<ProgressSnapshot>
typealias HistoryResponse = MobileResponse<HistorySnapshot>
```

Registration and routine response aliases follow the same pattern. Feature view-model read state owns the relevant `data` snapshot, while providers and deterministic fixtures preserve the full contract response.

```swift
protocol TodayProviding: Sendable {
    func today() async throws -> TodayResponse
}

protocol MealDetectionProviding: Sendable {
    func detect(_ input: MealDetectionInput) async throws
        -> RegistrationProposalRequest
}

protocol RegistrationProviding: Sendable {
    func propose(
        _ attempt: MutationAttempt<RegistrationProposalRequest>
    ) async throws -> RegistrationProposalResponse

    func edit(
        _ attempt: MutationAttempt<RegistrationEditCommand>
    ) async throws -> RegistrationProposalResponse

    func confirm(
        _ attempt: MutationAttempt<RegistrationIDCommand>
    ) async throws -> RegistrationConfirmationResponse

    func cancel(
        _ attempt: MutationAttempt<RegistrationIDCommand>
    ) async throws -> RegistrationCancellationResponse
}

protocol HydrationRecording: Sendable {
    func record(
        _ attempt: MutationAttempt<HydrationCommand>
    ) async throws -> HydrationReceipt
}

protocol WeightRecording: Sendable {
    func record(
        _ attempt: MutationAttempt<WeightCommand>
    ) async throws -> WeightDemoReceipt
}
```

```swift
protocol RoutineProviding: Sendable {
    func list(
        kind: RoutineItemKind,
        includeArchived: Bool
    ) async throws -> RoutineListResponse

    func record(
        _ attempt: MutationAttempt<RoutineActionCommand>
    ) async throws -> RoutineActionResponse

    func history(
        kind: RoutineItemKind,
        itemID: String,
        cursor: String?,
        limit: Int
    ) async throws -> RoutineHistoryPage
}

protocol PlanProviding: Sendable {
    func plan() async throws -> PlanResponse
}

protocol ProgressProviding: Sendable {
    func progress() async throws -> ProgressResponse
}

struct HistoryQuery: Equatable, Sendable {
    let before: APITimestamp?
    let limit: Int

    static let firstPage = HistoryQuery(before: nil, limit: 30)
}

protocol HistoryProviding: Sendable {
    func history(_ query: HistoryQuery) async throws -> HistoryResponse
}
```

`WeightCommand` and `WeightDemoReceipt` are app-domain values, not transport DTOs. No Prompt 13 capability gets an `APIRequest`, route constant, base URL or live adapter.
Every payload placed in `MutationAttempt` is a value-semantic `Hashable & Sendable` command. Response snapshots need only `Codable/Equatable/Sendable`; opaque Plan JSON is never used as mutation identity.

## File Map

### Shared execution support

- Create `apps/ios/BodyFlow/BodyFlow/Core/Support/APITimestamp.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Support/JSONValue.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Support/MobileResponse.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Support/BodyFlowCapabilityError.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Support/TimeProviding.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Support/Idempotency.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Support/PatientTimeZoneContext.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Support/FeatureInvalidationCenter.swift`.
- Create Debug-only `apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoExecutionSupport.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Features/Shared/FeatureReadState.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Features/Shared/FeatureReadStateView.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Features/Shared/StaleDataBanner.swift`.
- Modify `apps/ios/BodyFlow/BodyFlow/DesignSystem/Components/ScreenStateView.swift`.

### Capability contracts and adapters

- Create `apps/ios/BodyFlow/BodyFlow/Core/Today/TodayModels.swift` and `TodayProviding.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Registration/RegistrationModels.swift`, `MealDetectionProviding.swift` and `RegistrationProviding.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Routine/RoutineModels.swift`, `RoutineSnoozePolicy.swift`, `RoutineProviding.swift`, `HydrationRecording.swift` and `WeightRecording.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Plan/PlanModels.swift` and `PlanProviding.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Progress/ProgressModels.swift` and `ProgressProviding.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Core/History/HistoryModels.swift` and `HistoryProviding.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Unavailable/UnavailableBodyFlowCapabilities.swift`.
- Create Debug-only `apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoBodyFlowFixtures.swift` and `DemoBodyFlowRepository.swift`.
- Modify `apps/ios/BodyFlow/BodyFlow/App/AppLaunchConfiguration.swift`.
- Modify `apps/ios/BodyFlow/BodyFlow/App/AppDependencies.swift`.
- Modify `apps/ios/BodyFlow/BodyFlow/BodyFlowApp.swift`.

### Feature UI and navigation

- Replace the scaffold content in `apps/ios/BodyFlow/BodyFlow/Features/Today/TodayRootView.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Features/Today/TodayViewModel.swift` and focused Today section views.
- Modify `apps/ios/BodyFlow/BodyFlow/Features/Register/RegisterRootView.swift` and `RegistrationSheet.swift`.
- Create registration coordinators and views under `apps/ios/BodyFlow/BodyFlow/Features/Register/`.
- Create routine list, detail, action and history models/views under `apps/ios/BodyFlow/BodyFlow/Features/Routine/`.
- Replace the scaffold content in `apps/ios/BodyFlow/BodyFlow/Features/Plan/PlanRootView.swift`; create `PlanViewModel.swift`, `PlanComponents.swift` and `PlanDetailView.swift`.
- Replace the scaffold content in `apps/ios/BodyFlow/BodyFlow/Features/Progress/ProgressRootView.swift`; create `ProgressViewModel.swift`, `ProgressComponents.swift` and `Block7700DetailView.swift`.
- Create main-History files under `apps/ios/BodyFlow/BodyFlow/Features/History/`.
- Modify `apps/ios/BodyFlow/BodyFlow/App/AppRouter.swift` and `AppShellView.swift`.
- Modify `apps/ios/BodyFlow/BodyFlow/Core/Telemetry/TelemetryClient.swift` only to add bounded Prompt 13 event vocabulary.

### Tests, previews and evidence

- Create focused Swift Testing suites under `apps/ios/BodyFlow/BodyFlowTests/` as named in each task.
- Add `apps/ios/BodyFlow/BodyFlowUITests/BodyFlowUITestSupport.swift`.
- Add focused UI suites `Prompt13TodayUITests.swift`, `Prompt13RegistrationUITests.swift`, `Prompt13RoutineUITests.swift`, `Prompt13PlanProgressHistoryUITests.swift` and `Prompt13AccessibilityUITests.swift`.
- Create Debug-only preview support at `apps/ios/BodyFlow/BodyFlow/Features/PreviewSupport/Prompt13PreviewSupport.swift`.
- Create final evidence under `docs/superpowers/evidence/2026-07-29-bodyflow-ios-today-records-progress/`.

## Commands Used Throughout

Focused unit RED/GREEN example:

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -only-testing:BodyFlowTests/CapabilitySupportTests \
  test
```

Focused UI RED/GREEN example:

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -only-testing:BodyFlowUITests/Prompt13TodayUITests/testTodaySeparatesFoodRemainingFromNetBalance \
  test
```

Per-task hygiene:

```bash
git diff --check
git status --short
```

Do not treat a source scan as a replacement for behavior tests. Static scans below enforce absence constraints after behavior is already green.

---

### Task 1: Add Time, Timestamp, Opaque JSON And Idempotency Primitives

**Files:**

- Create: `apps/ios/BodyFlow/BodyFlowTests/CapabilitySupportTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Support/APITimestamp.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Support/JSONValue.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Support/BodyFlowCapabilityError.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Support/TimeProviding.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Support/Idempotency.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoExecutionSupport.swift`

**Interfaces:**

- `APITimestamp` decodes RFC 3339 with or without fractional seconds and encodes a UTC RFC 3339 value.
- `JSONValue` preserves opaque object, array, string, number, boolean and null values without business accessors.
- `SystemTimeProvider` is the non-mock clock available to Release; feature logic still receives it through the protocol and does not call `Date()` directly.
- Debug/test-only `FixedTimeProvider` and `DeterministicIdempotencyKeyProvider` live in `DemoExecutionSupport.swift`, whose complete contents are guarded by `#if DEBUG`.
- `IdempotencyKey(validating:)` accepts 8...128 characters from `[A-Za-z0-9._:-]`.
- `IdempotencyKeyProviding.nextKey()` throws so the Release implementation can fail before an attempt is created.
- `MutationAttempt` records operation, key, immutable payload and injected creation time.

- [ ] **Step 1: Write RED tests for timestamps and opaque payloads**

Add tests that decode timestamps with and without fractional seconds, round-trip a nested `JSONValue`, preserve explicit `null`, and ignore no value by coercing it to a typed nutrition field.

```swift
@Test("opaque nutrition payload round-trips without interpretation")
func opaquePayloadRoundTrips() throws {
    let data = Data(#"{"future":{"values":[1,true,null]},"version":"v9"}"#.utf8)
    let value = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(try JSONDecoder().decode(
        JSONValue.self,
        from: JSONEncoder().encode(value)
    ) == value)
}
```

- [ ] **Step 2: Run `CapabilitySupportTests` and observe RED**

Expected RED: compile failure because `APITimestamp`, `JSONValue` and `TimeProviding` do not exist.

- [ ] **Step 3: Implement the minimal timestamp, JSON and time-source types**

Keep formatter construction local or safely isolated for Swift 6. Add `SystemTimeProvider` for a future live graph, but inject `FixedTimeProvider` in Debug/previews/tests. No feature may instantiate `SystemTimeProvider` directly.

- [ ] **Step 4: Write the next RED tests for key validation and retained attempts**

Test 7-character, 129-character and forbidden-space keys; the 8- and 128-character boundaries; deterministic sequence; and an attempt timestamp equal to `FixedTimeProvider.value`.

```swift
@Test("retry retains the original mutation attempt")
func retryRetainsAttempt() throws {
    let fixedDate = Date(timeIntervalSince1970: 1_785_283_200)
    let attempt = MutationAttempt(
        operation: .hydration,
        key: try IdempotencyKey(validating: "test-key-0001"),
        payload: CapabilityPayloadFixture(value: "250"),
        createdAt: fixedDate
    )
    let retry = attempt
    #expect(retry.key == attempt.key)
    #expect(retry.payload == attempt.payload)
    #expect(retry.createdAt == attempt.createdAt)
}
```

- [ ] **Step 5: Run the focused test and observe the second RED**

Expected RED: missing `IdempotencyKey`, provider, operation and attempt types.

- [ ] **Step 6: Implement the minimal idempotency types and refactor**

Use explicit validation, no random fallback after failure, and no key in descriptions or telemetry. Define the test-local `CapabilityPayloadFixture: Hashable & Sendable` beside the tests. Keep the operation enum limited to proposal create/edit/confirm/cancel, hydration, weight and routine action. Keep the fixed clock/key implementations structurally out of Release.

- [ ] **Step 7: Run the focused suite green and commit**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowTests/CapabilitySupportTests test
git diff --check
git add apps/ios/BodyFlow/BodyFlow/Core/Support apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoExecutionSupport.swift apps/ios/BodyFlow/BodyFlowTests/CapabilitySupportTests.swift
git commit -m "feat(ios): add capability execution primitives"
```

---

### Task 2: Define The Today Contract Without Client Calculations

**Files:**

- Create: `apps/ios/BodyFlow/BodyFlowTests/TodayContractTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/BodyFlowTestFixtures.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Support/MobileResponse.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Today/TodayModels.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Today/TodayProviding.swift`

**Interfaces:**

- `MobileResponse<Payload>` mirrors the current `{data, meta}` result from `mobileSuccess`; every approved contract response reuses this exact envelope from this task onward.
- `TodaySnapshot` mirrors the documented fields inside `data`, and `TodayResponse` is `MobileResponse<TodaySnapshot>`.
- Nullable fields remain optional.
- Confirmed meal rows remain individual response rows.
- Nutrition source is decoded as an extensible raw string and mapped conservatively in presentation later.
- `block_7700` remains an optional server value with no calculator.

- [ ] **Step 1: Copy a sanitized current-contract Today response into the test fixture**

Use the existing response shape documented in `docs/mobile/api-v1.md` and the route implementation under `apps/admin/src/app/api/mobile/v1/today/route.ts`. Add one deliberately inconsistent fixture where `targets.calories_kcal`, `consumed.calories_kcal`, `remaining_food_kcal`, `food_excess_kcal`, `exercise_kcal`, `daily_balance_kcal` and `daily_balance_status` are independently authored and cannot be reproduced by a plausible local formula.

- [ ] **Step 2: Write RED decoding tests**

Assert exact coding keys, optional targets, completion status, hydration-without-target, routine occurrences, pending registrations, source metadata, and optional block. Add an unknown additive JSON key and an unfamiliar nutrition-source string; decoding must still succeed.

```swift
@Test("official daily values remain exactly as received")
func preservesOfficialDailyValues() throws {
    let response = try BodyFlowTestFixtures.decodeInconsistentToday()
    #expect(response.data.targets.caloriesKcal == 1_935)
    #expect(response.data.consumed.caloriesKcal == 1_200)
    #expect(response.data.remainingFoodKcal == 731)
    #expect(response.data.foodExcessKcal == 17)
    #expect(response.data.exerciseKcal == 419)
    #expect(response.data.dailyBalanceKcal == -83)
    #expect(response.data.dailyBalanceStatus == "provisional")
}
```

- [ ] **Step 3: Run `TodayContractTests` and observe RED**

Expected RED: compile failure because `TodayResponse` and `TodayProviding` do not exist.

- [ ] **Step 4: Implement the minimal models and provider**

Implement `MobileResponseMetadata` from only the currently documented metadata fields, then `MobileResponse<Payload>` and `TodaySnapshot`. Use explicit snake-case coding keys. Add no computed calories, percentages, totals or fallback-to-zero properties. Preserve response order for meals, workouts and occurrences.

- [ ] **Step 5: Refactor the mandatory shared response envelope**

Use the same `MobileResponse` directly for Registration, Routine, Plan, Progress and History tasks. Do not strip the envelope through an imaginary adapter, and do not create an endpoint, parser or transport client.

- [ ] **Step 6: Run green, run the legacy Today/API tests, and commit**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowTests/TodayContractTests -only-testing:BodyFlowTests/APIClientTests test
git diff --check
git add apps/ios/BodyFlow/BodyFlow/Core/Support/MobileResponse.swift apps/ios/BodyFlow/BodyFlow/Core/Today apps/ios/BodyFlow/BodyFlowTests/TodayContractTests.swift apps/ios/BodyFlow/BodyFlowTests/BodyFlowTestFixtures.swift
git commit -m "feat(ios): define today capability contract"
```

---

### Task 3: Define Meal And Workout Proposal Contracts

**Files:**

- Create: `apps/ios/BodyFlow/BodyFlowTests/RegistrationContractTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Registration/RegistrationModels.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Registration/MealDetectionProviding.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Registration/RegistrationProviding.swift`

**Interfaces:**

- `MealDetectionInput` distinguishes Text, labelled Photo sample and labelled Audio sample without media bytes.
- Detection returns a structured `RegistrationProposalRequest`; it does not persist.
- Meal and workout requests use the current discriminated proposal contract.
- Proposal, confirmation and cancellation responses reuse `MobileResponse` around their exact documented `data` snapshots.
- Meal edits expose only food name, quantity, optional patient kcal, meal type and supported time.
- No request accepts client-calculated macros, totals or workout calories.

- [ ] **Step 1: Write RED request-encoding tests**

Assert the exact current meal/workout discriminator and documented editable fields. Encode a meal edit and prove that the JSON has no macro-total, calorie-total, provider-source or confirmed-reference keys.

- [ ] **Step 2: Write RED response-decoding tests**

Decode complete pending proposal, warning, expiry, confirmation and cancellation fixtures. Keep unknown future response fields additive.

- [ ] **Step 3: Run `RegistrationContractTests` and observe RED**

Expected RED: missing registration models and protocols.

- [ ] **Step 4: Implement the minimal contracts**

Use nominal command types:

```swift
struct RegistrationEditCommand: Hashable, Sendable {
    let registrationID: String
    let proposal: RegistrationProposalRequest
}

struct RegistrationIDCommand: Hashable, Sendable {
    let registrationID: String
}
```

Do not add route strings or `APIRequest` mappings.

- [ ] **Step 5: Refactor common pending metadata without merging meal/workout semantics**

The returned complete proposal replaces the old proposal after edit. Do not add a local patch method.

- [ ] **Step 6: Run green and commit**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowTests/RegistrationContractTests test
git diff --check
git add apps/ios/BodyFlow/BodyFlow/Core/Registration apps/ios/BodyFlow/BodyFlowTests/RegistrationContractTests.swift
git commit -m "feat(ios): define registration capability contracts"
```

---

### Task 4: Define Routine, Hydration And Weight Contracts With Snooze Policy

**Files:**

- Create: `apps/ios/BodyFlow/BodyFlowTests/RoutineContractTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/RoutineSnoozePolicyTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Routine/RoutineModels.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Routine/RoutineSnoozePolicy.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Routine/RoutineProviding.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Routine/HydrationRecording.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Routine/WeightRecording.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Support/PatientTimeZoneContext.swift`

**Interfaces:**

- `RoutineActionCommand` carries item kind/id, status, reminder-rule id, scheduled time, occurrence time and optional snooze time.
- `RoutineSnoozePolicy` receives `scheduledFor`, injected `occurredAt` and an explicit patient IANA timezone context.
- `RoutineHistoryPage.nextCursor` is an opaque optional string.
- `HydrationCommand` carries an integer amount validated inclusively at `1...5000` ml and an occurrence time.
- `WeightCommand` validates inclusively at `30...300` kg, is a non-`Codable` app command and has no route/path representation.
- Documented hydration/routine responses reuse `MobileResponse`; the local weight receipt deliberately does not.

- [ ] **Step 1: Write RED contract tests**

Decode supplement and medication list responses—whose nested item later feeds the detail UI—and item-history responses from the currently documented route contracts. Assert that `next_cursor` is preserved byte-for-byte and callers pass it back unchanged. Do not create a `RoutineDetailResponse`, detail path or detail provider method.

Add literal command-boundary RED tests: hydration rejects `0` and `5001` ml and accepts `1` and `5000` ml; weight rejects `29.99` and `300.01` kg and accepts `30` and `300` kg. The weight limit is reused from the approved onboarding domain rule and must not create a transport DTO or presumed endpoint.

- [ ] **Step 2: Write RED snooze-policy tests**

Use a fixed `TimeProviding` instant and explicit IANA timezone. Cover:

- taken/skipped reject a non-nil `snoozedUntil`;
- snoozed rejects nil;
- 15, 30 and 60 minute presets are based on `occurredAt`;
- custom time must be later;
- a preset or custom value must stay on the patient-local date of the original `scheduledFor` occurrence;
- an `occurredAt` already outside the original occurrence's local date rejects snooze;
- a preset or custom value crossing that original local date is unavailable;
- a DST/date-edge value is validated in the injected patient timezone;
- the policy never clamps a crossing-date value.

```swift
@Test("preset crossing the patient local date is unavailable")
func crossingDatePresetIsUnavailable() throws {
    let policy = RoutineSnoozePolicy(timeZone: try #require(
        TimeZone(identifier: "America/Sao_Paulo")
    ))
    #expect(policy.date(
        for: .minutes(60),
        scheduledFor: BodyFlowTestFixtures.lateRoutineSchedule,
        occurredAt: BodyFlowTestFixtures.lateRoutineOccurrence
    ) == nil)
}
```

- [ ] **Step 3: Run both suites and observe RED**

Expected RED: missing routine commands, provider and snooze policy.

- [ ] **Step 4: Implement GREEN with explicit validation**

`PatientTimeZoneContext` is a small `Sendable` value with an optional documented IANA identifier. Debug/tests install a fixed identifier; Release has no synthetic patient timezone and operations fail unavailable before validation. Presets add to `occurredAt`, require a later result, and compare the result's patient-local date to `scheduledFor`'s patient-local date. Enforce the exact hydration and weight boundaries from Step 1 without clamping. Do not query a presumed endpoint or use `TimeZone.current` as an official patient timezone.

- [ ] **Step 5: Refactor action construction**

Centralize only structural validation. Provider/server validation remains authoritative. Do not construct or expose an internal occurrence key.

- [ ] **Step 6: Run green and commit**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowTests/RoutineContractTests -only-testing:BodyFlowTests/RoutineSnoozePolicyTests test
git diff --check
git add apps/ios/BodyFlow/BodyFlow/Core/Routine apps/ios/BodyFlow/BodyFlow/Core/Support/PatientTimeZoneContext.swift apps/ios/BodyFlow/BodyFlowTests/RoutineContractTests.swift apps/ios/BodyFlow/BodyFlowTests/RoutineSnoozePolicyTests.swift
git commit -m "feat(ios): define routine recording contracts"
```

---

### Task 5: Define Plan And Progress Contracts

**Files:**

- Create: `apps/ios/BodyFlow/BodyFlowTests/PlanProgressContractTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Plan/PlanModels.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Plan/PlanProviding.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Progress/ProgressModels.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Progress/ProgressProviding.swift`

**Interfaces:**

- Plan exposes only stable training/nutrition metadata approved in the specification.
- `PlanResponse` and `ProgressResponse` are `MobileResponse<PlanSnapshot>` and `MobileResponse<ProgressSnapshot>`.
- The nutrition prescription payload remains `JSONValue?` and has no business accessor.
- Progress preserves optional current weight/body-fat/block values and response-supplied XP, level, streak, badges and dates.
- No Progress type exposes a method that builds a Today block.

- [ ] **Step 1: Write RED decoding tests from current route responses**

Use sanitized output shapes from `apps/admin/src/app/api/mobile/v1/plan/route.ts` and `progress/route.ts`. Assert null preservation, additive unknown-field tolerance, and exact opaque JSON round-trip.

- [ ] **Step 2: Add RED API-shape tests for forbidden derivations**

Construct divergent Progress and Today block fixtures. The Plan/Progress models must expose only their own response values; no computed planned/completed sessions, projected weight or block percentage is present.

- [ ] **Step 3: Run `PlanProgressContractTests` and observe RED**

Expected RED: missing Plan/Progress models and providers.

- [ ] **Step 4: Implement minimal models/protocols and refactor date metadata**

Share `APITimestamp`; do not share unrelated Plan and Progress domain models.

- [ ] **Step 5: Run green and commit**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowTests/PlanProgressContractTests test
git diff --check
git add apps/ios/BodyFlow/BodyFlow/Core/Plan apps/ios/BodyFlow/BodyFlow/Core/Progress apps/ios/BodyFlow/BodyFlowTests/PlanProgressContractTests.swift
git commit -m "feat(ios): define plan and progress contracts"
```

---

### Task 6: Define First-Page-Only Main History

**Files:**

- Create: `apps/ios/BodyFlow/BodyFlowTests/HistoryContractTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/BodyFlowTestFixtures.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/History/HistoryModels.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/History/HistoryProviding.swift`

**Interfaces:**

- `HistoryResponse` is `MobileResponse<HistorySnapshot>`; `HistorySnapshot` contains independent `meals` and `workouts` arrays plus current response pagination metadata.
- `HistoryMealLogRow.id` is the row identifier. The Swift model has no `mealID`.
- `HistoryQuery.firstPage` is the only query exposed to the main-History view model.
- The provider has one `history(_:)` read method and no detail or load-more method.

- [ ] **Step 1: Write RED decoding tests with same-time rows**

Create a fixture with two meal rows that share `consumed_at` and `meal_type` but have distinct row ids and foods. Assert decoded count, order and row identity. Decode meals-only, workouts-only and both-empty responses.

```swift
@Test("history keeps meal log rows separate and ordered")
func rowsStaySeparate() throws {
    let response = try BodyFlowTestFixtures.decodeHistoryWithMatchingRows()
    #expect(response.data.meals.map(\.id) == [
        "fixture-meal-row-1",
        "fixture-meal-row-2"
    ])
}
```

- [ ] **Step 2: Write RED query-surface tests**

Assert `HistoryQuery.firstPage.before == nil` and `.limit == 30`. The spy surface must have no detail request and no pagination command.

- [ ] **Step 3: Run `HistoryContractTests` and observe RED**

Expected RED: missing History types.

- [ ] **Step 4: Implement the exact models and narrow provider**

Preserve arrays independently. Do not create a merged feed, inferred cursor, `meal_id`, occurrence group or a synthesized meal type.

- [ ] **Step 5: Refactor response metadata without interpreting it**

Pagination metadata may be decoded for transparency but must not produce `nextBefore`.

- [ ] **Step 6: Run green and commit**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowTests/HistoryContractTests test
git diff --check
git add apps/ios/BodyFlow/BodyFlow/Core/History apps/ios/BodyFlow/BodyFlowTests/HistoryContractTests.swift apps/ios/BodyFlow/BodyFlowTests/BodyFlowTestFixtures.swift
git commit -m "feat(ios): define bounded history contract"
```

---

### Task 7: Enforce The Release Fail-Closed Dependency Graph

**Files:**

- Create: `apps/ios/BodyFlow/BodyFlowTests/AppLaunchConfigurationPrompt13Tests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/AppDependenciesTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/BodyFlowTestFixtures.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Unavailable/UnavailableBodyFlowCapabilities.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Core/Networking/APIClient.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppLaunchConfiguration.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppDependencies.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/BodyFlowApp.swift`

**Interfaces:**

- `AppDependencies.make(configuration:)` installs every Prompt 13 capability plus time/key providers and explicit patient-timezone context. Mutable invalidation is intentionally not part of the `Sendable` dependency struct.
- Release installs unavailable providers for reads, detection and mutations.
- Until Task 9 creates the deterministic repository, Debug also receives unavailable Prompt 13 adapters while all inherited Prompt 12 services remain functional.
- Feature Debug/UI-test arguments are ignored whenever `buildFlavor == .release`.
- Release uses `SystemTimeProvider`, an `UnavailableIdempotencyKeyProvider` that throws before an attempt is formed, a timezone context without synthetic patient data, and an `UnavailableAPIClient`.

- [ ] **Step 1: Write RED configuration tests**

Pass every planned argument while resolving `.release`: `loaded`, `loading`, `empty`, `offline`, `stale-offline`, `error`, `stale-error`, `incomplete`, `unavailable`, `registration-error-once`, `routine-conflict-once` and `reduce-motion`, each with the `--ui-testing-prompt13-` prefix. Assert `.releaseUnavailable`, no fixed demo scenario, and no synthetic success behavior.

- [ ] **Step 2: Write RED service-level fail-closed tests**

Resolve Release dependencies and invoke every new read, detector and mutation protocol plus the idempotency-key provider. Each must throw `BodyFlowCapabilityError.operationUnavailable`; no method may return a receipt, proposal, key or fixture. Send the legacy `APIRequest<TodaySummary>(GET /today)` too and require `APIClientError.operationUnavailable`, proving the previous Today fixture is not reachable through the Release graph.

```swift
@Test("release meal detection fails closed")
func releaseDetectionIsUnavailable() async {
    let dependencies = AppDependencies.make(
        configuration: .resolve(arguments: ["--ui-testing-prompt13-loaded"],
                                buildFlavor: .release)
    )
    await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
        try await dependencies.mealDetection.detect(
            BodyFlowTestFixtures.textMealDetectionInput
        )
    }
}
```

- [ ] **Step 3: Run the focused tests and observe RED**

Expected RED: missing dependencies/unavailable adapters or a current graph path that still resolves demo success.

- [ ] **Step 4: Implement unavailable adapters and dependency selection**

Keep unavailable adapters free of fixtures and mutation state. Do not hide operations as the only guard; the service call itself must fail. Keep existing Prompt 12 authentication behavior intact and preserve the current `scaffold()`/`demo(configuration:)` wrappers while migrating their internals to `make(configuration:)`.

- [ ] **Step 5: Add a Release compile checkpoint**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -configuration Release \
  -destination "generic/platform=iOS Simulator" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Expected GREEN: Release compiles without referring to a Debug-only repository or fixture symbol.

- [ ] **Step 6: Refactor dependency construction and run green**

Keep `AppDependencies` immutable and `Sendable`. Do not place `FeatureInvalidationCenter`, view models or mutable official response snapshots in it or in the SwiftUI environment.

- [ ] **Step 7: Commit**

```bash
git diff --check
git add apps/ios/BodyFlow/BodyFlow/App apps/ios/BodyFlow/BodyFlow/BodyFlowApp.swift apps/ios/BodyFlow/BodyFlow/Core/Networking/APIClient.swift apps/ios/BodyFlow/BodyFlow/Core/Unavailable apps/ios/BodyFlow/BodyFlowTests/AppLaunchConfigurationPrompt13Tests.swift apps/ios/BodyFlow/BodyFlowTests/AppDependenciesTests.swift apps/ios/BodyFlow/BodyFlowTests/BodyFlowTestFixtures.swift
git commit -m "feat(ios): fail prompt 13 capabilities closed in release"
```

---

### Task 8: Add Typed Read/Mutation State And Signal-Only Invalidation

**Files:**

- Create: `apps/ios/BodyFlow/BodyFlowTests/FeatureReadStateTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/FeatureInvalidationTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Shared/FeatureReadState.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Shared/FeatureReadStateView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Shared/StaleDataBanner.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Support/FeatureInvalidationCenter.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppRootView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/DesignSystem/Components/ScreenStateView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Shared/FeatureComponents.swift`

**Interfaces:**

- Reads represent `idle`, `loading`, `loaded`, `empty`, `offline(previousValue:)`, `failed(previousValue:error:)` and `unavailable`.
- Mutations retain the exact typed attempt when recoverable. Registration wraps its four concrete `MutationAttempt` payload types in a `RegistrationMutationAttempt` enum and its four result types in `RegistrationMutationReceipt`; hydration, weight and routine may use their single concrete attempt/receipt directly.
- `FeatureInvalidationCenter` is declared `@MainActor @Observable final class` and stores integer revisions keyed by `.today`, `.history`, `.routineList(kind:)` and `.routineHistory(kind:itemID:)`.
- The single owning view for each read observes only its relevant expression with `.task(id: invalidationCenter.revision(for: key))`. The read model accepts that revision and deduplicates an already active or completed revision-driven load; revision zero performs the initial complete load and each later revision publishes at most one new complete response.
- When the `.task(id:)` identity changes, SwiftUI cancellation plus the read model's load-identity check prevents the prior task from publishing a late value/error. No second observer or `onChange` starts the same reload.
- `AppRootView` passes immutable dependencies explicitly into `AppShellView`; the shell owns one long-lived `@State FeatureInvalidationCenter` on the main actor. Later feature tasks pass that same instance explicitly to the models/sheets that need it.
- Screen state uses stable ids `state.loading`, `state.empty`, `state.offline`, `state.error`, `state.unavailable`, `state.stale-banner` and `state.retry`.

- [ ] **Step 1: Write RED state-mapping tests**

Assert:

- initial offline/error yields a full state with Retry;
- offline/error after content preserves that exact value and requests a stale banner;
- unavailable maps to exactly `Indisponível nesta versão` and offers no Retry;
- cancellation maps to no user-visible failure;
- a mutation failure retains its attempt and receipt is absent.

- [ ] **Step 2: Run `FeatureReadStateTests` and observe RED**

Expected RED: missing generic states and presentation mapping.

- [ ] **Step 3: Implement the state types and minimal shared views**

Make the enum cases mutually exclusive. Do not turn a missing value into empty or zero. Stack state content at accessibility Dynamic Type sizes and retain the existing 44-point target rules.

- [ ] **Step 4: Write RED invalidation-matrix tests**

Use a new center and verify the exact revision deltas:

```swift
@Test("proposal changes invalidate only Today")
@MainActor
func proposalInvalidation() {
    let center = FeatureInvalidationCenter()
    center.record(.proposalChanged)
    #expect(center.revision(for: .today) == 1)
    #expect(center.revision(for: .history) == 0)
}

@Test("confirmation invalidates Today and History")
@MainActor
func confirmationInvalidation() {
    let center = FeatureInvalidationCenter()
    center.record(.registrationConfirmed)
    #expect(center.revision(for: .today) == 1)
    #expect(center.revision(for: .history) == 1)
}
```

Also prove hydration affects Today only, routine action affects the exact three keys, and weight affects none. Add an observation harness proving an unrelated revision performs no reload, repeated observation of an already active/completed revision does not duplicate a load, one relevant revision performs exactly one complete reload, and a second relevant revision cancels the first task so only the newest complete response may publish. A cancelled incomplete load may be attempted again if the same revision becomes visible later; explicit Retry is a separate load intention.

- [ ] **Step 5: Run `FeatureInvalidationTests` and observe RED**

Expected RED: missing center, keys and effects.

- [ ] **Step 6: Implement signal-only invalidation and refactor**

The center must never contain `TodayResponse`, History rows, calorie values or mutation receipts. Implement it as `@MainActor @Observable final class`; consumers reload a complete snapshot from `.task(id:)` when their relevant revision changes. Every load checks cancellation and its captured revision/load identity before publication. Do not add the center to `AppDependencies`.

- [ ] **Step 7: Establish long-lived shell ownership**

Change `AppRootView` to construct `AppShellView(userID:dependencies:)`. Initialize one `@State` center in the shell initializer. Feature-model state and explicit center arguments are added incrementally in later tasks, but mutable models must always be created outside `body`. Do not add a competing notification, value-patching or `onChange` refresh channel.

- [ ] **Step 8: Run both suites green and commit**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowTests/FeatureReadStateTests -only-testing:BodyFlowTests/FeatureInvalidationTests -only-testing:BodyFlowTests/ScreenStateTests test
git diff --check
git add apps/ios/BodyFlow/BodyFlow/App/AppRootView.swift apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift apps/ios/BodyFlow/BodyFlow/Core/Support/FeatureInvalidationCenter.swift apps/ios/BodyFlow/BodyFlow/Features/Shared apps/ios/BodyFlow/BodyFlow/DesignSystem/Components/ScreenStateView.swift apps/ios/BodyFlow/BodyFlowTests/FeatureReadStateTests.swift apps/ios/BodyFlow/BodyFlowTests/FeatureInvalidationTests.swift
git commit -m "feat(ios): add feature states and invalidation signals"
```

---

### Task 9: Build Debug-Only Complete Read Snapshots

**Files:**

- Create: `apps/ios/BodyFlow/BodyFlowTests/DemoBodyFlowReadTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/Prompt13LaunchScenarioTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/AppDependenciesTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoBodyFlowFixtures.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoBodyFlowRepository.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppLaunchConfiguration.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppDependencies.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppRootView.swift`
- Create: `apps/ios/BodyFlow/BodyFlowUITests/BodyFlowUITestSupport.swift`

**Interfaces:**

- Both Demo files are wrapped completely in `#if DEBUG`.
- `DemoBodyFlowScenario` covers loaded, loading-delay, empty, initial offline, stale offline, initial error, stale error, incomplete day, unavailable presentation, one-shot registration failure, one-shot routine conflict and Reduce Motion verification.
- One actor implements narrow read protocols while callers depend on the individual protocol.
- `AppDependencies.make` constructs exactly one actor instance and reuses it for Today, Plan, Progress, History and routine list/history reads. Because `RoutineProviding` also contains `record`, Task 9 supplies a Debug stub on that same actor that throws `operationUnavailable` until its RED implementation in Task 11.
- Detection, registration, hydration and weight fields remain unavailable until Tasks 10–11 wire that same actor after the corresponding conformances exist.
- Snapshots are complete pre-authored responses, not deltas.

- [ ] **Step 1: Write RED launch-scenario tests**

Map these exact Debug flags:

- `--ui-testing-prompt13-loaded`
- `--ui-testing-prompt13-loading`
- `--ui-testing-prompt13-empty`
- `--ui-testing-prompt13-offline`
- `--ui-testing-prompt13-stale-offline`
- `--ui-testing-prompt13-error`
- `--ui-testing-prompt13-stale-error`
- `--ui-testing-prompt13-incomplete`
- `--ui-testing-prompt13-unavailable`
- `--ui-testing-prompt13-registration-error-once`
- `--ui-testing-prompt13-routine-conflict-once`
- `--ui-testing-prompt13-reduce-motion`

Assert fixed time, deterministic key seed and synthetic IANA timezone per scenario. `reduce-motion` must produce an optional Debug override of `true`; every other Debug scenario and every Release configuration leaves the override nil. Reassert that Release ignores each flag and installs no scenario.

- [ ] **Step 2: Run `Prompt13LaunchScenarioTests` and observe RED**

Expected RED: scenario enum/arguments do not exist.

- [ ] **Step 3: Implement Debug scenario parsing and shared UI-test launch support**

`BodyFlowUITestSupport` always launches with `--ui-testing` plus exactly one Prompt 13 scenario, uses the existing completed/reset auth fixture, and isolates state per test. It provides shared 44-point, screenshot and accessibility-tree helpers before the first Prompt 13 UI suite is added. `AppRootView` reads only the parsed optional override: when present it injects `accessibilityReduceMotion=true`; when nil it preserves the actual system environment value. No feature view reads process arguments.

- [ ] **Step 4: Write RED fixture-coherence tests**

Assert the actor returns the exact loaded Today/Plan/Progress/History/routine snapshots selected by the scenario. The inconsistent Today fixture from Task 2 must come back unchanged. Downcast the Debug read existentials in `AppDependenciesTests` and use actor identity (`===`) to prove they share one repository; assert mutation/detection fields still fail unavailable at this checkpoint.

- [ ] **Step 5: Write RED state-scenario tests**

Assert deterministic offline/recoverable errors and complete empty/incomplete snapshots. `insufficient_data` is a successful Today value, not an error.

- [ ] **Step 6: Run `DemoBodyFlowReadTests` and observe RED**

Expected RED: missing Debug repository/fixtures.

- [ ] **Step 7: Implement fixtures and actor reads**

Copy current response shapes into synthetic fixtures. The actor may select the next pre-authored snapshot by scenario but must not sum, increment, estimate, calculate or repair a value.

- [ ] **Step 8: Wire Debug dependencies only**

Under `#if DEBUG`, `AppDependencies.make(configuration:)` installs the one actor for the read capabilities available in this task plus fixed time, deterministic keys and an explicit synthetic patient timezone. Release continues to compile against only unavailable adapters.

- [ ] **Step 9: Refactor scenario selection**

Keep scenario parsing in `AppLaunchConfiguration`, not the views. Do not allow Release resolution to honor any scenario flag.

- [ ] **Step 10: Run green, rerun Release build, and commit**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowTests/Prompt13LaunchScenarioTests -only-testing:BodyFlowTests/DemoBodyFlowReadTests -only-testing:BodyFlowTests/AppDependenciesTests test
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -configuration Release -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO build
git diff --check
git add apps/ios/BodyFlow/BodyFlow/Core/Demo apps/ios/BodyFlow/BodyFlow/App/AppLaunchConfiguration.swift apps/ios/BodyFlow/BodyFlow/App/AppDependencies.swift apps/ios/BodyFlow/BodyFlow/App/AppRootView.swift apps/ios/BodyFlow/BodyFlowTests/AppDependenciesTests.swift apps/ios/BodyFlow/BodyFlowTests/DemoBodyFlowReadTests.swift apps/ios/BodyFlow/BodyFlowTests/Prompt13LaunchScenarioTests.swift apps/ios/BodyFlow/BodyFlowUITests/BodyFlowUITestSupport.swift
git commit -m "feat(ios): add deterministic prompt 13 snapshots"
```

---

### Task 10: Implement Debug Detection, Proposal Lifecycle And Idempotent Replay

**Files:**

- Create: `apps/ios/BodyFlow/BodyFlowTests/DemoRegistrationRepositoryTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/AppDependenciesTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppDependencies.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoBodyFlowFixtures.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoBodyFlowRepository.swift`

**Behaviors:**

- Text, labelled Photo and labelled Audio return complete pre-authored detected requests.
- The actor never parses input text, opens media or persists at detection.
- Propose creates a pending response; edit replaces the complete response; confirm/cancel accept only pending ids.
- Same key + same immutable payload returns the same result without applying twice.
- Same key + different payload throws `idempotencyConflict`.
- The same key reused for a different operation also throws `idempotencyConflict`.

- [ ] **Step 1: Write RED detection tests**

Pass very different bounded text strings and prove scenario/source, not nutritional interpretation, selects the draft. Photo/audio inputs contain labels only and no bytes/URLs.

- [ ] **Step 2: Run the focused detection tests and observe RED**

Expected RED: repository does not implement the detector.

- [ ] **Step 3: Implement minimal deterministic detection**

Return source-specific pre-authored requests. In Release, the unavailable adapter from Task 7 remains the only implementation.

- [ ] **Step 4: Write RED lifecycle/idempotency tests**

Cover meal and workout:

- confirm without a pending proposal fails;
- propose produces a pending response;
- edit returns and stores a complete replacement response;
- cancel removes only the open pending;
- confirm produces one pre-authored confirmation transition;
- repeated same attempt replays the first result;
- same key with changed payload conflicts;
- a proposal key reused for confirmation conflicts;
- expired/not-pending errors are typed.

- [ ] **Step 5: Run and observe the second RED**

Expected RED: missing lifecycle ledger/transitions.

- [ ] **Step 6: Implement GREEN with a replay ledger**

Key the ledger globally by `IdempotencyKey` and store operation, payload identity and typed result. Same key + same operation + same payload replays; any different operation or payload conflicts. At this checkpoint, make the cross-operation RED explicitly propose → confirm; the hydration cross-port case becomes available in Task 11. Do not calculate proposal nutrition or confirmed official values. Move only between full predefined snapshots.

- [ ] **Step 7: Refactor ledger helpers and run green**

Keep the actor isolated and `Sendable`; never expose ledger keys to telemetry or views.

- [ ] **Step 8: Wire detection/registration to the existing shared actor**

Modify Debug `AppDependencies.make` so `mealDetection` and `registration` receive the exact same actor already used by Today/History. In `AppDependenciesTests`, prove identity and behavior: create/confirm through `RegistrationProviding`, then read Today/History and receive the actor's predefined post-confirmation snapshots. Do not construct a second repository.

- [ ] **Step 9: Run dependency and repository suites green, then commit**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowTests/DemoRegistrationRepositoryTests -only-testing:BodyFlowTests/AppDependenciesTests test
git diff --check
git add apps/ios/BodyFlow/BodyFlow/App/AppDependencies.swift apps/ios/BodyFlow/BodyFlow/Core/Demo apps/ios/BodyFlow/BodyFlowTests/AppDependenciesTests.swift apps/ios/BodyFlow/BodyFlowTests/DemoRegistrationRepositoryTests.swift
git commit -m "feat(ios): add deterministic registration lifecycle"
```

---

### Task 11: Implement Debug Hydration, Weight And Routine Transitions

**Files:**

- Create: `apps/ios/BodyFlow/BodyFlowTests/DemoRoutineRepositoryTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/AppDependenciesTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppDependencies.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoBodyFlowFixtures.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoBodyFlowRepository.swift`

**Behaviors:**

- Hydration returns a complete predefined receipt/snapshot transition.
- Weight returns a clearly local, unsynchronized idempotent demonstration receipt and changes no official snapshot.
- Routine action targets the exact item/rule/scheduled occurrence, transitions to one complete snapshot and supports replay/conflict.
- Routine detail history accepts and returns opaque cursors without modification.

- [ ] **Step 1: Write RED hydration tests**

Use an old snapshot amount and a next snapshot amount deliberately unrelated to `old + command`. Assert the next complete response is returned unchanged and replay does not apply a second transition.

- [ ] **Step 2: Write RED weight tests**

Capture Today, Progress, History and block before/after the receipt. Assert equality, local-demo copy, same-attempt replay and changed-payload conflict.

- [ ] **Step 3: Write RED routine tests**

Cover exact occurrence identifiers, taken/skipped/snoozed, typed invalid transitions, conflict reload fixture, byte-for-byte pass-through of the opaque base64url cursor copied from the current routine-history contract fixture, and proposal-key reuse on hydration producing a cross-port idempotency conflict.

- [ ] **Step 4: Run `DemoRoutineRepositoryTests` and observe RED**

Expected RED: missing mutation implementations.

- [ ] **Step 5: Implement the predefined transitions**

Use the snooze validation policy from Task 4 before selecting an accepted snapshot. Do not create a clinical interpretation, dose recommendation, local adherence total or internal occurrence key.

- [ ] **Step 6: Refactor shared replay handling and run green**

Share replay mechanics with registration while keeping results typed per operation.

- [ ] **Step 7: Wire all remaining ports to the same actor**

Modify Debug `AppDependencies.make` so hydration and weight use the existing repository actor; routine continues to use that same instance but its `record` method now implements the GREEN behavior instead of the Task 9 unavailable stub. In `AppDependenciesTests`, prove identity across all new ports and behavior across capabilities: hydration changes the next complete Today snapshot, weight changes none, and routine action changes the next list/history snapshots. No second actor may be constructed.

- [ ] **Step 8: Run dependency and repository suites green, then commit**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowTests/DemoRoutineRepositoryTests -only-testing:BodyFlowTests/AppDependenciesTests test
git diff --check
git add apps/ios/BodyFlow/BodyFlow/App/AppDependencies.swift apps/ios/BodyFlow/BodyFlow/Core/Demo apps/ios/BodyFlow/BodyFlowTests/AppDependenciesTests.swift apps/ios/BodyFlow/BodyFlowTests/DemoRoutineRepositoryTests.swift
git commit -m "feat(ios): add deterministic routine recording transitions"
```

---

### Task 12: Replace The Today Scaffold With Official Snapshot Presentation

**Files:**

- Create: `apps/ios/BodyFlow/BodyFlowTests/TodayViewModelTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/TodayPresentationTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Today/TodayViewModel.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Today/TodayRootView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Today/TodayHeaderSection.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Today/TodayAttentionSection.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Today/TodayEnergySection.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Today/TodayProteinSection.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Today/TodayRecordsSection.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Today/TodayHydrationSection.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Today/TodayRoutineSection.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Today/TodayBlockCard.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift`
- Create: `apps/ios/BodyFlow/BodyFlowUITests/Prompt13TodayUITests.swift`

**Interfaces:**

- `@MainActor @Observable TodayViewModel` owns `FeatureReadState<TodaySnapshot>` and one cancellable load identity.
- Retry starts a provider read. `TodayRootView` observes the Today revision with `.task(id:)`; revision zero and every later revision each cause exactly one full refresh.
- Presentation formatters accept one received field at a time and never combine official fields.
- Stable ids include `today.header.local-date`, `today.header.protocol`, `today.header.updated-at`, `today.attention`, `today.pending`, `today.energy.remaining-food`, `today.energy.net-balance`, `today.completion.insufficient-data`, `today.protein`, `today.meals`, `today.workouts`, `today.hydration`, `today.routines`, `today.block` and `today.history`.

- [ ] **Step 1: Write RED model-state tests**

Cover load, empty, initial offline, offline with previous content, recoverable error with previous content, Retry, cancellation/replacement and unavailable. A late cancelled request must not publish. Through the same observable center owned by the shell, prove `.task(id: todayRevision)` runs one complete initial load, one relevant invalidation revision triggers exactly one additional complete provider reload without a local patch, an unrelated revision triggers none, and a newer Today revision cancels/supersedes the older load before publication.

- [ ] **Step 2: Run `TodayViewModelTests` and observe RED**

Expected RED: missing view model.

- [ ] **Step 3: Implement the minimal view model**

Read complete snapshots only. `load(revision:)` deduplicates an already active or completed revision while allowing an incomplete cancelled revision to be attempted again on a later appearance. On invalidation, transition to loading/stale presentation and fetch again; never patch a value while waiting. Check `Task.isCancelled`/`Task.checkCancellation()` and the captured revision/load identity immediately before every state publication.

- [ ] **Step 4: Write RED presentation tests**

Using the inconsistent fixture, assert literal food remaining and signed net balance. Add literal descriptor assertions for `targets.calories_kcal == 1_935`, `consumed.calories_kcal == 1_200`, `food_excess_kcal == 17`, `exercise_kcal == 419` and `daily_balance_status == "provisional"`; none may be derived from another field. Assert distinct labels/accessibility values:

- food remaining says exercise is excluded;
- net balance says exercise is included;
- local date, protocol and snapshot update time are rendered from the response;
- pending proposals and routine actions requiring attention appear before energy;
- `insufficient_data` produces `Dados insuficientes para fechar o dia`;
- nil target/block/hydration fields produce unavailable, not zero;
- confirmed meal rows preserve order and individual ids;
- `canonical_exact`/`product_label` map to confirmed reference;
- `llm_estimate`/`category_mismatch`/`protein_mismatch`/`composite_rejected` map to estimate;
- `user_kcal`/`user_correction` map to patient-provided;
- every unknown/nil provenance maps to “Origem não informada”.

- [ ] **Step 5: Run `TodayPresentationTests` and observe RED**

Expected RED: scaffold has no approved presentation descriptors.

- [ ] **Step 6: Implement Today sections and refactor responsive layout**

Use semantic tokens and `ViewThatFits`/vertical fallback at accessibility sizes. Do not animate official numbers when Reduce Motion is enabled. Status must have text/icon, never color only.

- [ ] **Step 7: Write and run focused UI RED tests**

Add:

- `testTodayShowsSnapshotHeaderAndAttentionBeforeEnergy`;
- `testTodaySeparatesFoodRemainingFromNetBalance`;
- `testTodayShowsIncompleteDayAsContent`;
- `testTodayPreservesTwoIndividualMealRows`;
- `testTodayOfflineContentShowsStaleBannerAndRetry`.

Expected RED: stable ids/labels absent before wiring.

- [ ] **Step 8: Wire Today into the shell and make UI tests green**

Create one long-lived `@State TodayViewModel` in `AppShellView.init(userID:dependencies:)`, outside `body`, and pass it plus the shell-owned invalidation center explicitly into `TodayRootView`. `TodayRootView` owns exactly one `.task(id: invalidationCenter.revision(for: .today))` that calls the model's complete-load entry point; do not add `onChange` or a second refresh observer. Do not store a response in `EnvironmentValues`.

- [ ] **Step 9: Run unit/UI green, refactor, and commit**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowTests/TodayViewModelTests -only-testing:BodyFlowTests/TodayPresentationTests test
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowUITests/Prompt13TodayUITests test
git diff --check
git add apps/ios/BodyFlow/BodyFlow/Features/Today apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift apps/ios/BodyFlow/BodyFlowTests/TodayViewModelTests.swift apps/ios/BodyFlow/BodyFlowTests/TodayPresentationTests.swift apps/ios/BodyFlow/BodyFlowUITests/Prompt13TodayUITests.swift
git commit -m "feat(ios): implement official today snapshot"
```

---

### Task 13: Implement Meal Detection, Pending Proposal, Edit, Confirm And Cancel

**Files:**

- Create: `apps/ios/BodyFlow/BodyFlowTests/MealRegistrationModelTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/RegistrationPresentationTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Register/RegisterRootView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Register/RegistrationSheet.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Register/MealRegistrationModel.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Register/MealCaptureSourceView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Register/MealTextDraftView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Register/MealDemonstrationSourceView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Register/MealProposalView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Register/MealProposalEditorView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Register/RegistrationOperationSummary.swift`
- Create: `apps/ios/BodyFlow/BodyFlowUITests/Prompt13RegistrationUITests.swift`

**Interfaces:**

- The model owns capture draft, current server-shaped pending proposal, mutation state and retained attempt.
- `RegistrationMutationAttempt` has typed `.propose`, `.edit`, `.confirm` and `.cancel` cases; `RegistrationMutationReceipt` has matching response cases. One heterogeneous `FeatureMutationState<RegistrationMutationAttempt, RegistrationMutationReceipt>` therefore retains the exact operation without type erasure or `Any`.
- Every initial form time comes from `TimeProviding`.
- The sheet owns an internal navigation stack; pending navigation does not enter a tab path.
- Stable ids use `registration.meal.source.text|photo|audio`, `registration.meal.detect`, `registration.proposal`, `registration.proposal.edit`, `registration.proposal.confirm`, `registration.proposal.cancel` and `registration.mutation.retry`.

- [ ] **Step 1: Write the first RED model tests for all capture sources**

Assert Text, Photo and Audio each call detection, then proposal, and never confirmation directly. For the local Text demonstration, assert `String.count` lengths 0 and 1,001 are rejected before the detector is called while lengths 1 and 1,000 are accepted. State in the test name that this is a Debug/preview/UI-test demonstration guard, not a present or future API request contract. Photo/audio tests assert no permission or media service dependency exists.

- [ ] **Step 2: Run the focused tests and observe RED**

Expected RED: missing model and capture-source state machine.

- [ ] **Step 3: Implement detection-to-proposal GREEN**

Validate the demonstration text at inclusive `String.count` length `1...1000` before calling detection, without trimming, parsing, encoding it into a presumed transport DTO or exposing the limit as an API contract. Label Photo/Audio as local demonstrations. Preserve the structured detected draft until proposal succeeds.

- [ ] **Step 4: Write RED lifecycle/retry tests**

Cover:

- default time from the fixed provider;
- edit sends only allowed fields and replaces the complete proposal;
- failed create/edit/confirm/cancel preserves draft or pending state;
- Retry reuses the exact attempt/key;
- payload change creates a new key;
- double submission is disabled;
- expired/not-pending discards only the invalid pending and offers a new proposal;
- create/edit/cancel signal Today only;
- confirm signals Today + History;
- no signal patches official values.
- mutation error/success sets a bounded `accessibilityFocusTarget` for the operation summary.
- a cancelled or superseded detection/mutation task cannot publish its late proposal, receipt, error or navigation.

Assert each operation produces the matching attempt/receipt enum case and Retry pattern-matches back to the original concrete `MutationAttempt`.

- [ ] **Step 5: Run and observe the lifecycle RED**

Expected RED: lifecycle, attempt retention or invalidation differs from the approved matrix.

- [ ] **Step 6: Implement lifecycle GREEN and refactor**

Move shared attempt construction into a small coordinator helper. Saving edit assigns the returned proposal wholesale. Confirmed state exposes no edit control.

- [ ] **Step 7: Write RED proposal-presentation tests**

Assert provider totals, item values, warnings and expiry are rendered literally. A pending proposal exposes no stable per-item provenance, so it must never display confirmed/estimated/patient-provided reference labels or infer provenance from the absence of a warning. The conservative mapping exists only for confirmed Today rows in Task 12.

- [ ] **Step 8: Write UI RED tests one journey at a time**

Add:

- `testTextMealReachesProposalBeforeConfirmation`;
- `testPhotoDemonstrationReachesProposalWithoutPermission`;
- `testAudioDemonstrationReachesProposalWithoutPermission`;
- `testPendingMealEditReplacesProposal`;
- `testMealMutationFailurePreservesPendingAndRetries`;
- `testConfirmedMealIsReadOnly`;
- `testUnavailableMealShowsVersionMessageWithoutSuccess`.

- [ ] **Step 9: Run presentation and UI tests and observe RED**

Run `RegistrationPresentationTests` and each new XCUI method separately. Expected RED: proposal descriptors, sheet controls, stable ids or error-once Retry behavior are absent.

- [ ] **Step 10: Implement the sheet views and accessibility focus**

Pass the shell-owned invalidation center explicitly into `RegistrationSheet` and its models. After errors/success, bind SwiftUI accessibility focus to the model's operation-summary target. Editor controls expose only approved fields; do not expose macros or totals. The `registration-error-once` Debug scenario fails the first immutable attempt and succeeds only when Retry reuses it. Release unavailable state contains no demo receipt.

- [ ] **Step 11: Run green, refactor previews later, and commit**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowTests/MealRegistrationModelTests -only-testing:BodyFlowTests/RegistrationPresentationTests test
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowUITests/Prompt13RegistrationUITests test
git diff --check
git add apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift apps/ios/BodyFlow/BodyFlow/Features/Register apps/ios/BodyFlow/BodyFlowTests/MealRegistrationModelTests.swift apps/ios/BodyFlow/BodyFlowTests/RegistrationPresentationTests.swift apps/ios/BodyFlow/BodyFlowUITests/Prompt13RegistrationUITests.swift
git commit -m "feat(ios): implement meal proposal workflow"
```

---

### Task 14: Implement Workout Proposal And Confirmation

**Files:**

- Create: `apps/ios/BodyFlow/BodyFlowTests/WorkoutRegistrationModelTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Register/WorkoutRegistrationModel.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Register/WorkoutRegistrationView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Register/WorkoutProposalView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Register/RegistrationSheet.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowUITests/Prompt13RegistrationUITests.swift`

**Behaviors:**

- Collect workout type, duration, intensity and performed time.
- Propose before confirmation.
- Display estimated calories only from the returned proposal.
- Support pending edit/cancel/confirm with the same attempt and invalidation rules as meal.
- Reuse the typed registration attempt/receipt enums; do not introduce `Any` or overwrite an attempt with a different generic payload.
- Confirmed workout is read-only.

- [ ] **Step 1: Write RED model tests**

Assert fixed-time default, proposal requirement, literal response calorie display, whole-response edit replacement, retained attempt on failure, the exact invalidation matrix, `.operationSummary` focus target after success or failure, and no late publication/navigation from a cancelled or superseded proposal/mutation task.

- [ ] **Step 2: Run `WorkoutRegistrationModelTests` and observe RED**

Expected RED: workout model does not exist.

- [ ] **Step 3: Implement minimal model GREEN**

Do not introduce a calorie estimator or depend on weight. Reuse only generic attempt/state helpers, not meal-specific presentation.

- [ ] **Step 4: Write focused UI RED**

Add `testWorkoutReachesProposalBeforeConfirmation`, `testWorkoutDisplaysProviderCalories`, `testConfirmedWorkoutIsReadOnly` and `testUnavailableWorkoutShowsNoSuccess`.

- [ ] **Step 5: Run the new UI methods and observe RED**

Expected RED: workout proposal controls, provider-calorie label and read-only destination do not exist.

- [ ] **Step 6: Implement UI GREEN**

Use stable ids `registration.workout.type`, `.duration`, `.intensity`, `.performed-at`, `.propose`, plus the shared pending controls. Bind `@AccessibilityFocusState` to the model's operation-summary target and clear the target after consumption. Keep all actions at least 44 points.

- [ ] **Step 7: Refactor, run green, and commit**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowTests/WorkoutRegistrationModelTests test
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowUITests/Prompt13RegistrationUITests test
git diff --check
git add apps/ios/BodyFlow/BodyFlow/Features/Register apps/ios/BodyFlow/BodyFlowTests/WorkoutRegistrationModelTests.swift apps/ios/BodyFlow/BodyFlowUITests/Prompt13RegistrationUITests.swift
git commit -m "feat(ios): implement workout proposal workflow"
```

---

### Task 15: Implement Hydration And Debug-Only Weight Operations

**Files:**

- Create: `apps/ios/BodyFlow/BodyFlowTests/HydrationWeightModelTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Register/HydrationRegistrationModel.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Register/HydrationRegistrationView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Register/WeightRegistrationModel.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Register/WeightRegistrationView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Register/RegistrationSheet.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowUITests/Prompt13RegistrationUITests.swift`

**Behaviors:**

- Hydration supports controlled quick values 250/500/750 ml plus custom input, with every command validated as an integer in the inclusive `1...5000` ml range, and an injected occurrence time.
- Success triggers only a Today revision and waits for a complete provider refresh.
- Weight accepts only the approved inclusive `30...300` kg app-domain range and returns only a Debug/test receipt labelled `Demonstração local; não sincronizado`.
- Weight changes no Today, Progress, History or block state.
- Release operations present `Indisponível nesta versão` and no success copy.

- [ ] **Step 1: Write RED hydration model tests**

Assert fixed time, quick/custom validation, one key per intention, same-attempt Retry, double-submit protection, exactly one Today revision, `.operationSummary` focus target after success/failure, and no late receipt/error/revision from a cancelled or superseded task. Add literal boundaries: `0` and `5001` ml are rejected without provider/invalidation calls; `1` and `5000` ml are accepted. Add an integration RED using the same `FeatureInvalidationCenter` plus the existing `TodayViewModel`: hydration emits only the revision, Today performs one provider reload through its `.task(id:)` owner, and the deliberately non-additive next snapshot is adopted whole. `HydrationRegistrationModel` must not receive `TodayProviding`.

- [ ] **Step 2: Run the hydration tests and observe RED**

Expected RED: missing model or a locally patched amount.

- [ ] **Step 3: Implement hydration GREEN**

Validate the exact inclusive integer `1...5000` ml range without clamping, submit the command, record Today invalidation, and let Today reload. Do not calculate percentage or remaining volume when a target is absent.

- [ ] **Step 4: Write RED weight tests**

Assert fixed recorded time, literal input bounds (`29.99` and `300.01` kg rejected; `30` and `300` kg accepted), receipt label, idempotent replay, payload-conflict behavior, no invalidation, Release unavailable state, `.operationSummary` focus target after success/failure, and no late receipt/error from a cancelled or superseded task.

- [ ] **Step 5: Run weight tests and observe RED**

Expected RED: missing model/receipt handling.

- [ ] **Step 6: Implement weight GREEN**

Enforce the reused inclusive `30...300` kg app-domain limit without clamping. Keep `WeightRecording` protocol-only. Do not add `Codable`, an endpoint path, `APIRequest` or a claimed synchronization flag.

- [ ] **Step 7: Write focused UI RED**

Add:

- `testHydrationQuickAndCustomFlowsUseCompleteRefresh`;
- `testHydrationAndWeightShowExactBoundaryValidation`;
- `testWeightReceiptIsClearlyLocal`;
- `testUnavailableHydrationAndWeightNeverShowSuccess`.

Use ids `registration.hydration.quick.250|500|750`, `.custom`, `.occurred-at`, `.submit`, and `registration.weight.value`, `.recorded-at`, `.submit`, `.demo-receipt`.

- [ ] **Step 8: Run the new UI methods and observe RED**

Expected RED: operational controls, local-receipt copy or unavailable state is absent.

- [ ] **Step 9: Implement UI GREEN**

Use the existing sheet host and pass the same shell-owned invalidation center explicitly. Bind `@AccessibilityFocusState` to the bounded operation-summary target after success/failure and clear the target after consumption.

- [ ] **Step 10: Run green, refactor, and commit**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowTests/HydrationWeightModelTests test
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowUITests/Prompt13RegistrationUITests test
git diff --check
git add apps/ios/BodyFlow/BodyFlow/Features/Register apps/ios/BodyFlow/BodyFlowTests/HydrationWeightModelTests.swift apps/ios/BodyFlow/BodyFlowUITests/Prompt13RegistrationUITests.swift
git commit -m "feat(ios): add hydration and local weight flows"
```

---

### Task 16: Implement Supplement And Medication Lists, Actions And Own Histories

**Files:**

- Create: `apps/ios/BodyFlow/BodyFlowTests/RoutineViewModelTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/RoutineActionModelTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/RoutinePresentationTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Routine/RoutineListViewModel.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Routine/RoutineListView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Routine/RoutineDetailViewModel.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Routine/RoutineDetailView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Routine/RoutineHistoryViewModel.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Routine/RoutineHistoryView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Routine/RoutineActionModel.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Routine/RoutineActionSheet.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Routine/RoutineSnoozeView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Today/TodayRoutineSection.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppRouter.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift`
- Create: `apps/ios/BodyFlow/BodyFlowUITests/Prompt13RoutineUITests.swift`

**Interfaces:**

- Typed routes carry only `RoutineItemKind`, item id and destination kind.
- `RoutineDetailViewModel` resolves `itemID` from the already-loaded list snapshot. When entered from Today before a list exists, it may call only `list(kind:includeArchived:false)` and select the returned row; no detail capability, path or `APIRequest` is created.
- `RoutineListView` and `RoutineHistoryView` each own exactly one `.task(id:)` for their matching observed revision. Their models deduplicate active/completed revisions and publish at most one complete list or item-history response per revision; a cancelled/superseded load cannot publish. Detail follows the refreshed list snapshot and never owns a detail reload.
- Routine-history load-more exists only when the response supplies a non-nil opaque `next_cursor`.
- The action model creates exact occurrence commands and retains an idempotent attempt for Retry.

- [ ] **Step 1: Write RED list/detail/history tests**

Cover loaded/empty/offline/error/unavailable state, include-archived value, response order, and append of a next page only after passing the exact cursor from the first response. Nil cursor hides load-more. A list spy must prove detail resolution uses the loaded snapshot with no call, or one documented list call when entered from Today; the protocol has no detail method. For matching list/history revisions, prove `.task(id:)` performs exactly one complete reload per revision, ignores unrelated revisions, cancels a superseded task and suppresses its late publication.

- [ ] **Step 2: Run `RoutineViewModelTests` and observe RED**

Expected RED: missing models and cursor handling.

- [ ] **Step 3: Implement list/detail/history GREEN**

Keep supplement and medication histories separate by kind/item id. Never add routine rows to main History. The detail model selects by id from the list snapshot and never presumes another endpoint.

- [ ] **Step 4: Write RED action tests**

Cover:

- default `occurredAt` from `TimeProviding`;
- taken/skipped omit `snoozedUntil`;
- snoozed requires it;
- 15/30/60 presets;
- custom later time on same patient-local date;
- crossing-date preset/custom unavailable;
- recoverable failure retains attempt;
- conflict reloads the exact documented list and matching item-history reads;
- after conflict, detail re-resolves `itemID` from the refreshed list snapshot,
  with no detail provider, path or reload call;
- success invalidates Today + exact list + matching item history;
- each exact revision triggers one complete list/history reload and carries no optimistic values;
- success/failure sets `.operationSummary` focus target;
- a cancelled or superseded list/history/action task cannot publish a late value, cursor append, receipt, error or navigation;
- Release unavailable produces no simulated occurrence.

- [ ] **Step 5: Run `RoutineActionModelTests` and observe RED**

Expected RED: action model or invalidation behavior missing.

- [ ] **Step 6: Implement action GREEN and refactor**

The provider remains authoritative. On conflict, advance only the matching list and item-history revisions; their `.task(id:)` owners reload those complete responses, and detail then resolves `itemID` from the refreshed list. On success, apply the approved Today/list/item-history invalidation matrix. Never create or call a detail provider, and do not apply optimistic status/counters while refresh is pending.

- [ ] **Step 7: Write RED routine-presentation tests**

Assert schedules, textual status and exact occurrence rows come only from response values; empty and unavailable differ; no recommendation, dose interpretation, inferred prescription or schedule editor descriptor exists.

- [ ] **Step 8: Run `RoutinePresentationTests` and observe RED**

Expected RED: approved presentation descriptors do not exist.

- [ ] **Step 9: Write UI RED scenarios**

Add:

- `testSupplementTakenUsesExactOccurrence`;
- `testMedicationSkippedUsesExactOccurrence`;
- `testSnoozeOffers15_30_60AndCustom`;
- `testCrossingDateSnoozeIsUnavailable`;
- `testRoutineHistoryLoadMoreAppendsNextPage`;
- `testUnavailableRoutineActionShowsNoSuccess`.

Use ids `routine.action.taken|snoozed|skipped`, `routine.snooze.15|30|60|custom`, `routine.snooze.custom-time`, `routine.action.submit`, `routine.history` and `routine.history.load-more`.

- [ ] **Step 10: Run each new UI method and observe RED**

Expected RED: list/detail/action/history views or stable ids are absent. Opaque cursor equality remains a unit-spy assertion; XCUI verifies only that the next returned rows append and load-more disappears at nil.

- [ ] **Step 11: Implement UI/navigation GREEN**

Keep the existing tab stacks. Install exactly one `.task(id:)` owner for the matching list revision and one for the visible item-history revision; both call complete-load methods and rely on cancellation/load identity before publication. Detail is selected again from the refreshed list snapshot. Use an item-driven action sheet, bind `@AccessibilityFocusState` to the model target, and clear it after consumption. Add no dose interpretation, prescription inference or schedule editor.

- [ ] **Step 12: Run green and commit**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowTests/RoutineViewModelTests -only-testing:BodyFlowTests/RoutineActionModelTests -only-testing:BodyFlowTests/RoutinePresentationTests test
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowUITests/Prompt13RoutineUITests test
git diff --check
git add apps/ios/BodyFlow/BodyFlow/Features/Routine apps/ios/BodyFlow/BodyFlow/Features/Today/TodayRoutineSection.swift apps/ios/BodyFlow/BodyFlow/App/AppRouter.swift apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift apps/ios/BodyFlow/BodyFlowTests/RoutineViewModelTests.swift apps/ios/BodyFlow/BodyFlowTests/RoutineActionModelTests.swift apps/ios/BodyFlow/BodyFlowTests/RoutinePresentationTests.swift apps/ios/BodyFlow/BodyFlowUITests/Prompt13RoutineUITests.swift
git commit -m "feat(ios): add routine occurrence workflows"
```

---

### Task 17: Replace The Plan Scaffold With Stable Contract Fields

**Files:**

- Create: `apps/ios/BodyFlow/BodyFlowTests/PlanViewModelTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/PlanPresentationTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Plan/PlanViewModel.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Plan/PlanRootView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Plan/PlanComponents.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Plan/PlanDetailView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppRouter.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift`
- Create: `apps/ios/BodyFlow/BodyFlowUITests/Prompt13PlanProgressHistoryUITests.swift`

**Behaviors:**

- Render training type, days/week, equipment, generated/valid-until dates, version and notes.
- Render only nutrition prescription type, dates, version and notes.
- Keep opaque nutrition payload unrendered and uninterpreted.
- Distinguish no active plan from unavailable.
- Remove scaffold-only planned/completed counters.

- [ ] **Step 1: Write RED view-model tests**

Cover loaded, feature empty, offline/error with previous value, Retry, cancellation and unavailable.

- [ ] **Step 2: Write RED presentation tests**

Assert stable fields are present and the scaffold labels `Planejadas`/`Concluídas` are absent. Use an opaque payload with misleading keys and prove they never become UI rows.

- [ ] **Step 3: Run unit tests and observe RED**

Expected RED: scaffold presentation and missing model.

- [ ] **Step 4: Implement model/root/detail GREEN**

The typed route carries no mutable plan snapshot. A Plan detail may reload the current Plan capability; it must not derive values from Today/History.

- [ ] **Step 5: Write UI RED**

Add `testPlanShowsOnlyStableContractFields`, `testPlanEmptyDiffersFromUnavailable` and verify `screen.plan.detail`.

- [ ] **Step 6: Run the Plan UI class and observe RED**

Expected RED: stable contract rows, distinct state copy or detail navigation is missing.

- [ ] **Step 7: Implement navigation GREEN**

Register the typed route in the existing Plan stack and keep mutable snapshots out of the route.

- [ ] **Step 8: Refactor responsive presentation, run green, and commit**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowTests/PlanViewModelTests -only-testing:BodyFlowTests/PlanPresentationTests test
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowUITests/Prompt13PlanProgressHistoryUITests test
git diff --check
git add apps/ios/BodyFlow/BodyFlow/Features/Plan apps/ios/BodyFlow/BodyFlow/App/AppRouter.swift apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift apps/ios/BodyFlow/BodyFlowTests/PlanViewModelTests.swift apps/ios/BodyFlow/BodyFlowTests/PlanPresentationTests.swift apps/ios/BodyFlow/BodyFlowUITests/Prompt13PlanProgressHistoryUITests.swift
git commit -m "feat(ios): implement stable plan presentation"
```

---

### Task 18: Replace The Progress Scaffold And Add The Today-Sourced 7,700 Block

**Files:**

- Create: `apps/ios/BodyFlow/BodyFlowTests/ProgressViewModelTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/ProgressPresentationTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/Block7700PresentationTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/BodyFlowTestFixtures.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Progress/ProgressViewModel.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Progress/Block7700ViewModel.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Progress/ProgressRootView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Progress/ProgressComponents.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Progress/Block7700DetailView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppRouter.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowUITests/Prompt13PlanProgressHistoryUITests.swift`

**Behaviors:**

- Render response-supplied XP, level, current/longest streak, completed blocks, weight, body-fat, badges, last active date, reevaluation and update time.
- Block detail reads only `TodayResponse.data.block7700`.
- Null block remains unavailable; no zero ring or reconstructed percentage.

- [ ] **Step 1: Write RED Progress state/presentation tests**

Cover all read states and literal optional values. Missing weight/body-fat does not become zero. A cancelled or superseded Progress load cannot publish a late snapshot/error.

- [ ] **Step 2: Write the critical RED block-source test**

Supply a Progress `deficit_block` fixture that conflicts with Today `block_7700`. Build the block model only with a `TodayProviding` spy and assert the detail descriptor equals Today target/current/percentage/completed/credited/source exactly. The divergent Progress fixture is rendered only by `ProgressViewModel`; it is never injected into the block model. Add a delayed-provider RED proving a cancelled or superseded block load cannot publish a late block/error.

```swift
@Test("block detail uses only the Today block")
@MainActor
func blockUsesTodayOnly() async {
    let provider = TodayProviderSpy(
        response: BodyFlowTestFixtures.todayResponseWithBlock
    )
    let model = Block7700ViewModel(today: provider)

    await model.load()

    #expect(
        model.descriptor?.percentage
            == BodyFlowTestFixtures.todayBlock.percentage
    )
    #expect(
        model.descriptor?.completedBlocks
            == BodyFlowTestFixtures.todayBlock.completedBlocks
    )
}
```

The production initializer has no `ProgressProviding` parameter.

- [ ] **Step 3: Run focused tests and observe RED**

Expected RED: missing model/descriptor or scaffold reconstruction.

- [ ] **Step 4: Implement Progress and block GREEN**

Format, never calculate. Use a typed block route that loads Today, not Progress.

- [ ] **Step 5: Write UI RED**

Add `testProgressShowsReceivedValues`, `testBlockDetailUsesTodaySnapshot`, and `testUnavailableBlockDoesNotShowZero`.

- [ ] **Step 6: Run the new UI methods and observe RED**

Expected RED: Progress values or Today-only block destination is absent.

- [ ] **Step 7: Implement UI GREEN**

Wire the block route only to `TodayProviding`; keep `ProgressProviding` out of the initializer and destination.

- [ ] **Step 8: Refactor, run green, and commit**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowTests/ProgressViewModelTests -only-testing:BodyFlowTests/ProgressPresentationTests -only-testing:BodyFlowTests/Block7700PresentationTests test
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowUITests/Prompt13PlanProgressHistoryUITests test
git diff --check
git add apps/ios/BodyFlow/BodyFlow/Features/Progress apps/ios/BodyFlow/BodyFlow/App/AppRouter.swift apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift apps/ios/BodyFlow/BodyFlowTests/ProgressViewModelTests.swift apps/ios/BodyFlow/BodyFlowTests/ProgressPresentationTests.swift apps/ios/BodyFlow/BodyFlowTests/Block7700PresentationTests.swift apps/ios/BodyFlow/BodyFlowTests/BodyFlowTestFixtures.swift apps/ios/BodyFlow/BodyFlowUITests/Prompt13PlanProgressHistoryUITests.swift
git commit -m "feat(ios): implement progress and persisted block views"
```

---

### Task 19: Implement First-Page Main History And Snapshot-Only Row Detail

**Files:**

- Create: `apps/ios/BodyFlow/BodyFlowTests/HistoryViewModelTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/HistoryPresentationTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/AppRouterTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/History/HistoryViewModel.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/History/HistoryFeatureCoordinator.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/History/MainHistoryView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/History/HistoryMealLogRowView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/History/HistoryMealLogDetailView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/History/HistoryWorkoutDetailView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Today/TodayRootView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppRouter.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowUITests/Prompt13PlanProgressHistoryUITests.swift`

**Required ownership design:**

`AppRootView` passes the already-created immutable dependencies explicitly into `AppShellView`. `AppShellView` creates one long-lived `@State HistoryViewModel` from `dependencies.history` and registers these lightweight route cases:

```swift
case mainHistory
case historyMealLog(rowID: String)
case historyWorkout(logID: String)
```

`MainHistoryView` receives that same model and the shell-owned invalidation
center. It owns exactly one
`.task(id: invalidationCenter.revision(for: .history))`; the model deduplicates
active/completed revisions, revision zero and each later History revision
publish at most one bounded complete `.firstPage` response, and a new revision
cancels/supersedes the prior load before it can publish. A detail route resolves
synchronously:

```swift
func mealLogRow(id: String) -> HistoryMealLogRow? {
    currentSnapshot?.meals.first { $0.id == id }
}

private var currentSnapshot: HistorySnapshot? {
    switch state {
    case let .loaded(response):
        response
    case let .offline(previousValue?):
        previousValue
    case let .failed(previousValue?, _):
        previousValue
    default:
        nil
    }
}
```

The detail destination receives the returned immutable row. It must not construct another model, call `load()`, call `HistoryProviding`, or accept a provider. The same rule applies to workout detail. A retained offline/failed snapshot remains eligible because it is already loaded. If the row no longer exists in the held snapshot, show a bounded unavailable-detail state without fetching.

- [ ] **Step 1: Write RED first-page load tests**

Use a spy that records every query. Assert revision-zero `.task(id:)` calls exactly `[.firstPage]`, Retry adds one more `.firstPage`, and no API exists for load more. Cover initial offline/error, stale offline/error with previous snapshot, unavailable, cancellation/replacement and Retry. After a confirmation increments the History revision, prove exactly one new `.firstPage` read occurs and no local row patch is applied; an unrelated revision performs no read, and a newer History revision cancels the older load so its late result/error cannot publish.

- [ ] **Step 2: Write RED row-preservation and empty-state tests**

Assert:

- same-time/same-type meal rows remain separate and ordered;
- one empty section does not create global empty;
- both arrays empty does create global empty;
- presentation has exactly Meal records and Workouts;
- no weight, hydration, supplement or medication section exists;
- no `meal_id` or aggregate detail is synthesized.

- [ ] **Step 3: Write the critical RED snapshot-detail test**

```swift
@Test("opening meal log detail does not fetch again")
@MainActor
func mealDetailUsesLoadedSnapshot() async throws {
    let spy = HistoryProviderSpy(
        response: BodyFlowTestFixtures.historyResponseWithMatchingRows
    )
    let model = HistoryViewModel(provider: spy)

    await model.load()
    let row = try #require(model.mealLogRow(id: "fixture-meal-row-1"))

    #expect(row.id == "fixture-meal-row-1")
    #expect(await spy.queries == [.firstPage])
}
```

Also resolve a second same-time row and assert it returns different individual content while the call count remains one.
Repeat the lookup while state contains the same snapshot as `offline(previousValue:)`; the row remains available and the call count stays one.
Repeat for `failed(previousValue:error:)` and for a workout detail; every lookup must preserve `spy.queries == [.firstPage]`.

- [ ] **Step 4: Run History unit tests and observe RED**

Expected RED: missing model/snapshot lookup or a design that fetches detail.

- [ ] **Step 5: Implement model and presentation GREEN**

Never sort, merge or group the arrays. Decode pagination metadata but expose no next-page command.

- [ ] **Step 6: Write route ownership RED tests**

Create a testable `@MainActor HistoryFeatureCoordinator` initialized with the long-lived `HistoryViewModel`. Assert all five tab paths remain independent, routes carry only ids, and coordinator resolution returns the individual row from `currentSnapshot` while the provider spy remains at one query. A route must not carry `HistoryResponse`, `HistorySnapshot` or `HistoryMealLogRow`.

- [ ] **Step 7: Implement shell ownership and typed destinations**

Keep `.mainHistory` on the Today stack. `AppShellView` owns the model/coordinator as `@State` initialized outside `body`; `MainHistoryView` has exactly one `.task(id: invalidationCenter.revision(for: .history))` complete-load owner and no competing `onChange` observer. The handler for meal/workout detail asks that coordinator to read the visible loaded/stale snapshot only. Delete/replace the obsolete generic scaffold detail route only after all call sites and existing router tests are green.

- [ ] **Step 8: Write UI RED journeys**

Add:

- `testHistoryKeepsMatchingMealRowsSeparate`;
- `testIndividualMealLogDetailShowsOnlySelectedRow`;
- `testHistoryHasOnlyMealsAndWorkouts`;
- `testHistoryHasNoLoadMore`;
- `testHistoryGlobalEmptyRequiresBothSectionsEmpty`.

Use ids `screen.history`, `history.meals`, `history.meal.<row-id>`, `history.workouts`, `history.workout.<id>` and `history.empty`. Deliberately do not create `history.load-more`.

- [ ] **Step 9: Run each new UI method and observe RED**

Expected RED: sections, individual row destination, empty semantics or absence of load-more differs from the contract. The exact `.firstPage` query count remains a Swift Testing spy assertion and is not exposed through UI instrumentation.

- [ ] **Step 10: Implement UI GREEN**

The meal detail title/copy must say “Registro de alimento” or equivalent singular row language, not “Refeição completa”. It is read-only.

- [ ] **Step 11: Refactor, run green, and commit**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowTests/HistoryViewModelTests -only-testing:BodyFlowTests/HistoryPresentationTests -only-testing:BodyFlowTests/AppRouterTests test
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowUITests/Prompt13PlanProgressHistoryUITests test
git diff --check
git add apps/ios/BodyFlow/BodyFlow/Features/History apps/ios/BodyFlow/BodyFlow/Features/Today/TodayRootView.swift apps/ios/BodyFlow/BodyFlow/App/AppRouter.swift apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift apps/ios/BodyFlow/BodyFlowTests/HistoryViewModelTests.swift apps/ios/BodyFlow/BodyFlowTests/HistoryPresentationTests.swift apps/ios/BodyFlow/BodyFlowTests/AppRouterTests.swift apps/ios/BodyFlow/BodyFlowUITests/Prompt13PlanProgressHistoryUITests.swift
git commit -m "feat(ios): add bounded individual-row history"
```

---

### Task 20: Add Debug Previews, Bounded Telemetry And Accessibility Verification

**Files:**

- Create: `apps/ios/BodyFlow/BodyFlowTests/Prompt13TelemetryTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Core/Telemetry/TelemetryClient.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/PreviewSupport/Prompt13PreviewSupport.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowUITests/BodyFlowUITestSupport.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowUITests/Prompt13TodayUITests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowUITests/Prompt13RegistrationUITests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowUITests/Prompt13RoutineUITests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowUITests/Prompt13PlanProgressHistoryUITests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowUITests/Prompt13AccessibilityUITests.swift`

- [ ] **Step 1: Write RED telemetry tests**

Allow only bounded screen id, registration kind, capture-source enum, outcome, bounded error category and `calculation_version` metadata. For `calculation_version`, add literal REDs accepting one ASCII character and exactly 64 ASCII characters from `[A-Za-z0-9._:-]`; omit empty, 65-character, whitespace-containing, slash-containing and non-ASCII values. Assert invalid values are neither truncated nor normalized into an accepted value. Reject or omit meal text/food names, media data, weight/body-fat, routine names/doses, raw responses, user ids and idempotency keys.

- [ ] **Step 2: Run `Prompt13TelemetryTests` and observe RED**

Expected RED: controlled Prompt 13 event vocabulary is missing.

- [ ] **Step 3: Implement controlled telemetry vocabulary**

Emit `calculation_version` only when its complete value has `1...64` ASCII characters all matching `[A-Za-z0-9._:-]`; otherwise omit the key without truncation, normalization or substitution. This mapper must not mutate the official Today snapshot. Do not log payload descriptions or raw errors.

- [ ] **Step 4: Run telemetry and Release-boundary unit suites green**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowTests/Prompt13TelemetryTests -only-testing:BodyFlowTests/Prompt13LaunchScenarioTests -only-testing:BodyFlowTests/AppDependenciesTests test
```

- [ ] **Step 5: Add Debug-only preview matrices**

Provide deterministic previews for loaded, loading, empty, offline, error, incomplete, unavailable, Dark Mode and accessibility XXXL. Cover Text/Photo/Audio proposal, edit, workout proposal, weight receipt, hydration, routine snooze/history, Plan, Progress/block and History.

- [ ] **Step 6: Add cross-feature acceptance UI tests**

Cover:

- all five tabs and independent navigation after deep feature use;
- Retry from initial and stale offline/error states;
- Dynamic Type accessibility XXXL without clipped labels or unreachable controls;
- Dark Mode launch and representative screenshots for manual semantic-color inspection;
- the Debug-only `--ui-testing-prompt13-reduce-motion` policy path;
- stable 44-point interactive targets;
- visible error/success summaries after the model's focus-target tests have passed.

These aggregate behaviors already introduced test-first in their owning feature tasks. They are acceptance checks, not permission to make an untested cross-feature rewrite here.

Refactor `BodyFlowUITestSupport.captureEvidence(named:)` so each owning journey supplies one of the 13 exact approved `.png` names and the attachment uses `.keepAlways`; attach the accessibility hierarchy with a distinct `.txt` name.

- [ ] **Step 7: Run the cross-feature checks**

Use `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` for Dynamic Type and `-AppleInterfaceStyle Dark` for Dark Mode. Use only the Debug scenario flag defined in Task 9 for Reduce Motion; do not rely on an ambiguous simulator default.

XCUI does not prove semantic color token use, VoiceOver focus movement or absence of motion from a static screenshot. Verify token/policy/focus state in unit tests and record manual simulator/accessibility-tree inspection. If an acceptance check fails, add a focused RED regression to the owning suite, observe it, make the smallest GREEN fix, rerun that suite, and create a separate Conventional Commit before continuing.

- [ ] **Step 8: Run all Prompt 13 UI classes green**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowUITests/Prompt13TodayUITests -only-testing:BodyFlowUITests/Prompt13RegistrationUITests -only-testing:BodyFlowUITests/Prompt13RoutineUITests -only-testing:BodyFlowUITests/Prompt13PlanProgressHistoryUITests -only-testing:BodyFlowUITests/Prompt13AccessibilityUITests test
```

- [ ] **Step 9: Refactor only preview/test support, rerun Release build, and commit**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -configuration Release -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO build
git diff --check
git add apps/ios/BodyFlow/BodyFlow/Core/Telemetry/TelemetryClient.swift apps/ios/BodyFlow/BodyFlow/Features/PreviewSupport apps/ios/BodyFlow/BodyFlowTests/Prompt13TelemetryTests.swift apps/ios/BodyFlow/BodyFlowUITests/BodyFlowUITestSupport.swift apps/ios/BodyFlow/BodyFlowUITests/Prompt13TodayUITests.swift apps/ios/BodyFlow/BodyFlowUITests/Prompt13RegistrationUITests.swift apps/ios/BodyFlow/BodyFlowUITests/Prompt13RoutineUITests.swift apps/ios/BodyFlow/BodyFlowUITests/Prompt13PlanProgressHistoryUITests.swift apps/ios/BodyFlow/BodyFlowUITests/Prompt13AccessibilityUITests.swift
git commit -m "test(ios): cover prompt 13 runtime and accessibility"
```

---

### Task 21: Run The Complete Local Gate And Capture Evidence

**Files:**

- Create: `docs/superpowers/evidence/2026-07-29-bodyflow-ios-today-records-progress/README.md`
- Create: curated PNG evidence in that same directory.
- Modify application/test files only if a newly observed defect first receives a focused RED regression test and then a GREEN fix in its own additional Conventional Commit.

**Rule:** Do not make an untested app-code fix inside the evidence commit.

- [ ] **Step 1: Verify branch, baseline and static absence constraints**

```bash
pwd
uname -s
git branch --show-current
git status --short
git diff --check codex/bodyflow-ios-auth-onboarding-v1...HEAD
xcodebuild -version
xcrun simctl list devices available
```

Expected:

- `/Users/eduardohenrique/Developer/bodyflow`;
- `Darwin`;
- `codex/bodyflow-ios-today-records-progress-v1`;
- clean worktree before evidence generation;
- Xcode 26.6;
- available iPhone 17 Pro on iOS 26.5 with id `27291590-659D-4A29-8F45-CA5CA2D154F9`.

Run scoped reviews:

```bash
rg -n "mealID|meal_id|nextBefore|next_before|history\\.load-more" apps/ios/BodyFlow/BodyFlow/Core/History apps/ios/BodyFlow/BodyFlow/Features/History
rg -n "APIRequest|https?://|Supabase|WhatsApp|whatsapp" apps/ios/BodyFlow/BodyFlow/Core/Today apps/ios/BodyFlow/BodyFlow/Core/Registration apps/ios/BodyFlow/BodyFlow/Core/Routine apps/ios/BodyFlow/BodyFlow/Core/Plan apps/ios/BodyFlow/BodyFlow/Core/Progress apps/ios/BodyFlow/BodyFlow/Core/History
rg -n "Date\\(\\)" apps/ios/BodyFlow/BodyFlow/Features/Today apps/ios/BodyFlow/BodyFlow/Features/Register apps/ios/BodyFlow/BodyFlow/Features/Routine
```

Expected:

- review every match and confirm there is no production property, fixture field, cursor derivation or main-History load-more behavior; a bounded source comment naming the forbidden contract gap is not runtime behavior;
- no Prompt 13 route/client/live-service additions;
- no direct feature clock reads;
- routine's documented `next_cursor` remains allowed and is reviewed separately as opaque pass-through.

- [ ] **Step 2: Run the complete unit and UI suite into a fresh result bundle**

```bash
BODYFLOW_GATE_ROOT="$(mktemp -d /tmp/bodyflow-prompt13-gate.XXXXXX)"
BODYFLOW_RESULT_BUNDLE="$BODYFLOW_GATE_ROOT/BodyFlowPrompt13.xcresult"
BODYFLOW_DEBUG_ROOT="$BODYFLOW_GATE_ROOT/debug"
BODYFLOW_RELEASE_ROOT="$BODYFLOW_GATE_ROOT/release"
BODYFLOW_RUN_ROOT="$BODYFLOW_GATE_ROOT/run"
BODYFLOW_ATTACHMENT_ROOT="$BODYFLOW_GATE_ROOT/attachments"
mkdir -p "$BODYFLOW_DEBUG_ROOT" "$BODYFLOW_RELEASE_ROOT" "$BODYFLOW_RUN_ROOT" "$BODYFLOW_ATTACHMENT_ROOT"

xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -resultBundlePath "$BODYFLOW_RESULT_BUNDLE" \
  test

xcrun xcresulttool get test-results summary \
  --path "$BODYFLOW_RESULT_BUNDLE"
```

Run Steps 2–7 in the same persistent PTY so these task-specific variables remain defined. If execution is interrupted or a tool must open another shell, copy the literal `BODYFLOW_GATE_ROOT` returned above into that shell and redeclare all derived paths before continuing; never assume variables crossed tool sessions. The unique root makes every path fresh without deleting or overwriting earlier results. Record the literal paths in the README.

Expected: all inherited and Prompt 13 unit/UI tests pass with zero failures and zero skips. Record the actual bundle path, logical-test count, execution count, UI-test count and duration; do not guess counts in advance.

- [ ] **Step 3: Run fresh Debug and Release builds**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -derivedDataPath "$BODYFLOW_DEBUG_ROOT" \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -configuration Release \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$BODYFLOW_RELEASE_ROOT" \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -derivedDataPath "$BODYFLOW_RUN_ROOT" \
  build
```

Expected: `** BUILD SUCCEEDED **` for the unsigned Debug/Release compile gates and the separately signed Simulator Debug runtime build. Release must compile without Debug fixture/repository symbols. The unsigned products are never used as runtime evidence.

- [ ] **Step 4: Boot, install and launch the Debug app**

```bash
xcrun simctl list devices available
xcrun simctl bootstatus 27291590-659D-4A29-8F45-CA5CA2D154F9 -b
xcrun simctl install 27291590-659D-4A29-8F45-CA5CA2D154F9 "$BODYFLOW_RUN_ROOT/Build/Products/Debug-iphonesimulator/BodyFlow.app"
xcrun simctl launch 27291590-659D-4A29-8F45-CA5CA2D154F9 com.bodyflow.app --ui-testing --ui-testing-prompt13-loaded
```

If the device list shows `Shutdown`, run `xcrun simctl boot 27291590-659D-4A29-8F45-CA5CA2D154F9` before `bootstatus`. If it is already `Booted`, do not issue a failing duplicate boot command.

Expected: the app remains running on the five-tab shell without crash.

- [ ] **Step 5: Inspect every approved flow visually**

Manually verify:

- Today hierarchy, literal energy semantics, incomplete day, provenance, hydration, occurrences and block;
- meal Text/Photo/Audio proposal, edit, Retry, confirm and cancel;
- workout proposal/edit/confirm/cancel;
- local weight receipt and hydration;
- supplement/medication list, detail, exact actions, snooze, own cursor history;
- Plan stable fields only;
- Progress and Today-sourced block;
- main History with two sections, separate same-time rows, individual row detail, no second page;
- loading, empty, offline, error, Retry and unavailable copy;
- all five tabs still open and retain independent stacks;
- no crash, clipping, misleading success or unexpected permission dialog.

- [ ] **Step 6: Inspect accessibility variants**

Repeat the representative screens in:

- Light and Dark Mode;
- default Dynamic Type and accessibility XXXL;
- Reduce Motion enabled.

Use the exact simulator appearance/content-size commands:

```bash
xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 appearance dark
xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 content_size accessibility-extra-extra-extra-large
xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 appearance light
xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 content_size large
```

Use `--ui-testing-prompt13-reduce-motion` for the deterministic motion-policy path. Inspect the XCUI accessibility hierarchy for visible labels, values, stable ids, focus summaries and reachable 44-point controls. Record manual observation for VoiceOver focus, semantic colors and motion; a screenshot alone does not prove those behaviors. Restore Light Mode, Large content size and the normal launch scenario afterward.

- [ ] **Step 7: Capture curated synthetic evidence**

Create:

- `01-today.png`
- `02-meal-proposal-edit.png`
- `03-individual-meal-log-detail.png`
- `04-workout-proposal.png`
- `05-hydration-routine.png`
- `06-plan.png`
- `07-progress-block.png`
- `08-main-history.png`
- `09-offline-error-retry.png`
- `10-dark-mode.png`
- `11-accessibility-xxxl.png`
- `12-reduce-motion.png`
- `13-final-simulator.png`

Before the full run, each owning UI journey must set `XCTAttachment.name` to the exact approved PNG filename below and attach its accessibility hierarchy with a distinct `.txt` name. Export all attachments first:

```bash
BODYFLOW_EVIDENCE_ROOT="/Users/eduardohenrique/Developer/bodyflow/docs/superpowers/evidence/2026-07-29-bodyflow-ios-today-records-progress"
mkdir -p "$BODYFLOW_EVIDENCE_ROOT"
xcrun xcresulttool export attachments \
  --path "$BODYFLOW_RESULT_BUNDLE" \
  --output-path "$BODYFLOW_ATTACHMENT_ROOT"
```

Use this reproducible source mapping when curating the root-level PNGs:

| Evidence | Scenario/journey |
|---|---|
| `01-today.png` | loaded Today |
| `02-meal-proposal-edit.png` | Text meal pending edit |
| `03-individual-meal-log-detail.png` | first individual History meal row |
| `04-workout-proposal.png` | workout pending proposal |
| `05-hydration-routine.png` | hydration success then routine detail |
| `06-plan.png` | loaded Plan |
| `07-progress-block.png` | Progress then Today-sourced block |
| `08-main-history.png` | two-section first page |
| `09-offline-error-retry.png` | stale-offline or one-shot failure Retry |
| `10-dark-mode.png` | loaded representative screen after `appearance dark` |
| `11-accessibility-xxxl.png` | representative screen at accessibility XXXL |
| `12-reduce-motion.png` | context image for the Reduce Motion policy/manual observation |
| `13-final-simulator.png` | restored Light/Large app left running |

Read `$BODYFLOW_ATTACHMENT_ROOT/manifest.json`. For every approved name, locate the entry whose `suggestedHumanReadableName` matches exactly, then copy its `exportedFileName` from the attachment root to the exact root-level evidence filename. Use explicit source and destination paths after the manifest reveals the generated filename; do not commit the raw attachment directory.

For any state not exported as an attachment, navigate using its exact Debug scenario and capture with an explicit path, for example:

```bash
xcrun simctl io 27291590-659D-4A29-8F45-CA5CA2D154F9 screenshot /Users/eduardohenrique/Developer/bodyflow/docs/superpowers/evidence/2026-07-29-bodyflow-ios-today-records-progress/13-final-simulator.png
```

Validate all materialized files before writing the README:

```bash
for BODYFLOW_EVIDENCE_FILE in 01-today.png 02-meal-proposal-edit.png 03-individual-meal-log-detail.png 04-workout-proposal.png 05-hydration-routine.png 06-plan.png 07-progress-block.png 08-main-history.png 09-offline-error-retry.png 10-dark-mode.png 11-accessibility-xxxl.png 12-reduce-motion.png 13-final-simulator.png; do
  test -s "$BODYFLOW_EVIDENCE_ROOT/$BODYFLOW_EVIDENCE_FILE" || exit 1
done
```

- [ ] **Step 8: Write and review the evidence README**

Record:

- branch and tested SHA;
- Xcode/runtime/simulator id;
- exact test/build commands and result-bundle path;
- actual test counts with zero failure/skip evidence;
- every screenshot and inspected state;
- Debug fixtures are synthetic only;
- Release returns `operationUnavailable`/`Indisponível nesta versão`;
- History is first page only and row detail is snapshot-only;
- backend work is still required for reliable shared History pagination and aggregated meal occurrence identity;
- no real endpoint/client, secrets, provider integration, WhatsApp architecture, migration, deployment, merge or TestFlight action occurred.

- [ ] **Step 9: Commit evidence after final diff checks**

```bash
git diff --check
git status --short
git add docs/superpowers/evidence/2026-07-29-bodyflow-ios-today-records-progress
git commit -m "docs(ios): add prompt 13 verification evidence"
git status --short
```

Expected: clean worktree.

- [ ] **Step 10: Publish only after the local gate is green**

Push only `codex/bodyflow-ios-today-records-progress-v1`, verify local/remote hashes match, and create one draft stacked PR with:

- base: `codex/bodyflow-ios-auth-onboarding-v1`;
- head: `codex/bodyflow-ios-today-records-progress-v1`.

Do not create another PR, merge it, deploy, migrate or change production.

## Plan Completion Checklist

- [ ] Every task has an observed RED before production implementation.
- [ ] Every task reaches focused GREEN and passes `git diff --check`.
- [ ] Every task has one Conventional Commit checkpoint.
- [ ] All capability boundaries remain small and `Sendable`.
- [ ] Debug fixtures/repository are structurally excluded from Release.
- [ ] Release calls fail `operationUnavailable` and never present simulated success.
- [ ] All official values come from complete provider responses.
- [ ] Today tests preserve `targets`, `consumed`, `food_excess_kcal`, `exercise_kcal` and `daily_balance_status` literally.
- [ ] Proposal invalidation and routine invalidation match the approved matrix exactly.
- [ ] `@MainActor @Observable FeatureInvalidationCenter` revisions are observed with one `.task(id:)` complete reload per revision and cancellation-safe publication.
- [ ] Hydration enforces inclusive integer `1...5000` ml and weight reuses inclusive `30...300` kg.
- [ ] Demonstration meal text enforces `String.count` `1...1000` without becoming an API contract.
- [ ] Routine conflict reloads list and item history only; detail re-resolves from the refreshed list and no detail provider exists.
- [ ] Telemetry emits only valid 1...64-character ASCII `[A-Za-z0-9._:-]` `calculation_version` values without normalization.
- [ ] Retry retains idempotency key, immutable payload and injected creation time.
- [ ] Main History performs only `.firstPage` reads.
- [ ] Individual meal-log detail uses only the already-loaded History snapshot.
- [ ] Same-time/same-type meal rows remain separate.
- [ ] Routine histories alone use opaque `next_cursor` pagination.
- [ ] Full unit/UI suite, Debug, Release, simulator and visual/accessibility gates pass.
- [ ] Evidence records actual results and synthetic-only boundaries.
- [ ] No real service, secret, production, migration, deploy, merge, TestFlight or WhatsApp architecture is introduced.

Task 1 must remain paused after this documentary revision is committed. Begin
implementation only after a later explicit user instruction.
