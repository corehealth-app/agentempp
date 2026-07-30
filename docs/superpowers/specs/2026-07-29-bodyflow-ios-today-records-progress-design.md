# BodyFlow iOS Today, Records And Progress Design

**Status:** approved.

## Objective

Implement the first complete native iOS experience for daily state, patient
records and progress:

- Today;
- meal detection, proposal, editing and confirmation;
- workout proposal and confirmation;
- weight and hydration recording;
- supplement and medication adherence;
- Plan;
- Progress and the persisted 7,700 kcal block;
- confirmed meal and workout History.

The implementation uses Swift 6, SwiftUI and an iOS 18 deployment target. It
must be fully testable with deterministic adapters without connecting a live
Supabase project or mobile BFF.

The iOS app is a presenter and command client. It must not calculate official
calories, macros, targets, hydration progress, net balance, streak, level or
7,700 kcal block credit. Official values are accepted only as complete
server-shaped responses.

## Evidence And Constraints

The existing app provides:

- five independent tab navigation stacks for Today, Register, Plan, Progress
  and Profile;
- SwiftUI design tokens, reusable cards, screen-state components and stable
  accessibility identifiers;
- protocol-based dependency injection through `AppDependencies`;
- `@MainActor @Observable` view-model patterns with typed asynchronous states;
- deterministic Debug authentication and onboarding;
- a Release runtime mode that rejects unavailable demo operations;
- 194 logical tests and 213 successful test executions on the starting commit.

The existing mobile BFF documents:

- `GET /api/mobile/v1/today` as the official versioned daily state;
- `POST /registrations/propose`, `PATCH /registrations/:id`,
  `POST /registrations/:id/confirm` and `DELETE /registrations/:id`;
- the private media lifecycle for future photo and audio processing;
- `POST /routine/hydration`;
- supplement and medication list, exact-occurrence log and opaque-cursor
  history contracts;
- `GET /plan`;
- `GET /progress`;
- `GET /history`, returning independent confirmed meal and workout arrays.

Important contract gaps remain:

- no mobile BFF mutation exists for a weight check-in;
- no common mobile endpoint accepts raw text, photo or audio and returns a
  structured meal draft;
- the sanitized pending proposal and `GET /history` do not expose per-item
  nutrition provenance;
- each element of `GET /history.data.meals` is one individual `meal_logs` row
  identified only by its row `id`; the response has no `meal_id` or another
  shared meal-occurrence identifier;
- no endpoint edits an already confirmed meal;
- `GET /history` does not return a trustworthy next cursor for its two
  independently limited arrays;
- the nutrition prescription payload in `GET /plan` is opaque.

The iOS implementation must not fill these gaps with presumed paths, provider
SDKs, local parsers or local business formulas.

## Chosen Delivery Strategy

Use small capability protocols backed in Debug by one shared deterministic
actor. The actor maintains coherent, complete response snapshots and an
idempotency replay ledger. Mutations move the actor between pre-authored
snapshots; they never derive a new official number from existing values.

This strategy was selected over two alternatives:

1. One view-facing repository for the complete app would initially require
   fewer types, but it would couple Today, registration, routine, Plan,
   Progress and History behavior.
2. An offline-first event store and synchronization queue would require
   persistence, conflict resolution and live mutation contracts that are not
   approved for this increment.

Capability protocols remain stable when a future BFF adapter is introduced.
The deterministic actor is a test and development implementation, not a
production data source.

## Execution Boundary

All mock-only behavior is limited to:

- Debug application builds;
- SwiftUI previews;
- unit tests;
- UI tests.

The Debug graph may construct `DemoBodyFlowRepository`, pre-authored snapshots
and deterministic meal-detection fixtures. These implementations are compiled
or instantiated only under the Debug/test boundary.

A Release graph must instead install unavailable adapters for every new
capability. Reads and mutations return the typed
`operationUnavailable` result. The UI maps that result to:

> Indisponível nesta versão

Release must not:

- return a deterministic Today, Plan, Progress or History fixture;
- claim that a meal, workout, weight, hydration or routine action was saved;
- return a locally detected meal proposal;
- advance a pending registration;
- update a routine occurrence;
- display a successful demo receipt;
- honor Debug or UI-test launch arguments.

This boundary is enforced at both launch-configuration and service levels.
Hiding a button alone is insufficient. Unit tests must prove that resolving a
Release configuration with Debug or UI-test arguments still installs
unavailable behavior.

## Architecture

### Contract Models

`Decodable`, `Sendable` and `Equatable` models mirror only current mobile
contract fields:

- `TodayResponse`;
- `RegistrationProposalRequest` and `RegistrationProposalResponse`;
- `PlanResponse`;
- `ProgressResponse`;
- `HistoryResponse`;
- `HistoryMealLogRow`;
- `RoutineListResponse`;
- `RoutineHistoryPage`.

Snake-case wire names use explicit coding keys. Nullable contract fields remain
optional and are never defaulted to zero. Unknown additive response fields are
ignored safely by decoding.

App-facing request models never accept client-calculated meal macros, totals,
workout calories, hydration percentages or block values.

### Capability Protocols

The dependency graph exposes small protocols:

- `TodayProviding`;
- `MealDetectionProviding`;
- `RegistrationProviding`;
- `HydrationRecording`;
- `WeightRecording`;
- `RoutineProviding`;
- `PlanProviding`;
- `ProgressProviding`;
- `HistoryProviding`;
- `TimeProviding`;
- `IdempotencyKeyProviding`.

`MealDetectionProviding` and `WeightRecording` are explicitly mock-only in this
increment. They have no path constant, `APIRequest` mapping or live adapter.

The other protocols reflect documented BFF capabilities without configuring a
base URL, bearer token or real network transport.

### Time Source

`TimeProviding` is an injectable `Sendable` source of the current instant.
Feature logic does not call `Date()` directly for:

- initial form dates and times;
- default `occurred_at` values;
- routine occurrence actions;
- snooze preset calculation;
- idempotent mutation-attempt creation times.

Debug, previews and tests use a fixed deterministic source. A future live
adapter may use a system-backed source, but server validation remains
authoritative for accepted timestamps. Official Today dates, response update
times and persisted event times always come from response contracts rather
than the injected client clock.

### Deterministic Repository

`DemoBodyFlowRepository` is an actor that may implement several capability
protocols while callers depend only on the narrow protocol they need.

It owns:

- complete pre-authored Today, Plan, Progress, History and routine responses;
- complete pre-authored pending meal and workout proposals;
- deterministic loading, empty, offline and recoverable-error scenarios;
- an idempotency ledger keyed by operation key and payload identity;
- controlled transitions between complete response snapshots.

The actor does not:

- sum meal or workout values;
- add hydration amounts to a prior total;
- calculate percentages;
- calculate remaining food or net balance;
- calculate a weight trend;
- calculate XP, streak or block credit;
- interpret opaque nutrition prescription payloads.

### View Models

Feature view models are `@MainActor @Observable` and receive capability
protocols through initializers. The immutable dependency graph remains in the
SwiftUI environment; mutable official data does not.

Each view model owns only:

- a typed read state;
- a separate mutation state;
- form drafts or the current server-shaped proposal;
- the current in-flight task identity;
- a retained idempotent mutation attempt when retry is allowed.

Late task completion after cancellation or replacement must not publish state
or navigate.

### Refresh And Invalidation

Successful commands explicitly invalidate affected reads:

- meal or workout proposal creation invalidates Today;
- meal or workout proposal editing invalidates Today;
- meal or workout proposal cancellation invalidates Today;
- meal or workout confirmation invalidates Today and main History;
- hydration invalidates Today;
- a routine action invalidates Today, its routine list and its detail history;
- a Debug-only weight receipt does not invalidate or alter Today, Progress,
  History or block state.

Invalidation carries only revision signals. It never carries or patches
official values. A refreshed screen reads a complete response from its
provider. No successful command corrects, increments, groups or otherwise
changes an official value locally while the refresh is pending.

## Navigation

The five existing tabs and their order remain unchanged. Each retains its
independent `NavigationStack`.

The generic detail route evolves into typed destinations for:

- a pending registration;
- an individual confirmed `meal_logs` row detail;
- a confirmed workout-log read-only detail;
- the main History screen;
- a routine list;
- a supplement or medication detail;
- a routine-item history;
- Plan detail;
- the 7,700 kcal block detail.

The existing item-driven registration sheet remains the entry point for meal,
workout, weight and hydration flows. The sheet owns an internal navigation
stack so multi-step proposals do not pollute a tab path.

Routes and sheets carry only lightweight identifiers and types. They do not
carry complete mutable response snapshots.

## Today

### Source Of Truth

`TodayProviding` returns the complete equivalent of
`GET /api/mobile/v1/today`. It is the only source for:

- targets;
- consumed totals;
- remaining food;
- food excess;
- exercise;
- net daily balance;
- protein status;
- confirmed meals and workouts;
- hydration;
- supplement and medication occurrences;
- pending actions;
- completion status;
- the persisted 7,700 kcal block;
- calculation version and source metadata.

The UI may format dates, units and signed values. It must not derive one
official field from another.

### Information Hierarchy

Today presents:

1. local date, protocol and snapshot update time;
2. pending proposals and routine actions requiring attention;
3. the daily energy section;
4. protein;
5. confirmed meals;
6. confirmed workouts;
7. hydration;
8. supplement and medication occurrences;
9. a compact 7,700 kcal block card;
10. navigation to main History.

Confirmed meal rows are displayed individually as supplied by Today. The UI
does not infer an aggregate meal from a shared time or `meal_type`.

The energy section visually separates:

- `remaining_food_kcal`, labelled as food remaining and explicitly excluding
  exercise;
- `daily_balance_kcal`, labelled as net balance and explicitly including
  exercise.

The signed net value is displayed as received. The app does not recompute it or
apply an absolute-value transformation.

### Incomplete And Unavailable Data

`completion_status.status=insufficient_data` is loaded content, not an error.
The UI uses neutral language:

> Dados insuficientes para fechar o dia

It must not imply failure, punishment or insufficient effort.

An unavailable target, hydration goal, routine collection or block is
displayed as unavailable. Missing data never becomes zero, a completed state or
an empty progress bar.

## Meal Registration

### Detection Sources

The flow offers Text, Photo and Audio.

In this increment all three sources use `MealDetectionProviding` with a
deterministic Debug implementation:

- Text accepts a bounded description but is not parsed by an iOS nutrition
  algorithm.
- Photo uses a labelled local demonstration sample. It does not open Photos or
  Camera, request permission or upload bytes.
- Audio uses a labelled local demonstration sample. It does not request
  microphone permission, record sound, transcribe or upload bytes.

The Debug detector selects a complete pre-authored draft by launch scenario and
source kind. It does not interpret the entered text or media content.

Every source produces a structured draft before `RegistrationProviding`
creates a pending proposal. No capture source can confirm or save a meal
directly.

The Release implementation fails closed with `operationUnavailable`.

### Proposal And Confirmation

The proposal lifecycle is:

```text
source
  -> detected structured draft
  -> pending proposal
  -> optional pending edit
  -> explicit confirmation or cancellation
```

The proposal screen displays:

- meal type and time;
- items and quantities;
- server-shaped calorie and macro values;
- totals from the proposal response;
- warnings returned by the provider;
- pending expiration;
- explicit proposal, edit, confirm and cancel states.

The app never sends edited macros or totals. Editing permits only fields the
current proposal request accepts:

- food name;
- quantity;
- optional kcal explicitly supplied by the patient;
- meal type and consumed time where supported.

Saving an edit replaces the complete proposal with the returned response. It
does not patch displayed totals locally.

Confirmation writes the pending registration. Cancellation cancels an open
pending. A confirmed meal is read-only because the mobile contract has no
confirmed-meal edit endpoint.

Confirmed meal navigation opens only an individual meal-log row. The screen
must not present the row as a complete meal or combine sibling rows that happen
to share a time or `meal_type`.

### Nutrition Provenance

Registration lifecycle and nutrition provenance are separate concepts:

- a pending proposal is not yet a confirmed record;
- a confirmed record is not automatically a confirmed nutrition reference.

The sanitized pending response exposes warnings but no stable per-item
`nutrition_source`. The proposal displays provider warnings and never infers a
confirmed reference from the absence of a warning.

Today may receive `nutrition_source` for confirmed meal rows. Its presentation
mapping is deliberately conservative:

- `canonical_exact` and `product_label` are shown as confirmed references;
- `llm_estimate`, `category_mismatch`, `protein_mismatch` and
  `composite_rejected` are shown as estimates;
- `user_kcal` and `user_correction` are shown as patient-provided;
- every nil, unfamiliar or future value is shown as origin not informed.

Main History does not display provenance because its current response does not
include it.

## Workout Registration

Workout entry collects:

- workout type;
- duration;
- intensity;
- performed time.

The request creates a pending proposal. Estimated workout calories are
displayed only from the proposal response. The iOS app does not use weight,
duration or intensity to estimate calories.

The user may edit the open pending, confirm it or cancel it. Confirmation
invalidates Today and main History. Confirmed workouts are read-only.

## Weight Recording

There is no current mobile weight-mutation endpoint.

`WeightRecording` therefore represents an app capability rather than a BFF
route. Its command contains a weight, recorded time and idempotency key, but it
is not a `Codable` transport DTO and has no route mapping.

Debug and tests may return a clearly labelled local demonstration receipt. The
receipt:

- is idempotent;
- does not claim BFF synchronization;
- does not add a main History entry;
- does not alter Today, Progress or the 7,700 kcal block;
- does not become production persistence.

Release always returns `operationUnavailable`, and the UI displays
“Indisponível nesta versão” instead of a success state.

A future live implementation requires a documented BFF command and response
before an adapter is added.

## Hydration

Hydration accepts a controlled quick amount or a validated custom amount and an
occurrence time. It maps conceptually to the documented
`POST /routine/hydration` capability and requires an idempotency key.

The Debug adapter returns a complete pre-authored response state. It does not
increment a prior value. Successful Debug submission invalidates Today and
reloads the complete official-shaped snapshot.

When no hydration target exists, Today shows tracked-without-target semantics.
It does not calculate a percentage or remaining amount.

Release has no real persistence adapter and therefore returns
`operationUnavailable`.

## Supplements And Medications

This increment supports:

- Today occurrences;
- active supplement and medication lists;
- item detail;
- schedules;
- exact-occurrence actions;
- item-specific history.

Supported occurrence actions are the documented `taken`, `snoozed` and
`skipped` transitions. Commands include the exact reminder-rule identifier,
scheduled time and occurrence time required by the contract. The app does not
construct or expose an internal occurrence key.

For `snoozed`, `snoozed_until` is mandatory. It must be later than
`occurred_at` and must remain on the same local date as the original occurrence.
The snooze UI provides:

- 15 minutes;
- 30 minutes;
- 60 minutes;
- a custom local time.

The action's default `occurred_at` comes from `TimeProviding`. Presets add 15,
30 or 60 minutes to that `occurred_at` and use the patient's IANA timezone to
check the date boundary. A preset that would cross the original occurrence's
local-date boundary is unavailable; the client does not silently clamp it. A
custom value is limited to the same local date, and the provider still
validates the final timestamp. For `taken` and `skipped`, `snoozed_until` is
absent.

Terminal or invalid transitions remain disabled or produce a typed recoverable
error. A version or transition conflict triggers a reload; the app never
silently overwrites the server-shaped state.

Item detail history uses the documented opaque `next_cursor`. The iOS app may
request another page with that exact token. It must not parse, derive or modify
the token.

Full supplement and medication CRUD, schedule management and medication legal
acceptance are outside this prompt. The UI offers no clinical recommendation,
dose interpretation or inferred prescription.

Release routine actions are unavailable and never display a simulated
successful adherence state.

## Plan

Plan renders only stable fields returned by `GET /plan`:

- active training plan type;
- days per week;
- equipment summary;
- generated and valid-until dates;
- version;
- notes;
- nutrition prescription type, dates, version and notes.

The app does not derive planned or completed session counts from Today or
History. It does not parse or interpret an opaque nutrition prescription
payload.

No active plan is a feature-specific empty state. An unavailable Release
adapter presents “Indisponível nesta versão” rather than a demo plan.

## Progress And The 7,700 Kcal Block

Progress renders values received from `GET /progress`:

- total XP and level;
- current and longest streak;
- completed block count;
- current weight and body-fat percentage;
- earned badges;
- last active date;
- next reevaluation;
- update time.

The detailed 7,700 kcal block uses only `block_7700` from Today, including its
provided target, current value, percentage, completed block count, credited
total, availability and source.

The app does not:

- reconstruct the block from `ProgressResponse.deficit_block`;
- project credit from an open day;
- calculate a percentage;
- treat missing progress as zero.

Unavailable block data produces an unavailable state with no empty ring or
zero-value implication.

## Main History

Main History consumes only the first bounded response from
`GET /api/mobile/v1/history`.

Each screen load or retry makes one conceptual request with:

- `before=nil`;
- `limit=30`, matching the documented default bound.

The response remains:

- a meal-log row array;
- a workout array;
- the returned pagination metadata.

Every element of the meal array represents exactly one `meal_logs` row with its
own `id`, `meal_type`, food values and `consumed_at`. The response does not
contain `meal_id`. Rows with the same `consumed_at` or `meal_type` remain
separate and preserve response order.

The iOS app does not:

- derive `next_before`;
- infer a cursor from the oldest timestamp;
- request a second page;
- implement “Load more”;
- merge the arrays into a transport feed;
- group meal-log rows by `consumed_at`, `meal_type` or another heuristic;
- synthesize a meal identifier;
- add weight, hydration, supplement or medication entries.

The screen presents exactly two sections, Meal records and Workouts. Each
meal-record row may open a read-only detail for that individual `meal_logs`
row. It never opens an aggregated meal detail. One section may be empty while
the other has content. The global empty state appears only when both arrays are
empty.

The presentation layer is structured so another real section can be added
later, but it constructs no future section, endpoint or placeholder data.

Reliable main-History pagination is explicitly deferred to backend work. The
BFF must first return a trustworthy shared cursor or independent documented
cursors before iOS pagination is designed.

An aggregated meal presentation is also deferred to backend work. It requires a
documented meal-occurrence identifier, such as `meal_id`, and explicit grouping
semantics before iOS can combine food rows.

This restriction does not apply to supplement and medication detail histories,
which already provide documented opaque `next_cursor` values.

## State And Recovery

Read state is represented as a mutually exclusive generic state:

```text
idle
loading
loaded(value)
empty
offline(previousValue?)
failed(previousValue?, recoverableError)
unavailable
```

Mutation state is separate:

```text
idle
submitting(attempt)
succeeded(receipt)
failed(attempt, recoverableError)
unavailable
```

Behavioral rules:

- initial offline state presents a full offline screen with Retry;
- offline after content preserves the content and adds a stale-data banner;
- read Retry starts a new fetch;
- mutation Retry reuses the retained attempt and idempotency key;
- a failed mutation preserves the draft or pending proposal;
- task cancellation is not shown as a user-visible error;
- expired or no-longer-pending registration errors discard only the invalid
  pending and offer a new proposal;
- `operationUnavailable` maps to the Release unavailable state, not a generic
  retry loop.

## Idempotency

Every mutation attempt owns:

- a validated key of 8 to 128 allowed characters;
- an immutable payload identity;
- the operation kind;
- the attempt creation time supplied by `TimeProviding`.

Rules:

- one user intention creates one key;
- retry of the same immutable attempt reuses the key;
- changing the payload creates a new intention and key;
- double submission is disabled while an attempt is in flight;
- a key reused with a different payload produces a conflict;
- proposal creation, confirmation, edit, cancellation, weight, hydration and
  routine actions each have independent keys.

The deterministic repository replay ledger returns the same pre-authored result
for the same key and payload. It never applies a mutation twice.

## Privacy And Telemetry

Telemetry uses controlled event names and bounded metadata only:

- screen identifier;
- registration kind;
- meal capture source enum;
- operation outcome;
- bounded error category;
- calculation-version string where available.

Telemetry must not contain:

- meal text or food names;
- image or audio data;
- weight or body-fat values;
- supplement or medication names or doses;
- signed URLs, provider identifiers or raw response bodies;
- user IDs or idempotency keys.

Debug photo and audio samples contain no patient data. No captured media is
stored because this increment does not perform real capture.

## Accessibility And Visual Behavior

- Existing semantic colors, typography and spacing remain the foundation.
- Every control has a visible label and a stable accessibility identifier.
- Interactive targets remain at least 44 points.
- Status always has text or an icon; color is never the only indicator.
- Energy, protein, hydration and block values expose descriptive
  accessibility values from the response.
- Food remaining explicitly announces that exercise is excluded.
- Net balance explicitly announces that exercise is included.
- At accessibility Dynamic Type sizes, metric rows and action grids stack
  vertically without fixed text heights.
- Dark Mode uses semantic tokens only.
- Reduce Motion removes non-essential number, bar and navigation animation.
- Error and success summaries receive accessibility focus after submission.

Deterministic previews cover loaded, loading, empty, offline, recoverable error,
incomplete day, unavailable, Dark Mode and accessibility XXXL states.

## Testing Strategy

Implementation follows TDD. Each behavior starts with a focused failing test,
the failure is observed, and only then is production code added.

Unit and component tests cover:

- exact contract decoding and nullable fields;
- Release launch arguments failing closed;
- Release dependency graphs containing no successful demo behavior;
- unavailable Release reads, detection and mutations;
- fixed `TimeProviding` defaults for forms, occurrences, snooze choices and
  idempotent attempts;
- complete pre-authored snapshot transitions;
- deliberately inconsistent Today values proving the iOS app does not
  recalculate official fields;
- separation of food remaining and signed net balance;
- insufficient data as content rather than error;
- conservative nutrition provenance and unknown fallback;
- mandatory proposal before meal or workout confirmation;
- Text, Photo and Audio reaching a proposal without direct persistence;
- pending meal editing replacing the complete response;
- confirmed meal and workout read-only behavior;
- idempotency-key preservation on retry;
- idempotency payload conflict;
- failed mutations preserving draft and pending state;
- proposal creation, editing and cancellation invalidating Today;
- confirmation invalidating Today and main History;
- invalidation never patching an official value locally;
- hydration refresh without client-side incrementing;
- weight having no path or transport adapter;
- exact routine occurrence actions and opaque routine-history cursors;
- `snoozed_until` required only for snooze;
- 15, 30 and 60 minute snooze presets plus a custom same-local-date time;
- rejection of snooze values that cross the original local date;
- Plan leaving opaque nutrition payloads uninterpreted;
- unavailable block values remaining unavailable;
- main History making only one `before=nil, limit=30` request;
- absence of main-History next-page behavior;
- one History meal row per response `meal_logs` row;
- preservation of separate meal rows with matching time or `meal_type`;
- individual meal-log detail with no synthesized `meal_id`;
- main History containing only confirmed meal and workout sections.

UI tests cover:

- the five existing tabs and independent navigation;
- Today content and separate food-remaining/net-balance cards;
- incomplete, loading, empty, offline, recoverable-error and Retry states;
- Text meal to proposal, edit and confirmation;
- Photo and Audio demonstration sources reaching a proposal;
- workout to proposal and confirmation;
- Debug weight and hydration flows;
- supplement and medication occurrence actions and item histories;
- snooze presets, custom time and same-local-date validation;
- Plan;
- Progress and 7,700 kcal block detail;
- main History with only individual Meal records and Workouts, no grouping and
  no Load more command;
- read-only detail for one individual meal-log row;
- Release/unavailable presentation through configuration-level tests;
- Dynamic Type accessibility layout;
- Dark Mode;
- Reduce Motion.

The final gate runs the complete unit and UI suite, Debug build, Release build,
`git diff --check`, simulator launch and visual inspection on the iPhone 17 Pro
with iOS 26.5.

## Evidence

Final evidence is stored under:

`docs/superpowers/evidence/2026-07-29-bodyflow-ios-today-records-progress/`

It includes:

- an evidence README with commands, hashes and results;
- Today;
- meal proposal and edit;
- individual meal-log detail;
- workout proposal;
- hydration and routine;
- Plan;
- Progress and block detail;
- main History;
- offline/error Retry;
- Dark Mode;
- accessibility XXXL;
- Reduce Motion verification;
- the final simulator launch.

Evidence uses synthetic Debug data only.

## Future Backend Work

The following work requires an approved backend contract before iOS changes:

- a versioned weight-recording mutation;
- a structured raw text/photo/audio-to-meal-draft contract;
- stable per-item nutrition provenance in pending proposals and History;
- editing confirmed meal or workout logs;
- an explicit meal-occurrence identifier and grouping semantics for aggregated
  meal History;
- reliable main-History pagination with a shared cursor or independent cursors;
- a typed nutrition prescription payload;
- a live environment base URL and authenticated mobile transport.

Future work must be additive and must not repurpose the main History contract or
infer server state locally.

## Deliberately Out Of Scope

- live Supabase or BFF integration;
- real endpoint, bearer-token or base-URL configuration;
- a real text parser, Vision, speech-to-text, photo picker, camera or audio
  recorder;
- local nutrition, workout, hydration, progress or block formulas;
- optimistic patching of official values;
- main-History pagination or Load more;
- aggregated meal History without a backend `meal_id` contract;
- weight, hydration or routine entries in main History;
- editing a confirmed meal or workout;
- supplement or medication CRUD and medication legal acceptance;
- clinical recommendation, dose interpretation or inferred prescription;
- offline mutation queues or background synchronization;
- external provider SDKs, secrets or production persistence;
- WhatsApp or another legacy messaging-channel architecture;
- migrations, deployment, merge, TestFlight or production changes.

## Acceptance Criteria

- Today renders a complete server-shaped daily snapshot without recomputing any
  official value.
- Food remaining and net balance are distinct and explain their exercise
  semantics.
- Incomplete day data is neutral loaded content.
- Text, Photo and Audio each produce a proposal before confirmation in Debug and
  tests.
- Meal editing applies only to an open pending and replaces the returned
  proposal.
- Workout calories are displayed only from a proposal response.
- Proposal creation, editing and cancellation invalidate Today; confirmation
  invalidates Today and main History.
- Invalidation never patches or corrects an official value locally.
- Weight has no presumed BFF route or transport DTO.
- Hydration and routine commands preserve idempotency keys on Retry.
- Defaults, occurrence actions, snooze choices and idempotent attempts use an
  injected time source.
- Snooze requires `snoozed_until`, offers 15, 30 and 60 minute presets plus a
  custom time, and cannot cross the original occurrence's local date.
- Supplement and medication details use their own opaque-cursor histories.
- Plan does not interpret opaque nutrition payloads.
- Progress and the 7,700 kcal block use only supplied values.
- Main History performs one bounded first-page read and shows only confirmed
  meal-log rows and Workouts.
- Each History meal row remains an individual `meal_logs` record; equal times
  or `meal_type` values are not grouped, and detail uses only the row `id`.
- Main History has no derived cursor, second-page request or Load more command.
- Debug, previews and tests may use deterministic complete snapshots.
- Release reads and operations fail closed with “Indisponível nesta versão” and
  cannot show a simulated success.
- Loading, empty, offline, recoverable-error, Retry and unavailable states are
  covered.
- Dynamic Type, Dark Mode and Reduce Motion behavior is verified.
- Full tests and Debug and Release builds pass on the required Xcode and
  simulator environment.
- No live service, secret, official iOS formula, production change or
  messaging-channel architecture is introduced.
