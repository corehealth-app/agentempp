# BodyFlow iOS Auth, Onboarding And Coach Persona Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a complete, deterministic iOS entry journey from splash through demo email authentication, onboarding and coach-persona selection into Today, with production-shaped service boundaries and no live provider calls.

**Architecture:** One `@MainActor` root state machine selects authentication, onboarding or the existing five-tab shell. Feature views call protocol-typed authentication, onboarding and persona services; actor-backed demo implementations persist only bounded development state through a throwing secure-storage boundary. The future Supabase Auth and mobile BFF adapters replace those services without changing feature views.

**Tech Stack:** Xcode 26.6, Swift 6.0 with complete concurrency checking, SwiftUI, Observation, Security framework Keychain APIs, Swift Testing, XCTest/XCUIAutomation, iOS 18.0, iPhone 17 Pro simulator on iOS 26.5.

## Global Constraints

- Execute implementation only in `/Users/eduardohenrique/Developer/bodyflow` on branch `codex/bodyflow-ios-auth-onboarding-v1`, based on commit `c8fbe84` or its pushed equivalent.
- Keep the visible product name `BodyFlow`, bundle ID `com.bodyflow.app`, Swift 6 language mode and iOS 18.0 deployment target unchanged.
- Add no Supabase Swift package, base URL, publishable key, bearer token, external dependency or live network call.
- Create no real account, email, patient record, legal acceptance, staging data or production data.
- Do not implement or reference any legacy messaging channel in new mobile architecture or source files.
- Never calculate calories, macros, targets, protocols or health outcomes in the iOS client.
- Never persist or log passwords, email addresses, birth dates, body measurements, free text, provider tokens or raw errors in telemetry.
- `balanced` remains backend-only and must never be shown as a selectable coach persona.
- Synthetic consent documents are Debug/test fixtures only. Release must reject them and must not complete onboarding with those IDs.
- Preserve the existing five-tab order, typed navigation, accessibility identifiers and scaffold tests.
- Use Swift Testing for unit tests and XCTest only for UI tests.
- Implement every non-generated behavior test-first and observe the expected RED result before production code.
- Keep each task in its own Conventional Commit checkpoint. Do not squash the checkpoints.
- Do not merge, deploy, run migrations, configure environments, sign for a physical device, archive or upload to TestFlight.
- Push and create a draft PR only after the final local verification gate passes.

---

## File Map

### Application state and dependencies

- Create `apps/ios/BodyFlow/BodyFlow/App/AppFlowModel.swift`: root launch/auth/onboarding/authenticated state machine.
- Create `apps/ios/BodyFlow/BodyFlow/App/AppRootView.swift`: switches the visible root from one explicit app-flow state.
- Create `apps/ios/BodyFlow/BodyFlow/App/AppLaunchConfiguration.swift`: parses deterministic Debug/UI-test launch scenarios.
- Modify `apps/ios/BodyFlow/BodyFlow/App/AppDependencies.swift`: install authentication, onboarding and persona repositories.
- Modify `apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift`: receive the authenticated user ID and pass it to Profile.
- Modify `apps/ios/BodyFlow/BodyFlow/BodyFlowApp.swift`: own the root model and render `AppRootView`.

### Core authentication, onboarding and persona contracts

- Create `apps/ios/BodyFlow/BodyFlow/Core/Auth/AuthenticationService.swift`: session models, typed errors and async service contract; remove the scaffold-only `AuthSessionProviding.swift` only when the dependency graph switches in Task 3.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Onboarding/OnboardingModels.swift`: draft, steps, objective, routine and development-consent models.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Onboarding/OnboardingRepository.swift`: draft persistence and idempotent completion contract.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Coach/CoachPersona.swift`: public Focus, Impulse and Zen model.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Coach/CoachPersonaRepository.swift`: selected-persona read/write contract.

### Secure development persistence and deterministic services

- Modify `apps/ios/BodyFlow/BodyFlow/Core/Storage/SecureStoring.swift`: make secure-store failures explicit with `async throws`.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Storage/KeychainSecureStore.swift`: Security-framework implementation with a configurable service namespace.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Storage/DemoStateStore.swift`: Codable storage for session, onboarding draft and selected public persona.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Auth/DemoAuthenticationService.swift`: deterministic no-network authentication.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Onboarding/DemoOnboardingRepository.swift`: deterministic draft/completion behavior.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Coach/DemoCoachPersonaRepository.swift`: deterministic persona persistence.

### Authentication feature

- Create `apps/ios/BodyFlow/BodyFlow/Features/Auth/AuthFormState.swift`: bounded field validation and operation state.
- Create `apps/ios/BodyFlow/BodyFlow/Features/Auth/SplashView.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Features/Auth/SignInView.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Features/Auth/SignUpView.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Features/Auth/EmailConfirmationView.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Features/Auth/PasswordRecoveryView.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Features/Auth/AuthFieldMessage.swift`: accessible field-level validation presentation.

### Onboarding and Profile features

- Create `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/OnboardingFlowModel.swift`: validated step transitions, save and completion orchestration.
- Create `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/OnboardingContainerView.swift`: progress, back and primary-action composition.
- Create `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/WelcomeStepView.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/BodyDataStepView.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/ObjectiveStepView.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/RoutineStepView.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/PersonaStepView.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/ConsentStepView.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/OnboardingCompletionView.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Features/Profile/CoachPersonaEditorModel.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Features/Profile/CoachPersonaPickerView.swift`.
- Modify `apps/ios/BodyFlow/BodyFlow/Features/Profile/ProfileRootView.swift`: expose the persona editor and current selection.

### Tests and evidence

- Create focused suites in `apps/ios/BodyFlow/BodyFlowTests/` for app flow, contracts, secure persistence, demo services, auth forms, onboarding and persona editing.
- Modify existing storage, dependencies, fixtures and telemetry tests only where the internal contracts intentionally change.
- Extend `apps/ios/BodyFlow/BodyFlowUITests/BodyFlowUITests.swift` with fresh-auth, complete-onboarding, restoration, recovery and error scenarios while retaining the three scaffold scenarios.
- Create `docs/superpowers/evidence/2026-07-26-bodyflow-ios-auth-onboarding/README.md` and curated simulator screenshots after final verification.

---

### Task 1: Define Domain Contracts And The Root State Machine

**Files:**

- Create: `apps/ios/BodyFlow/BodyFlowTests/AppFlowModelTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/OnboardingModelsTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/BodyFlowTestFixtures.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Auth/AuthenticationService.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Onboarding/OnboardingModels.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Onboarding/OnboardingRepository.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Coach/CoachPersona.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Coach/CoachPersonaRepository.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/App/AppFlowModel.swift`

**Interfaces:**

- Produces `AuthSession`, `AuthSignUpResult`, `AuthenticationError`, and `AuthenticationService`.
- Produces `OnboardingDraft`, `OnboardingStep`, `BodyFlowObjective`, `BiologicalSex`, routine enums and `DevelopmentConsentAcceptance`.
- Produces `OnboardingRepository` and `CoachPersonaRepository`.
- Produces `AppFlowState`, `AuthDestination`, `AppPresentationError`, and `@MainActor @Observable final class AppFlowModel`.

- [ ] **Step 1: Write RED tests for the public domain values**

Add tests asserting these exact contracts:

```swift
@Test("only public coach personas are selectable")
func selectablePersonas() {
    #expect(CoachPersona.allCases == [.focus, .impulse, .zen])
    #expect(CoachPersona.allCases.map(\.displayName) == [
        "Focus", "Impulse", "Zen"
    ])
}

@Test("onboarding follows the approved seven-step order")
func onboardingOrder() {
    #expect(OnboardingStep.allCases == [
        .welcome, .bodyData, .objective, .routine,
        .persona, .consent, .completion
    ])
}

@Test("objectives mirror the backend domain vocabulary")
func objectiveCodes() {
    #expect(BodyFlowObjective.allCases.map(\.rawValue) == [
        "recomposicao", "ganho_massa", "manutencao"
    ])
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowTests/OnboardingModelsTests test
```

Expected: compile failure because the models do not exist.

- [ ] **Step 3: Add the minimal models and service protocols**

Use these exact public shapes:

```swift
struct AuthSession: Codable, Equatable, Sendable {
    let userID: String
    let email: String
    let isEmailConfirmed: Bool
    let isOnboardingCompleted: Bool
}

enum AuthSignUpResult: Equatable, Sendable {
    case confirmationRequired(email: String)
    case authenticated(AuthSession)
}

enum AuthenticationError: Error, Equatable, Sendable {
    case invalidInput
    case invalidCredentials
    case confirmationRequired
    case operationUnavailable
    case serviceUnavailable
    case storageUnavailable
}

enum AppPresentationError: Equatable, Sendable {
    case invalidInput
    case invalidCredentials
    case confirmationRequired
    case operationUnavailable
    case serviceUnavailable
    case storageUnavailable
}

enum OnboardingRepositoryError: Error, Equatable, Sendable {
    case invalidDraft
    case developmentConsentForbidden
    case storageUnavailable
    case serviceUnavailable
}

enum CoachPersonaRepositoryError: Error, Equatable, Sendable {
    case storageUnavailable
    case serviceUnavailable
}

protocol AuthenticationService: Sendable {
    func restoreSession() async throws -> AuthSession?
    func signIn(email: String, password: String) async throws -> AuthSession
    func signUp(email: String, password: String) async throws -> AuthSignUpResult
    func confirmEmailForDevelopment() async throws -> AuthSession
    func requestPasswordRecovery(email: String) async throws
    func signOut() async throws
}

protocol OnboardingRepository: Sendable {
    func loadDraft(for userID: String) async throws -> OnboardingDraft?
    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws
    func complete(_ draft: OnboardingDraft, for userID: String) async throws
    func clear(for userID: String) async throws
}

protocol CoachPersonaRepository: Sendable {
    func selectedPersona(for userID: String) async throws -> CoachPersona?
    func setPersona(_ persona: CoachPersona, for userID: String) async throws
}
```

Use these exact raw values for server-shaped domain enums:

```swift
enum BiologicalSex: String, CaseIterable, Codable, Sendable {
    case masculine = "masculino"
    case feminine = "feminino"
}

enum BodyFlowObjective: String, CaseIterable, Codable, Sendable {
    case bodyRecomposition = "recomposicao"
    case muscleGain = "ganho_massa"
    case maintenance = "manutencao"
}

enum ActivityLevel: String, CaseIterable, Codable, Sendable {
    case sedentary = "sedentario"
    case light = "leve"
    case moderate = "moderado"
    case high = "alto"
    case athlete = "atleta"
}

enum WaterIntake: String, CaseIterable, Codable, Sendable {
    case low = "pouco"
    case moderate = "moderado"
    case high = "bastante"
}

enum HungerLevel: String, CaseIterable, Codable, Sendable {
    case low = "pouca"
    case moderate = "moderada"
    case high = "muita"
}

enum FoodOrganization: String, CaseIterable, Codable, Sendable {
    case yes = "sim"
    case no = "nao"
}
```

`OnboardingDraft` is `Codable`, `Equatable`, and `Sendable`. It has the typed fields `displayName`, `localeIdentifier`, `countryCode`, `timeZoneIdentifier`, `biologicalSex`, `birthDate`, `heightCM`, `weightKG`, `bodyFatPercent`, `objective`, `activityLevel`, `trainingFrequency`, `waterIntake`, `hungerLevel`, `wakeTime`, `bedtime`, `foodOrganization`, `persona`, `consent`, and `currentStep`. Use a small Codable `LocalTime(hour:minute:)` value instead of persisting locale-dependent strings or `DateComponents`. `DevelopmentConsentAcceptance` stores only `documentIDs: [String]` and `acceptedAt: Date`.

- [ ] **Step 4: Write RED state-transition tests**

Cover these exact cases with protocol spies local to the test target:

```swift
@MainActor
@Test("fresh launch restores into sign in")
func freshLaunch() async {
    let model = AppFlowModel(
        authentication: AuthenticationServiceSpy(restoredSession: nil),
        onboarding: OnboardingRepositorySpy(),
        persona: CoachPersonaRepositorySpy(),
        telemetry: InMemoryTelemetryClient()
    )

    await model.start()

    #expect(model.state == .signedOut(.signIn))
}

@MainActor
@Test("confirmed incomplete session resumes its saved onboarding step")
func resumesOnboarding() async {
    let session = AuthSession(
        userID: "fixture-user",
        email: "fixture@example.invalid",
        isEmailConfirmed: true,
        isOnboardingCompleted: false
    )
    let draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .objective)
    let model = AppFlowModel(
        authentication: AuthenticationServiceSpy(restoredSession: session),
        onboarding: OnboardingRepositorySpy(loadedDraft: draft),
        persona: CoachPersonaRepositorySpy(),
        telemetry: InMemoryTelemetryClient()
    )

    await model.start()

    #expect(model.state == .onboarding(userID: "fixture-user", step: .objective))
}
```

Define `BodyFlowTestFixtures.onboardingDraft(currentStep:)` in `BodyFlowTestFixtures.swift`. It must initialize every field with fixed synthetic values, including locale `pt-BR`, country `US`, timezone `America/New_York`, `Date(timeIntervalSince1970: 946_684_800)`, `LocalTime(hour: 7, minute: 0)`, `LocalTime(hour: 23, minute: 0)`, `.bodyRecomposition`, `.moderate`, `.focus`, and the development document IDs. Keep this factory internal to the test target; do not add fixture factories to the app target.

Also test confirmed-complete -> `.authenticated(userID: "fixture-user")`, unconfirmed -> `.awaitingEmailConfirmation`, restoration error -> `.signedOut(.signIn)` with a recoverable presentation error, and sign-out -> `.signedOut(.signIn)`.

- [ ] **Step 5: Run the state tests and verify RED**

Run the `AppFlowModelTests` suite. Expected: compile failure because `AppFlowModel` does not exist.

- [ ] **Step 6: Implement the root model minimally**

Define:

```swift
enum AuthDestination: Equatable, Sendable {
    case signIn
    case signUp
    case passwordRecovery
}

enum AppFlowState: Equatable, Sendable {
    case launching
    case signedOut(AuthDestination)
    case awaitingEmailConfirmation(email: String)
    case onboarding(userID: String, step: OnboardingStep)
    case authenticated(userID: String)
}
```

`AppFlowModel.start()` must call `restoreSession()` once, derive exactly one root state, and never navigate after a cancelled task. Keep `private(set) var currentSession: AuthSession?` synchronized with the state so the root can pass the authenticated user ID explicitly into `AppShellView`. Keep user-facing error state bounded to `AppPresentationError`, without raw provider text.

- [ ] **Step 7: Run focused tests and the existing unit target**

Expected: `AppFlowModelTests`, `OnboardingModelsTests` and every existing scaffold unit test pass. Keep `AuthSessionProviding.swift` unchanged as a temporary compatibility boundary until Task 3 switches `AppDependencies` atomically.

- [ ] **Step 8: Commit the domain checkpoint**

```bash
git add apps/ios/BodyFlow/BodyFlow/Core apps/ios/BodyFlow/BodyFlow/App/AppFlowModel.swift apps/ios/BodyFlow/BodyFlowTests/AppFlowModelTests.swift apps/ios/BodyFlow/BodyFlowTests/OnboardingModelsTests.swift apps/ios/BodyFlow/BodyFlowTests/BodyFlowTestFixtures.swift
git diff --cached --check
git commit -m "feat(ios): define auth onboarding state model"
```

---

### Task 2: Add Throwing Secure Storage And Demo State Persistence

**Files:**

- Modify: `apps/ios/BodyFlow/BodyFlow/Core/Storage/SecureStoring.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Storage/KeychainSecureStore.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Storage/DemoStateStore.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/SecureStorageTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/DemoStateStoreTests.swift`

**Interfaces:**

- Replaces each `SecureStoring` operation with an `async throws` equivalent.
- Produces `KeychainSecureStore(service:accessGroup:)` and typed `SecureStorageError`.
- Produces `DemoStateStore` methods for session and onboarding draft load/save/clear.

Use these exact error contracts:

```swift
enum SecureStorageError: Error, Equatable, Sendable {
    case invalidKey
    case unhandledStatus(OSStatus)
}

enum DemoStateStoreError: Error, Equatable, Sendable {
    case invalidPayload
    case secureStorageUnavailable
}
```

Map any `SecureStoring` error at the Codable boundary to `.secureStorageUnavailable`; preserve JSON encode/decode failures as `.invalidPayload`.

- [ ] **Step 1: Write RED tests for throwing storage**

Retain the in-memory round-trip test and add failure propagation through a failing test store. Add one simulator Keychain test using a unique namespace:

```swift
@Test("Keychain round trips and removes data")
func keychainRoundTrip() async throws {
    let service = "com.bodyflow.app.tests.\(UUID().uuidString)"
    let store = KeychainSecureStore(service: service)
    let key = "session"
    let payload = Data("fixture".utf8)

    try await store.store(payload, forKey: key)
    #expect(try await store.data(forKey: key) == payload)
    try await store.removeData(forKey: key)
    #expect(try await store.data(forKey: key) == nil)
}
```

- [ ] **Step 2: Run `SecureStorageTests` and verify RED**

Expected: compile failure because existing methods do not throw and `KeychainSecureStore` does not exist.

- [ ] **Step 3: Implement the throwing protocol and Keychain adapter**

Use `kSecClassGenericPassword`, service, account key and
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Treat `errSecItemNotFound` as
`nil`; map all other non-success statuses to `SecureStorageError.unhandledStatus(OSStatus)`.

Never print the query, stored bytes or OSStatus context containing a value.

- [ ] **Step 4: Run secure-storage tests and verify GREEN**

Expected: in-memory, failure and Keychain round-trip tests pass repeatedly without sharing state between test runs.

- [ ] **Step 5: Write RED Codable demo-state tests**

Test exact round trips for `AuthSession`, `OnboardingDraft` and `CoachPersona`, corrupted JSON returning `DemoStateStoreError.invalidPayload`, and `clearAll()` removing all three keys. Use fixed dates and synthetic `.invalid` emails only.

- [ ] **Step 6: Implement `DemoStateStore`**

Use fixed private keys:

```swift
private enum DemoStateKey {
    static let session = "bodyflow.demo.session.v1"
    static let onboardingDraft = "bodyflow.demo.onboarding-draft.v1"
    static let coachPersona = "bodyflow.demo.coach-persona.v1"
}
```

Expose `loadSession`, `saveSession`, `loadOnboardingDraft`, `saveOnboardingDraft`, `loadCoachPersona`, `saveCoachPersona`, `clearSession`, `clearOnboardingDraft`, and `clearAll`. Use `JSONEncoder` and `JSONDecoder` with `.iso8601`. Do not silently discard decode errors.

- [ ] **Step 7: Run focused and full unit tests**

Expected: storage suites pass. Update existing `SecureStorageTests` call sites to `try await`; no `try?` suppression is allowed in production code.

- [ ] **Step 8: Commit secure persistence**

```bash
git add apps/ios/BodyFlow/BodyFlow/Core/Storage apps/ios/BodyFlow/BodyFlowTests/SecureStorageTests.swift apps/ios/BodyFlow/BodyFlowTests/DemoStateStoreTests.swift
git diff --cached --check
git commit -m "feat(ios): persist demo session securely"
```

---

### Task 3: Implement Deterministic Demo Services And Dependency Graph

**Files:**

- Create: `apps/ios/BodyFlow/BodyFlow/Core/Auth/DemoAuthenticationService.swift`
- Delete: `apps/ios/BodyFlow/BodyFlow/Core/Auth/AuthSessionProviding.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Onboarding/DemoOnboardingRepository.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Coach/DemoCoachPersonaRepository.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/App/AppLaunchConfiguration.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppDependencies.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/DemoServicesTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/AppDependenciesTests.swift`

**Interfaces:**

- Produces generic `DemoOperationBehavior<Failure>` with deterministic success, delay and typed failure.
- Produces deterministic demo service actors backed by `DemoStateStore`.
- Produces `AppLaunchConfiguration.current()`, `AppLaunchConfiguration.resolve(arguments:buildFlavor:)`, and `AppDependencies.demo(configuration:)`.

Use these exact configuration types:

```swift
enum DemoOperationBehavior<Failure: Error & Sendable>: Sendable {
    case succeed(after: Duration?)
    case fail(Failure, after: Duration?)
}

enum AppRuntimeMode: Equatable, Sendable {
    case demo
    case releaseUnavailable
}

enum AppBuildFlavor: Equatable, Sendable {
    case debug
    case release
}

struct AppLaunchConfiguration: Sendable {
    let mode: AppRuntimeMode
    let shouldResetDemoState: Bool
    let startsWithCompletedFixture: Bool
    let preloadsSyntheticOnboardingValues: Bool
    let authBehavior: DemoOperationBehavior<AuthenticationError>
}
```

Because a generic enum with an associated `Error` does not synthesize `Equatable`, compare the concrete configuration fields in tests through explicit computed scenario IDs rather than adding unsafe equality. `AppLaunchConfiguration.resolve(arguments:buildFlavor:)` accepts an injected `AppBuildFlavor` for tests; `current()` supplies `.debug` or `.release` through `#if DEBUG`.

- [ ] **Step 1: Write RED demo-auth tests**

Cover:

- fresh restore returns `nil`;
- sign-up returns `.confirmationRequired` and stores no password;
- development confirmation creates a confirmed incomplete session;
- sign-in rejects structurally empty credentials before state mutation;
- recovery succeeds with the same public result for any plausible email;
- sign-out removes only the session;
- configured delay exposes cancellability;
- configured failure writes no session.

- [ ] **Step 2: Run `DemoServicesTests` and verify RED**

Expected: compile failure because demo services do not exist.

- [ ] **Step 3: Implement demo authentication**

Normalize email only for in-memory comparison, never telemetry. Use the fixed synthetic user ID `demo-user-v1`. A successful sign-in returns a confirmed session whose onboarding completion is loaded from the demo state store; it does not accept a privileged bypass value.

The first `restoreSession()` call applies `shouldResetDemoState` exactly once inside the actor before reading state. When `startsWithCompletedFixture` is true, it returns a fixed confirmed/completed synthetic session without writing a password or relying on prior test order. All fresh-state UI scenarios set `shouldResetDemoState = true` and `startsWithCompletedFixture = false`.

Development confirmation is allowed only when `AppLaunchConfiguration.mode == .demo`. The service must throw `AuthenticationError.operationUnavailable` in `.releaseUnavailable`. No launch argument may change a Release build to `.demo`.

Centralize deterministic delay/failure handling inside each actor:

```swift
private func apply(_ behavior: DemoOperationBehavior<AuthenticationError>) async throws {
    switch behavior {
    case .succeed(let delay):
        if let delay { try await Task.sleep(for: delay) }
    case .fail(let error, let delay):
        if let delay { try await Task.sleep(for: delay) }
        try Task.checkCancellation()
        throw error
    }
}
```

Call `Task.checkCancellation()` again immediately before every state write.

- [ ] **Step 4: Add RED repository tests**

Test draft save/load, idempotent repeated completion, persona save/read, failure preserving the previous persona, and rejection of a development consent in a `.release` policy:

```swift
await #expect(throws: OnboardingRepositoryError.developmentConsentForbidden) {
    try await releaseRepository.complete(draftWithDevelopmentConsent, for: "demo-user-v1")
}
```

- [ ] **Step 5: Implement demo onboarding and persona repositories**

The onboarding repository validates a complete draft before changing the stored session. It sets `isOnboardingCompleted = true` only after validation succeeds. Repeated completion of the same valid draft returns success without duplicating state.

The persona repository accepts only `CoachPersona`. Its storage key is scoped to the current demo user and no public initializer accepts arbitrary string codes.

- [ ] **Step 6: Add RED launch-configuration tests**

Exact scenarios:

```text
--ui-testing                       -> completed authenticated fixture
--ui-testing-fresh-auth            -> clear state, start signed out, prefill only synthetic onboarding fields
--ui-testing-auth-error            -> fresh state and one deterministic sign-in failure
--ui-testing-recovery              -> fresh state and deterministic recovery success
```

Unknown arguments must not enable a bypass. Release configuration must ignore all Debug-only demo-control arguments.

`preloadsSyntheticOnboardingValues` is true only for UI-test scenarios. It provides valid synthetic country, timezone, body and routine values after email confirmation, but it does not select an objective, persona, consent or completion action. Debug launches without UI-test arguments start with an empty draft plus device-suggested country/timezone.

- [ ] **Step 7: Implement dependencies and update scaffold expectations**

Replace `authSession` in `AppDependencies` with:

```swift
let authentication: any AuthenticationService
let onboarding: any OnboardingRepository
let coachPersona: any CoachPersonaRepository
```

Keep `apiClient`, `secureStore`, and `telemetry`. `AppDependencies.scaffold()` remains available for previews and maps to a deterministic completed demo fixture so existing tab previews remain isolated.

After every `AppDependencies` and test call site uses `AuthenticationService`, delete the scaffold-only `AuthSessionProviding.swift` in the same checkpoint. The build and full unit target must pass before commit.

- [ ] **Step 8: Run focused tests and the complete unit target**

Expected: all demo service, launch configuration and updated dependency tests pass; no network request occurs.

- [ ] **Step 9: Commit deterministic services**

```bash
git add apps/ios/BodyFlow/BodyFlow/App apps/ios/BodyFlow/BodyFlow/Core/Auth apps/ios/BodyFlow/BodyFlow/Core/Onboarding apps/ios/BodyFlow/BodyFlow/Core/Coach apps/ios/BodyFlow/BodyFlowTests
git diff --cached --check
git commit -m "feat(ios): add deterministic auth services"
```

---

### Task 4: Build Splash And Authentication Surfaces

**Files:**

- Create: `apps/ios/BodyFlow/BodyFlowTests/AuthFormStateTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Auth/AuthFormState.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Auth/AuthFieldMessage.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Auth/SplashView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Auth/SignInView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Auth/SignUpView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Auth/EmailConfirmationView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Auth/PasswordRecoveryView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/App/AppRootView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/BodyFlowApp.swift`

**Interfaces:**

- Produces `AuthValidationIssue`, `AuthOperationState` and pure `AuthInputValidator`.
- `AppRootView` consumes `AppFlowModel` and `AppDependencies`, rendering exactly one root surface.
- Authentication views invoke `AppFlowModel` commands and never call a concrete demo actor.

- [ ] **Step 1: Write RED validation tests**

Test that whitespace-only input is rejected, `person@example.invalid` is structurally accepted, malformed input is rejected, sign-up passwords must match, and no final provider password-length rule is invented.

```swift
@Test("password confirmation must match without imposing provider policy")
func passwordConfirmation() {
    #expect(AuthInputValidator.signUp(
        email: "person@example.invalid",
        password: "local-pass",
        confirmation: "different"
    ) == [.passwordsDoNotMatch])
}
```

- [ ] **Step 2: Run `AuthFormStateTests` and verify RED**

Expected: compile failure because validation types do not exist.

- [ ] **Step 3: Implement pure validation and bounded presentation errors**

Use these exact shapes:

```swift
enum AuthValidationIssue: Equatable, Sendable {
    case emailRequired
    case emailMalformed
    case passwordRequired
    case passwordConfirmationRequired
    case passwordsDoNotMatch
}

enum AuthOperationState: Equatable, Sendable {
    case idle
    case submitting
    case recoveryConfirmation
    case failed(AppPresentationError)
}

enum AuthInputValidator {
    static func signIn(email: String, password: String) -> [AuthValidationIssue]
    static func signUp(
        email: String,
        password: String,
        confirmation: String
    ) -> [AuthValidationIssue]
    static func recovery(email: String) -> [AuthValidationIssue]
}
```

Validation order is email-required/malformed, password-required, confirmation-required, then mismatch. Raw provider messages never enter `AuthOperationState`.

- [ ] **Step 4: Write RED app-flow command tests**

Extend `AppFlowModelTests` for:

- `showSignUp`, `showPasswordRecovery`, and `showSignIn`;
- sign-in success to onboarding or authenticated based on session;
- sign-up success to email confirmation;
- development confirmation to onboarding;
- recovery success without account-disclosure data;
- double-tap suppression while an operation is in flight;
- cancellation preventing late state transition.

- [ ] **Step 5: Run the command tests and verify RED**

Expected: missing command methods or failed expectations.

- [ ] **Step 6: Implement the root and auth screens**

Use these stable accessibility IDs:

```text
screen.splash
screen.auth.sign-in
screen.auth.sign-up
screen.auth.email-confirmation
screen.auth.password-recovery
auth.email
auth.password
auth.password-confirmation
auth.sign-in.submit
auth.sign-up.submit
auth.open-sign-up
auth.open-recovery
auth.confirm-development
auth.recovery.submit
auth.recovery.confirmation
```

Requirements:

- Splash has no timer and shows only the `BodyFlow` text mark plus native progress.
- Password fields use `SecureField`, email uses `.textContentType(.emailAddress)`, and submit labels follow form order.
- Disable only the active submit command while loading; navigation commands cannot create concurrent requests.
- Recovery success copy is exactly: `Se houver uma conta para este e-mail, enviaremos as instruções de recuperação.`
- The development-confirmation command appears only in demo configuration and is labeled `Continuar no ambiente de teste`.
- Each screen has normal, loading and recoverable-error previews as applicable.

The root switch remains exhaustive and contains no fallback branch:

```swift
@ViewBuilder
private var rootContent: some View {
    switch model.state {
    case .launching:
        SplashView()
    case .signedOut(.signIn):
        SignInView(model: model)
    case .signedOut(.signUp):
        SignUpView(model: model)
    case .signedOut(.passwordRecovery):
        PasswordRecoveryView(model: model)
    case .awaitingEmailConfirmation(let email):
        EmailConfirmationView(
            email: email,
            allowsDevelopmentConfirmation: configuration.mode == .demo,
            model: model
        )
    case .onboarding(_, _):
        if let onboardingFlowModel {
            OnboardingContainerView(model: onboardingFlowModel)
        } else {
            ProgressView().accessibilityLabel("Carregando onboarding")
        }
    case .authenticated(let userID):
        AppShellView(userID: userID)
    }
}
```

`AppRootView` owns `@State private var onboardingFlowModel: OnboardingFlowModel?` and creates it once per authenticated user transition through an id-scoped task. It must not construct an observable model from the computed `body`. Signing out sets this state back to `nil`.

For `.authenticated(userID:)`, `AppRootView` must render `AppShellView(userID: userID)`. Add `userID: String = "fixture-user"` to `AppShellView` so existing previews and scaffold UI tests retain a synthetic default; pass that value explicitly into `ProfileRootView(userID:)`. Do not read identity from a global singleton or from view-local storage.

- [ ] **Step 7: Run unit tests and build Debug**

Run:

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -configuration Debug -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" build
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -only-testing:BodyFlowTests test
```

Expected: build and all unit tests pass. A manual launch with `--ui-testing-fresh-auth` visibly reaches sign-in.

- [ ] **Step 8: Commit authentication UI**

```bash
git add apps/ios/BodyFlow/BodyFlow/BodyFlowApp.swift apps/ios/BodyFlow/BodyFlow/App apps/ios/BodyFlow/BodyFlow/Features/Auth apps/ios/BodyFlow/BodyFlowTests
git diff --cached --check
git commit -m "feat(ios): build demo authentication flow"
```

---

### Task 5: Implement Validated Onboarding Draft And Core Steps

**Files:**

- Create: `apps/ios/BodyFlow/BodyFlowTests/OnboardingFlowModelTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/OnboardingFlowModel.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/OnboardingContainerView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/WelcomeStepView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/BodyDataStepView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/ObjectiveStepView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/RoutineStepView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppRootView.swift`

**Interfaces:**

- Produces `OnboardingValidationIssue`, `OnboardingOperationState`, and `@MainActor @Observable final class OnboardingFlowModel` with `draft`, `step`, `operationState`, `back()`, `continueFromCurrentStep()`, typed field update methods, `onStepChanged`, and `onCompleted` callbacks.
- Produces step views that bind only to `OnboardingFlowModel` and have no repository access.

Use these bounded state shapes:

```swift
enum OnboardingOperationState: Equatable, Sendable {
    case idle
    case saving
    case failed(AppPresentationError)
}

enum OnboardingValidationIssue: Equatable, Sendable {
    case displayNameRequired
    case countryInvalid
    case timeZoneInvalid
    case biologicalSexRequired
    case birthDateRequired
    case birthDateInFuture
    case heightOutOfRange
    case weightOutOfRange
    case bodyFatOutOfRange
    case objectiveRequired
    case activityLevelRequired
    case trainingFrequencyOutOfRange
    case waterIntakeRequired
    case hungerLevelRequired
    case wakeTimeRequired
    case bedtimeRequired
    case foodOrganizationRequired
    case personaRequired
    case consentRequired
}
```

- [ ] **Step 1: Write RED transition and validation tests**

Cover exact bounds already enforced by the mobile contract:

```text
country_code: exactly two uppercase ISO 3166-1 alpha-2 letters
time_zone_identifier: an identifier accepted by TimeZone(identifier:)
height_cm: 100...250
weight_kg: 30...300
body_fat_percent: optional 3...60
training_frequency: integer 0...7
```

Also test birth date cannot be in the future, each Continue saves the draft before advancing, Back preserves fields, invalid input does not save or advance, a save failure leaves the current step visible with retry, and `onStepChanged` fires only after a successful save.

- [ ] **Step 2: Run `OnboardingFlowModelTests` and verify RED**

Expected: compile failure because the flow model does not exist.

- [ ] **Step 3: Implement the model and pure step validators**

The model receives `userID`, initial draft, `OnboardingRepository`, `onStepChanged: @MainActor (OnboardingStep) -> Void`, and `onCompleted: @MainActor () -> Void`. It does not receive concrete storage. `continueFromCurrentStep()` validates only the current step, advances by `OnboardingStep.allCases`, saves the new `currentStep`, then calls `onStepChanged`; it suppresses concurrent submissions. `AppRootView` wires that callback to `AppFlowModel.updateOnboardingStep(_:)` so root state and draft state cannot diverge.

- [ ] **Step 4: Run model tests and verify GREEN**

Expected: transitions, field bounds, save-before-advance and retry behavior pass.

- [ ] **Step 5: Add the container and first four screens**

Use stable IDs:

```text
screen.onboarding.welcome
screen.onboarding.body-data
screen.onboarding.objective
screen.onboarding.routine
onboarding.back
onboarding.continue
onboarding.progress
onboarding.display-name
onboarding.country
onboarding.timezone
onboarding.objective.recomposicao
onboarding.objective.ganho-massa
onboarding.objective.manutencao
```

UI rules:

- Welcome collects display name, suggests the supported app locale plus device country/timezone, and requires visible confirmation of country and timezone. Country uses a searchable native picker backed by `Locale.Region.isoRegions`; timezone uses `TimeZone.knownTimeZoneIdentifiers`. Persist only the uppercase alpha-2 code and IANA identifier, never localized display strings.
- Body data uses native DatePicker, segmented/single selection for biological sex, decimal numeric fields for height/weight/body fat, and explicit units.
- Objective uses one native selection from `Recomposição corporal`, `Ganho de massa` and `Manutenção`.
- Routine uses native menu/picker controls for activity, water and hunger; a stepper for weekly frequency; native time pickers; and a binary toggle for food organization.
- No screen displays calorie or macro predictions.
- Progress has stable dimensions and includes text such as `Etapa 2 de 7`, not color alone.
- Dynamic Type can wrap all labels without horizontal clipping.

Keep step composition exhaustive and feature-local:

```swift
@ViewBuilder
private var stepContent: some View {
    switch model.step {
    case .welcome:
        WelcomeStepView(model: model)
    case .bodyData:
        BodyDataStepView(model: model)
    case .objective:
        ObjectiveStepView(model: model)
    case .routine:
        RoutineStepView(model: model)
    case .persona:
        PersonaStepView(model: model)
    case .consent:
        ConsentStepView(model: model)
    case .completion:
        OnboardingCompletionView(model: model)
    }
}
```

Tasks 5 and 6 may introduce the switch with temporary compile-safe branches only within the same uncommitted RED/GREEN cycle. No checkpoint commit may contain an empty or temporary screen.

- [ ] **Step 6: Add deterministic previews**

Create previews for every new step in valid, validation-error and save-error states where applicable. Use only synthetic values.

- [ ] **Step 7: Build and run complete unit tests**

Expected: Debug build and all unit tests pass. Inspect each preview for clipping at an accessibility text size.

- [ ] **Step 8: Commit core onboarding**

```bash
git add apps/ios/BodyFlow/BodyFlow/App/AppRootView.swift apps/ios/BodyFlow/BodyFlow/Features/Onboarding apps/ios/BodyFlow/BodyFlowTests/OnboardingFlowModelTests.swift
git diff --cached --check
git commit -m "feat(ios): add validated onboarding steps"
```

---

### Task 6: Complete Persona, Consent, Completion And Profile Editing

**Files:**

- Create: `apps/ios/BodyFlow/BodyFlowTests/CoachPersonaTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/OnboardingCompletionTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/PersonaStepView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/ConsentStepView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/OnboardingCompletionView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Profile/CoachPersonaEditorModel.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Profile/CoachPersonaPickerView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Profile/ProfileRootView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppFlowModel.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/OnboardingFlowModel.swift`

**Interfaces:**

- `OnboardingFlowModel.complete()` persists persona, completes the onboarding repository idempotently, and only then reports completion to `AppFlowModel`.
- `CoachPersonaPickerView` reads and updates the same repository through `@MainActor @Observable final class CoachPersonaEditorModel` without changing calculations or prior messages.

`CoachPersonaEditorModel` exposes `selected`, `persisted`, and an operation state with exactly `.loading`, `.idle`, `.saving`, and `.failed(AppPresentationError)`. It dismisses only when `selected` has been persisted successfully.

- [ ] **Step 1: Write RED persona presentation tests**

Assert exact neutral descriptions:

```swift
#expect(CoachPersona.focus.summary == "Direto, firme e objetivo.")
#expect(CoachPersona.impulse.summary == "Motivador, positivo e energético.")
#expect(CoachPersona.zen.summary == "Calmo, didático e acolhedor.")
```

Assert no public enum case or display string contains `balanced` or `Equilibrado`.

- [ ] **Step 2: Write RED completion-order tests**

Test:

- missing persona blocks completion;
- missing either consent checkbox blocks completion;
- persona persistence happens before onboarding completion;
- persona failure leaves profile incomplete;
- onboarding completion failure leaves app in the consent step and retry is safe;
- a second successful completion call produces one state transition;
- Release policy rejects `dev.terms.v1` and `dev.privacy.v1`.

- [ ] **Step 3: Run focused suites and verify RED**

Expected: failures because persona/consent completion is not implemented.

- [ ] **Step 4: Implement persona, consent and completion screens**

Use fixed development document IDs only in Debug/test:

```swift
static let terms = "dev.terms.v1"
static let privacy = "dev.privacy.v1"
```

Visible consent notice:

`Ambiente de validação. Estes documentos são sintéticos e não representam um aceite jurídico real.`

Use two explicit checkboxes for the development Terms and Privacy documents. The primary completion action remains disabled until both are selected. The completion view has one command, `Ir para Hoje`, which triggers the root transition only after repository success.

Add deterministic previews for Persona, Consent and Completion in normal state plus a saving or recoverable-error state. Preview repositories use only synthetic in-memory values.

- [ ] **Step 5: Implement safe completion orchestration**

Use this order:

1. validate the complete draft;
2. call `setPersona` with the selected public persona;
3. call idempotent `onboarding.complete`;
4. update the root session to completed;
5. transition to `.authenticated(userID: currentSession.userID)`.

If step 3 fails after persona succeeds, retrying repeats the idempotent persona write and completion call. Never transition on partial failure.

- [ ] **Step 6: Write RED Profile persona-edit tests**

Test initial selection, successful update, failure preserving the prior selection, double-tap suppression and dismissal only after success.

- [ ] **Step 7: Implement Profile editing**

Change `ProfileRootView` to accept `userID: String = "fixture-user"` and read the current selection through `CoachPersonaRepository`. Replace the fixture-only coach row with a navigation link labeled `Personalidade do coach`, showing the selected display name. Present `CoachPersonaPickerView` as an item-driven sheet owned by the Profile feature, rather than adding a generic `AppRoute.detail` case that loses the user identity. Keep notification and existing profile fixture rows intact.

Use IDs:

```text
profile.coach-persona
screen.profile.coach-persona
screen.onboarding.persona
screen.onboarding.consent
screen.onboarding.completion
persona.focus
persona.impulse
persona.zen
persona.save
consent.terms
consent.privacy
onboarding.go-to-today
```

- [ ] **Step 8: Run focused tests, full unit tests and Debug build**

Expected: persona and completion suites pass; all prior scaffold/auth/onboarding tests remain green.

- [ ] **Step 9: Commit complete onboarding and persona editing**

```bash
git add apps/ios/BodyFlow/BodyFlow/App apps/ios/BodyFlow/BodyFlow/Features/Onboarding apps/ios/BodyFlow/BodyFlow/Features/Profile apps/ios/BodyFlow/BodyFlowTests
git diff --cached --check
git commit -m "feat(ios): complete persona onboarding flow"
```

---

### Task 7: Enforce Privacy Telemetry, Accessibility And End-To-End UI Tests

**Files:**

- Modify: `apps/ios/BodyFlow/BodyFlow/Core/Telemetry/TelemetryClient.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/TelemetryTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowUITests/BodyFlowUITests.swift`
- Modify authentication/onboarding views only for defects proven by tests or simulator inspection.

**Interfaces:**

- Adds controlled event names for screen, bounded outcome, onboarding step and public persona only.
- Adds launch helpers that select one deterministic demo scenario without secrets or personal fixtures.

- [ ] **Step 1: Write RED telemetry privacy tests**

Allow these names:

```text
auth_screen_viewed
auth_operation_completed
onboarding_step_viewed
onboarding_step_completed
coach_persona_selected
onboarding_completed
sign_out_completed
```

Allow only metadata keys `screen`, `outcome`, `error_category`, `step`, and `persona`. Assert unsupported keys such as `email`, `password`, `birth_date`, `height_cm`, `weight_kg`, `body_fat_percent`, `token`, `raw_error`, and `message` are discarded.

- [ ] **Step 2: Run `TelemetryTests` and verify RED**

Expected: new event cases or metadata allowlist expectations fail.

- [ ] **Step 3: Implement the minimal telemetry additions**

Record only after actual state transitions. A cancelled operation records no success. A failure records its bounded category, never localized or provider error text.

- [ ] **Step 4: Add UI tests for the fresh user journey**

Retain all three existing scaffold UI tests. Add:

1. fresh launch -> sign-up -> development confirmation;
2. all seven onboarding screens -> Today;
3. relaunch -> authenticated Today;
4. Profile -> change persona -> reflected selection;
5. recovery -> neutral success message;
6. deterministic sign-in failure -> retry remains available.

Each fresh-state test launches with its explicit argument and resets its own demo state. Tests must not depend on execution order.

Use one launch helper that makes the scenario explicit:

```swift
@MainActor
private func launchApp(arguments: [String] = ["--ui-testing"]) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = arguments
    app.launch()
    return app
}

@MainActor
func testFreshUserCompletesOnboardingAndReachesToday() {
    let app = launchApp(arguments: ["--ui-testing-fresh-auth"])
    XCTAssertTrue(app.otherElements["screen.auth.sign-in"].waitForExistence(timeout: 3))
    app.buttons["auth.open-sign-up"].tap()
    app.textFields["auth.email"].typeText("person@example.invalid")
    app.secureTextFields["auth.password"].typeText("local-pass")
    app.secureTextFields["auth.password-confirmation"].typeText("local-pass")
    app.buttons["auth.sign-up.submit"].tap()
    XCTAssertTrue(app.otherElements["screen.auth.email-confirmation"].waitForExistence(timeout: 3))
    app.buttons["auth.confirm-development"].tap()
    XCTAssertTrue(app.otherElements["screen.onboarding.welcome"].waitForExistence(timeout: 3))

    app.textFields["onboarding.display-name"].typeText("Pessoa Teste")
    app.buttons["onboarding.continue"].tap()
    XCTAssertTrue(app.otherElements["screen.onboarding.body-data"].waitForExistence(timeout: 3))
    app.buttons["onboarding.continue"].tap()

    XCTAssertTrue(app.otherElements["screen.onboarding.objective"].waitForExistence(timeout: 3))
    app.buttons["onboarding.objective.recomposicao"].tap()
    app.buttons["onboarding.continue"].tap()

    XCTAssertTrue(app.otherElements["screen.onboarding.routine"].waitForExistence(timeout: 3))
    app.buttons["onboarding.continue"].tap()

    XCTAssertTrue(app.otherElements["screen.onboarding.persona"].waitForExistence(timeout: 3))
    app.buttons["persona.focus"].tap()
    app.buttons["onboarding.continue"].tap()

    XCTAssertTrue(app.otherElements["screen.onboarding.consent"].waitForExistence(timeout: 3))
    app.buttons["consent.terms"].tap()
    app.buttons["consent.privacy"].tap()
    app.buttons["onboarding.continue"].tap()

    XCTAssertTrue(app.otherElements["screen.onboarding.completion"].waitForExistence(timeout: 3))
    app.buttons["onboarding.go-to-today"].tap()
    XCTAssertTrue(app.otherElements["screen.hoje"].waitForExistence(timeout: 5))
}
```

The committed test must traverse every step and must not call a hidden completion shortcut.

- [ ] **Step 5: Run the new UI tests and verify RED**

Run each new UI test individually. Expected: missing identifiers or interaction behavior fails before UI fixes.

- [ ] **Step 6: Fix only observed accessibility and interaction defects**

Verify:

- every visible field has a label;
- errors are announced and linked to the field;
- persona/checkbox selection has selected traits and text;
- buttons are at least 44 points;
- keyboard Next/Done ordering works;
- no control is hidden behind the keyboard;
- Dynamic Type accessibility sizes wrap without overlap;
- Reduce Motion removes optional onboarding transitions.

- [ ] **Step 7: Run the complete test suite**

```bash
RESULT_BUNDLE="/tmp/BodyFlowAuthOnboarding-$(date +%Y%m%d%H%M%S).xcresult"
xcodebuild test -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" -resultBundlePath "$RESULT_BUNDLE"
```

Expected: all unit and UI tests pass with zero failures and zero ignored tests.

- [ ] **Step 8: Commit privacy and UI coverage**

```bash
git add apps/ios/BodyFlow/BodyFlow/Core/Telemetry apps/ios/BodyFlow/BodyFlow/Features apps/ios/BodyFlow/BodyFlowTests apps/ios/BodyFlow/BodyFlowUITests
git diff --cached --check
git commit -m "test(ios): verify auth onboarding journey"
```

---

### Task 8: Final Simulator Gate, Evidence And Draft PR

**Files:**

- Create: `docs/superpowers/evidence/2026-07-26-bodyflow-ios-auth-onboarding/README.md`
- Create curated PNG screenshots in the same directory.
- Modify source or tests only if this gate proves a defect; each fix receives its own RED test and commit.

**Interfaces:**

- Produces reproducible local evidence and a clean stacked branch ready for review.
- Creates a draft PR with base `codex/bodyflow-ios-scaffold-v1`; it performs no merge or deployment.

- [ ] **Step 1: Run static repository checks**

```bash
git diff --check codex/bodyflow-ios-scaffold-v1...HEAD
rg -n "https?://|service_role|sb_secret_|SUPABASE|Authorization: Bearer|WhatsApp|whatsapp" apps/ios/BodyFlow
rg -n "email|password|birth_date|height_cm|weight_kg|body_fat_percent|token|raw_error" apps/ios/BodyFlow/BodyFlow/Core/Telemetry
```

Expected:

- diff check exits 0;
- endpoint/secret/provider/channel search prints no source matches;
- sensitive telemetry search appears only in rejection/allowlist tests, never event construction.

- [ ] **Step 2: Build Debug and Release without signing**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -configuration Debug -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" CODE_SIGNING_ALLOWED=NO build
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -configuration Release -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO build
```

Expected: both builds succeed. Release UI exposes no development-confirmation command and the repository boundary rejects synthetic consent IDs.

- [ ] **Step 3: Run all tests from a fresh result bundle**

Create a new timestamped `RESULT_BUNDLE` path and run the full `xcodebuild test` command from Task 7. Use `xcresulttool` against that exact path to record test counts, failures and ignored tests. Do not reuse or delete a prior result bundle.

Expected: zero failures and zero ignored tests.

- [ ] **Step 4: Launch and inspect the complete journey**

Boot the approved iPhone 17 Pro simulator, install the Debug app and run the fresh-auth scenario. Inspect the accessibility tree and capture stable screenshots for:

1. sign-in;
2. body-data onboarding;
3. persona selection;
4. synthetic consent notice;
5. Today after completion;
6. Profile persona editor;
7. one accessibility Dynamic Type screen;
8. one dark-appearance screen.

Confirm every screenshot contains visible BodyFlow product identity, no overlap, no clipped command and no real user information.

- [ ] **Step 5: Write the evidence README**

Record:

- exact Xcode and Swift versions;
- simulator runtime and device ID;
- branch and full HEAD;
- exact build/test commands;
- unit/UI test counts and outcomes;
- screenshot filenames;
- static scan results;
- known limitation that Supabase/BFF and legal consent are not live;
- confirmation that no merge, deployment, migration, production, real account, email, secret, TestFlight or external provider was used.

- [ ] **Step 6: Commit evidence**

```bash
git add docs/superpowers/evidence/2026-07-26-bodyflow-ios-auth-onboarding
git diff --cached --check
git commit -m "docs(ios): capture auth onboarding evidence"
```

- [ ] **Step 7: Verify final branch state**

```bash
git status --short --branch
git log --oneline codex/bodyflow-ios-scaffold-v1..HEAD
git rev-list --count codex/bodyflow-ios-scaffold-v1..HEAD
```

Expected: worktree clean and only Prompt 12 commits appear above the scaffold branch.

- [ ] **Step 8: Push the reviewed branch**

```bash
git push -u origin codex/bodyflow-ios-auth-onboarding-v1
git rev-parse HEAD
git rev-parse origin/codex/bodyflow-ios-auth-onboarding-v1
```

Expected: local and remote HEADs are identical.

- [ ] **Step 9: Create a draft stacked PR**

```bash
gh pr create --draft \
  --base codex/bodyflow-ios-scaffold-v1 \
  --head codex/bodyflow-ios-auth-onboarding-v1 \
  --title "feat(ios): add BodyFlow auth and onboarding" \
  --body-file /tmp/bodyflow-ios-auth-onboarding-pr.md
```

The PR body must include scope, test counts, screenshots/evidence path, demo-only limitations, live-integration prerequisites and explicit confirmation that there was no deployment, migration or production change.

Expected: draft PR is open with the scaffold branch as its base and has no merge action.

---

## Final Acceptance Gate

Do not declare Prompt 12 complete until all statements are proven:

- The app launches through one explicit root state machine.
- Fresh demo users can sign up, simulate confirmed email, complete all seven onboarding steps and reach Today.
- Existing authenticated scaffold UI scenarios continue to pass.
- Demo progress restores after relaunch without storing passwords.
- Focus, Impulse and Zen are selectable and editable from Profile; no user-selectable balanced option exists.
- Objective and routine selections are captured without client-side health calculations.
- Country and IANA timezone are visibly confirmed and preserved for the later `/me` integration.
- Synthetic consent is visibly development-only and impossible to accept as valid in Release.
- Loading, validation, cancellation and recoverable errors are covered.
- Telemetry contains no email, password, body data, token, free text or raw error.
- Debug and Release builds pass on the approved toolchain.
- All unit and UI tests pass with zero failures and zero ignored tests.
- The worktree is clean, the branch is pushed and the draft PR targets only the scaffold branch.
- No live Supabase/BFF call, external provider, real account, email, migration, deployment, merge, production action or TestFlight upload occurred.
