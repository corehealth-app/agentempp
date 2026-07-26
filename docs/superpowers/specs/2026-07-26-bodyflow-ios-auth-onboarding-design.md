# BodyFlow iOS Auth, Onboarding And Coach Persona Design

**Status:** approved for specification on 2026-07-26.

## Objective

Implement the first complete entry flow for the native BodyFlow iOS app:
splash, email/password authentication, password recovery, email-confirmation
guidance, onboarding, coach-persona selection and transition to the existing
Today tab shell.

This increment must be fully usable and testable without a live environment.
It establishes production-shaped boundaries for a later Supabase Auth and
mobile BFF integration, but it does not make network calls, create real
accounts, send email or persist data in staging or production.

## Evidence And Constraints

The existing scaffold provides:

- Swift 6 and SwiftUI with an iOS 18 deployment target;
- protocol-based dependencies for API, auth, secure storage and telemetry;
- a five-tab application shell with Today as its initial tab;
- deterministic mocks, previews, unit tests and UI smoke tests;
- no external Swift package or live endpoint.

The mobile backend already provides authenticated `GET /me`, `GET /profile`,
`POST /onboarding`, and `GET/PATCH /coach/persona` contracts. It requires a
confirmed Supabase Auth email and a bearer access token. The public staging BFF
base URL, mobile publishable key and native redirect URLs are not configured in
the iOS project.

Two backend gaps prevent claiming a production-complete onboarding flow:

- the current onboarding input does not persist the selected product objective
  (`recomposicao`, `ganho_massa` or `manutencao`);
- there is no general versioned Terms of Use or Privacy Policy acceptance
  contract for the patient onboarding flow.

The iOS implementation must not invent either server contract. Both are
explicit requirements of the later live-integration gate.

## Chosen Delivery Strategy

Use an offline-capable demo implementation behind production-shaped protocols.
The complete user journey works in Debug and tests, while the real Supabase and
BFF adapters remain a separate gated increment.

This strategy was selected over two alternatives:

1. Connecting live staging immediately would require a published BFF URL,
   Supabase mobile configuration, redirect allowlisting, email templates and
   the missing objective/consent contracts before UI behavior could be verified.
2. Building screens with view-local fake state would be faster initially, but
   would make navigation, error handling and later provider replacement
   disposable.

No Supabase Swift package is added in this increment. The live integration gate
will select and pin the provider dependency after its current API, changelog and
security behavior are reviewed against the staging configuration.

## Root Application State

The app root owns one observable session model. It exposes a finite set of
mutually exclusive states:

```text
launching
  -> signedOut
  -> awaitingEmailConfirmation
  -> onboarding(step)
  -> authenticated
```

Restoring an authenticated demo session with incomplete onboarding enters the
saved onboarding step. Restoring a completed session opens the existing tab
shell on Today. Signing out clears the session and returns to `signedOut`.

Navigation inside authentication and onboarding is derived from this state.
Views do not independently decide whether the user is signed in or whether
onboarding is complete.

## Service Boundaries

### Authentication

`AuthenticationService` owns:

- restoring an existing session;
- signing in with email and password;
- creating an email/password account;
- representing the pending email-confirmation state;
- requesting password recovery;
- signing out.

The deterministic demo adapter accepts bounded fixture credentials and can be
configured for success, delay or a typed failure. It never stores a password.
The production adapter will later wrap Supabase Auth without leaking provider
types into feature views.

### Onboarding

`OnboardingRepository` owns loading, saving and completing an
`OnboardingDraft`. It does not calculate calories, macros, targets, protocols or
health outcomes. Those values remain backend responsibilities.

The draft contains only the fields represented by the screens:

- display name;
- biological sex used by the existing calculation contract;
- birth date;
- height, weight and optional body-fat percentage;
- product objective;
- activity level and weekly training frequency;
- water intake, hunger level, wake time, bedtime and food organization;
- selected coach persona;
- development-consent acknowledgements.

The product-objective values mirror the existing domain vocabulary:

- body recomposition;
- muscle gain;
- maintenance.

The later BFF gate must add an explicit server mapping before these values are
sent over the network.

### Coach Persona

`CoachPersonaRepository` exposes the three selectable public values:

- `focus`: direct, firm, objective and respectful;
- `impulse`: motivating, positive and energetic without infantilization;
- `zen`: calm, explanatory and welcoming without judgment.

`balanced` remains an internal backend fallback and is never presented as an
option. Selection is required before onboarding completion and can be changed
later from Profile through the same repository boundary.

### Local Storage

`KeychainSecureStore` implements the existing `SecureStoring` protocol using
the Security framework. The demo session and compact onboarding draft may be
encoded into Keychain so the flow survives relaunch during development.

Passwords, free-form notes and raw telemetry are never stored. Signing out
removes the demo session. A reset command used only by tests and Debug fixtures
clears the draft and selected persona deterministically.

The real integration will use the provider's supported session persistence
strategy after review. The demo session format is not treated as a production
token format.

## Screens And User Flow

### Splash

Splash displays the BodyFlow wordmark as text using the existing design tokens
while local state is restored. It has no artificial timer. Success immediately
routes to the correct state; failure safely routes to sign-in with a recoverable
message.

No final logo, mascot animation or branded launch asset is introduced in this
increment.

### Sign In

The sign-in screen provides email and password fields, a primary sign-in
command, and commands for account creation and password recovery. It uses
content types and submit labels appropriate for iOS password managers.

Local validation checks only structural requirements such as non-empty input
and a plausibly formatted email. It does not invent a final server password
policy. Authentication errors use bounded user-facing categories and do not
disclose whether an email is registered.

### Sign Up

Sign-up collects email, password and password confirmation. The two passwords
must match. Successful demo registration transitions to an
email-confirmation guidance screen rather than silently authenticating the
patient.

### Email Confirmation

The demo confirmation screen explains that the email must be confirmed before
profile creation. A deterministic Debug action simulates returning from a
confirmed email link. The action is clearly isolated in the mock service and is
not part of the future production UI contract.

Native deep-link handling is deferred until redirect URLs are configured in
Supabase staging. The real implementation must handle both confirmation and
password-recovery callbacks.

### Password Recovery

Recovery accepts an email and always shows a neutral completion message after a
successful request. The wording does not reveal whether the account exists.
The demo service records no email and sends no message.

### Onboarding Container

Onboarding uses one stable container with a compact progress indicator, Back
where permitted, and one primary Continue command. Each step owns focused local
form state and writes a validated value into the shared draft before advancing.

The ordered steps are:

1. welcome and display name;
2. body data;
3. objective;
4. routine;
5. coach persona;
6. development consent;
7. completion.

The user can move backward without losing entered values. Completion is one
idempotent repository operation; repeated taps cannot create multiple sessions
or transitions.

### Body Data

The form follows current server bounds for date, height, weight and optional
body-fat percentage. Numeric entry uses appropriate keyboards and unit labels.
The UI explains only that the values support personalization; it does not claim
diagnosis or guaranteed results.

### Objective

The three product objectives are displayed in a native single-selection list.
Supporting text is short, neutral and does not promise a physiological result.

### Routine

Routine collects the existing backend-compatible activity, training, water,
hunger, wake-time, bedtime and food-organization fields. Binary choices use
toggles or radio-style selection; numeric frequency uses a stepper or picker;
times use native time pickers.

### Persona

Each persona option includes its name and one short behavioral description.
Selection is explicit and uses a native single-selection control. The screen
does not imply that persona changes calculations or medical guidance.

### Development Consent

The repository has no approved legal documents. Therefore Debug and automated
tests use synthetic, versioned development documents that are explicitly not a
legal acceptance. The completion state stores only their technical IDs and
timestamps.

A Release build must not complete onboarding with development document IDs. The
live-integration gate must provide approved versioned documents, content URLs
or bodies, and a server-side acceptance endpoint before TestFlight.

### Profile Persona Editing

The existing Profile fixture gains a reachable persona editor. A successful
change updates the repository and reflected selection. Failure leaves the prior
selection intact and presents a retry path.

## View State And Validation

Every asynchronous screen exposes explicit idle, loading, success and
recoverable-error behavior. Only one submission can be in flight. Cancellation
when a view disappears must not produce a late navigation transition.

Validation errors are attached to the relevant field and summarized for VoiceOver
when submission is attempted. Server-shaped errors remain typed at the service
boundary and are mapped to localized presentation messages.

No view catches an error and proceeds as if persistence succeeded.

## Privacy And Telemetry

Allowed telemetry is limited to controlled event names and non-sensitive state:

- auth screen viewed;
- auth operation succeeded or failed by bounded category;
- onboarding step viewed or completed by step identifier;
- persona selected by public code;
- onboarding completed;
- sign-out completed.

Telemetry must never include email, password, birth date, measurements,
free-form input, provider tokens or raw error bodies. UI tests and previews use
synthetic identities only.

## Accessibility And Visual Scope

- All fields have visible labels and stable accessibility identifiers.
- Validation, selection and progress are not communicated by color alone.
- Dynamic Type must not clip commands or option descriptions.
- Keyboard focus and submit behavior follow the form order.
- Interactive targets remain at least 44 points.
- Reduce Motion removes any optional transition animation.
- Current scaffold colors and typography remain the temporary foundation.

Final logo, mascot, custom fonts, animation language and full visual-polish work
remain assigned to the later visual prompts. This phase creates functional,
quiet native UI without preempting that identity work.

## Testing Strategy

Behavior is implemented test-first on the Mac Xcode environment.

Unit and component tests cover:

- every root state transition;
- session restoration, sign-in, sign-up, confirmation, recovery and sign-out;
- password mismatch and structural email validation;
- deterministic loading and typed failure behavior;
- onboarding step order, back navigation and draft preservation;
- field bounds matching the existing mobile contract;
- objective and persona selection;
- idempotent onboarding completion;
- Keychain store, load and removal behavior;
- persona changes from Profile;
- telemetry privacy allowlisting;
- Release rejection of development consent documents.

UI tests cover:

- launch into sign-in with a fresh demo state;
- sign-up through simulated email confirmation;
- complete onboarding through all steps;
- arrival on Today after completion;
- relaunch restoration into the authenticated shell;
- changing persona from Profile;
- recovery success and one representative recoverable error.

Every screen receives deterministic previews for its normal state and at least
one loading, validation or recoverable-error state where applicable.

## Live Integration Gate

The app is not production-authenticated until all of the following are approved
and verified:

1. publish the staging mobile BFF and record its HTTPS base URL;
2. obtain the staging Supabase URL and mobile publishable key without exposing a
   secret or `service_role` value;
3. select and pin the current official Supabase Swift Auth dependency;
4. configure an environment-specific native URL scheme or universal link;
5. allowlist confirmation and recovery redirect URLs in Supabase staging;
6. configure staging email templates and a non-production email delivery path;
7. add the missing objective persistence contract;
8. add approved versioned legal documents and auditable consent persistence;
9. implement bearer-token injection and refresh behavior for the mobile BFF;
10. run account creation, confirmation, recovery, onboarding and persona tests
    against synthetic staging identities only;
11. verify Keychain behavior, logout revocation expectations and error mapping;
12. complete security review before any TestFlight build.

## Deliberately Out Of Scope

- live Supabase Auth or BFF calls;
- adding a Supabase Swift package;
- staging or production configuration changes;
- database migrations or legal-content authoring;
- real email delivery or deep-link callbacks;
- Apple Sign In, social login, passkeys or biometrics;
- final logo, mascot, custom font, animation system or app icon;
- nutrition, meal, training or daily-state implementation;
- StoreKit, RevenueCat, APNs, TestFlight, deployment or merge;
- any architecture tied to a legacy messaging channel.

## Acceptance Criteria

- A fresh app launch reaches the sign-in flow after splash restoration.
- Demo sign-in, sign-up, email confirmation and recovery have loading, success
  and recoverable-error states.
- A new demo user can complete every onboarding screen and reach Today.
- Onboarding progress survives a development relaunch without storing a
  password or logging health values.
- Focus, Impulse and Zen are selectable; `balanced` is not user-selectable.
- The selected persona can be changed from Profile.
- Root navigation is driven by one explicit application state model.
- Unit, UI and preview coverage described above is present and passing in Xcode.
- Release configuration cannot treat synthetic development consent as legally
  valid.
- No live call, real account, secret, production change, deployment, migration,
  merge or TestFlight action occurs.
