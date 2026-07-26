# BodyFlow Native iOS Scaffold Design

**Status:** approved for implementation on 2026-07-26.

## Objective

Create the first native BodyFlow iOS application as a small, buildable SwiftUI
foundation. The scaffold must make navigation, dependency injection, previews,
tests and future feature ownership explicit without connecting to live services
or duplicating backend calculations.

This phase establishes the application shell used by the later Auth,
Onboarding, Today, Register, Plan, Progress, Content, Routine and Subscription
prompts. It does not attempt to complete those product flows.

## Approved Product Decisions

- Visible product name: `BodyFlow`.
- Xcode project, application target and shared scheme: `BodyFlow`.
- Bundle identifier: `com.bodyflow.app`.
- Minimum deployment target: iOS 18.0.
- Language and UI framework: Swift 6 and SwiftUI.
- App Store SDK baseline: Xcode 26 or newer for future distribution.
- Project location: `apps/ios/BodyFlow/BodyFlow.xcodeproj`.
- No external package, project generator or runtime dependency in this phase.

The Bundle ID is a technical identifier and does not alter the visible product
name. Apple Developer registration, availability, signing and provisioning are
deferred until the release phase and must happen before the first uploaded
build.

## Chosen Project Strategy

Commit a native `.xcodeproj` generated through the available Xcode tooling.
This is preferred over XcodeGen or Tuist because the initial project is small
and should open without installing another tool. It is preferred over a
SwiftPM-first app because asset catalogs, previews, signing and simulator
execution remain native Xcode concerns.

The project file must use deterministic groups, relative paths and a shared
scheme. Generated user data, DerivedData and local Xcode state are ignored.

## Project Structure

```text
apps/ios/BodyFlow/
  BodyFlow.xcodeproj/
  BodyFlow/
    BodyFlowApp.swift
    App/
      AppDependencies.swift
      AppRouter.swift
      AppShellView.swift
      AppTab.swift
    DesignSystem/
      BodyFlowColor.swift
      BodyFlowSpacing.swift
      BodyFlowTypography.swift
      Components/
        ScreenStateView.swift
    Core/
      Auth/
        AuthSessionProviding.swift
      Models/
        AppFixtures.swift
        TodaySummary.swift
      Networking/
        APIClient.swift
        APIRequest.swift
      Storage/
        SecureStoring.swift
      Telemetry/
        TelemetryClient.swift
    Features/
      Today/
      Register/
      Plan/
      Progress/
      Profile/
    Resources/
      Assets.xcassets/
  BodyFlowTests/
  BodyFlowUITests/
```

Only files that express real scaffold behavior are created. Empty directories
for later features are not committed.

## Application Architecture

### Dependency boundary

`AppDependencies` is an immutable value installed once in the SwiftUI
environment. It contains protocol-typed dependencies for API access, auth
session state, secure storage and telemetry. Feature-local state remains owned
by the feature and is passed explicitly rather than stored in a global service
locator.

Production-shaped protocols have deterministic in-memory implementations for
the scaffold. There is no real base URL, token, Keychain write, analytics SDK or
provider call. A missing dependency is a programmer error in tests and previews,
not an optional runtime branch hidden from the UI.

### Networking

The networking boundary models method, relative path and decoded response but
does not know a production host. Requests are asynchronous, cancellable and
`Sendable`. A mock client returns typed fixtures or controlled errors.

No calorie, macro, hydration, deficit or bloco formula exists in the app.
Fixture DTOs represent values already calculated by the backend.

### Authentication and secure storage

The initial auth protocol exposes only a mock session state needed to wire the
future root flow. The app launches into the tab shell in this phase. Login,
registration, recovery, token refresh and Keychain persistence belong to
Prompt 12.

The secure storage protocol and in-memory test implementation establish the
boundary without persisting secrets. No service-role credential, API token or
provider secret is present in source, assets, previews or test fixtures.

### Telemetry

Telemetry accepts controlled event names and non-sensitive scalar metadata.
The scaffold implementation records events in memory for tests. It does not log
body measurements, health values, free text, credentials or raw network data.

## Navigation

The app has five tabs in this stable order:

1. Hoje (`house`).
2. Registrar (`plus.circle`).
3. Plano (`list.clipboard`).
4. Progresso (`chart.line.uptrend.xyaxis`).
5. Perfil (`person.crop.circle`).

Each tab owns an independent `NavigationStack` and typed route path so switching
tabs preserves local history. Routes contain lightweight identifiers, never
view instances. Sheet presentation is enum-driven rather than represented by
multiple booleans.

The scaffold includes at least one deterministic child destination to prove
that navigation works without inventing a later feature workflow. Routes and
tabs have stable accessibility identifiers for UI smoke tests.

## Initial Screens

The first screen is the usable tab shell, not a landing page. Each root is a
quiet native operational surface backed by fixtures:

- Hoje: server-shaped daily summary, routine status and next action.
- Registrar: commands for meal, training, weight and hydration registration.
- Plano: a compact weekly plan summary.
- Progresso: a small set of server-provided progress values.
- Perfil: profile, coach preference and notification rows.

These screens prove composition and navigation only. Commands do not persist or
call a backend. They may present a deterministic mock destination or sheet so
the interaction is testable, but must not claim that a real registration was
saved.

## View State Model

Shared screen composition supports four explicit non-content states:

- loading;
- empty;
- recoverable error;
- offline.

Loaded content remains feature-owned. Error and offline views expose a clear
retry command whose closure is injected. Previews cover loaded and at least one
non-happy state without network, authentication or global singleton setup.

## BodyFlow Design Foundation

The scaffold centralizes the approved brand tokens:

- Teal Green `#006D67`;
- Warm Cream `#F6EFE3`;
- Charcoal `#222528`;
- Muted Coral `#FF7F6B`;
- Soft Gold `#D4AF7A`.

Semantic colors decide background, surface, primary text, secondary text,
accent, warning and achievement usage. Views do not repeat hexadecimal values.
The base shell supports light and dark appearances without becoming a one-color
theme.

SF Pro is the temporary system font because licensed Space Grotesk and Inter
font files are not available in the repository. Typography uses Dynamic Type
text styles and does not scale from viewport width.

SF Symbols provide temporary interface icons. No logo, mascot or final app icon
is recreated in code. The official visual assets remain a separate approved
asset task.

## Accessibility And Layout

- Dynamic Type must not clip tab labels, commands or state messages.
- Interactive controls use native controls and minimum 44-point hit areas.
- Icons have localized labels where their meaning is not already visible.
- Color is never the only state indicator.
- Layouts support compact and regular iPhone widths without overlap.
- Motion is minimal in the scaffold and respects Reduce Motion when later added.

## Testing Strategy

Behavior is implemented test-first where code is not generated. The initial
test targets prove:

- the five-tab order and stable identifiers;
- independent navigation paths per tab;
- typed mock API success and controlled failure;
- screen-state retry behavior;
- telemetry excludes unsupported metadata types;
- the app launches and all five tabs are reachable in the simulator.

Swift Testing is used for unit tests. XCTest UI testing is used for the launch
and tab smoke path. Previews are deterministic fixtures and are not substitutes
for automated tests.

## Build And Simulator Validation

The Xcode session is configured only after project generation. Validation uses
the shared `BodyFlow` scheme, Debug configuration and an available iPhone
simulator. The sequence is:

1. discover the generated project and available simulators;
2. set explicit Xcode session defaults;
3. build the application target;
4. run unit and UI tests;
5. build, install and launch the app;
6. inspect the accessibility tree and capture a screenshot;
7. navigate through every tab and verify the app remains responsive.

Simulator signing must not require an Apple Developer team. No archive,
TestFlight upload, App Store record or provider registration occurs.

## Error Handling And Privacy

- Async errors are converted into bounded user-facing states.
- Debug diagnostics use controlled error categories, not raw response bodies.
- No credential or secret is committed.
- No real patient fixture or personally identifiable value is used.
- No background job, provider integration or live API is invoked.

## Deliberately Out Of Scope

- real authentication, onboarding and personality persistence;
- live mobile API requests and refresh-token handling;
- Keychain implementation;
- real meal, training, weight, hydration or routine mutations;
- StoreKit, RevenueCat SDK, paywall or purchases;
- push registration and APNs token handling;
- final logo, mascot, app icon, custom font or visual QA prompt;
- signing, provisioning, archive, TestFlight and App Store submission;
- backend, database, migration, staging or production changes.

## Acceptance Criteria

- The native project exists at the approved path with Bundle ID
  `com.bodyflow.app` and iOS 18.0 deployment target.
- The shared `BodyFlow` scheme builds in Debug without external dependencies.
- The app launches in an iPhone simulator and visibly presents five tabs.
- Every tab has an independent navigation stack and reachable fixture content.
- Loading, empty, error and offline states are represented and previewable.
- Services are injected through protocols and mocks make the app usable without
  a backend.
- Unit and UI smoke tests pass.
- No secret, real user data, live call, signing action, deployment or external
  configuration is introduced.
