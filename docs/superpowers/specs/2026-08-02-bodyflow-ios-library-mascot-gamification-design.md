# BodyFlow iOS Library, Mascot And Gamification Design

**Date:** 2026-08-02

**Status:** awaiting approval

**Stacked branch:** `codex/bodyflow-ios-library-mascot-gamification-v1`

**Stacked base:** `codex/bodyflow-ios-today-records-progress-v1` at
`94c5dd1e5a62d2948eb5e56a1c63d2dfaf689123`

## Objective

Design the next native BodyFlow iOS increment for:

- the educational Library and published-content detail;
- published CMS recommendations on Today;
- a first-party BodyFlow mascot whose presentation reflects the current coach
  personality and server-owned mascot state;
- the existing XP, level, earned-badge and streak data;
- a non-punitive return experience when the current streak is zero;
- honest unavailable treatment for daily missions whose backend contract does
  not yet exist.

The design uses only contracts already implemented under
`/api/mobile/v1`. It does not infer a new endpoint from database tables, admin
screens, internal RPCs, legacy product documents, or desired future behavior.
It does not calculate official gamification values in iOS.

This document is the complete Prompt 14 design. It does not authorize a TDD
plan or application implementation.

## Verified Evidence And Constraints

The design was derived from the executable BFF, shared schemas, migrations,
mobile API documentation, prior accepted ADRs/specifications, and the current
iOS app. Primary sources include:

- `docs/mobile/api-v1.md`;
- `docs/adr/015-bodyflow-educational-content-cms.md`;
- `docs/superpowers/specs/2026-07-21-bodyflow-content-cms-design.md`;
- `docs/superpowers/specs/2026-07-20-bodyflow-personalities-messages-mascot-design.md`;
- `packages/core/src/content.ts`;
- `packages/core/src/coach-messages.ts`;
- `apps/admin/src/lib/mobile-api/content-service.ts`;
- `apps/admin/src/lib/mobile-api/supabase-content.ts`;
- `apps/admin/src/lib/mobile-api/coach-service.ts`;
- `apps/admin/src/lib/mobile-api/supabase-coach.ts`;
- `apps/admin/src/lib/mobile-api/read-model.ts`;
- route handlers under `apps/admin/src/app/api/mobile/v1`;
- `apps/ios/BodyFlow/BodyFlow` and its unit/UI test targets.

### Real Mobile Operations

| Capability | Existing operation | Prompt 14 use |
| --- | --- | --- |
| Published feed | `GET /api/mobile/v1/content` | Today, Library and Saved feeds |
| Published detail | `GET /api/mobile/v1/content/:id` | Article detail |
| Read state | `POST /api/mobile/v1/content/:id/read` | Impression, opened and explicit completion |
| Saved state | `POST /api/mobile/v1/content/:id/save` | Save and unsave |
| Private cover | `GET /api/mobile/v1/content/covers/:token` | Authenticated, short-lived cover image |
| Coach snapshot | `GET /api/mobile/v1/coach/persona` | Effective persona, public options and mascot state |
| Persona update | `PATCH /api/mobile/v1/coach/persona` | Existing server capability; not broadened by this workpack |
| Gamification snapshot | `GET /api/mobile/v1/progress` | XP, level, streaks and earned badge strings |

Every operation requires the established authenticated patient envelope. Content
operations are entitlement-protected by the current route policy. The client
does not send locale, plan, protocol, personality, patient ID, publication
eligibility, or publication status.

The staging base URL is not currently defined in `docs/mobile/api-v1.md`, and
the native app has no live authenticated HTTP transport. Prompt 14 must not
hardcode a host, bearer, secret, service-role credential, or staging/production
environment. Deterministic adapters remain limited to Debug, previews and
tests. Release continues to fail closed with `operationUnavailable` until a
separate live-transport workpack is approved.

### Confirmed Contract Gaps

No patient mobile endpoint or DTO currently exists for:

- daily missions, mission completion, mission rewards, or mission history;
- streak restoration, freeze, grace eligibility, recovery currency, or a
  recovery mutation;
- a patient ranking or leaderboard;
- cooperative missions or teams;
- XP event history or XP breakdown;
- level names, level thresholds, XP-to-next-level, or level percentage;
- badge IDs, catalog metadata, description, image, earned timestamp, or locked
  badges;
- mascot transition, mascot history, mascot asset, or animation;
- a rendered recurring coach message for the native app;
- a recommendation score, reason, model, related-content endpoint, search, or
  category catalog;
- content embedded in `GET /today`.

Admin-only “Top XP” data and service-role database RPCs are not mobile
contracts. They must not be reused by iOS. The design does not declare
`MissionDTO`, `RankingDTO`, `CooperativeMissionDTO`, a streak-recovery command,
or an assumed route for any of them.

### Mascot State Contract Mismatch

The requested visual scope names four states: inactive, reactivating, active and
neglected. The real v1 wire contract contains five values:

- `inactive`;
- `reactivating`;
- `active`;
- `evolving`;
- `neglected`.

The iOS wire model must decode all five, plus preserve an unknown future raw
value safely. It may not omit `evolving`, fail a valid v1 response, or silently
map it to `active`. The four requested states receive approved presentations in
this workpack. `evolving` and unknown values receive a neutral unsupported
presentation until product supplies a specific visual contract.

## Considered Delivery Strategies

### 1. Capability composition using the existing BFF — chosen

Library, content mutations, coach snapshot and progress remain separate small
capabilities. Today composes its official daily state and a separate
`surface=today` published-content feed without changing `TodayResponse`.
Progress renders only persisted values returned by `/progress`. Mascot renders
only the server snapshot returned by `/coach/persona`.

This approach preserves failure isolation, matches the existing iOS dependency
graph, and allows missing capabilities to remain explicitly unavailable.

### 2. A new aggregated “engagement dashboard” endpoint — rejected

Combining Today, recommendations, mascot, XP and missions would require a route
and DTO that do not exist. It would also couple independent loading, error and
cache policies. Prompt 14 will not describe or simulate this contract.

### 3. Local-first gamification and recommendation engine — rejected

Calculating XP, level progress, streak recovery, recommendations or missions in
iOS would duplicate backend authority and invent rules not present in the
mobile API. Persisting a local content catalog would also bypass publication,
locale, targeting, archive and entitlement checks.

## Execution Boundary

After this specification is approved, a later TDD plan may implement native
models and surfaces subject to all of the following:

- Swift 6, SwiftUI and iOS 18 remain unchanged;
- the five existing tabs and their independent navigation stacks remain
  unchanged;
- no application behavior is implemented before a focused RED test;
- no live URL, provider session, secret, CMS table access, Supabase client, or
  production configuration is added;
- no article body, recommendation, mascot state, XP, badge, streak or mission
  is invented in Release;
- synthetic fixtures are visibly deterministic and are compiled/constructed
  only for Debug, previews and tests;
- Release adapters return `operationUnavailable` and surfaces display
  “Indisponível nesta versão” rather than fixture success;
- no migration, deploy, merge, TestFlight, production change or WhatsApp-based
  architecture is part of the workpack.

## Architecture

### Feature Boundaries

Prompt 14 adds three independent native feature domains:

1. `Core/Content` and `Features/Library` own published content, detail, read
   state and saved state.
2. `Core/CoachExperience` and `Features/Mascot` own the read-only coach/mascot
   snapshot and its presentation.
3. The existing `Core/Progress` and `Features/Progress` remain the sole native
   owner of XP, level, badges and streaks.

`TodayRootView` composes a separate recommendations view model. It does not add
content fields to `TodaySnapshot`, and `TodayProviding` remains unchanged.

`AppDependencies` receives small `Sendable` capabilities. A single monolithic
“engagement repository” is prohibited because it would couple unrelated
contracts and failure states.

### Capability Protocols

The stable native boundaries are:

```swift
protocol PublishedContentListing: Sendable {
    func content(_ query: ContentFeedQuery) async throws
        -> PublishedContentFeedResponse
}

protocol PublishedContentDetailProviding: Sendable {
    func contentDetail(publicationID: String) async throws
        -> PublishedContentDetailResponse
}

protocol PublishedContentStateRecording: Sendable {
    func recordRead(_ attempt: MutationAttempt<ContentReadCommand>) async throws
        -> PublishedContentStateResponse

    func setSaved(_ attempt: MutationAttempt<ContentSaveCommand>) async throws
        -> PublishedContentStateResponse
}

protocol CoachExperienceProviding: Sendable {
    func coachExperience() async throws -> CoachExperienceResponse
}
```

These are native capability boundaries, not new HTTP endpoints. A deterministic
Debug repository may implement several protocols, as the current Prompt 13
repository does, while production dependencies remain protocol-oriented.

The existing `ProgressProviding` remains authoritative. No mission, ranking,
cooperative or streak-recovery provider is declared.

### Ownership And Session Lifetime

`AppRootView` creates `AppShellView` only for the authenticated user. Prompt 14
view models and their in-memory state are owned under that shell and therefore
have one authenticated-session lifetime.

On sign-out or user-ID change:

- the shell is destroyed;
- content snapshots and cover images are discarded;
- active loads and mutations are cancelled;
- late results may not publish into the next session;
- no patient-targeted content remains in a global singleton.

### Loading And Publication Safety

Feature owners reuse:

- `@MainActor @Observable` view models;
- `FeatureReadState` for idle, loading, loaded, empty, stale offline, stale
  error and unavailable states;
- immutable mutation attempts and `FeatureMutationState`;
- `FeatureRevisionLoadController` or equivalent ownership checks;
- `.task(id:)` revisions for one complete load per revision;
- cancellation-safe publication and latest-intent-wins behavior.

An older page, detail, coach or progress result must never replace a newer
filter, revision, route or user session.

### Injected Time

Prompt 14 reuses the existing `TimeProviding` dependency from
`AppDependencies`. Feature code reads `timeProvider.now` for:

- `MutationAttempt.createdAt` when a new content intent is created;
- the receipt instant used to turn cover `private, max-age` into an in-memory
  expiry;
- comparisons with `cover.expires_at`.

No content, cover, mascot or gamification feature calls `Date()` directly.
`SystemTimeProvider` remains the only Release implementation allowed to read
wall-clock time; Debug/previews/tests use the existing fixed provider. Retrying
an intent reuses the complete immutable attempt, including its original
`createdAt`, rather than consulting the clock again.

## Exact Native Contract Models

### Standard Envelope

Every JSON success preserves the existing envelope:

```swift
struct MobileResponse<Payload: Codable & Sendable>: Codable, Sendable {
    let data: Payload
    let meta: MobileResponseMetadata
}

extension MobileResponse: Equatable where Payload: Equatable {}
```

The implementation must preserve `api_version` and `request_id`. It must not
add a client-computed `published`, `eligible`, recommendation score or source.

### Content Query

```swift
enum ContentSurface: String, Codable, Hashable, Sendable {
    case today
    case library
    case saved
}

enum ContentLocale: String, Codable, Hashable, Sendable {
    case ptBR = "pt-BR"
    case enUS = "en-US"
}

enum ContentCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case weightLoss = "weight_loss"
    case hypertrophy
    case nutrition
    case training
    case neuroscience
    case habitFormation = "habit_formation"
    case cardiovascularHealth = "cardiovascular_health"
    case hydration
    case supplementation
    case sleep
    case usingBodyFlow = "using_bodyflow"
}

struct ContentFeedQuery: Equatable, Hashable, Sendable {
    let surface: ContentSurface
    let category: ContentCategory?
    let limit: Int
    let cursor: String?
}
```

The real endpoint accepts `limit` in `1...50`, defaulting to 20, and a server
cursor of 1...512 characters. `cursor` is opaque: iOS stores and returns the
exact value and never decodes, derives, sorts or edits it.

The raw values above are the eleven v1 categories. Localized category labels
are presentation copy owned by iOS. They are not claimed to come from the API,
and there is no category-discovery endpoint:

- `weight_loss`;
- `hypertrophy`;
- `nutrition`;
- `training`;
- `neuroscience`;
- `habit_formation`;
- `cardiovascular_health`;
- `hydration`;
- `supplementation`;
- `sleep`;
- `using_bodyflow`.

### Published Content Summary

The item DTO mirrors the BFF exactly:

```swift
struct PublishedContentSummary: Codable, Equatable, Sendable, Identifiable {
    let publicationID: String
    let slug: String
    let locale: ContentLocale
    let title: String
    let excerpt: String
    let category: ContentCategory
    let tags: [String]
    let readingTimeMinutes: Int
    let publishAt: APITimestamp
    let featuredToday: Bool
    let version: Int
    let saved: Bool
    let completed: Bool
    let cover: PublishedContentCover?

    var id: String { publicationID }
}

struct PublishedContentCover: Codable, Equatable, Sendable {
    let url: String
    let expiresAt: APITimestamp
}
```

`url` is the exact wire field. Its value is a relative authenticated BFF
capability, not a public URL or Storage path. The app never persists or logs
it.

The list response is:

```swift
struct PublishedContentFeed: Codable, Equatable, Sendable {
    let items: [PublishedContentSummary]
    let nextCursor: String?
}

typealias PublishedContentFeedResponse = MobileResponse<PublishedContentFeed>
```

There is no total count, recommendation reason, author, reviewer, rating,
popularity, public share URL or related-content field.

Published values are decoded against the existing contract invariants; iOS
does not truncate or repair malformed server values:

| Field | Existing invariant |
| --- | --- |
| `publication_id` | UUID |
| `slug` | 3...120 lowercase ASCII letters/digits separated by hyphens |
| `locale` | exactly `pt-BR` or `en-US` |
| `title` | 3...120 characters |
| `excerpt` | 20...280 characters |
| `tags` | at most 20 unique lowercase slugs, each 1...40 characters |
| `reading_time_minutes` | integer in 1...500 |
| `version` | integer in 1...2,147,483,647 |
| `body_markdown` | 100...50,000 characters after approved normalization |

### Published Content Detail

Detail repeats every summary field and adds only `body_markdown`:

```swift
struct PublishedContentDetail: Codable, Equatable, Sendable {
    let summary: PublishedContentSummary
    let bodyMarkdown: String
}

typealias PublishedContentDetailResponse = MobileResponse<PublishedContentDetail>
```

This nested native representation may use a custom decoder to flatten the wire
object. It does not imply a nested server object.

The route is identified only by `publication_id` UUID. Slug navigation and
detail-by-slug are not supported.

### Content Read And Saved State

```swift
enum ContentReadEvent: String, Codable, Hashable, Sendable {
    case impression
    case opened
    case completed
}

enum ContentOrigin: String, Codable, Hashable, Sendable {
    case today
    case library
    case push
}

struct ContentReadBody: Codable, Equatable, Hashable, Sendable {
    let event: ContentReadEvent
    let origin: ContentOrigin
    let version: Int
}

struct ContentReadCommand: Equatable, Hashable, Sendable {
    let publicationID: String
    let body: ContentReadBody
}

struct ContentSaveBody: Codable, Equatable, Hashable, Sendable {
    let saved: Bool
    let version: Int
}

struct ContentSaveCommand: Equatable, Hashable, Sendable {
    let publicationID: String
    let body: ContentSaveBody
}

struct PublishedContentState: Codable, Equatable, Sendable {
    let publicationID: String
    let version: Int
    let saved: Bool
    let completed: Bool
    let changed: Bool
    let replayed: Bool
}

typealias PublishedContentStateResponse = MobileResponse<PublishedContentState>
```

Only each command's `body` is encoded as JSON; `publicationID` identifies the
route and must not be emitted as an unknown body field. `origin` is not
included in the save body; the BFF fixes it to `library`. The client supplies
no event timestamp. Completion is one-way because no uncomplete operation
exists.

`MutationOperation` gains only `.contentRead` and `.contentSave`. The immutable
attempt payload contains the event/save intent and version, so retries keep the
same route, JSON body and idempotency key without creating event-specific
operation cases.

### Coach And Mascot Snapshot

```swift
struct CoachExperienceSnapshot: Codable, Equatable, Sendable {
    let selected: SelectableCoachPersona?
    let effective: EffectiveCoachPersona
    let options: [CoachPersonaOption]
    let mascot: MascotSnapshot
    let contractVersion: String
}

struct CoachPersonaOption: Codable, Equatable, Sendable, Identifiable {
    let code: SelectableCoachPersona
    let name: String
    let description: String

    var id: SelectableCoachPersona { code }
}

struct MascotSnapshot: Codable, Equatable, Sendable {
    let state: MascotWireState
    let changedAt: APITimestamp?
}

typealias CoachExperienceResponse = MobileResponse<CoachExperienceSnapshot>
```

`SelectableCoachPersona` contains exactly `focus`, `impulse` and `zen`.
`EffectiveCoachPersona` contains those values plus internal `balanced`.
`selected` is selectable or `null`; `balanced` is never shown as a fourth
choice. Option names and descriptions come from the server response rather
than the current hard-coded Swift summaries.

`MascotWireState` is lossless and supports:

```text
inactive | reactivating | active | evolving | neglected | unknown(rawValue)
```

`contract_version` must equal `bodyflow.coach-persona.v1` for the v1 presenter.
An unsupported version fails closed instead of guessing semantics.

### Gamification Snapshot

The existing `/progress` fields remain exact:

```swift
struct ProgressSnapshot: Codable, Equatable, Sendable {
    let xpTotal: Int
    let level: Int
    let currentStreak: Int
    let longestStreak: Int
    let blocksCompleted: Int
    let deficitBlock: Int
    let currentWeight: Decimal?
    let currentBodyFatPercent: Decimal?
    let badgesEarned: [String]
    let lastActiveDate: String?
    let nextReevaluation: String?
    let updatedAt: APITimestamp
}

typealias ProgressResponse = MobileResponse<ProgressSnapshot?>
```

The BFF uses `maybeSingle()`, so `data` may be `null` when no `user_progress`
row exists. Only `data == null` publishes an empty state. Every non-null
snapshot is official and publishes `.loaded`. The persisted minimum snapshot
has `xp_total=0`, `level=1`, both streaks and `blocks_completed` at zero,
`deficit_block=0`, nullable weight/body-fat/date fields at null, an empty
`badges_earned` array and a valid `updated_at`. Absence may not become that
minimum official snapshot; conversely, minimum official values may not be
reclassified as absence.

No additional gamification field is added to the native wire model.

## Navigation

The app retains exactly these five tabs and stable accessibility identifiers:

1. Today;
2. Register;
3. Plan;
4. Progress;
5. Profile.

Library is not a sixth tab. It is a typed destination in the Today navigation
stack. New routes carry identity and origin, not mutable response snapshots:

```swift
enum LibrarySelection: Hashable, Sendable {
    case all
    case saved

    var contentSurface: ContentSurface {
        switch self {
        case .all: .library
        case .saved: .saved
        }
    }
}

enum ContentRoute: Hashable, Sendable {
    case library(initialSelection: LibrarySelection)
    case detail(publicationID: String, origin: ContentOrigin)
}

enum MascotRoute: Hashable, Sendable {
    case detail
}

// New cases on the existing router enum; all inherited cases remain.
enum AppRoute: Hashable, Sendable {
    // ...existing Prompt 13 cases...
    case content(ContentRoute)
    case mascot(MascotRoute)
}
```

The presentation-only `LibrarySelection` prevents `surface=today` from becoming
an unsupported third Library segment while mapping exactly to the two real feed
surfaces used by that screen.

The real router continues to store `[AppRoute]`. Both `.content` and `.mascot`
map to `.today` in `AppRoute.tab`, so `AppRouter.navigate` appends them only to
the Today stack. `AppShellView.destination(for:)` dispatches content routes to
Library/detail destinations and `.mascot(.detail)` to a mascot detail that
reloads `CoachExperienceProviding`. No route carries an article, coach or
mascot response snapshot.

Entry points are:

- a persistent Library toolbar action or card in Today;
- “Ver biblioteca” from the Today recommendations section;
- selecting a Today recommendation, Library item or Saved item opens content
  detail;
- selecting the Today mascot card opens `.mascot(.detail)`.

The detail route always reloads `GET /content/:id` to revalidate version,
entitlement, locale, targeting, schedule and archive state. It does not trust a
list snapshot as the full detail contract.

## Educational Library

### Information Architecture

The Library screen contains:

- a title and concise description;
- a segmented selection for `Todos` (`surface=library`) and `Salvos`
  (`surface=saved`);
- one optional category filter using the fixed v1 category values;
- published cards in server order;
- load-more only when `next_cursor` is non-null;
- pull to refresh;
- explicit loading, empty, stale, offline, recoverable-error and unavailable
  states.

There is no search box, tag filter, sort control, total count, popularity label
or “recommended because” explanation because the API provides none.

Initial Library/Saved reads use `limit=20`. Changing surface or category:

- cancels the prior request;
- resets the cursor and visible page chain;
- starts a complete first-page read;
- prevents late publication from the old query.

Subsequent pages reuse the exact same surface, category and limit plus the
opaque `next_cursor`. A next-page failure keeps the already loaded rows and
offers an inline Retry using the same cursor. A first-page failure uses the
normal full-screen/stale state.

### Card Content

A card may display only:

- the returned private cover or a neutral first-party placeholder;
- returned title and excerpt;
- a localized presentation label for returned category;
- returned reading time;
- returned saved/completed state.

Cards do not display unpublished labels, authorship, publication workflow,
scores, health promises or inferred audience targeting. A cover has no alt text
in the contract, so it is decorative when title and excerpt already convey the
card identity.

### Empty States

- Empty Library: “Nenhum conteúdo publicado está disponível para você agora.”
- Empty Saved: “Você ainda não tem conteúdos salvos disponíveis.”
- Empty category: “Nenhum conteúdo disponível nesta categoria.”

These messages do not reveal whether absence is caused by locale, targeting,
schedule, archive, entitlement history or editorial availability.

## Published Content Detail

### Loading And Presentation

Detail loads by publication ID. It renders:

- title;
- category and reading time;
- optional cover;
- saved/completed state;
- normalized published Markdown;
- Save/Unsave action;
- an explicit “Marcar como concluído” action when not completed.

The article title is the screen heading. The Markdown body never supplies an H1.

### Native Markdown Policy

The renderer accepts exactly the backend-approved subset:

- paragraphs;
- H2 and H3;
- emphasis and strong;
- ordered lists beginning at 1;
- unordered lists;
- block quotes;
- absolute HTTPS links;
- nesting no deeper than eight levels.

It does not use `WKWebView`, arbitrary HTML, remote scripts, inline images,
attachments, inline or block code, embeds, thematic breaks, link titles,
reference-style links, HTTP links, protocol-relative links, data URLs or
JavaScript URLs. Unsupported or malformed local parsing fails closed with a
recoverable content rendering error. Raw Markdown is not displayed as trusted
health content.

Links use the system open-URL path only after an HTTPS check. The app does not
rewrite, track or decorate a link as a BodyFlow endorsement.

### Read Events

- `impression` is created only after a card is actually visible.
- `opened` is created when a user selects a card/detail.
- `completed` requires an explicit user action at the article detail.

SwiftUI re-rendering must not emit duplicate impressions. The feed owner keeps
one immutable attempt per publication/version/origin for the current visible
response. The endpoint remains the authoritative deduplication layer.

Opened-event failure does not block reading an already authorized detail. It
appears as a non-blocking recoverable state. Save and completion operations show
submitting, success, recoverable failure and unavailable states and prevent
double submission.

No event is persisted into an offline queue. The server owns event time, so a
later replay after another session could misrepresent when a card was visible.

### Version Conflict

On `409 content_version_changed`:

1. preserve the failed immutable attempt for diagnostics;
2. invalidate and reload the current detail plus every resident Today, Library,
   Saved and category-filtered feed;
3. discard the old version's cover capability and bytes unconditionally,
   regardless of their wall-clock expiry;
4. do not rewrite the old payload to the new version;
5. require a new explicit Save/Complete action for the new version.

Cover capabilities are version-bound, so a version conflict makes the prior
cover invalid immediately. The client never marks a replacement article
completed because an older version was completed.

### Not Found

`404 content_not_found` produces one generic “Este conteúdo não está mais
disponível” state with a Back/Library action. It does not distinguish missing,
archived, future, wrong locale, lost entitlement or changed targeting.

## Today Recommendations

Recommendations are a separate CMS read:

```text
GET /api/mobile/v1/content?surface=today&limit=3
```

They are not fields in `TodayResponse`, and their failure must not hide or
degrade official Today nutrition/routine state.

The section title is “Conteúdos para hoje”. “Recommended” means only content
that the BFF has already filtered as published, localized, eligible and
`featured_today=true`. The app does not calculate relevance or claim an AI
recommendation.

Behavior:

- show at most the three items returned in server order;
- send `origin=today` for impression/opened events;
- expose “Ver biblioteca” regardless of recommendation count;
- do not paginate the compact Today section;
- when its response contains `next_cursor`, the CTA opens the normal Library
  rather than deriving or consuming another Today page;
- empty state says “Nenhum conteúdo selecionado para hoje” without implying an
  error;
- offline/error/unavailable treatment remains inside the section.

Save/unsave and completion mutations invalidate the affected Today
recommendation list, Library list, Saved list and open detail. Impression and
opened events do not invalidate official content feeds. No content event or
mutation invalidates or patches official `TodaySnapshot` nutrition values.

## BodyFlow Mascot

### Source Of Truth

The mascot is a read-only native presentation of:

```text
GET /api/mobile/v1/coach/persona
```

The iOS client does not call `transition_user_mascot_state`, access mascot
tables, infer a transition from inactivity, or add a state mutation route. A
refresh can only render the next snapshot returned by the BFF.

The primary mascot card appears in Today and navigates through
`.mascot(.detail)` to a lightweight destination that reloads the coach snapshot
and explains its current state and communication personality. It must not block
Today when unavailable.

### Requested State Presentations

| Wire state | User-facing presentation | Behavioral rule |
| --- | --- | --- |
| `inactive` | “Em repouso” | Neutral readiness; no claim that the patient failed |
| `reactivating` | “Retomando com você” | Gentle return presentation; no promised timer |
| `active` | “Ativo” | Stable companion presentation; no reward inference |
| `neglected` | “Em pausa” | Non-shaming language; never call the patient negligent |

`changed_at` may be displayed as a server-provided timestamp. It is never used
to calculate days inactive or to trigger another state.

### Evolving And Unknown Values

`evolving` is a valid backend state but has no approved Prompt 14 visual
semantics. It renders a neutral first-party placeholder and “Estado do mascote
em atualização”. An unknown raw value uses the same neutral presentation and
bounded telemetry. Neither is mapped to another state.

### Personality Variations

The effective persona controls visual tone only:

- Focus: stable geometry, clear alignment and restrained accent;
- Impulse: energetic composition and brighter BodyFlow accent variation;
- Zen: calm composition, softer spacing and restrained motion;
- Balanced fallback: neutral BodyFlow composition.

The state remains independent from the persona. A Focus mascot is not more
“active” than a Zen mascot, and a visual variation cannot award XP or change
backend state.

Persona names/descriptions shown to the user come from the `options` response.
No recurring personalized speech bubble is generated locally.

### Recurring Messages

The backend has a deterministic, human-reviewed message catalog with no runtime
LLM fallback, but no mobile route currently returns a rendered message. Prompt
14 therefore does not:

- call the internal claim RPC;
- copy the 1,080-message catalog into iOS;
- generate recurring copy with an LLM;
- invent a rendered-message endpoint;
- silently use a local dynamic fallback.

Only short, static and reviewed interface labels are part of this native
increment. Dynamic recurring mascot messages remain backend work.

## XP, Levels, Badges And Streaks

### Authority

`GET /progress` remains the only source. iOS does not port `global_config`, XP
rules, daily-close logic, legacy spreadsheets, database functions or admin
ranking code.

### XP And Level

The screen displays only:

- returned `xp_total` as “N XP”;
- returned `level` as “Nível N”.

It does not show a next-level progress bar, threshold, level name, XP forecast,
award animation, or event breakdown because none is returned by the API.

### Earned Badges / Medals

`badges_earned` is an ordered array of strings. The app may label the section
“Medalhas conquistadas” and pair each received string with one generic
first-party medal treatment. It must:

- preserve text and order exactly;
- use positional identity so duplicate strings do not collide in SwiftUI;
- provide no invented description, rarity, image, date or locked catalog;
- show a neutral empty state when the returned array is empty.

### Streaks

The app displays current and longest streak exactly as returned. It does not
derive a gap from `last_active_date`, alter a streak, or claim a grace period.

When `current_streak == 0`, the presentation may say:

> Sua sequência pode recomeçar hoje. O que você já construiu continua contando.

The CTA “Retomar em Hoje” navigates to the Today tab. It does not restore a
number, create XP, mark a mission complete, or promise that a future action will
preserve the prior streak. After normal server-owned activity, Progress reloads
the next official snapshot.

The UI contains no red loss state, countdown, guilt, punishment, paid recovery,
freeze token or destructive animation.

### Daily Missions

Daily missions are named in product scope but have no mobile contract. Prompt
14 may show only a bounded section-level unavailable state:

> Missões diárias — Indisponível nesta versão.

It does not show mission cards, completion, rewards, progress, deadlines or
sample data. Existing Today actions are not renamed as missions and do not
claim XP. No mission DTO/provider is created.

### Ranking And Cooperative Missions

No patient endpoint exists. Ranking and cooperative missions are completely
omitted. They may be added only after a reviewed mobile contract defines
privacy, identity/alias exposure, consent, pagination, membership, scoring,
moderation, reward and error semantics.

## Cache And Offline Behavior

### JSON

Patient JSON responses declare `Cache-Control: no-store`. Prompt 14 adds no
persistent HTTP cache, SQLite/Core Data store, file cache, sync token or offline
content catalog.

The last visible value in an authenticated feature view model may remain in
memory to support the existing stale offline/error presentation. This is
session view state, not durable cache. It is cleared with the authenticated
shell.

No stale snapshot may be presented as freshly updated XP, streak, mascot or
publication state. Stale surfaces display the existing stale-data disclosure.

### Covers

Cover responses are private and valid for at most the remaining capability
TTL, initially 300 seconds. A small session-owned image loader may retain image
bytes in memory only until the earlier of:

- `cover.expires_at`;
- response `private, max-age` expiry;
- user/session change;
- content version invalidation;
- cover 404 or loss of eligibility.

The loader accepts only the existing proxy MIME allowlist (`image/jpeg`,
`image/png`, `image/webp`), honors `X-Content-Type-Options: nosniff`, and treats
any other media type as a failed cover rather than attempting content
interpretation.

Cover tokens, relative paths and bytes are not written to disk, Keychain,
telemetry or logs. After expiry/404, the parent list/detail is reloaded to obtain
a new capability. Offline stale text may remain visible while an expired cover
falls back to the neutral placeholder.

## Refresh And Invalidation

`FeatureInvalidationCenter` remains `@MainActor @Observable`. Prompt 14 adds
content-scoped keys without broad feature coupling:

```text
contentCatalog
contentDetail(publicationID)
coachExperience
```

Every feed owner drives `.task(id:)` with a composite of its exact
`ContentFeedQuery` and the observed `contentCatalog` revision. A query change
therefore reloads only that feed, while one catalog revision performs exactly
one complete first-page reload in every resident Today, Library, Saved or
category-filtered feed and safely cancels its older load. Detail and coach use
their own observed revisions.

Invalidation behavior:

| Event | Invalidates |
| --- | --- |
| impression success | nothing; card state does not change |
| opened success | no invalidation; reconcile only the returned canonical state for that item/version |
| completed success | `contentCatalog` and affected detail |
| save/unsave success | `contentCatalog` and affected detail |
| content version conflict | `contentCatalog` and affected detail; discard the old cover unconditionally |
| cover expiry/404 | parent list/detail only |
| persona change through existing flow | coach experience and `contentCatalog` |
| manual content refresh | only the selected feed/detail |

No content invalidation patches Today nutrition, routine or history providers.
No existing Today mutation is assumed to change XP or mascot state. Progress and
coach snapshots reload on their own entry/refresh lifecycle because the backend
does not document an immediate cross-feature mutation contract.

Each observed revision triggers at most one complete reload. A newer revision
cancels the older load, and a cancelled load never publishes a late stale value
or error.

## Idempotency

Read/save mutations reuse the approved `IdempotencyKeyProviding` and immutable
`MutationAttempt` pattern.

- Key length: 8...128.
- Allowed characters: `[A-Za-z0-9._:-]`.
- Retry of the same intent preserves key, path and payload exactly.
- A new user intent receives a new key.
- `idempotency_request_in_progress` retains the same attempt for retry.
- `idempotency_key_conflict` is recoverable but never rewrites a payload under
  the same key.
- `content_version_changed` ends the old attempt; after reload, a new explicit
  action creates a new attempt for the new version.

There is no durable offline mutation queue.

## Error And Empty-State Matrix

| Condition | Native behavior |
| --- | --- |
| initial loading | skeleton/progress with accessible label |
| empty feed | surface-specific neutral empty message |
| offline, no prior value | offline state with Retry |
| offline, prior value | stale disclosure plus prior in-memory value |
| service/internal failure | recoverable error; preserve prior value if present |
| `operationUnavailable` | “Indisponível nesta versão”; never show fixture success |
| `subscription_required` | content unavailable for current subscription; no fake purchase flow |
| `content_not_found` | generic no-longer-available detail |
| `content_cover_not_found` | placeholder, then bounded parent refresh |
| `content_version_changed` | reload; require new explicit mutation |
| invalid cursor | discard only the invalid page attempt and offer first-page reload |
| coach locale unsupported | coach/mascot unavailable with Retry/profile-language guidance |
| unsupported coach contract version | fail closed with neutral unsupported state |
| `/progress` data `null` | empty, not zeroed official progress |
| missing mission/ranking capability | no data model; approved unavailable/omitted treatment |

Authentication expiry continues through the existing root authentication
boundary. Content errors never disclose publication targeting or editorial
state.

## Accessibility And Inclusive Behavior

All new screens must pass:

- Dynamic Type through Accessibility XXXL without clipping or horizontal
  scrolling for primary content;
- VoiceOver labels, values, headings and stable accessibility identifiers;
- 44-by-44-point minimum interactive targets;
- Light and Dark Mode using semantic BodyFlow tokens;
- Increase Contrast and Differentiate Without Color;
- Reduce Motion;
- logical focus after load, filter change, mutation success/error and Retry;
- external-link identification before opening an HTTPS link.

Specific rules:

- mascot art is decorative and hidden from accessibility; a sibling semantic
  element announces “Mascote BodyFlow, personalidade <name>, estado <state>”;
- state and persona are never conveyed by color, pose or motion alone;
- Focus, Impulse and Zen retain the same information and control hierarchy;
- `evolving`/unknown announces the neutral unsupported state;
- badge rows announce the exact returned text, without invented rarity;
- streak zero copy remains neutral and non-judgmental;
- covers are decorative when the card already exposes title/excerpt;
- Markdown headings become native accessibility headings;
- list semantics and link traits are preserved;
- Save is not nested inside a tappable navigation card;
- repeating mascot animation stops under Reduce Motion and the static end state
  preserves meaning.

## Temporary Asset Strategy

The repository currently has no approved mascot asset pack. Prompt 14 must not
imitate a third-party character, fitness brand, game, palette, silhouette,
animation or trademark.

### Debug, Previews And UI Tests

A temporary `MascotPlaceholderArtwork` may be built from original, abstract
SwiftUI vector primitives and BodyFlow semantic colors. It must:

- be clearly first-party and generic;
- remain presentational, outside domain models;
- resolve through `(effectivePersona, mascotPresentationState)`;
- include neutral Balanced, Evolving and Unknown fallbacks;
- avoid storing asset names in server-shaped fixtures;
- use deterministic motion only when Reduce Motion is off;
- be structurally limited to Debug/previews/UI tests.

Synthetic content covers use neutral first-party placeholders and are labeled
as demonstration context by launch configuration, not by adding a non-contract
field to the DTO.

### Release

Until approved BodyFlow-owned art and live providers exist, Release shows the
normal unavailable text treatment and no successful fixture mascot/content.

Future final art must:

- be owned or licensed for BodyFlow;
- include a provenance manifest;
- use semantic asset names independent of transport models;
- support vector/PDF or appropriately scaled raster variants;
- pass light/dark, contrast, Dynamic Type context and Reduce Motion review;
- replace placeholder providers without changing wire/domain contracts.

CMS covers remain the only remote content images. They are not bundled or
reused as mascot/medal art.

## Privacy, Security And Telemetry

- iOS accesses content only through the authenticated mobile BFF.
- It never accesses CMS tables, RPCs, buckets, object paths or service-role
  credentials.
- Locale, plan, protocol, personality and publication eligibility remain
  server-owned.
- Cover capability paths and article bodies are excluded from telemetry/logs.
- Telemetry may include bounded technical publication ID, version, surface,
  event kind, effective persona code, mascot raw state classification,
  request ID and outcome.
- Telemetry excludes title, excerpt, Markdown, cover URL/token, message copy,
  badge text, name, email, bearer, targeting reason and patient health values.
- Unknown enum telemetry is length-bounded and never emitted as arbitrary
  unbounded server text.
- There is no ranking identity exposure or cooperative membership in this
  increment.
- No runtime LLM is called for recurring messages, mascot copy,
  recommendations, missions or gamification.

## Testing Strategy

Every future implementation behavior starts with an observed RED test, reaches
focused GREEN, passes `git diff --check`, and receives its own logical
Conventional Commit checkpoint.

### Contract Tests

Test literal decoding/encoding for:

- all content summary fields, snake-case keys, null cover and relative cover
  URL;
- all eleven categories and three surfaces;
- exact list default/limits and opaque cursor round-trip without decoding;
- detail flattening and `body_markdown`;
- impression/opened/completed bodies and origin, without publication ID in
  JSON;
- save body without publication ID or origin;
- content state response fields including `changed` and `replayed`;
- selected-null/effective-balanced coach snapshot;
- server-localized persona options;
- all five real mascot states and an unknown raw state;
- exact `bodyflow.coach-persona.v1` handling;
- `/progress` data-null, complete literal snapshots and the non-null minimum
  official snapshot with `level=1` and `deficit_block=0`;
- absence of next-level, mission, ranking and recovery fields.

### Markdown Tests

- paragraphs, H2/H3, strong, emphasis, ordered/unordered lists, quotes and
  HTTPS links render correctly;
- nested content respects depth eight;
- HTML, H1, inline image, code, embed, thematic break, link title,
  reference-style link, non-HTTPS URL and malformed structures fail closed;
- headings/lists/links expose native accessibility semantics;
- no WebView or executable content path exists.

### Provider And State Tests

- Today recommendations send only `surface=today`, no locale or score;
- Library/Saved initial requests use exact surface/category/limit;
- next-page requests preserve the opaque cursor and all query dimensions;
- category/surface changes cancel old loads and suppress late publication;
- `AppRoute.content` and `AppRoute.mascot` map only to the Today stack and
  destinations carry no mutable response snapshots;
- first-page and next-page loading/error behavior remain distinct;
- stale offline content is memory-only and visibly stale;
- detail always loads by publication ID;
- impression emits only for an actually visible card and deduplicates a single
  rendered response;
- opened failure does not hide authorized detail;
- save/complete retry preserves the exact idempotency attempt;
- version conflict drops the old cover, reloads every resident feed plus detail
  and never reapplies the old mutation;
- cover expiry/404 discards the token and performs a bounded parent refresh;
- fixed time proves the earlier cover expiry wins and no feature calls `Date()`
  directly;
- retry preserves the original attempt key, payload, route and `createdAt`
  even after the fixed clock advances;
- sign-out/user change cancels and clears every patient-scoped value;
- Release dependencies return `operationUnavailable` for every new capability;
- no fixture repository or Prompt 14 launch symbol is present in Release.

### Mascot And Gamification Tests

- effective Focus, Impulse, Zen and Balanced select only their presentation
  descriptor;
- inactive, reactivating, active and neglected use approved neutral copy;
- evolving and unknown use the neutral unsupported descriptor;
- no local transition is performed from time, activity, XP, weight or streak;
- `changed_at` is displayed but never used as a behavior threshold;
- XP, level, current/longest streak and badge strings are literal;
- a non-null minimum progress snapshot (`xp_total=0`, `level=1`,
  `deficit_block=0`) is loaded official data, never the empty state;
- duplicate badge strings render as separate rows without identity collision;
- data-null is empty, not zero;
- current streak zero exposes supportive copy and Today navigation only;
- no threshold, next-level percentage, XP award, mission completion, ranking or
  cooperative data is calculated or displayed;
- no recurring message endpoint, LLM or local dynamic catalog is called.

### UI And Accessibility Tests

Deterministic Debug journeys cover:

- all five original tabs still open and preserve independent stacks;
- Today recommendations loaded, empty, offline, error and unavailable;
- Today continues to render when recommendations fail;
- Library all/saved/category filters and opaque load-more;
- content detail, Markdown, save, unsave, completion and conflict reload;
- cover success, nil, expiry and placeholder;
- Focus/Impulse/Zen plus Balanced fallback;
- four requested mascot presentations plus Evolving/Unknown fallback;
- Today mascot navigation to its snapshot-reloading typed detail;
- progress data, data-null empty response, non-null minimum official response,
  streak-zero recovery copy and mission unavailable state;
- no ranking/cooperative surface;
- VoiceOver, 44-point controls, Dark Mode, Accessibility XXXL and Reduce Motion;
- visual evidence for representative Library, detail, Today recommendation,
  mascot personalities/states and gamification states.

The full inherited unit/UI suite, Debug build and Release build remain mandatory
at the final implementation gate.

## Future Backend Work

The following require separately reviewed backend contracts before native
implementation:

1. Daily mission definition, assignment, date/timezone, progress, completion,
   reward, idempotency and history.
2. Streak recovery/freeze/grace eligibility and an explicit mutation/receipt.
3. Patient-safe ranking with consent, alias/privacy rules, cohort, score,
   pagination, moderation and opt-out.
4. Cooperative mission membership, ownership, contribution, reward and abuse
   handling.
5. XP event history, level names/thresholds and badge metadata if those details
   should appear in iOS.
6. A rendered recurring-message mobile contract if the mascot should speak
   dynamic approved catalog copy.
7. An approved mascot-state mobile transition command if the patient is ever
   allowed to trigger transitions.
8. Approved BodyFlow-owned final mascot and medal assets.
9. A deployed staging BFF URL and reviewed bearer/session bridge for live iOS
   transport.

All additions must be additive. Prompt 14 reserves no speculative wire shape
for them.

## Deliberately Out Of Scope

- sixth tab or replacement of the existing tab shell;
- admin CMS editing/review/publication UI on iOS;
- draft, scheduled, rejected or archived content exposure;
- search, related articles, comments, reactions, sharing or social feed;
- local recommendation scoring or AI recommendation;
- local XP, level, streak, badge or mission calculations;
- mission/ranking/cooperative mock success;
- automatic or client-written mascot transitions;
- dynamic recurring mascot messages;
- LLM dependency for recurring copy;
- third-party brands, characters, visual references or unreviewed assets;
- persistent content/cache/offline mutation queue;
- live Supabase/BFF wiring, secrets or real service configuration;
- migration, deploy, merge, TestFlight or production change;
- WhatsApp or another messaging transport in the native architecture.

## Acceptance Criteria

The later implementation is acceptable only when all of the following are true:

- the app still has exactly five tabs;
- Library is reachable in the Today navigation stack;
- content and mascot destinations are typed `AppRoute` cases mapped to Today
  and carry no mutable response snapshot;
- all content shown in a live-capable contract path comes only from the
  published, localized and eligible `/content` BFF responses;
- Today recommendations use a separate `surface=today` request and never modify
  `TodayResponse`;
- Library and Saved use exact real surfaces and opaque server pagination;
- detail uses publication ID and only the real detail DTO;
- the native Markdown renderer supports exactly the approved subset without a
  WebView;
- impression/opened/completed/save mutations preserve exact version and
  idempotency semantics;
- version conflicts invalidate every resident content feed and detail, discard
  the prior version's cover and never auto-apply an old intent to new content;
- JSON and private cover data are not persisted across sessions;
- cover expiry never exposes a Storage path or stale capability;
- mascot state/personality come only from the coach snapshot;
- all five real mascot wire states decode, while only the four requested states
  receive dedicated visual semantics;
- Evolving/Unknown remain neutral and explicit;
- no time/activity/health threshold changes mascot state locally;
- Focus, Impulse and Zen vary presentation without changing data or reward;
- Balanced remains internal and neutral;
- no runtime LLM or local recurring-message catalog exists;
- XP, level, streaks and earned badge strings are rendered literally from
  `/progress`;
- only `/progress` `data: null` is empty; every non-null snapshot, including
  the minimum official `level=1`/`deficit_block=0` snapshot, is loaded data;
- no next-level formula, badge metadata or XP award is invented;
- a zero streak receives supportive, non-punitive copy and Today navigation,
  not a fake restoration;
- daily missions show only the approved unavailable state until a contract
  exists;
- ranking and cooperative missions are absent because no endpoint exists;
- loading, empty, offline, stale, error, conflict, unavailable and retry states
  are deterministic and accessible;
- cover expiry and mutation attempt creation use injected `TimeProviding`, and
  retry preserves the original attempt timestamp;
- Dynamic Type, Dark Mode, VoiceOver, 44-point targets and Reduce Motion pass;
- temporary visuals are first-party, neutral and Debug/preview/test-only;
- Release contains no Prompt 14 fixture success and fails closed;
- full tests, Debug/Release builds, simulator and visual evidence pass before
  any publication action;
- no live service, secret, migration, deploy, merge, TestFlight, production or
  WhatsApp architecture is introduced.
