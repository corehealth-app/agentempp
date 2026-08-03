# BodyFlow iOS Library, Mascot And Gamification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the approved Prompt 14 native iOS experience for the published educational Library and detail, Today recommendations, the BodyFlow mascot, and literal server-owned XP, level, earned-medal and streak presentation without inventing APIs, rewards or calculations.

**Architecture:** Mandatory backend Task 0 first makes the existing Markdown authority detect and reject GFM pipe-table AST nodes at author writes, legacy clone/workflow guards and mobile-detail reads. Tasks 6 and 7 reconcile the distinct editorial-source, backend-canonical and native-payload boundaries before Task 8 resumes the shared corpus: backend hardening rejects the three portable semantic sources and serves only `toMarkdown` canonical detail, while iOS consumes that canonical payload without reproducing the serializer. A minimal per-version validation snapshot prevents the admin service from loading publication history or identities. Local fail-closed guards mirror existing source/approve/publish preconditions without redefining them; the database remains final authority for eligible mutations, and the locked submit RPC remains authority for concurrent revision/lifecycle outcomes. Then small `Sendable` capabilities keep content listing, content detail/state, coach experience and existing progress reads independent. Authenticated-session-owned `@MainActor @Observable` feature models publish complete immutable responses through cancellation-safe revision keys; Debug/previews/tests use deterministic actors, while Release installs only unavailable providers and no Prompt 14 URL, bearer, fixture or successful fallback. Published canonical Markdown is converted fail-closed from exact-pinned `swift-markdown` into a BodyFlow-owned AST, and private covers pass strict capability validation, streamed byte limits, ImageIO downsampling and bounded session memory caching.

**Tech Stack:** Xcode 26.6 (build 17F113), Swift 6, SwiftUI, Observation, Foundation, ImageIO, Swift Testing, XCTest/XCUIAutomation, exact `swift-markdown` 0.8.0 at `3c6f9523da3a1ec2fd829673e472d95b8097a3b8`, iOS 18.0 deployment target, and iPhone 17 Pro on iOS 26.5 (`27291590-659D-4A29-8F45-CA5CA2D154F9`). Backend keeps exact `mdast-util-from-markdown` 2.0.3, `mdast-util-to-markdown` 2.1.2, `micromark-extension-gfm-table` 2.1.1 and `mdast-util-gfm-table` 2.0.0; Task 6 adds exact `micromark-extension-gfm-strikethrough` 2.1.0, `mdast-util-gfm-strikethrough` 2.0.0, `micromark-extension-gfm-task-list-item` 2.1.0 and `mdast-util-gfm-task-list-item` 2.0.0 solely for rejection.

## Approval And Execution Boundary

- The specification at `docs/superpowers/specs/2026-08-02-bodyflow-ios-library-mascot-gamification-design.md` is `awaiting contract reconciliation approval` after this documentary revision.
- Tasks 0 through 5 are already committed. The former Task 6 stopped at the diagnosed compatibility gate and is renumbered Task 8 below; do not execute Tasks 6, 7 or 8 until this reconciliation receives explicit approval.
- Execute later implementation only in `/Users/eduardohenrique/Developer/bodyflow` on `codex/bodyflow-ios-library-mascot-gamification-v1`.
- Preserve the stacked base `codex/bodyflow-ios-today-records-progress-v1` at `94c5dd1e5a62d2948eb5e56a1c63d2dfaf689123`; do not rewrite, reset, rebase or force the stack.
- Preserve visible name `BodyFlow`, bundle ID `com.bodyflow.app`, Swift 6 language mode, complete concurrency checking and iOS 18.0.
- Keep exactly the existing five tabs and their independent navigation stacks. Library and mascot are typed destinations in Today, never new tabs.
- Use Swift Testing for unit, contract, parser, provider and presentation tests. Use XCTest/XCUIAutomation for UI and accessibility journeys.
- For every production behavior, first add the focused test, run it and record the expected RED reason. Add only the minimal GREEN implementation, refactor while green, run `git diff --check`, review adherence/quality and make exactly one Conventional Commit for the task.
- A failing test must fail for the intended missing behavior, not for a malformed fixture, broken project or unrelated inherited failure.
- New Swift source/test/resource files under the file-system-synchronized roots join their respective targets automatically. Modify `BodyFlow.xcodeproj/project.pbxproj` only in Task 4 for the reviewed Swift package reference/product link.
- Do not add a live API client, authenticated transport, base URL, session-token bridge, secret, Supabase SDK/client, service-role credential, CMS table/RPC/bucket access or production configuration.
- Do not add a mission, ranking, cooperative mission, streak recovery, recurring-message, recommendation-score, search, related-content, badge-catalog or XP-history provider/DTO/route.
- Do not port backend XP, level, streak, recommendation, publication eligibility or mascot transition calculations into iOS.
- Do not persist patient JSON, Markdown, cover capability strings, raw/decoded cover data, offline mutations or content events.
- Do not add a runtime LLM or a local recurring-message catalog.
- Do not introduce WhatsApp or another messaging transport into any native architecture.
- Do not run migration, deploy, merge, archive, production change, TestFlight, push or PR creation while executing this plan unless a later user instruction explicitly authorizes the exact action.

## Approved Mandatory Pipe-Table Decision

The approved contract chooses backend fail-closed rejection. GFM pipe tables
are not BodyFlow content. Task 0 must complete and commit before Task 1 begins:
the backend recognizes a real table through compatible AST extensions, rejects
the `table` node clearly at both author-input boundaries, guards legacy clone,
submit, approval and publish transitions, and revalidates legacy stored
Markdown before the mobile detail service emits any DTO or cover capability.
Rejecting an incompatible `in_review` version remains deliberately available.

No regex or broad `|` search is permitted. The backend must not escape,
rewrite or reinterpret a table as prose, and the iOS parser remains strict.
Ordinary paragraphs containing `|` and escaped `\|` remain valid. Task 8 locks
the reconciled decision through one shared backend/iOS JSON corpus only after
the separate backend and iOS commits in Tasks 6 and 7. The full plan contains
29 sequential tasks: Task 0 followed by Tasks 1 through 28.

## Reconciled Markdown Boundary And Corpus Contract

The backend alone owns editorial-source parsing and `toMarkdown`
canonicalization. It applies `100...50_000` UTF-16 units to the complete
canonical result, including terminal LF, and decides whether the source can be
published. Mobile detail revalidates the stored source and returns only that
canonical result; it never rewrites the stored row. iOS consumes the returned
payload, normalizes CRLF/CR to LF for its independent safety bound, and never
implements or imitates `toMarkdown`.

The shared JSON uses exactly this expectation matrix:

| `accepted` | `native_expectation` | Required fields | Native action |
| --- | --- | --- | --- |
| `true` | `parse_normalized` | `normalized`, `document` | parse canonical payload and compare exact AST |
| `false` | `reject_source` | neither accepted field | parse original source and require semantic rejection |
| `false` | `backend_canonicalization_only` | neither accepted field | make no native-parser call |

`backend_canonicalization_only` is allowed only for
`normalized-body-under-100-characters`,
`normalized-body-over-50000-characters` and
`normalized-crlf-over-50000-utf16-units`. The final 50 fixtures must split
exactly into 11/36/3 rows and leave no unexplained divergence. Tasks 6, 7 and 8
are separate ordered commits; Task 9 cannot begin before all three are GREEN.

## Mandatory Separate Pre-TestFlight Gate

Prompt 14 does not implement or approve live Release transport. TestFlight remains blocked after every task in this plan until a separate workpack designs, security-reviews, implements and tests all three dependencies together:

1. an authenticated HTTP transport restricted to one configuration-injected BodyFlow BFF HTTPS origin, `no-store`, no redirects for covers, and proof that Authorization can never cross origin;
2. an approved staging base URL with no hard-coded production fallback and no host derived from content payloads;
3. an authentication-session bridge that supplies and rotates the current bearer, clears it and cancels patient-scoped work on sign-out/user change, and suppresses every late publication.

That later gate must include same-origin/redirect tests, current-token/rotation tests, sign-out cancellation tests and an explicit distribution approval. A successful Release build from this plan is only a compile/fail-closed check and never authorizes TestFlight.

The Markdown audit is a second independent distribution gate. A separately
authorized live read-only run must report zero incompatible `current` and
`scheduled` visibility candidates before TestFlight. Task 0 documents the
exact activation-point query/output constraints and adds no automatic live
command. If an affected version exists, its historical row remains immutable
and editors create a new compatible version through the existing workflow;
TestFlight stays blocked until a fresh read-only audit is clean in both
candidate classes.

## Authoritative Contract Sources

- `docs/mobile/api-v1.md`
- `packages/core/src/content.ts`
- `packages/core/src/content.test.ts`
- `packages/core/src/coach-messages.ts`
- `apps/admin/src/lib/content/admin-service.ts`
- `apps/admin/src/lib/content/supabase-repository.ts`
- `apps/admin/src/lib/mobile-api/content-service.ts`
- `apps/admin/src/lib/mobile-api/supabase-content.ts`
- `apps/admin/src/lib/mobile-api/coach-service.ts`
- `apps/admin/src/lib/mobile-api/supabase-coach.ts`
- `apps/admin/src/lib/mobile-api/read-model.ts`
- route handlers under `apps/admin/src/app/api/mobile/v1/content`, `coach/persona` and `progress`
- `supabase/migrations/20260501120100_users_core.sql`
- `supabase/migrations/20260721124600_bodyflow_content_cms_domain.sql`
- `supabase/migrations/20260721141618_bodyflow_content_delivery.sql`
- `supabase/migrations/20260722123000_bodyflow_content_visibility_order.sql`
- `supabase/tests/bodyflow_content_delivery.sql`
- `supabase/tests/bodyflow_content_cms.sql`

The Markdown compatibility corpus completed by Task 8 is test-only. It distinguishes `parse_normalized`, `reject_source` and `backend_canonicalization_only`, is checked against the real `validateContentMarkdown` implementation and the applicable native-parser boundary, and does not define a new endpoint or reproduce the backend serializer on iOS.

## Non-Negotiable Contract Invariants

- `GET /content` sends only `surface`, optional approved `category`, `limit` in `1...50`, and an unchanged opaque cursor of `1...512` backend-compatible UTF-16 code units. iOS never sends locale, targeting, score or patient identity.
- Today recommendations use exactly `surface=today&limit=3`; Library/Saved first pages use `limit=20`.
- Detail routes carry only `publicationID` and `origin`; they never carry card summaries, Markdown or card version.
- A card tap performs no `opened` mutation. A current authorized, decoded, validated and Markdown-renderable detail produces exactly one route-lifetime `opened` attempt using the version returned by that detail response.
- Detail failure, unavailability, cancellation, supersession, invalid contract or invalid Markdown produces zero `opened` attempts. `opened` failure is non-blocking, has no automatic retry/offline queue and cannot duplicate within the route lifetime.
- Impression is deduplicated per visible publication/version/origin response. Completion requires explicit action.
- Content mutation retry preserves the exact immutable route, JSON body, version, idempotency key and injected `createdAt`.
- A version conflict reloads catalog and affected detail, discards the old cover and never rewrites/replays the old intent against a new version.
- `swift-markdown` is exactly version `0.8.0`, revision `3c6f9523da3a1ec2fd829673e472d95b8097a3b8`; `Package.resolved` also locks `swift-cmark` 0.8.0 at `924936d0427cb25a61169739a7660230bffa6ea6`.
- Every backend JavaScript string bound is measured with JavaScript `String.length`, equivalent to Swift `utf16.count`; Swift grapheme `String.count` is prohibited for contract limits. The backend applies the `100...50_000` publication bound to the complete `toMarkdown` canonical representation, including terminal LF. iOS independently applies `100...50_000` as a safety bound to the received canonical payload after CRLF/CR → LF and never reproduces `toMarkdown`.
- Backend table detection uses only exact-pinned GFM-table micromark/mdast AST extensions. A `table` node is rejected clearly before normalization; ordinary and escaped pipes remain valid, and neither backend nor iOS uses regex, escaping, rewriting or permissive fallback to hide a table.
- CMS action/service writes invoke the shared validator before persistence. Mobile detail revalidates stored editorial Markdown before cover capability/DTO construction, returns exactly the validator's canonical `normalized` value without rewriting storage, and maps any legacy-invalid body to an opaque error with no partial response or content log.
- The shared corpus contains exactly 50 unique fixtures: 11 `accepted=true`/`parse_normalized`, 36 `accepted=false`/`reject_source` and three named `accepted=false`/`backend_canonicalization_only` cases. The last mode never invokes the native parser.
- Markdown parsing never uses regex as the parser, `AttributedString(markdown:)`, WKWebView, HTML, JavaScript, raw/permissive fallback or remote scripts.
- Cover paths match only `^/api/mobile/v1/content/covers/[A-Za-z0-9_-]+$`. Scheme, host, user info, port, protocol-relative form, query, fragment, percent encoding, backslash, extra segment and traversal fail before transport invocation.
- Cover streaming accepts at most `10_485_760` bytes, checks declared and actual length, requires exact JPEG/PNG/WebP MIME matching ImageIO, rejects invalid/zero/abusive dimensions and downsamples to displayed pixels without `UIImage(data:)` or full-raster decode.
- The session cache enforces `totalCostLimit=33_554_432` and `countLimit=64` with deterministic LRU eviction. Session change/sign-out cancels work, invalidates the stream session and clears both cache and ledger.
- Mascot state/persona come only from `GET /coach/persona`; no local time/activity/health/reward transition is permitted.
- Focus, Impulse and Zen vary presentation only. Balanced, Evolving and Unknown are explicit neutral fallbacks.
- `GET /progress` decodes `MobileResponse<ProgressSnapshot?>`; only `data == nil` is empty. Every non-null row, including `xp_total=0`, `level=1` and `deficit_block=0`, is official loaded data.
- XP, level, current/longest streak and badge strings are literal. Duplicate badge strings remain distinct rows by positional identity.
- Zero streak uses supportive return copy and Today navigation only. No restoration, freeze, grace, countdown, guilt or reward is invented.
- Daily missions render only “Missões diárias — Indisponível nesta versão.” Ranking and cooperative missions have no surface or provider.
- Prompt 14 fixtures, fake streams and temporary mascot art are available only under `#if DEBUG`, previews and tests. Release remains `operationUnavailable` with “Indisponível nesta versão” and contains no Prompt 14 base URL, bearer, outbound request or fixture success.

## Stable Interfaces To Produce

These signatures establish task boundaries. Later tasks may add private helpers but must not broaden network capability or leak package AST types into feature/UI layers.

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
    func recordRead(
        _ attempt: MutationAttempt<ContentReadCommand>
    ) async throws -> PublishedContentStateResponse

    func setSaved(
        _ attempt: MutationAttempt<ContentSaveCommand>
    ) async throws -> PublishedContentStateResponse
}

protocol CoachExperienceProviding: Sendable {
    func coachExperience() async throws -> CoachExperienceResponse
}
```

```swift
enum ContentSurface: String, Codable, Hashable, Sendable {
    case today
    case library
    case saved
}

struct ContentFeedQuery: Equatable, Hashable, Sendable {
    let surface: ContentSurface
    let category: ContentCategory?
    let limit: Int
    let cursor: String?

    init(
        surface: ContentSurface,
        category: ContentCategory?,
        limit: Int,
        cursor: String?
    ) throws
}

enum ContentRoute: Hashable, Sendable {
    case library(initialSelection: LibrarySelection)
    case detail(publicationID: String, origin: ContentOrigin)
}

enum MascotRoute: Hashable, Sendable {
    case detail
}
```

```swift
struct BodyFlowMarkdownDocument: Equatable, Sendable {
    let blocks: [BodyFlowMarkdownBlock]
}

indirect enum BodyFlowMarkdownBlock: Equatable, Sendable {
    case paragraph([BodyFlowMarkdownInline])
    case heading(level: Int, children: [BodyFlowMarkdownInline])
    case blockQuote([BodyFlowMarkdownBlock])
    case list(ordered: Bool, items: [[BodyFlowMarkdownBlock]])
}

indirect enum BodyFlowMarkdownInline: Equatable, Sendable {
    case text(String)
    case strong([BodyFlowMarkdownInline])
    case emphasis([BodyFlowMarkdownInline])
    case link(destination: URL, children: [BodyFlowMarkdownInline])
}

protocol BodyFlowMarkdownParsing: Sendable {
    func parse(_ source: String) throws -> BodyFlowMarkdownDocument
}
```

```swift
struct ContentCoverPath: Equatable, Hashable, Sendable {
    let rawValue: String

    init(validating rawValue: String) throws
}

struct ContentCoverTargetSize: Equatable, Hashable, Sendable {
    let widthPixels: Int
    let heightPixels: Int
}

struct ContentCoverTrustedOrigin: Equatable, Hashable, Sendable {
    let url: URL

    init(validating url: URL) throws
}

struct ContentCoverTransportRequest: Equatable, Sendable {
    let path: ContentCoverPath
    let url: URL

    fileprivate init(path: ContentCoverPath, url: URL)
}

struct ContentCoverImage: @unchecked Sendable {
    let cgImage: CGImage
    let widthPixels: Int
    let heightPixels: Int
}

protocol ContentCoverByteStreaming: Sendable {
    func stream(_ request: ContentCoverTransportRequest) async throws
        -> ContentCoverByteStream
    func cancelAll() async
}

protocol ContentCoverLoading: Sendable {
    func image(
        publicationID: String,
        version: Int,
        cover: PublishedContentCover,
        target: ContentCoverTargetSize
    ) async throws -> ContentCoverImage

    func remove(publicationID: String, version: Int) async
    func endSession() async
}

protocol ContentCoverSessionCreating: Sendable {
    func makeLoader(userID: String) -> any ContentCoverLoading
}
```

`ContentCoverTransportRequest` and its only resolver live in the same `ContentCoverStreaming.swift` file. Its explicit `fileprivate init` prevents every other file in the application module from constructing a request; the resolver combines a validated path with a validated HTTPS trusted origin and then rechecks scheme, host and effective port. The stream boundary is concrete:

```swift
struct ContentCoverByteStream: Sendable {
    let statusCode: Int
    let declaredLength: Int64?
    let mimeType: String?
    let cacheMaxAgeSeconds: Int?
    let redirectLocation: URL?
    let chunks: AsyncThrowingStream<Data, any Error>
    let cancel: @Sendable () async -> Void
}

@MainActor
final class FeatureKeyedLoadController<
    Key: Hashable & Sendable,
    Value: Sendable
> {
    func load(
        key: Key,
        operation: @escaping @Sendable () async throws -> Value,
        publish: @escaping @MainActor (FeatureLoadCompletion<Value>) -> Void
    ) async

    func retry(
        key: Key,
        operation: @escaping @Sendable () async throws -> Value,
        publish: @escaping @MainActor (FeatureLoadCompletion<Value>) -> Void
    ) async

    func cancel()
}
```

The keyed controller retains only the current key, at most one completed key, one sequence and one active ownership token. A changed key discards the prior completed identity, cancels its active work and cannot publish late. `ContentCoverByteStream` contains no bearer or Storage path. The separately gated future authenticated transport owns bearer attachment; Release supplies no trusted origin at all.

Prompt 14 dependency composition uses session factories, not a monolithic feature provider:

```swift
struct PublishedContentSession: Sendable {
    let listing: any PublishedContentListing
    let detail: any PublishedContentDetailProviding
    let state: any PublishedContentStateRecording
    let lifetime: any PublishedContentSessionLifetime
}

protocol PublishedContentSessionCreating: Sendable {
    func makeSession(userID: String) -> PublishedContentSession
}

protocol PublishedContentSessionLifetime: Sendable {
    func endSession() async
}

protocol CoachExperienceSessionCreating: Sendable {
    func makeCoachExperience(userID: String) -> any CoachExperienceProviding
}
```

These factories only create authenticated-shell-scoped protocol capabilities. They define no endpoint and expose no cross-domain repository API. Progress remains the existing independent capability; cover loading has its own session-scoped factory/lifetime.

```swift
typealias ProgressResponse = MobileResponse<ProgressSnapshot?>

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
```

## File Map

### Backend Markdown prerequisite

- Modify `packages/core/package.json` and `pnpm-lock.yaml` only for the exact
  Task 0 GFM-table AST dependencies and Task 6's four exact strikethrough/task-
  list rejection extensions; no broad GFM or rendering extension is allowed.
- Modify `packages/core/src/content.ts` and
  `packages/core/src/content.test.ts` for AST classification, portable semantic
  source rejection, canonical-size boundaries and safe literal text behavior.
- Modify `apps/admin/src/app/(admin)/content/actions.test.ts` to preserve the
  untrusted `saveDraft` boundary test and extend it to every Task 6 portable
  semantic rejection.
- Modify `apps/admin/src/lib/content/admin-service.ts` and
  `apps/admin/src/lib/content/admin-service.test.ts` to add the minimal
  per-version validation snapshot contract and guard source cloning, submit,
  approve and publish while leaving reject available.
- Modify `apps/admin/src/lib/content/supabase-repository.ts` and
  `apps/admin/src/lib/content/supabase-repository.test.ts` for the exact
  seven-column `content_versions` snapshot query; do not reuse publication
  detail/history.
- Modify `apps/admin/src/lib/mobile-api/content-service.ts`,
  `apps/admin/src/lib/mobile-api/content-service.test.ts` and
  `apps/admin/src/app/api/mobile/v1/content/route.test.ts` for atomic,
  fail-closed legacy-body defense and canonical `normalized` delivery before
  cover/DTO emission, without rewriting storage.
- Do not create a live-audit executable in this workpack. Task 0 records the
  exact future read-only query, output allowlist and stop conditions in its
  reviewed checkpoint; running it requires separate explicit authorization.

### Project dependency and shared contract support

- Modify `apps/ios/BodyFlow/BodyFlow.xcodeproj/project.pbxproj` only to add the exact `swift-markdown` package reference and `Markdown` product to the `BodyFlow` application target.
- Create `apps/ios/BodyFlow/BodyFlow.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` through Xcode/SwiftPM resolution; never hand-author a floating pin.
- Modify `apps/ios/BodyFlow/BodyFlow/Core/Support/BodyFlowCapabilityError.swift`.
- Modify `apps/ios/BodyFlow/BodyFlow/Core/Support/Idempotency.swift`.
- Modify `apps/ios/BodyFlow/BodyFlow/Core/Support/FeatureInvalidationCenter.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Support/FeatureKeyedLoadController.swift`.
- Modify `apps/ios/BodyFlow/BodyFlow/Core/Telemetry/TelemetryClient.swift` whenever a new exhaustive `BodyFlowCapabilityError` case is introduced.

### Published-content contracts, Markdown and covers

- Create `apps/ios/BodyFlow/BodyFlow/Core/Content/PublishedContentModels.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Content/PublishedContentProviding.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Content/PublishedContentContractValidator.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Content/BodyFlowMarkdownAST.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Content/BodyFlowMarkdownParser.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Content/MarkdownSourceGuards.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Content/ContentCoverPath.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Content/ContentCoverStreaming.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Content/ContentCoverDecoder.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Content/SessionCoverCache.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Core/Content/ContentCoverLoader.swift`.

### Coach, dependencies and deterministic execution

- Create `apps/ios/BodyFlow/BodyFlow/Core/CoachExperience/CoachExperienceModels.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Core/CoachExperience/CoachExperienceProviding.swift`.
- Create Debug-only `apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoPrompt14Fixtures.swift`.
- Create Debug-only `apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoPrompt14Repository.swift`.
- Create Debug-only `apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoContentCoverByteStream.swift`.
- Modify `apps/ios/BodyFlow/BodyFlow/Core/Unavailable/UnavailableBodyFlowCapabilities.swift`.
- Modify `apps/ios/BodyFlow/BodyFlow/App/AppDependencies.swift`.
- Modify `apps/ios/BodyFlow/BodyFlow/App/AppLaunchConfiguration.swift`.
- Modify `apps/ios/BodyFlow/BodyFlow/App/AppRootView.swift`.
- Modify `apps/ios/BodyFlow/BodyFlow/App/AppRouter.swift`.
- Modify `apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/App/Prompt14SessionOwner.swift`.
- Modify `apps/ios/BodyFlow/BodyFlow/Features/Profile/ProfileRootView.swift`.
- Modify `apps/ios/BodyFlow/BodyFlow/Features/Profile/CoachPersonaEditorModel.swift`.
- Modify `apps/ios/BodyFlow/BodyFlow/Features/Profile/CoachPersonaPickerView.swift`.

### Library, Today, mascot and progress UI

- Create files under `apps/ios/BodyFlow/BodyFlow/Features/Library/`: `PublishedContentFeedViewModel.swift`, `ContentDetailViewModel.swift`, `LibraryRootView.swift`, `PublishedContentCard.swift`, `PublishedContentDetailView.swift`, `BodyFlowMarkdownView.swift`, and `ContentCoverView.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Features/Today/TodayRecommendationsViewModel.swift`.
- Create `apps/ios/BodyFlow/BodyFlow/Features/Today/TodayRecommendationsSection.swift`.
- Modify `apps/ios/BodyFlow/BodyFlow/Features/Today/TodayRootView.swift`.
- Create files under `apps/ios/BodyFlow/BodyFlow/Features/Mascot/`: `MascotExperienceViewModel.swift`, `MascotPresentation.swift`, `MascotCardView.swift`, `MascotDetailView.swift`, and Debug-only `MascotPlaceholderArtwork.swift`.
- Modify `apps/ios/BodyFlow/BodyFlow/Core/Progress/ProgressModels.swift`.
- Modify `apps/ios/BodyFlow/BodyFlow/Features/Progress/ProgressViewModel.swift`.
- Modify `apps/ios/BodyFlow/BodyFlow/Features/Progress/ProgressComponents.swift`.
- Modify `apps/ios/BodyFlow/BodyFlow/Features/Progress/ProgressRootView.swift`.
- Create Debug-only `apps/ios/BodyFlow/BodyFlow/Features/PreviewSupport/Prompt14PreviewSupport.swift`.
- Modify `apps/ios/BodyFlow/BodyFlow/Core/Telemetry/TelemetryClient.swift` only for bounded Prompt 14 screen/outcome/state classifications; never log body, title, excerpt, badge text or cover capability.

### Unit, integration, UI and compatibility tests

- Create focused Swift Testing files under `apps/ios/BodyFlow/BodyFlowTests/`: `PublishedContentContractTests.swift`, `CoachExperienceContractTests.swift`, `FeatureKeyedLoadControllerTests.swift`, `BodyFlowMarkdownParserTests.swift`, `MarkdownBackendCompatibilityTests.swift`, `ContentCoverPathTests.swift`, `ContentCoverDecoderTests.swift`, `SessionCoverCacheTests.swift`, `ContentCoverLoaderTests.swift`, `DemoPrompt14RepositoryTests.swift`, `PublishedContentFeedViewModelTests.swift`, `ContentDetailViewModelTests.swift`, `LibraryPresentationTests.swift`, `TodayRecommendationsTests.swift`, `MascotPresentationTests.swift`, `MascotExperienceViewModelTests.swift`, `Prompt14LaunchConfigurationTests.swift`, `Prompt14ReleaseBoundaryTests.swift`, `Prompt14TelemetryPrivacyTests.swift`, and `Prompt14PreviewSupportTests.swift`.
- Create focused Swift Testing support/files under `apps/ios/BodyFlow/BodyFlowTests/`: `Fixtures/Prompt14CoverFixtures.swift`, `Prompt14SessionOwnershipTests.swift`, `ContentCoverViewModelTests.swift`, and `MascotAccessibilityModelTests.swift`.
- Create `apps/ios/BodyFlow/BodyFlowTests/Fixtures/Prompt14MarkdownCompatibility.json`.
- Create `packages/core/src/content-ios-compatibility.test.ts` to validate the exact `native_expectation` schema/counts and run the same JSON corpus through the hardened backend validator; Task 8 does not modify production parser behavior.
- Modify `apps/ios/BodyFlow/BodyFlowTests/AppDependenciesTests.swift`.
- Modify `apps/ios/BodyFlow/BodyFlowTests/AppRouterTests.swift`.
- Modify `apps/ios/BodyFlow/BodyFlowTests/BodyFlowTestFixtures.swift`.
- Modify `apps/ios/BodyFlow/BodyFlowTests/PlanProgressContractTests.swift`.
- Modify `apps/ios/BodyFlow/BodyFlowTests/ProgressViewModelTests.swift`.
- Modify `apps/ios/BodyFlow/BodyFlowTests/ProgressPresentationTests.swift`.
- Create `apps/ios/BodyFlow/BodyFlowUITests/Prompt14UITestSupport.swift`.
- Create `apps/ios/BodyFlow/BodyFlowUITests/Prompt14LibraryUITests.swift`.
- Create `apps/ios/BodyFlow/BodyFlowUITests/Prompt14TodayMascotUITests.swift`.
- Create `apps/ios/BodyFlow/BodyFlowUITests/Prompt14ProgressUITests.swift`.
- Create `apps/ios/BodyFlow/BodyFlowUITests/Prompt14AccessibilityUITests.swift`.
- Create verification evidence under `docs/superpowers/evidence/2026-08-02-bodyflow-ios-library-mascot-gamification/` only in the final gate task.

---

### Task 0: Reject GFM Pipe Tables At Every Backend Content Boundary

> **Committed checkpoint:** Task 0 records the implementation that established
> table rejection and legacy guards. Its valid-detail behavior of returning the
> stored body unchanged is intentionally superseded by Task 6, which returns
> the validator's canonical value without rewriting storage. Do not rerun or
> amend the Task 0 commit.

This task is mandatory and must be committed before Task 1 starts. It changes
the existing backend Markdown contract only; it adds no mobile endpoint,
database migration, live audit or iOS behavior.

**Files:**
- Modify: `packages/core/package.json`
- Modify: `pnpm-lock.yaml`
- Modify: `packages/core/src/content.ts`
- Modify: `packages/core/src/content.test.ts`
- Modify: `apps/admin/src/app/(admin)/content/actions.test.ts`
- Modify: `apps/admin/src/lib/content/admin-service.ts`
- Modify: `apps/admin/src/lib/content/admin-service.test.ts`
- Modify: `apps/admin/src/lib/content/supabase-repository.ts`
- Modify: `apps/admin/src/lib/content/supabase-repository.test.ts`
- Modify: `apps/admin/src/lib/mobile-api/content-service.ts`
- Modify: `apps/admin/src/lib/mobile-api/content-service.test.ts`
- Modify: `apps/admin/src/app/api/mobile/v1/content/route.test.ts`

**Interfaces:**
- Consumes: existing `validateContentMarkdown`, `contentDraftInputSchema`, CMS
  `saveDraft` action/service boundaries, admin `createDraft`/`submit`/`review`/
  `publish`, `ContentRepository.get`, `getContent`, the editorial RPC
  concurrency contract and the current opaque `MobileApiError` mapping.
- Produces: exact-pinned GFM-table AST recognition solely for rejection; a
  seven-field `ContentVersionValidationSnapshot` repository capability;
  legacy clone/workflow guards; and atomic mobile-detail revalidation before
  cover/DTO work.
- Preserves: the existing CMS normalization contract for allowed Markdown and
  the original stored `bodyMarkdown` bytes returned by a valid detail; reject
  remains available; submit's locked RPC remains the stale authority. It adds
  no table renderer, alternate parser, endpoint, migration or live query.

- [ ] **Step 1: Revalidate the documentary and dependency preconditions**

Confirm the approved specification contains the pipe-table rule, both
author-input boundaries, every legacy clone/workflow guard, mobile-detail
defense and current/scheduled read-only audit gate. Confirm the branch and
clean worktree, then prove the existing versions before changing anything:

```bash
set -euo pipefail
test "$(git branch --show-current)" = \
  "codex/bodyflow-ios-library-mascot-gamification-v1"
test -z "$(git status --porcelain)"
rg -n '"mdast-util-from-markdown": "2\.0\.3"' packages/core/package.json
rg -n '"mdast-util-to-markdown": "2\.1\.2"' packages/core/package.json
git diff --exit-code -- pnpm-workspace.yaml
```

Expected: exact current pins and no workspace-file drift. Do not contact the
live database and do not run a Supabase linked command.

- [ ] **Step 2: Add every focused test first and observe the intended RED**

In `packages/core/src/content.test.ts`, add literal tests proving:

1. a 100...50,000-UTF-16-unit, syntactically valid GFM pipe table is rejected
   with the clear bounded message
   `Invalid content Markdown: tables are not supported`;
2. a length-valid ordinary paragraph containing `|` remains accepted as one
   paragraph/text AST;
3. a length-valid paragraph containing escaped `\|` remains accepted;
4. neither accepted case is classified by searching raw pipe characters.

Use the same table-bearing draft in the CMS suites. The action test must prove
untrusted `saveDraft` input is rejected before `service.saveDraft`; the service
test must prove direct service input is rejected before
`repository.saveDraft`.

In `apps/admin/src/lib/content/supabase-repository.test.ts`, first require a
new `getVersionValidationSnapshot(versionId, expectedUpdatedAt?)` capability.
Its strict row fixture and query log must prove that it:

- selects exactly `id, publication_id, locale, state, body_markdown,
  updated_at, publish_at` from `content_versions`;
- filters by `id` and, only when supplied, by `updated_at`;
- maps only `versionId`, `publicationId`, `locale`, `state`, `bodyMarkdown`,
  `updatedAt` and `publishAt`;
- returns null for a missing row and maps malformed/provider failures through
  the existing opaque repository error path;
- performs no publication-detail/history, target, asset or admin-identity
  query.

In `apps/admin/src/lib/content/admin-service.test.ts`, add controlled snapshot
and mutation spies proving all workflow guards before their repositories are
called:

1. `createDraft` with an immutable source containing a table never calls
   `repository.createDraft`;
2. a legacy table-bearing draft never calls `repository.submit`;
3. a table-bearing `in_review` version never calls
   `repository.review(decision=approve)`;
4. the same `in_review` version can call
   `repository.review(decision=reject)`, without a validation-snapshot read;
5. a table-bearing approved version never calls `repository.publish`;
6. a valid ordinary-pipe body advances through source clone, submit, approve
   and publish without normalization or rewriting;
7. a submit whose exact-`expectedUpdatedAt` snapshot is no longer available
   because the row changed but remains `draft` still delegates to the locked
   submit RPC and surfaces its existing `stale` result; the same draft-revision
   race raised after a matching valid preflight also remains `stale`, while a
   controlled state transition after a matching valid preflight preserves the
   RPC's lifecycle error;
8. absent source/approve/publish snapshots fail closed as `not_found` without
   calling their mutation repositories;
9. a source snapshot with wrong publication/locale/state, or an approve/publish
   snapshot with the wrong lifecycle, fails locally as `lifecycle` without
   calling a mutation; include an incompatible `in_review` source and prove it
   cannot reach
   `repository.createDraft` even though a concurrent reject could make that
   source eligible;
10. a submit snapshot already in the wrong lifecycle delegates to the locked
    RPC and preserves its lifecycle error;
11. null or invalid Markdown fails closed and no incompatible body is cloned,
    persisted, approved or published.

`createDraft` without `sourceVersionId` remains unchanged. Do not add a body
field to its command. The source guard exists specifically because the real
`create_content_draft` RPC copies `v_source.body_markdown`.

In the mobile service and route suites, make the repository return a legacy
record whose body is that valid pipe table and whose cover is non-null. Assert:

- `getContent` fails with only `500/internal_error`;
- `covers.issue` is never called;
- the route's atomic error response contains neither `body_markdown` nor any
  table cell/source fragment;
- no partially successful detail payload exists.

Run all new tests against the current implementation:

```bash
set -euo pipefail
bodyflow_expect_red() {
  local red_status
  set +e
  "$@"
  red_status=$?
  set -e
  test "$red_status" -ne 0
}
bodyflow_expect_red pnpm --filter @mpp/core test -- content.test.ts
bodyflow_expect_red pnpm --filter @mpp/admin test -- \
  'src/app/(admin)/content/actions.test.ts'
bodyflow_expect_red pnpm --filter @mpp/admin test -- \
  src/lib/content/admin-service.test.ts
bodyflow_expect_red pnpm --filter @mpp/admin test -- \
  src/lib/content/supabase-repository.test.ts
bodyflow_expect_red pnpm --filter @mpp/admin test -- \
  src/lib/mobile-api/content-service.test.ts
bodyflow_expect_red pnpm --filter @mpp/admin test -- \
  src/app/api/mobile/v1/content/route.test.ts
```

Expected RED: the current parser accepts the pipe table as paragraph text, the
minimal snapshot does not exist, and clone/submit/approve/publish do not guard
stored bodies. Each command exits non-zero for its intended missing behavior:
core AST rejection, untrusted CMS action, admin workflow service, exact
snapshot repository, mobile detail service and atomic route. Ordinary and
escaped-pipe acceptance assertions inside the core run must already pass; if
they fail, correct the fixtures rather than weakening the contract. Inspect
each report and record the named failing assertion; an unrelated compile,
fixture or infrastructure failure is not an acceptable RED.

- [ ] **Step 3: Add only the exact compatible AST dependencies**

Add exact `micromark-extension-gfm-table` `2.1.1` and
`mdast-util-gfm-table` `2.0.0` to `@mpp/core`. Keep
`mdast-util-from-markdown` exactly `2.0.3` and `mdast-util-to-markdown` exactly
`2.1.2`. The mdast GFM-table package's `2.0.0` dependency ranges accept both
existing mdast 2.x pins; the micromark extension is compatible with the
parser's micromark 4 line.

```bash
set -euo pipefail
pnpm --filter @mpp/core add --save-exact \
  micromark-extension-gfm-table@2.1.1 \
  mdast-util-gfm-table@2.0.0
git diff --exit-code -- pnpm-workspace.yaml
rg -n '"mdast-util-from-markdown": "2\.0\.3"' packages/core/package.json
rg -n '"mdast-util-to-markdown": "2\.1\.2"' packages/core/package.json
rg -n '"micromark-extension-gfm-table": "2\.1\.1"' packages/core/package.json
rg -n '"mdast-util-gfm-table": "2\.0\.0"' packages/core/package.json
python3 - <<'PY'
import re
from pathlib import Path

lock = Path('pnpm-lock.yaml').read_text()
match = re.search(r'^  packages/core:\n(.*?)(?=^  \S|\Z)', lock, re.M | re.S)
assert match is not None
importer = match.group(1)
for package, version in {
    'mdast-util-from-markdown': '2.0.3',
    'mdast-util-to-markdown': '2.1.2',
    'micromark-extension-gfm-table': '2.1.1',
    'mdast-util-gfm-table': '2.0.0',
}.items():
    exact = (
        f'      {package}:\n'
        f'        specifier: {version}\n'
        f'        version: {version}\n'
    )
    assert exact in importer, (package, 'importer pin mismatch')
    assert re.search(rf'^  {re.escape(package)}@{re.escape(version)}:', lock, re.M), (
        package,
        'resolved lock entry missing',
    )
print('Task 0 lock pins: PASS')
PY
```

Expected: only `packages/core/package.json` and `pnpm-lock.yaml` change at this
step. Do not add the broad GFM bundle or a table-to-Markdown extension.

- [ ] **Step 4: Implement the minimal AST, snapshot and workflow GREEN**

In `packages/core/src/content.ts`, import `gfmTable` from
`micromark-extension-gfm-table` and `gfmTableFromMarkdown` from
`mdast-util-gfm-table`. Parse with exactly:

```typescript
fromMarkdown(source, {
  extensions: [gfmTable()],
  mdastExtensions: [gfmTableFromMarkdown()],
})
```

Add an explicit `case 'table'` to the exhaustive block conversion that throws
`Invalid content Markdown: tables are not supported`. Reject before
`toMarkdown`; do not install `gfmTableToMarkdown`, use regex, scan `|`, escape
the table or add permissive fallback. This makes the existing
`contentDraftInputSchema` enforce the decision at both author-input CMS write
boundaries.

In `apps/admin/src/lib/content/admin-service.ts`, add only the narrow contract:

```typescript
interface ContentVersionValidationSnapshot {
  versionId: string
  publicationId: string
  locale: 'pt-BR' | 'en-US'
  state: 'draft' | 'in_review' | 'approved' | 'rejected'
  bodyMarkdown: string | null
  updatedAt: string
  publishAt: string | null
}

getVersionValidationSnapshot(
  versionId: string,
  expectedUpdatedAt?: string,
): Promise<ContentVersionValidationSnapshot | null>
```

Implement it in `apps/admin/src/lib/content/supabase-repository.ts` with a
strict schema over exactly
`id, publication_id, locale, state, body_markdown, updated_at, publish_at` and
`eq('id', versionId).maybeSingle()`. When `expectedUpdatedAt` is present, add
only `eq('updated_at', expectedUpdatedAt)` so PostgreSQL applies the timestamp
equality used by the submit preflight. Do not call
`ContentAdminRepository.get(publicationId)` or query publication history,
targets, assets or identities.

Add one shared admin-service helper that calls `validateContentMarkdown` and
discards its normalized output. It must never log or rewrite `bodyMarkdown`.
Apply it as follows:

- a `createDraft` without `sourceVersionId` delegates unchanged; with a source,
  read its snapshot, require the command's publication/locale and the RPC's
  immutable `approved`/`rejected` source lifecycle, then validate before
  `repository.createDraft`;
- `submit` requests the snapshot with the command's exact
  `expectedUpdatedAt`, requires `draft`, validates it, then calls
  `repository.submit` with the original precondition unchanged;
- `review(approve)` reads an `in_review` snapshot and validates it before its
  RPC;
- `review(reject)` calls the existing RPC directly, with no snapshot read, so
  incompatible content can be rejected out of the workflow;
- `publish` reads an `approved` snapshot with null `publishAt` and validates it
  before its RPC.

If an unfiltered source/approve/publish snapshot is absent, return the existing
bounded admin `not_found` error and call no mutation. Return the bounded admin
`lifecycle` error with no mutation when the source publication/locale/state
does not match, approval is not `in_review`, or publish is not `approved` with
null `publishAt`. This local source stop is mandatory: delegating an
incompatible `in_review` source could race with allowed `review(reject)` and
let the RPC clone it after it becomes `rejected`. If the submit query has no
matching `draft` snapshot for `expectedUpdatedAt`, or finds a snapshot already
outside `draft`, delegate unchanged to the submit RPC solely so its locked
checks return the authoritative `stale`/not-found/lifecycle result; do not
manufacture those outcomes in TypeScript. A concurrent body update that leaves
the row in `draft` returns `stale`; a concurrent submit that changes state
after a valid preflight returns the RPC lifecycle error. The database's
existing immutability rules keep eligible source, `in_review` and `approved`
bodies unchanged between a successful validation and transition. Any
applicable snapshot with null or invalid `bodyMarkdown` fails closed before the
mutation call. Do not change an RPC or migration.

In `apps/admin/src/lib/mobile-api/content-service.ts`, call
`validateContentMarkdown(record.bodyMarkdown)` immediately after the
repository returns a non-null detail and before `mapFeedItem` can issue a cover
capability. Discard the validation result and return the original stored
`record.bodyMarkdown` only after success. Map any validation failure to the
existing opaque `internal_error`; never include the validator message or body
in logs or response details.

- [ ] **Step 5: Reach focused GREEN, refactor and prove atomic failure**

Run the Step 2 commands again. Then refactor only duplicated synthetic fixture
construction, keeping the production path minimal. Assert the accepted
ordinary/escaped pipe ASTs literally; the exact seven-column snapshot query;
zero clone/submit/approve/publish calls for matching incompatible snapshots;
reject availability; absent and lifecycle-mismatch local stops; the unsafe
`in_review` source/reject race; both authoritative draft-revision stale timings;
post-preflight lifecycle preservation; and that the detail route never issues
a cover or serializes a partial body.

```bash
set -euo pipefail
pnpm --filter @mpp/core test -- content.test.ts
pnpm --filter @mpp/admin test -- \
  'src/app/(admin)/content/actions.test.ts' \
  src/lib/content/admin-service.test.ts \
  src/lib/content/supabase-repository.test.ts \
  src/lib/mobile-api/content-service.test.ts \
  src/app/api/mobile/v1/content/route.test.ts
git diff --check
```

Expected GREEN: all literal tests pass; invalid Markdown is never persisted,
cloned, approved, published, served or partially rendered; ordinary/escaped
pipes still work; reject and RPC-owned stale behavior are preserved.

- [ ] **Step 6: Review the future live read-only audit without executing it**

Record the following runbook in the Task 0 review/commit handoff; do not create
or invoke a linked-database command in this task:

1. obtain separate explicit authorization, open one read-only snapshot and
   freeze one `audit_timestamp` for the entire calculation;
2. read only `public.content_versions` joined to
   `public.content_publications`, internally selecting the fields needed for
   eligibility, ordering and parsing; include only non-archived publications
   and versions with `state='approved'` and non-null `publish_at`;
3. partition by `(publication_id, locale)`, create activation points at
   `audit_timestamp` and at every distinct future `publish_at`, and at each
   point rank all rows with `publish_at <= activation_at` by exactly
   `version DESC, publish_at DESC`;
4. label the winner at `audit_timestamp` as `candidate_class=current`; label a
   newly winning version at a later activation as
   `candidate_class=scheduled`; deduplicate unchanged winners;
5. exclude a historical or future row only when the same ordering proves that
   it cannot win now or at any future activation. Exclude approved rows with
   null `publish_at`: they cannot activate automatically and any later publish
   command passes through the new guard;
6. scan the conservative current/scheduled union before patient-specific
   targeting; query no user, profile, preference, subscription, health or
   other PII table;
7. pass only candidate bodies directly to the same
   `validateContentMarkdown` implementation in memory, without printing,
   logging, persisting or including Markdown/parser details in an exception;
8. emit aggregate scanned/compatible/incompatible counts separated by class
   and, only for affected rows, `version_id`, `publication_id`, numeric
   `version`, `locale`, `state` and `candidate_class` (`current` or
   `scheduled`). Never emit `body_markdown`, `publish_at`, activation time,
   title, excerpt, tags or content fragments;
9. expose no apply mode and perform no insert, update, delete, RPC mutation,
   migration or editorial state transition.

The later audit workpack must fixture-review at least: a current highest
version; first future winner with no current row; a higher future winner; a
lower future version shadowed by a higher current version; a later lower
version shadowed by an earlier higher schedule; same-activation ordering;
archived, unscheduled and non-approved exclusion; winner deduplication; and an
exact output-key allowlist with no Markdown or PII. This task does not build or
run that audit.

If the future audit reports any incompatible `current` or `scheduled`
candidate, stop the TestFlight gate. Do not alter a historical version or
clone an incompatible source. Create and publish a new compatible version only
through the existing editorial workflow, then rerun the read-only audit under
fresh authorization. Task 1 may follow Task 0 GREEN without a live audit;
TestFlight may not proceed until both incompatible counts are zero.

- [ ] **Step 7: Run the backend checkpoint, review and commit Task 0**

```bash
set -euo pipefail
pnpm --filter @mpp/core test
pnpm --filter @mpp/core typecheck
pnpm --filter @mpp/admin test
pnpm --filter @mpp/admin typecheck
git diff --check
git status --short
```

Review the diff against this exact allowlist, verify no migration, live/real
content body or audit output is present, and confirm that the only Markdown
bodies are the reviewed synthetic test fixtures before making one conventional
checkpoint:

```bash
git add packages/core/package.json \
  pnpm-lock.yaml \
  packages/core/src/content.ts \
  packages/core/src/content.test.ts \
  'apps/admin/src/app/(admin)/content/actions.test.ts' \
  apps/admin/src/lib/content/admin-service.ts \
  apps/admin/src/lib/content/admin-service.test.ts \
  apps/admin/src/lib/content/supabase-repository.ts \
  apps/admin/src/lib/content/supabase-repository.test.ts \
  apps/admin/src/lib/mobile-api/content-service.ts \
  apps/admin/src/lib/mobile-api/content-service.test.ts \
  apps/admin/src/app/api/mobile/v1/content/route.test.ts
git diff --cached --name-only
test "$(git diff --cached --name-only | wc -l | tr -d ' ')" -eq 12
git commit -m "fix(content): reject pipe-table markdown"
```

Expected: one Task 0 commit touching only the twelve listed files. No live
audit, migration, deploy, push, PR, merge or TestFlight action occurs.

### Task 1: Define And Validate Published Content Contracts

> **Committed checkpoint:** Task 1 established the wire DTO and initial body
> bound. Task 7 supersedes only its raw-body size check by measuring the
> received payload after CRLF/CR → LF; the decoded canonical body itself remains
> lossless and unmodified. Do not amend the Task 1 commit.

**Files:**
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Content/PublishedContentModels.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Content/PublishedContentProviding.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Content/PublishedContentContractValidator.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Core/Support/BodyFlowCapabilityError.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Core/Telemetry/TelemetryClient.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/PublishedContentContractTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/CapabilitySupportTests.swift`

**Interfaces:**
- Consumes: `MobileResponse`, `MobileResponseMetadata`, `APITimestamp`.
- Produces: the four content capabilities and exact DTO/query/command/state types shown in the approved specification.

- [ ] **Step 1: Write the contract tests first**

Create literal JSON tests that assert all eleven categories, all three surfaces, flat detail decoding, nullable cover, opaque cursor preservation, strict read/save bodies and consolidated state fields. Include malformed summary cases for UUID, slug, locale, title, excerpt, duplicate/invalid tags, reading-time and version bounds. Add literal query-boundary cases proving limits `1` and `50` plus cursor lengths `1` and `512` UTF-16 units are accepted; limits `0`/`51` throw `.invalidContentContract`, while cursors empty/length `513` throw `.invalidContentCursor`. Add emoji/surrogate-pair cases for cursor, title, excerpt and body proving `utf16.count` parity with backend JavaScript rather than Swift grapheme `count`. Add capability-support tests for both new errors' bounded telemetry mapping so the exhaustive switch changes in the same task.

```swift
@Test("detail is flat on the wire and adds only body_markdown")
func decodesFlatDetail() throws {
    let response = try JSONDecoder().decode(
        PublishedContentDetailResponse.self,
        from: Prompt14ContractJSON.detail
    )
    #expect(response.data.summary.publicationID == Prompt14ContractJSON.publicationID)
    #expect(response.data.summary.version == 4)
    #expect(response.data.bodyMarkdown.hasPrefix("## Exemplo"))
    try PublishedContentContractValidator.validate(response.data)
}

@Test("route identity is absent from strict mutation bodies")
func encodesStrictBodies() throws {
    let read = ContentReadCommand(
        publicationID: Prompt14ContractJSON.publicationID,
        body: ContentReadBody(event: .opened, origin: .library, version: 4)
    )
    let save = ContentSaveCommand(
        publicationID: Prompt14ContractJSON.publicationID,
        body: ContentSaveBody(saved: true, version: 4)
    )
    #expect(try encodedKeys(read.body) == ["event", "origin", "version"])
    #expect(try encodedKeys(save.body) == ["saved", "version"])
}

private func encodedKeys<Value: Encodable>(_ value: Value) throws -> Set<String> {
    let data = try JSONEncoder().encode(value)
    guard let object = try JSONSerialization.jsonObject(with: data)
        as? [String: Any] else {
        return []
    }
    return Set(object.keys)
}
```

- [ ] **Step 2: Run the focused suite and observe RED**

```bash
set -euo pipefail
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -only-testing:BodyFlowTests/PublishedContentContractTests \
  -only-testing:BodyFlowTests/CapabilitySupportTests \
  test
```

Expected RED: compile failure for missing content DTOs/protocols/validator.

- [ ] **Step 3: Implement the minimal exact models and validator**

First add `.invalidContentContract` and `.invalidContentCursor` to `BodyFlowCapabilityError` and map both to the existing bounded `.invalidInput` telemetry category so the target remains exhaustive. Then define snake-case coding keys, lossless opaque cursor storage, exact category/surface enums, flat-detail custom decoding into `PublishedContentDetail(summary:bodyMarkdown:)`, and validation that rejects rather than truncates/normalizes malformed server fields. `ContentFeedQuery` validates limit/cursor once at construction and never trims, derives or decodes a cursor. Query and DTO validators use `.utf16.count` for every backend-bounded string that may contain non-ASCII text; ASCII-only UUID/slug/tag/capability rules keep their explicit scalar/byte checks.

```swift
struct PublishedContentFeed: Codable, Equatable, Sendable {
    let items: [PublishedContentSummary]
    let nextCursor: String?

    private enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }
}

enum PublishedContentContractValidator {
    static func validate(_ detail: PublishedContentDetail) throws {
        try validate(detail.summary)
        guard (100...50_000).contains(detail.bodyMarkdown.utf16.count) else {
            throw BodyFlowCapabilityError.invalidContentContract
        }
    }
}
```

The validator uses deterministic ASCII/scalar checks for UUID/slug/tag invariants and never repairs received values. It does not parse cover URLs or Markdown; Tasks 4–11 own those boundaries.

- [ ] **Step 4: Reach GREEN and refactor**

Run both focused suites again. Then extract fixture-only `Prompt14ContractJSON` inside the test file, verify no provider method constructs an endpoint, and run:

```bash
git diff --check
```

- [ ] **Step 5: Review and commit**

Review contract adherence and Swift 6 `Sendable` conformance, then commit only Task 1 files:

```bash
git add apps/ios/BodyFlow/BodyFlow/Core/Content/PublishedContentModels.swift \
  apps/ios/BodyFlow/BodyFlow/Core/Content/PublishedContentProviding.swift \
  apps/ios/BodyFlow/BodyFlow/Core/Content/PublishedContentContractValidator.swift \
  apps/ios/BodyFlow/BodyFlow/Core/Support/BodyFlowCapabilityError.swift \
  apps/ios/BodyFlow/BodyFlow/Core/Telemetry/TelemetryClient.swift \
  apps/ios/BodyFlow/BodyFlowTests/PublishedContentContractTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/CapabilitySupportTests.swift
git commit -m "feat(ios): add published content contracts"
```

### Task 2: Define Coach Experience And Correct The Progress Wire Contract

**Files:**
- Create: `apps/ios/BodyFlow/BodyFlow/Core/CoachExperience/CoachExperienceModels.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/CoachExperience/CoachExperienceProviding.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/CoachExperienceContractTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Core/Progress/ProgressModels.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoBodyFlowFixtures.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Progress/ProgressViewModel.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Progress/ProgressComponents.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/PlanProgressContractTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/BodyFlowTestFixtures.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/ProgressViewModelTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/ProgressPresentationTests.swift`

**Interfaces:**
- Consumes: `MobileResponse`, `APITimestamp` and the existing `ProgressProviding` boundary.
- Produces: `CoachExperienceProviding`, lossless `MascotWireState`, `ProgressResponse == MobileResponse<ProgressSnapshot?>`, and non-null `ProgressSnapshot.deficitBlock`.

- [ ] **Step 1: Add literal RED contract cases**

Add coach JSON tests for selected-null/effective-balanced, localized options, all five wire states, unknown raw preservation and exact `bodyflow.coach-persona.v1`. Replace every synthetic progress-empty row fixture with literal `data: null`, assert the minimum non-null row remains real data, and update view-model/presentation RED cases so only nil is empty and literal `deficit_block=0` displays `0 kcal`.

```swift
@Test("minimum persisted progress is non-null official data")
func decodesMinimumProgress() throws {
    let response = try JSONDecoder().decode(
        ProgressResponse.self,
        from: Prompt14ProgressJSON.minimum
    )
    let snapshot = try #require(response.data)
    #expect(snapshot.xpTotal == 0)
    #expect(snapshot.level == 1)
    #expect(snapshot.deficitBlock == 0)
}

@Test("unknown mascot value is preserved without mapping to active")
func preservesUnknownMascot() throws {
    let state = try JSONDecoder().decode(
        MascotWireState.self,
        from: Data("\"future_state\"".utf8)
    )
    #expect(state == .unknown("future_state"))
}
```

- [ ] **Step 2: Run RED**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -only-testing:BodyFlowTests/CoachExperienceContractTests \
  -only-testing:BodyFlowTests/PlanProgressContractTests \
  -only-testing:BodyFlowTests/ProgressViewModelTests \
  -only-testing:BodyFlowTests/ProgressPresentationTests \
  test
```

Expected RED: missing coach types and failure to decode nullable progress/non-null `deficit_block` under the old model.

- [ ] **Step 3: Implement GREEN contract types**

```swift
enum MascotWireState: Equatable, Sendable, Codable {
    case inactive
    case reactivating
    case active
    case evolving
    case neglected
    case unknown(String)
}

typealias CoachExperienceResponse = MobileResponse<CoachExperienceSnapshot>
typealias ProgressResponse = MobileResponse<ProgressSnapshot?>
```

Use custom `MascotWireState` decoding/encoding to preserve unknown raw values. Validate coach contract version at the presenter/view-model boundary, not by accepting unsupported semantics. Make `deficitBlock` an `Int`; only measurements and documented dates remain optional. In the same GREEN, change `ProgressViewModel` to switch on `response.data` (`nil` → `.empty`, non-null → `.loaded`), remove the impossible zero-row heuristic, render non-null deficit literally, and update both inherited fixture families. Do not add the new medal/missions UI yet; Task 25 owns that presentation increment.

- [ ] **Step 4: Run GREEN, refactor and check the diff**

Run all four focused suites from Step 2, confirm no level/XP threshold fields were added, and run `git diff --check`.

- [ ] **Step 5: Commit**

```bash
git add apps/ios/BodyFlow/BodyFlow/Core/CoachExperience/CoachExperienceModels.swift \
  apps/ios/BodyFlow/BodyFlow/Core/CoachExperience/CoachExperienceProviding.swift \
  apps/ios/BodyFlow/BodyFlow/Core/Progress/ProgressModels.swift \
  apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoBodyFlowFixtures.swift \
  apps/ios/BodyFlow/BodyFlow/Features/Progress/ProgressViewModel.swift \
  apps/ios/BodyFlow/BodyFlow/Features/Progress/ProgressComponents.swift \
  apps/ios/BodyFlow/BodyFlowTests/CoachExperienceContractTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/PlanProgressContractTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/BodyFlowTestFixtures.swift \
  apps/ios/BodyFlow/BodyFlowTests/ProgressViewModelTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/ProgressPresentationTests.swift
git commit -m "fix(ios): align coach and progress contracts"
```

### Task 3: Add Content Errors, Attempts, Invalidation And Composite Load Ownership

**Files:**
- Modify: `apps/ios/BodyFlow/BodyFlow/Core/Support/BodyFlowCapabilityError.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Core/Support/Idempotency.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Core/Support/FeatureInvalidationCenter.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Support/FeatureKeyedLoadController.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Core/Telemetry/TelemetryClient.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/CapabilitySupportTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/FeatureInvalidationTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/FeatureKeyedLoadControllerTests.swift`

**Interfaces:**
- Consumes: existing `MutationAttempt`, `TimeProviding`, `IdempotencyKeyProviding`, `FeatureLoadOwnership`.
- Produces: `.contentRead`, `.contentSave`, content/coach errors, content invalidation keys/events, and `FeatureKeyedLoadController<Key, Value>`.

- [ ] **Step 1: Write RED execution-policy tests**

Assert the exact invalidation matrix, immutable retry attempts and composite-key behavior. A newer `(query, revision)` must cancel and suppress an older result; the same completed key must not reload; explicit retry may repeat only the current key.

```swift
@Test("content mutation invalidation never patches Today nutrition")
@MainActor
func contentInvalidationMatrix() {
    let center = FeatureInvalidationCenter()
    center.record(.contentSaved(publicationID: "publication-1"))
    #expect(center.revision(for: .contentCatalog) == 1)
    #expect(center.revision(for: .contentDetail("publication-1")) == 1)
    #expect(center.revision(for: .today) == 0)
}
```

The composite-supersession test must use checked continuations and an actor call counter: start key A, start key B, complete B with `"new"`, complete A with `"old"`, and assert the publication array is exactly `["new"]`. It must not use sleeps.

- [ ] **Step 2: Run RED**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -only-testing:BodyFlowTests/CapabilitySupportTests \
  -only-testing:BodyFlowTests/FeatureInvalidationTests \
  -only-testing:BodyFlowTests/FeatureKeyedLoadControllerTests \
  test
```

Expected RED: missing content operations/keys/events and keyed controller.

- [ ] **Step 3: Implement minimal GREEN primitives**

Add only documented error categories not already introduced in Task 1: unsupported Markdown/coach contract, content not found, cover not found, invalid cover, cover too large, subscription required, version changed, idempotency in progress and coach locale unsupported. The exact new cases are `.unsupportedMarkdown`, `.unsupportedCoachContract`, `.contentNotFound`, `.contentCoverNotFound`, `.invalidContentCover`, `.contentCoverTooLarge`, `.subscriptionRequired`, `.contentVersionChanged`, `.idempotencyRequestInProgress`, and `.coachLocaleUnsupported`. Update `TelemetryClient.swift` in the same GREEN so its exhaustive switch compiles; map only to bounded existing error classes until Task 26 adds reviewed Prompt 14 screen/outcome classifications.

```swift
enum FeatureInvalidationKey: Hashable, Sendable {
    case today
    case history
    case routineList(kind: RoutineItemKind)
    case routineHistory(kind: RoutineItemKind, itemID: String)
    case contentCatalog
    case contentDetail(String)
    case coachExperience
}

struct FeedLoadKey: Equatable, Hashable, Sendable {
    let query: ContentFeedQuery
    let catalogRevision: Int
}
```

Add only these Prompt 14 invalidation events: `contentSaved(publicationID:)`, `contentCompleted(publicationID:)`, `contentVersionConflict(publicationID:)`, and `coachPersonaChanged`. Save/completion/conflict increment catalog plus the affected detail; persona change increments coach experience plus catalog. Cover expiry/404 stays a local parent callback rather than a global invalidation event. Impression/opened success has no invalidation event.

`FeatureKeyedLoadController` implements the exact stable `load(key:operation:publish:)`, `retry(key:operation:publish:)` and `cancel()` API above. It mirrors the existing cancellation/publication ownership contract with an arbitrary `Hashable & Sendable` key, retains only one current/completed identity and does not become a cache.

- [ ] **Step 4: Reach GREEN and refactor**

Run focused tests, reuse `FeatureLoadOwnership` instead of inventing another lock, audit exhaustive error-to-presentation/telemetry switches, then run `git diff --check`.

- [ ] **Step 5: Commit**

```bash
git add apps/ios/BodyFlow/BodyFlow/Core/Support/BodyFlowCapabilityError.swift \
  apps/ios/BodyFlow/BodyFlow/Core/Support/Idempotency.swift \
  apps/ios/BodyFlow/BodyFlow/Core/Support/FeatureInvalidationCenter.swift \
  apps/ios/BodyFlow/BodyFlow/Core/Support/FeatureKeyedLoadController.swift \
  apps/ios/BodyFlow/BodyFlow/Core/Telemetry/TelemetryClient.swift \
  apps/ios/BodyFlow/BodyFlowTests/CapabilitySupportTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/FeatureInvalidationTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/FeatureKeyedLoadControllerTests.swift
git commit -m "feat(ios): add content execution primitives"
```

### Task 4: Pin `swift-markdown` 0.8.0 Reproducibly

**Files:**
- Modify: `apps/ios/BodyFlow/BodyFlow.xcodeproj/project.pbxproj`
- Create: `apps/ios/BodyFlow/BodyFlow.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`

**Interfaces:**
- Consumes: Xcode project `5575F9C8301658E800FB4722`, app target `5575F9CF301658E800FB4722`, app Frameworks phase `5575F9CD301658E800FB4722`.
- Produces: the `Markdown` product linked only to `BodyFlow`; unit/UI targets continue to access only the BodyFlow adapter.

- [ ] **Step 1: Prove the package pin is absent (structural RED)**

```bash
set -euo pipefail
BODYFLOW_LOCK="apps/ios/BodyFlow/BodyFlow.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
test -f "$BODYFLOW_LOCK"
```

Expected RED: exit non-zero because no resolved package file exists yet. Also confirm `rg 'XCRemoteSwiftPackageReference|Markdown in Frameworks' apps/ios/BodyFlow/BodyFlow.xcodeproj/project.pbxproj` returns no match.

- [ ] **Step 2: Add the exact package reference and resolve it**

Add one `XCRemoteSwiftPackageReference` with URL `https://github.com/swiftlang/swift-markdown.git`, `kind = exactVersion`, `version = 0.8.0`; one `XCSwiftPackageProductDependency` for `Markdown`; one `Markdown in Frameworks` entry in app Frameworks phase `5575F9CD301658E800FB4722`; and the matching project/target references. Do not normalize unrelated PBX content or link the product directly to either test target.

```bash
set -euo pipefail
BODYFLOW_SPM_ROOT="$(mktemp -d /tmp/bodyflow-prompt14-spm.XXXXXX)"
xcodebuild -resolvePackageDependencies \
  -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -clonedSourcePackagesDirPath "$BODYFLOW_SPM_ROOT/SourcePackages"
```

- [ ] **Step 3: Verify the generated lock exactly (GREEN)**

```bash
set -euo pipefail
BODYFLOW_LOCK="apps/ios/BodyFlow/BodyFlow.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
jq -e '
  .version == 3
  and ([.pins[] | select(.identity == "swift-markdown")
        | [.state.version, .state.revision]]
       == [["0.8.0", "3c6f9523da3a1ec2fd829673e472d95b8097a3b8"]])
  and ([.pins[] | select(.identity == "swift-cmark")
        | [.state.version, .state.revision]]
       == [["0.8.0", "924936d0427cb25a61169739a7660230bffa6ea6"]])
' "$BODYFLOW_LOCK"

BODYFLOW_SPM_VERIFY_ROOT="$(mktemp -d /tmp/bodyflow-prompt14-spm-verify.XXXXXX)"
xcodebuild -resolvePackageDependencies \
  -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -clonedSourcePackagesDirPath "$BODYFLOW_SPM_VERIFY_ROOT/SourcePackages" \
  -onlyUsePackageVersionsFromResolvedFile \
  -skipPackageUpdates
```

Expected GREEN: both commands exit zero and resolution reports `swift-markdown @ 0.8.0` without updating the lock.

- [ ] **Step 4: Refactor/review the generated project diff**

Confirm the diff contains no individual PBX references for synchronized Swift files, no test-target package product, no floating `upToNext*` requirement and no unrelated project normalization. Run `git diff --check`.

- [ ] **Step 5: Commit only package metadata**

```bash
git add -- \
  apps/ios/BodyFlow/BodyFlow.xcodeproj/project.pbxproj \
  apps/ios/BodyFlow/BodyFlow.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
git diff --cached --check
git commit -m "build(ios): pin swift-markdown 0.8.0"
```

Every later `xcodebuild` command in this plan must include `-onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates`.

### Task 5: Build The Fail-Closed BodyFlow Markdown AST Adapter

> **Committed checkpoint:** Task 5 records the initial conservative source-form
> policy. Task 7 supersedes its broad rejection of literal pipe, directive and
> Doxygen spellings when the configured parser produces only allowlisted
> `Text`; actual prohibited nodes and portable semantic sources remain rejected.
> Do not amend the Task 5 commit.

**Files:**
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Content/BodyFlowMarkdownAST.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Content/BodyFlowMarkdownParser.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Content/MarkdownSourceGuards.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/BodyFlowMarkdownParserTests.swift`

**Interfaces:**
- Consumes: exact-pinned `Markdown.Document`, `MarkupVisitor`, `ParseOptions.disableSmartOpts`.
- Produces: `BodyFlowMarkdownParsing` and an immutable package-independent `BodyFlowMarkdownDocument`.

- [ ] **Step 1: Write accepted/rejected parser tests before adapter code**

Add exact AST assertions for paragraph, H2/H3, quote, lists starting at one, strong, emphasis, absolute HTTPS links, CRLF and soft breaks. Add a table-driven fail-closed suite for both block and inline HTML; H1/H4-H6; fenced/indented/inline code; image; hard break; thematic break; table; strikethrough; task-list checkbox; titled, reference, collapsed-reference and shortcut-reference links; nested removed reference definitions; HTTP/data/JavaScript/protocol-relative URLs; ordered start other than one; depth nine; symbol-link syntax; block/inline directives; inline attributes; custom-node probe; Doxygen command/source; malformed source; and the 99/50,001-UTF-16-unit bounds including surrogate pairs. Exercise the visitor's single default-reject path with a current unsupported `Markup` node and a test-only `.unknown` converter classification so the same path is proven for future nodes rather than merely described.

```swift
@Test("approved nodes become a BodyFlow-owned AST")
func parsesApprovedSubset() throws {
    let source = "## Título\r\n\r\nLinha um\nlinha dois com **força** e [fonte](https://bodyflow.app)." + String(repeating: " texto", count: 12)
    let document = try BodyFlowMarkdownParser().parse(source)
    #expect(document.blocks.first == .heading(level: 2, children: [.text("Título")]))
    #expect(document.blocks.count == 2)
}

@Test("reference definitions fail closed without raw fallback")
func rejectsReferenceLinks() {
    let source = "[fonte][bodyflow]\n\n[bodyflow]: https://bodyflow.app\n\n" + String(repeating: "texto ", count: 20)
    #expect(throws: BodyFlowCapabilityError.unsupportedMarkdown) {
        try BodyFlowMarkdownParser().parse(source)
    }
}
```

- [ ] **Step 2: Run RED**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/BodyFlowMarkdownParserTests \
  test
```

Expected RED: missing BodyFlow AST/parser types.

- [ ] **Step 3: Implement the minimal exhaustive adapter**

Normalize CRLF/CR to LF, enforce the `100...50_000` bounds with `normalizedSource.utf16.count`, then parse only with:

```swift
let document = Markdown.Document(
    parsing: normalizedSource,
    options: [.disableSmartOpts]
)
```

Walk every node through explicit approved and rejected cases. Route every known unsupported and test-only unknown classification through one throwing helper so the default-rejection test cannot bypass production behavior. A `SoftBreak` appends `"\n"` to the BodyFlow text stream and adjacent text is coalesced, matching the backend multiline text node. No default visitor branch may render. The final unknown branch throws `unsupportedMarkdown`.

`InlineLinkSourceGuard` must be a bounded Unicode-scalar state machine that accepts only inline/autolink source forms represented by an approved AST link. `DocumentSourceCoverageGuard` must compare parser source ranges and known delimiters, rejecting unowned non-whitespace such as omitted reference definitions. Neither guard may interpret Markdown with regex.

- [ ] **Step 4: Reach GREEN and refactor**

Run the focused suite. Audit source for forbidden rendering paths:

```bash
set -euo pipefail
bodyflow_task5_require_no_rg_match() {
  local probe_exit
  set +e
  rg "$@"
  probe_exit=$?
  set -e
  case "$probe_exit" in
    0) return 1 ;;
    1) return 0 ;;
    *) return "$probe_exit" ;;
  esac
}
bodyflow_task5_require_no_rg_match -n \
  'AttributedString\(markdown:|WKWebView|NSRegularExpression|UIImage\(data:' \
  apps/ios/BodyFlow/BodyFlow/Core/Content
git diff --check
```

Expected: no forbidden match and clean diff.

- [ ] **Step 5: Commit**

```bash
git add apps/ios/BodyFlow/BodyFlow/Core/Content/BodyFlowMarkdownAST.swift \
  apps/ios/BodyFlow/BodyFlow/Core/Content/BodyFlowMarkdownParser.swift \
  apps/ios/BodyFlow/BodyFlow/Core/Content/MarkdownSourceGuards.swift \
  apps/ios/BodyFlow/BodyFlowTests/BodyFlowMarkdownParserTests.swift
git commit -m "feat(ios): enforce the published markdown subset"
```

### Task 6: Harden Portable Markdown Semantics And Canonical Mobile Delivery

This task starts only after the reconciled contract is approved. It must leave
the three in-progress Task 8 corpus files byte-identical and must not execute
their stale compatibility suite.

**Files:**
- Modify: `packages/core/package.json`
- Modify: `pnpm-lock.yaml`
- Modify: `packages/core/src/content.ts`
- Modify: `packages/core/src/content.test.ts`
- Modify: `apps/admin/src/app/(admin)/content/actions.test.ts`
- Modify: `apps/admin/src/lib/content/admin-service.test.ts`
- Modify: `apps/admin/src/lib/mobile-api/content-service.ts`
- Modify: `apps/admin/src/lib/mobile-api/content-service.test.ts`
- Modify: `apps/admin/src/app/api/mobile/v1/content/route.test.ts`

**Interfaces:**
- Consumes: Task 0's real `validateContentMarkdown`, exact GFM-table pins,
  existing CMS/workflow validation calls, opaque mobile error mapping and
  atomic cover-before-detail boundary.
- Produces: exact AST recognition and rejection for strikethrough and task-list
  items; a bounded source-range guard for corpus-defined malformed strong; and
  canonical `body_markdown` delivery from `ValidatedContentMarkdown.normalized`.
- Preserves: ordinary/escaped pipes, valid strong, literal directive/Doxygen
  text, reject availability, RPC-owned stale/lifecycle behavior, immutable
  historical rows and all three Task 8 files.

- [ ] **Step 1: Freeze the paused-corpus and dependency preconditions**

Confirm branch/HEAD/worktree expectations from the authorization. Record and
require these current hashes before and after every Task 6 command:

```bash
set -euo pipefail
test "$(git branch --show-current)" = \
  "codex/bodyflow-ios-library-mascot-gamification-v1"
test "$(git diff --name-only)" = ""
test "$(git diff --cached --name-only)" = ""
test "$(shasum -a 256 apps/ios/BodyFlow/BodyFlowTests/Fixtures/Prompt14MarkdownCompatibility.json | awk '{print $1}')" = \
  "e676d38a3db5d3445720eae55dad19e7eb9c32e74ab700f79ef80b1cead94775"
test "$(shasum -a 256 apps/ios/BodyFlow/BodyFlowTests/MarkdownBackendCompatibilityTests.swift | awk '{print $1}')" = \
  "675e465df56d614c5c47db9286c6b4552b8258988cd38c267ea84e2dc936ff93"
test "$(shasum -a 256 packages/core/src/content-ios-compatibility.test.ts | awk '{print $1}')" = \
  "4dd8a9e901450a716fe786732a222ffda3a60a7f801e2c9147f911a537750d2c"
```

Expected: only the three named Task 8 files are untracked; manifests retain
the exact Task 0 pins. Do not run `content-ios-compatibility.test.ts` yet.

- [ ] **Step 2: Write every focused backend and mobile RED first**

In `packages/core/src/content.test.ts`, add a table-driven contract proving
that length-valid strikethrough, `- [x]`/`- [X]`/`- [ ]` task-list source and
`Texto com **ênfase sem fechamento` each throw a bounded
`Invalid content Markdown` error before canonicalization. Add controls proving
that valid `**strong**`, ordinary/escaped pipes, escaped literal delimiters,
block/inline directive spelling and Doxygen command/source remain accepted when
their configured backend AST is safe text. Preserve the three literal
canonical-size cases from the audit: trailing spaces serialize below 100;
50,000 text units serialize to 50,001 with terminal LF; CRLF/CR normalizes to
50,000 before serializing to 50,001.

In `actions.test.ts`, prove each source is rejected by the untrusted
`saveDraft` action before `service.saveDraft`. In `admin-service.test.ts`,
prove direct `saveDraft` rejects each source before `repository.saveDraft`,
then parameterize the existing workflow spies so the same sources stop source
clone, submit, `review(approve)` and publish before mutation while
`review(reject)` and the existing stale/lifecycle cases remain unchanged.

In the mobile service/route tests, first prove two missing behaviors:

1. a valid stored escaped-pipe source is returned as the exact canonical
   `normalized` body, not as the stored source, without writing the repository;
2. each new invalid legacy source returns only the opaque atomic error before
   cover issuance and exposes no source/canonical fragment or partial DTO.

Run only the focused suites and record the intended REDs:

```bash
set -euo pipefail
bodyflow_expect_red() {
  local status
  set +e
  "$@"
  status=$?
  set -e
  test "$status" -ne 0
}
bodyflow_expect_red pnpm --filter @mpp/core test -- content.test.ts
bodyflow_expect_red pnpm --filter @mpp/admin test -- \
  'src/app/(admin)/content/actions.test.ts'
bodyflow_expect_red pnpm --filter @mpp/admin test -- \
  src/lib/content/admin-service.test.ts
bodyflow_expect_red pnpm --filter @mpp/admin test -- \
  src/lib/mobile-api/content-service.test.ts
bodyflow_expect_red pnpm --filter @mpp/admin test -- \
  src/app/api/mobile/v1/content/route.test.ts
```

Expected RED: the backend currently accepts all three portable-invalid sources,
workflow guards therefore allow them, and valid mobile detail still returns
the stored source instead of `normalized`. Fixture, syntax or infrastructure
errors are not valid REDs.

- [ ] **Step 3: Add only the four exact rejection extensions**

Add these exact compatible pins to `@mpp/core`:

```bash
pnpm --filter @mpp/core add --save-exact \
  micromark-extension-gfm-strikethrough@2.1.0 \
  mdast-util-gfm-strikethrough@2.0.0 \
  micromark-extension-gfm-task-list-item@2.1.0 \
  mdast-util-gfm-task-list-item@2.0.0
```

Keep `mdast-util-from-markdown` exactly `2.0.3`,
`mdast-util-to-markdown` exactly `2.1.2` and every Task 0 table pin unchanged.
Configure only the narrowly scoped syntax/mdast extensions; do not add the
broad GFM bundle or any strikethrough/task-list `toMarkdown` extension. Verify
all eight exact importer/resolution pins structurally in `pnpm-lock.yaml` and
confirm `pnpm-workspace.yaml` is unchanged.

- [ ] **Step 4: Implement structural rejection and canonical read GREEN**

In `content.ts`, add the exact strikethrough and task-list micromark/mdast
extensions beside the table extensions. Reject mdast `delete` and a list item
whose `checked` value is non-null before `toMarkdown`. For malformed strong,
walk only parsed `text` node source ranges and use a bounded Unicode-scalar
state machine: respect backslash escapes, reject an unescaped `**` delimiter
that remains literal text, and leave a real `strong` node valid. The guard may
not regex-scan the document, ban `*`, `|`, `@` or backslash globally, repair
source, or reinterpret an unsupported node as text.

In `content-service.ts`, capture the complete validator result immediately
after the repository read and before cover/DTO work. Map exactly
`validated.normalized` to the outgoing detail's `bodyMarkdown`; never mutate or
persist the stored source. Preserve the existing opaque failure mapping and
zero-cover/zero-partial-response ordering.

- [ ] **Step 5: Reach focused GREEN and verify both backend packages**

```bash
set -euo pipefail
pnpm --filter @mpp/core test -- content.test.ts
pnpm --filter @mpp/core typecheck
pnpm --filter @mpp/admin test -- \
  'src/app/(admin)/content/actions.test.ts' \
  src/lib/content/admin-service.test.ts \
  src/lib/mobile-api/content-service.test.ts \
  src/app/api/mobile/v1/content/route.test.ts
pnpm --filter @mpp/admin typecheck
git diff --check
```

Expected: focused tests are GREEN; the three portable-invalid sources never
persist, transition or serve; valid canonical detail uses `normalized`; safe
text and all concurrency/lifecycle controls remain GREEN. Do not run the stale
Task 8 compatibility test or the complete core suite in this task.

- [ ] **Step 6: Review the exact allowlist and commit Task 6**

Recheck the three frozen hashes, exact dependency pins and nine-path allowlist.
Then stage only:

```bash
git add packages/core/package.json \
  pnpm-lock.yaml \
  packages/core/src/content.ts \
  packages/core/src/content.test.ts \
  'apps/admin/src/app/(admin)/content/actions.test.ts' \
  apps/admin/src/lib/content/admin-service.test.ts \
  apps/admin/src/lib/mobile-api/content-service.ts \
  apps/admin/src/lib/mobile-api/content-service.test.ts \
  apps/admin/src/app/api/mobile/v1/content/route.test.ts
git diff --cached --check
test "$(git diff --cached --name-only | wc -l | tr -d ' ')" -eq 9
git commit -m "fix(content): reject nonportable markdown source"
```

Expected: one backend commit; Task 8 files remain byte-identical and untracked.

### Task 7: Align Native Guards With Canonical Published Markdown

This task starts only after Task 6 is committed and must not edit or execute
the Task 8 corpus.

**Files:**
- Modify: `apps/ios/BodyFlow/BodyFlow/Core/Content/MarkdownSourceGuards.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/BodyFlowMarkdownParserTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Core/Content/PublishedContentContractValidator.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/PublishedContentContractTests.swift`

**Interfaces:**
- Consumes: Task 5's immutable BodyFlow AST, exact `swift-markdown` parser and
  source-range ownership model; Task 6's canonical mobile-detail boundary.
- Produces: escape-aware exact text coverage with no broad character bans and
  post-line-ending-normalization payload-size validation.
- Preserves: single fail-closed unknown-node route, removed-reference/unowned-
  span rejection, URL/depth guards and native rejection of strikethrough,
  checkbox and corpus-defined malformed strong.

- [ ] **Step 1: Write canonical-payload and contract REDs**

Add exact AST assertions for ordinary pipe; the canonical literal result of an
escaped pipe; block and inline directive spellings parsed only as `Text`;
Doxygen command/source spellings parsed only as `Text`; and safe backend-
emitted backslash escapes whose decoded AST stays in the allowlist. Preserve
literal rejection assertions for actual Directive/Doxygen probe nodes,
strikethrough, raw task-list/checkbox, corpus-defined malformed strong,
reference definitions, unowned spans and unknown/future nodes. Add mutation
tests proving no global `|`, `@` or backslash blacklist can pass.

In `PublishedContentContractTests`, add CRLF/isolated-CR payload boundaries
proving validation measures `100...50_000` after CRLF/CR → LF, uses UTF-16 and
does not append a terminal LF or invoke editorial canonicalization.

Run the two suites and record RED: the current broad `validateText` blacklist
rejects the six safe text families, and the contract validator measures the
pre-normalized body.

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/BodyFlowMarkdownParserTests \
  -only-testing:BodyFlowTests/PublishedContentContractTests \
  test
```

- [ ] **Step 2: Implement the minimum exact native alignment**

Replace only the broad text-character blacklist. `DocumentSourceCoverageGuard`
must compare a `Text` range through a bounded Unicode-scalar state machine that
either matches literal text exactly or consumes only a CommonMark backslash
escape whose decoded scalar matches `Text.string`. A backslash before a
non-escapable scalar remains literal. Every byte must still be owned; there is
no raw fallback. Reject an unescaped `**` sequence that remains in a `Text`
range, while actual strikethrough/checkbox/Directive/Doxygen/unknown nodes stay
on the converter's fail-closed route.

In `PublishedContentContractValidator`, normalize CRLF and isolated CR to LF
only for safety-bound measurement with `utf16.count`; do not mutate the decoded
DTO, trim, escape, append LF or import/reproduce `toMarkdown`.
`BodyFlowMarkdownParser.swift`, `project.pbxproj` and `Package.resolved` remain
unchanged.

- [ ] **Step 3: Reach GREEN and audit prohibited paths**

Run the two focused suites again with the resolved lockfile. Then execute the
Task 5 forbidden-path `rg` audit, `git diff --check`, strict-concurrency review
and the three frozen Task 8 hash checks. Expected: safe canonical text is
accepted with exact AST; portable semantic sources, removed references,
unowned spans and current/future unsupported nodes remain rejected.

- [ ] **Step 4: Commit Task 7 independently**

```bash
git add \
  apps/ios/BodyFlow/BodyFlow/Core/Content/MarkdownSourceGuards.swift \
  apps/ios/BodyFlow/BodyFlowTests/BodyFlowMarkdownParserTests.swift \
  apps/ios/BodyFlow/BodyFlow/Core/Content/PublishedContentContractValidator.swift \
  apps/ios/BodyFlow/BodyFlowTests/PublishedContentContractTests.swift
git diff --cached --check
test "$(git diff --cached --name-only | wc -l | tr -d ' ')" -eq 4
git commit -m "fix(ios): align canonical markdown guards"
```

Expected: one native commit and no Task 8 corpus mutation.

### Task 8: Resume And Lock The Shared Markdown Compatibility Corpus

**Files:**
- Create: `apps/ios/BodyFlow/BodyFlowTests/Fixtures/Prompt14MarkdownCompatibility.json`
- Create: `packages/core/src/content-ios-compatibility.test.ts`
- Create: `apps/ios/BodyFlow/BodyFlowTests/MarkdownBackendCompatibilityTests.swift`

**Interfaces:**
- Consumes: Task 6's hardened backend/canonical detail contract and Task 7's
  aligned native parser/contract guards.
- Produces: one checked-in, test-only 50-row corpus with `name`, `source`,
  `accepted`, `native_expectation`, and accepted-only `normalized` plus
  `document`; exactly 11 `parse_normalized`, 36 `reject_source` and 3
  `backend_canonicalization_only` rows.

- [ ] **Step 1: Tighten both test decoders first and observe schema RED**

Before changing the JSON, update both test-only decoders to require exactly:

```text
native_expectation = parse_normalized
                   | reject_source
                   | backend_canonicalization_only
```

Reject unknown values and every invalid field combination. `accepted=true`
requires `parse_normalized`, non-null `normalized` and non-null `document`.
`accepted=false` permits only the other two expectations and must have neither
accepted field. Restrict `backend_canonicalization_only` by exact fixture name
to:

- `normalized-body-under-100-characters`;
- `normalized-body-over-50000-characters`;
- `normalized-crlf-over-50000-utf16-units`.

Require 50 unique names and exact counts `11/36/3`. The portable document wire
shape is `{ "blocks": [...] }`, not a package AST and not top-level `blocks`.
Run the backend and native compatibility suites against the existing paused
JSON before editing it. Expected RED: `native_expectation`/`document` are
missing and the current distribution is 14 accepted/36 rejected. No production
file may change to reach this RED.

- [ ] **Step 2: Reconcile only the synthetic JSON corpus**

Preserve all 50 names and exact synthetic source strings. Apply the approved
expectations:

- retain 11 accepted rows as `accepted=true`, `parse_normalized` with their
  exact canonical `normalized` and portable `document`;
- change `strikethrough-is-backend-literal-text`,
  `task-list-marker-is-backend-literal-list-text` and
  `malformed-strong-is-backend-literal-text` to `accepted=false`,
  `reject_source`, removing accepted-only fields;
- assign the three exact size/canonicalization names above to
  `backend_canonicalization_only`;
- assign every other backend-invalid row to `reject_source`.

Do not rename, rewrite or weaken a source to obtain GREEN. Confirm the file
contains only synthetic data and no PII, clinical content or real message.

- [ ] **Step 3: Run the backend authority over all 50 rows**

The backend test reads the JSON relative to `import.meta.url`, validates its
schema/counts first, then applies:

```typescript
switch (fixture.native_expectation) {
  case 'parse_normalized':
    expect(validateContentMarkdown(fixture.source)).toEqual({
      normalized: fixture.normalized,
      blocks: fixture.document.blocks,
      wordCount: expect.any(Number),
    })
    break
  case 'reject_source':
  case 'backend_canonicalization_only':
    expect(() => validateContentMarkdown(fixture.source)).toThrow()
    break
}
```

For the three canonicalization-only names, also require the bounded normalized-
body size error so a future semantic reclassification cannot pass unnoticed.
Run the backend authority first and stop on any mismatch; never change a source
or expectation outside the approved mapping to force GREEN.

```bash
set -euo pipefail
git diff --exit-code -- pnpm-workspace.yaml pnpm-lock.yaml
pnpm --filter @mpp/core test -- content-ios-compatibility.test.ts
git diff --exit-code -- pnpm-workspace.yaml pnpm-lock.yaml
```

Expected: all 50 backend outcomes match exactly: 11 canonical documents and 39
throws split by the two explicit native expectations.

- [ ] **Step 4: Evaluate only the applicable 47 rows on iOS**

Resolve the JSON from the Swift test's `#filePath`; do not add PBX resource
membership. Put the switch in a private test-only evaluator that accepts a
recording parse closure:

```swift
for fixture in try Prompt14MarkdownCorpus.load() {
    switch fixture.nativeExpectation {
    case .parseNormalized:
        #expect(
            try BodyFlowMarkdownParser().parse(try #require(fixture.normalized))
                == try #require(fixture.document)
        )
    case .rejectSource:
        #expect(throws: BodyFlowCapabilityError.unsupportedMarkdown) {
            try BodyFlowMarkdownParser().parse(fixture.source)
        }
    case .backendCanonicalizationOnly:
        break
    }
}
```

The recorder must prove exactly 47 parser invocations and zero invocation for
all three canonicalization-only names. This is a boundary assertion, not a
skip: those sources never form a mobile payload. For all 11 accepted rows,
compare the exact BodyFlow document; for all 36 portable rejects, require
`unsupportedMarkdown` from the original source.

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/BodyFlowMarkdownParserTests \
  -only-testing:BodyFlowTests/MarkdownBackendCompatibilityTests \
  test
```

Expected: all 47 applicable native evaluations pass and the three editorial-
only canonicalization rows produce no parser call.

- [ ] **Step 5: Run the joint gate, independently review and commit**

Run the backend compatibility suite again, both native suites again, complete
`@mpp/core` tests and typecheck, then `git diff --check`. Confirm exactly the
three allowlisted test files changed; PBX, package resolution, manifests,
lockfiles and every production parser remain unchanged. Independently review
schema validation, exact counts, source preservation and zero unexplained
divergence. Then:

```bash
git add apps/ios/BodyFlow/BodyFlowTests/Fixtures/Prompt14MarkdownCompatibility.json \
  apps/ios/BodyFlow/BodyFlowTests/MarkdownBackendCompatibilityTests.swift \
  packages/core/src/content-ios-compatibility.test.ts
test "$(git diff --cached --name-only | wc -l | tr -d ' ')" -eq 3
git diff --cached --check
git commit -m "test(ios): lock markdown backend compatibility"
```

Expected: one Task 8 commit, corpus `50 = 11 + 36 + 3`, no unexplained
divergence. Only now may Task 9 begin.

### Task 9: Validate Cover Capabilities Before Any Transport Boundary

**Files:**
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Content/ContentCoverPath.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Content/ContentCoverStreaming.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/ContentCoverPathTests.swift`

**Interfaces:**
- Consumes: raw `PublishedContentCover.url` only at the validator boundary.
- Produces: validated `ContentCoverPath`, `ContentCoverTrustedOrigin`, a same-origin-only request resolver, `ContentCoverByteStreaming`, and redirect-aware stream metadata without bearer ownership.

- [ ] **Step 1: Write the strict path matrix as RED tests**

Test one valid capability and literal rejection of empty token, absolute URL, protocol-relative URL, scheme, host, user info, port, query, fragment, percent encoding, backslash, extra segment, dot/dot-dot traversal and external host. Test trusted-origin validation rejects non-HTTPS, credentials, query, fragment and non-origin base paths; resolution rechecks HTTPS scheme, exact host and effective port. Verify the fake transport call count remains zero for every rejected raw value.

```swift
@Test("only exact relative capability paths are accepted")
func validatesCapabilityShape() throws {
    #expect(
        try ContentCoverPath(
            validating: "/api/mobile/v1/content/covers/AbC_123-xyz"
        ).rawValue == "/api/mobile/v1/content/covers/AbC_123-xyz"
    )
    for value in Prompt14InvalidCoverPaths.all {
        #expect(throws: BodyFlowCapabilityError.invalidContentCover) {
            try ContentCoverPath(validating: value)
        }
    }
}
```

- [ ] **Step 2: Run RED**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/ContentCoverPathTests \
  test
```

Expected RED: missing path/stream types.

- [ ] **Step 3: Implement minimal scalar validation and stream metadata**

Validate the raw string before creating any `URL`. Require the exact fixed prefix and at least one capability byte; every remaining UTF-8 byte must be ASCII letter/digit/underscore/hyphen. Do not expose capability values through `CustomStringConvertible`, telemetry or logs.

Define `ContentCoverTrustedOrigin`, `ContentCoverTransportRequest` and its only resolver together in `ContentCoverStreaming.swift`. Give the request an explicit `fileprivate init(path:url:)`; no memberwise/internal initializer remains available to another application file. Resolve only an already validated path, then compare the resolved URL's HTTPS scheme, case-normalized host and effective port with the trusted origin. Add a structural test/helper assertion that feature/test consumers can obtain requests only through the resolver. Define stream status/MIME/cache/redirect metadata so Task 10 can reject redirects before reading a body. The protocol accepts only the resolved request, so an invalid/external string cannot cross the transport boundary. There is still no live URL or bearer.

- [ ] **Step 4: Reach GREEN and refactor**

Run the focused suite, inspect all initializer exits before transport invocation, and run `git diff --check`.

- [ ] **Step 5: Commit**

```bash
git add apps/ios/BodyFlow/BodyFlow/Core/Content/ContentCoverPath.swift \
  apps/ios/BodyFlow/BodyFlow/Core/Content/ContentCoverStreaming.swift \
  apps/ios/BodyFlow/BodyFlowTests/ContentCoverPathTests.swift
git commit -m "feat(ios): validate private cover capabilities"
```

### Task 10: Stream-Bound And Downsample Cover Images With ImageIO

**Files:**
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Content/ContentCoverDecoder.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/ContentCoverDecoderTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/Fixtures/Prompt14CoverFixtures.swift`

**Interfaces:**
- Consumes: `ContentCoverByteStream`, `ContentCoverTargetSize`.
- Produces: immutable `ContentCoverImage` wrapping a downsampled `CGImage`; no raw bytes survive the call. The narrow `@unchecked Sendable` wrapper is reviewed because Core Graphics image storage is immutable after creation.

- [ ] **Step 1: Write exact byte/MIME/dimension RED tests**

Generate tiny deterministic first-party JPEG, PNG and WebP fixtures inside the test target. Test `10_485_760` bytes accepted up to the decoder boundary, declared or actual `10_485_761` rejected/cancelled, missing/wrong/mismatched MIME rejected, redirect rejected, zero/invalid dimension rejected, either dimension over `16_384` rejected, more than `64_000_000` pixels rejected, multiplication overflow rejected and a valid large raster downsampled to requested point-size × scale.

```swift
@Test("actual body is cancelled at byte 10 MiB plus one")
func rejectsOversizedStream() async {
    let fixture = Prompt14CoverFixtures.chunkedBody(byteCount: 10_485_761)
    await #expect(throws: BodyFlowCapabilityError.contentCoverTooLarge) {
        try await ContentCoverDecoder().decode(fixture.stream, target: .init(
            widthPixels: 240,
            heightPixels: 160
        ))
    }
    #expect(await fixture.probe.wasCancelled)
}
```

- [ ] **Step 2: Run RED**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/ContentCoverDecoderTests \
  test
```

Expected RED: missing decoder and decode-safety errors.

- [ ] **Step 3: Implement bounded streaming and ImageIO GREEN**

Reject redirect/status/headers before consuming chunks. Reject `Content-Length > 10_485_760`, count each chunk with overflow checks and cancel on byte `10_485_761`. Require exact `image/jpeg`, `image/png` or `image/webp` and match `CGImageSourceGetType` to the declared type.

Read source properties with `kCGImageSourceShouldCache: false`; validate dimensions; then call `CGImageSourceCreateThumbnailAtIndex` with transform, immediate thumbnail caching and `kCGImageSourceThumbnailMaxPixelSize` derived from the target. Never call `UIImage(data:)` or create the full source raster.

- [ ] **Step 4: Run GREEN and refactor**

Run focused tests under Address Sanitizer only if the normal suite exposes an ImageIO memory fault; otherwise keep the deterministic normal gate. Confirm temporary byte buffers leave scope after decode and run `git diff --check`.

- [ ] **Step 5: Commit**

```bash
git add apps/ios/BodyFlow/BodyFlow/Core/Content/ContentCoverDecoder.swift \
  apps/ios/BodyFlow/BodyFlowTests/ContentCoverDecoderTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/Fixtures/Prompt14CoverFixtures.swift
git commit -m "feat(ios): bound private cover decoding"
```

### Task 11: Add The Session Cover Cache, Expiry And Cancellation Boundary

**Files:**
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Content/SessionCoverCache.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Content/ContentCoverLoader.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/SessionCoverCacheTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/ContentCoverLoaderTests.swift`

**Interfaces:**
- Consumes: `ContentCoverByteStreaming`, `ContentCoverDecoder`, `TimeProviding`.
- Produces: `ContentCoverLoading` with bounded cache, earlier-expiry semantics, targeted removal and `endSession()`.

- [ ] **Step 1: Write RED cache/lifecycle tests**

Test exact cost/count boundaries, deterministic LRU overflow before insertion, key separation by publication/version/target size, earlier capability/header expiry using fixed time, 404 removal, content-version removal, memory-warning clear, in-flight coalescing, caller cancellation and full session replacement/sign-out cancellation with no late image publication.

```swift
@Test("cache never exceeds either fixed limit")
func enforcesBothLimits() async throws {
    let cache = SessionCoverCache(totalCostLimit: 33_554_432, countLimit: 64)
    try await Prompt14CacheFixture.fillBeyondBothLimits(cache)
    let snapshot = await cache.debugSnapshot()
    #expect(snapshot.totalCost <= 33_554_432)
    #expect(snapshot.count <= 64)
    #expect(snapshot.keys == Prompt14CacheFixture.expectedLRUSurvivors)
}

@Test("session end cancels and suppresses a late image")
func endSessionCancelsWork() async {
    let task = Task {
        try await loader.image(
            publicationID: publicationID,
            version: 4,
            cover: cover,
            target: target
        )
    }
    await stream.waitUntilStarted()
    await loader.endSession()
    await stream.succeedLate()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(await cache.debugSnapshot().count == 0)
}
```

- [ ] **Step 2: Run RED**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/SessionCoverCacheTests \
  -only-testing:BodyFlowTests/ContentCoverLoaderTests \
  test
```

Expected RED: missing cache/loader.

- [ ] **Step 3: Implement minimal bounded actor state**

Wrap `NSCache` with an actor-owned deterministic LRU ledger. Set `totalCostLimit=33_554_432` and `countLimit=64`; compute cost with overflow-checked `bytesPerRow * height`; evict before insert. Use key `(publicationID, version, targetPixelSize)`. Expiry is `min(cover.expiresAt, receiptTime + maxAge)` using only the existing `timeProvider.now` property. Before streaming, validate `cover.url` into `ContentCoverPath` and resolve it against the injected optional trusted origin; a nil origin returns `operationUnavailable` before request construction and without invoking the stream.

`ContentCoverLoader` has one concrete initializer: `init(stream:origin:decoder:cache:timeProvider:)`. Its public behavior is exactly the stable `ContentCoverLoading` protocol; tests use protocol spies rather than another request-shaped loader overload.

`endSession()` increments an ownership generation, cancels all tracked load/decode tasks, calls `stream.cancelAll()`, clears LRU and `removeAllObjects()`. Every completion checks generation and cancellation before cache/publication.

- [ ] **Step 4: Reach GREEN and refactor**

Run both suites. Confirm cache/capability/image types have no `Codable` persistence path and no global singleton. Run `git diff --check`.

- [ ] **Step 5: Commit**

```bash
git add apps/ios/BodyFlow/BodyFlow/Core/Content/SessionCoverCache.swift \
  apps/ios/BodyFlow/BodyFlow/Core/Content/ContentCoverLoader.swift \
  apps/ios/BodyFlow/BodyFlowTests/SessionCoverCacheTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/ContentCoverLoaderTests.swift
git commit -m "feat(ios): add session-scoped cover loading"
```

### Task 12: Extend The Fail-Closed Dependency And Launch-Scenario Boundary

**Files:**
- Modify: `apps/ios/BodyFlow/BodyFlow/Core/Unavailable/UnavailableBodyFlowCapabilities.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Core/Content/PublishedContentProviding.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Core/CoachExperience/CoachExperienceProviding.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Core/Content/ContentCoverLoader.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppDependencies.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppLaunchConfiguration.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppRootView.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/Prompt14LaunchConfigurationTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/Prompt14ReleaseBoundaryTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/AppDependenciesTests.swift`

**Interfaces:**
- Consumes: content/coach capability protocols, `ContentCoverByteStreaming`, existing `.demo`/`.releaseUnavailable` configuration.
- Produces: protocol-typed per-authenticated-shell session factories, `UnavailableContentCoverByteStream`, and Debug-only `DemoPrompt14Scenario` parsing.

- [ ] **Step 1: Write Release and launch-argument RED tests**

Add tests proving every new capability throws `operationUnavailable`, nil trusted origin prevents cover-request construction and leaves the unavailable stream spy uncalled, Release ignores every `--ui-testing-prompt14-*` flag, and Prompt 13 behavior remains unchanged. Define the UI scenario strings in the test first:

```swift
private let prompt14Arguments = [
    "--ui-testing-prompt14-loaded",
    "--ui-testing-prompt14-loading",
    "--ui-testing-prompt14-empty",
    "--ui-testing-prompt14-offline",
    "--ui-testing-prompt14-error",
    "--ui-testing-prompt14-stale",
    "--ui-testing-prompt14-unavailable",
    "--ui-testing-prompt14-opened-error",
    "--ui-testing-prompt14-content-not-found",
    "--ui-testing-prompt14-subscription-required",
    "--ui-testing-prompt14-markdown-invalid",
    "--ui-testing-prompt14-cover-invalid",
    "--ui-testing-prompt14-mascot-variants",
    "--ui-testing-prompt14-progress-empty",
    "--ui-testing-prompt14-progress-minimum",
    "--ui-testing-prompt14-streak-zero",
    "--ui-testing-prompt14-conflict",
    "--ui-testing-prompt14-reduce-motion",
    "--ui-testing-prompt14-differentiate-without-color",
]
```

- [ ] **Step 2: Run RED**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/Prompt14LaunchConfigurationTests \
  -only-testing:BodyFlowTests/Prompt14ReleaseBoundaryTests \
  -only-testing:BodyFlowTests/AppDependenciesTests \
  test
```

Expected RED: missing dependency fields, unavailable implementations and Prompt 14 scenario parser.

- [ ] **Step 3: Implement the unavailable graph first**

Add these `AppDependencies` fields:

```swift
let publishedContentSessions: any PublishedContentSessionCreating
let coachExperienceSessions: any CoachExperienceSessionCreating
let contentCoverSessions: any ContentCoverSessionCreating
```

Define the session composition/lifetime protocols exactly as in the stable interface section. `ContentCoverSessionCreating.makeLoader(userID:)` returns only `any ContentCoverLoading`. In all builds, initialize the three factories to unavailable adapters unless the later Task 13 Debug branch supplies deterministic factories. The unavailable cover factory creates a loader with a nil trusted origin; test that resolution throws `operationUnavailable` before a `ContentCoverTransportRequest` exists and a stream spy remains at call count zero. The unavailable stream itself accepts only an already-resolved request and still throws if called directly. Keep `DemoPrompt14Scenario` and every literal Prompt 14 launch flag inside `#if DEBUG`.

Because SwiftUI's system `accessibilityDifferentiateWithoutColor` value is read-only, add a writable BodyFlow-owned `bodyFlowDifferentiateWithoutColor` environment key. `AppRootView` reads the system value and installs `configuration.differentiateWithoutColorOverride ?? systemValue` into that custom key; feature views read only the custom key. The Debug-only flag sets the optional override, while Release ignores the flag and uses the real system value. Increase Contrast is controlled only through `simctl ui`, not a fake application state. Release configuration exposes no `prompt14Scenario`, origin URL or bearer field/value.

- [ ] **Step 4: Reach GREEN and refactor**

Run focused tests. Verify the Release branch does not call the legacy `APIClient` for Prompt 14, its factories create only unavailable capabilities, a nil origin prevents request construction and the unavailable stream spy remains uncalled. Run `git diff --check`.

- [ ] **Step 5: Commit**

```bash
git add apps/ios/BodyFlow/BodyFlow/Core/Unavailable/UnavailableBodyFlowCapabilities.swift \
  apps/ios/BodyFlow/BodyFlow/Core/Content/PublishedContentProviding.swift \
  apps/ios/BodyFlow/BodyFlow/Core/CoachExperience/CoachExperienceProviding.swift \
  apps/ios/BodyFlow/BodyFlow/Core/Content/ContentCoverLoader.swift \
  apps/ios/BodyFlow/BodyFlow/App/AppDependencies.swift \
  apps/ios/BodyFlow/BodyFlow/App/AppLaunchConfiguration.swift \
  apps/ios/BodyFlow/BodyFlow/App/AppRootView.swift \
  apps/ios/BodyFlow/BodyFlowTests/Prompt14LaunchConfigurationTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/Prompt14ReleaseBoundaryTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/AppDependenciesTests.swift
git commit -m "feat(ios): enforce the prompt 14 release boundary"
```

### Task 13: Add Complete Deterministic Prompt 14 Read Fixtures

**Files:**
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoPrompt14Fixtures.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoPrompt14Repository.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoContentCoverByteStream.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppDependencies.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/DemoPrompt14RepositoryTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/AppDependenciesTests.swift`

**Interfaces:**
- Consumes: Debug-only scenarios, fixed `TimeProviding`, existing deterministic idempotency provider.
- Produces: Debug-only factories that create a fresh content actor/lifetime, a separate coach provider and a cover loader per authenticated shell; scenario-specific progress remains an independent pre-authored provider.

- [ ] **Step 1: Write RED read-snapshot tests**

Assert complete pre-authored responses for Today recommendations, Library, Saved, category-filtered pages, detail, content-not-found, subscription-required, selected-null/effective-balanced and Focus/Impulse/Zen coach snapshots, all five mascot wire states, unknown fallback, progress complete/minimum/null/streak-zero, loading/offline/error/unavailable behavior and opaque next cursor.

```swift
@Test("Debug content session shares capabilities but never crosses users")
func debugGraphScopesRepositoryToOneSession() async throws {
    let dependencies = prompt14Dependencies("--ui-testing-prompt14-loaded")
    let first = dependencies.publishedContentSessions.makeSession(userID: "user-a")
    let second = dependencies.publishedContentSessions.makeSession(userID: "user-b")
    let listing = try #require(first.listing as? DemoPrompt14Repository)
    let detail = try #require(first.detail as? DemoPrompt14Repository)
    let state = try #require(first.state as? DemoPrompt14Repository)
    let secondListing = try #require(second.listing as? DemoPrompt14Repository)
    #expect(listing === detail)
    #expect(listing === state)
    #expect(listing !== secondListing)
    await first.lifetime.endSession()
    await #expect(throws: CancellationError.self) {
        let query = try ContentFeedQuery(
            surface: .today,
            category: nil,
            limit: 3,
            cursor: nil
        )
        try await first.listing.content(query)
    }
}
```

- [ ] **Step 2: Run RED**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/DemoPrompt14RepositoryTests \
  -only-testing:BodyFlowTests/AppDependenciesTests \
  test
```

Expected RED: missing Debug fixture/repository/stream.

- [ ] **Step 3: Implement complete immutable read fixtures**

Keep every new file under a whole-file `#if DEBUG`. Use only synthetic UUIDs, the Prompt 14-specific trusted origin `https://prompt14-fixture.invalid`, and first-party neutral image bytes. Pre-author full response envelopes instead of calculating feed, coach or progress values. Repository queries select pre-authored pages by exact `ContentFeedQuery`; they never decode/sort a cursor or calculate recommendation order.

The Debug dependency fields are factories. Each `makeSession(userID:)` call creates a fresh `DemoPrompt14Repository` actor and returns that actor only through the three small content capabilities plus a lifetime token whose `endSession()` increments a generation, cancels pending operations and clears feed/detail/mutation/idempotency state. Coach and cover factories create separate session-scoped objects. No factory caches by user ID and no provider becomes a global singleton.

When a Prompt 14 scenario is active, `AppDependencies` also supplies the Prompt 13 loaded Today repository so the official Today screen remains available while recommendations fail independently. Prompt 14 progress scenarios may replace only `ProgressProviding` with the pre-authored Prompt 14 response.

- [ ] **Step 4: Run GREEN and refactor**

Run focused tests. Assert every fixture validates through the contract validator/parser before UI use, two user IDs receive distinct actors/loaders, ended sessions cannot publish or mutate, fixture art/body is visibly synthetic, and no Release branch references a fixture type. Run `git diff --check`.

- [ ] **Step 5: Commit**

```bash
git add apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoPrompt14Fixtures.swift \
  apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoPrompt14Repository.swift \
  apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoContentCoverByteStream.swift \
  apps/ios/BodyFlow/BodyFlow/App/AppDependencies.swift \
  apps/ios/BodyFlow/BodyFlowTests/DemoPrompt14RepositoryTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/AppDependenciesTests.swift
git commit -m "test(ios): add prompt 14 deterministic reads"
```

### Task 14: Implement Debug Content Mutations And Exact Idempotent Replay

**Files:**
- Modify: `apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoPrompt14Repository.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoPrompt14Fixtures.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/DemoPrompt14RepositoryTests.swift`

**Interfaces:**
- Consumes: `MutationAttempt<ContentReadCommand>`, `MutationAttempt<ContentSaveCommand>`.
- Produces: deterministic consolidated `PublishedContentStateResponse` and a per-session idempotency replay ledger.

- [ ] **Step 1: Write RED mutation/replay tests**

Test impression/opened/completed, save/unsave, `changed`, `replayed`, same-attempt replay, same-key/different-route/body conflict, in-progress behavior, version conflict and response state without locally changing XP/mascot/official Today values. End the session during one controlled mutation, complete it late and assert cancellation, no state publication and an empty ledger; a second user's fresh session must not observe the first user's save or replay key.

```swift
@Test("retry replays the exact content attempt")
func replaysExactAttempt() async throws {
    let attempt = try Prompt14Attempts.opened(version: 4, key: "content-open-0001")
    let first = try await repository.recordRead(attempt)
    let replay = try await repository.recordRead(attempt)
    #expect(first.data.changed)
    #expect(replay.data.replayed)
    #expect(!replay.data.changed)
}

@Test("same key never changes publication, version or payload")
func rejectsKeyReuse() async throws {
    let first = try Prompt14Attempts.saved(true, version: 4, key: "content-save-0001")
    let changed = try Prompt14Attempts.saved(false, version: 4, key: "content-save-0001")
    _ = try await repository.setSaved(first)
    await #expect(throws: BodyFlowCapabilityError.idempotencyConflict) {
        try await repository.setSaved(changed)
    }
}
```

- [ ] **Step 2: Run RED**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/DemoPrompt14RepositoryTests \
  test
```

Expected RED: deterministic repository still returns unavailable or has no mutation/session ledger.

- [ ] **Step 3: Implement minimal actor mutation state**

Ledger identity includes operation, publication route and exact payload. Keep attempt timestamp/key unchanged. Apply state only to pre-authored content responses; completion is one-way. Every operation captures the repository generation and checks it before committing state; `endSession()` cancels controlled work, advances the generation and clears all mutable state. Never calculate event time, XP, level, streak, mission or mascot transition. Scenario failures are deterministic and one-shot only when explicitly configured.

- [ ] **Step 4: Reach GREEN and refactor**

Run the same command again, verify no mutation touches `TodaySnapshot`, `ProgressSnapshot` or coach fixtures and verify user/session separation, then run `git diff --check`.

- [ ] **Step 5: Commit**

```bash
git add apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoPrompt14Repository.swift \
  apps/ios/BodyFlow/BodyFlow/Core/Demo/DemoPrompt14Fixtures.swift \
  apps/ios/BodyFlow/BodyFlowTests/DemoPrompt14RepositoryTests.swift
git commit -m "feat(ios): add idempotent demo content mutations"
```

### Task 15: Implement Query, Paging And Cancellation-Safe Content Feed State

**Files:**
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Library/PublishedContentFeedViewModel.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/PublishedContentFeedViewModelTests.swift`

**Interfaces:**
- Consumes: `PublishedContentListing`, `PublishedContentContractValidator`, `FeatureKeyedLoadController<FeedLoadKey, PublishedContentFeedResponse>`.
- Produces: first-page `FeatureReadState<PublishedContentFeed>`, next-page state, exact query changes and retry APIs.

- [ ] **Step 1: Write RED state-machine tests**

Cover initial loading/loaded/empty/offline/error/unavailable/stale states; `library`/`saved`/category query values; initial `limit=20`; opaque next-cursor pass-through; no load-more when cursor is null; next-page service/offline failure preserving visible items and allowing retry of the same cursor; `.invalidContentCursor` discarding only that page attempt and exposing a first-page reload action; query/revision supersession; duplicate publication rejection; and one complete first-page load per `(query, catalogRevision)`.

Add literal pagination recovery assertions: after an invalid cursor, `loadNextPage()` cannot reuse it, visible items remain, and `reloadFirstPageAfterInvalidCursor()` sends the same surface/category/limit with `cursor:nil`. Boundary construction for limit `0`/`51` and cursor empty/length `513` remains in Task 1 and is referenced here as a prerequisite, not reimplemented.

```swift
@Test("next page preserves every query dimension and opaque cursor")
@MainActor
func opaquePagination() async throws {
    let model = PublishedContentFeedViewModel(listing: provider)
    let query = try ContentFeedQuery(
        surface: .library,
        category: .sleep,
        limit: 20,
        cursor: nil
    )
    let expectedFirst = try ContentFeedQuery(
        surface: .library,
        category: .sleep,
        limit: 20,
        cursor: nil
    )
    let expectedNext = try ContentFeedQuery(
        surface: .library,
        category: .sleep,
        limit: 20,
        cursor: "opaque.next_1"
    )
    await model.load(query: query, catalogRevision: 7)
    await model.loadNextPage()
    #expect(await provider.queries == [expectedFirst, expectedNext])
}
```

- [ ] **Step 2: Run RED**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/PublishedContentFeedViewModelTests \
  test
```

Expected RED: missing feed model.

- [ ] **Step 3: Implement minimal GREEN feed ownership**

Use the composite first-page key; replace complete first-page state per revision; append next page only if the active query and expected cursor still match; suppress late result/error after cancellation. Keep next-page error separate from `FeatureReadState` so loaded rows remain visible. Store the cursor unchanged and never infer order/total. Generic recoverable next-page errors retain the immutable attempt for Retry; `.invalidContentCursor` clears that attempt/cursor, sets a distinct first-page-reload presentation and can only call the nil-cursor reload API.

- [ ] **Step 4: Run GREEN and refactor**

Run the same command again, eliminate duplicated cancellation code through the keyed controller, and run `git diff --check`.

- [ ] **Step 5: Commit**

```bash
git add apps/ios/BodyFlow/BodyFlow/Features/Library/PublishedContentFeedViewModel.swift \
  apps/ios/BodyFlow/BodyFlowTests/PublishedContentFeedViewModelTests.swift
git commit -m "feat(ios): add published content feed state"
```

### Task 16: Record Visible Impressions Once Per Feed Response

**Files:**
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Library/PublishedContentFeedViewModel.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/PublishedContentFeedViewModelTests.swift`

**Interfaces:**
- Consumes: `PublishedContentStateRecording`, `IdempotencyKeyProviding`, `TimeProviding`, `FeatureInvalidationCenter` and session `ContentCoverLoading`.
- Produces: `recordImpression(for:origin:)` with response-scoped deduplication and no offline queue.

- [ ] **Step 1: Write RED visibility/idempotency tests**

Assert no event before a card reports visible, one event for repeated appearances/rerenders of the same publication/version/origin in one response, distinct Today/Library origins, a new attempt for a new response version, immutable key/body/time, and ordinary non-blocking failure with no automatic retry. Add `contentVersionChanged` for an impression: evict the exact old publication/version cover, invalidate catalog+detail once, keep the response guard marked, and perform no replay, retry or second impression. A subsequent reloaded response at the new version may emit one new visible-response impression only after the card becomes visible again.

```swift
@Test("visible card emits one immutable impression")
@MainActor
func impressionDeduplicates() async throws {
    await model.recordImpression(for: summaryV4, origin: .library)
    await model.recordImpression(for: summaryV4, origin: .library)
    let attempts = await recorder.readAttempts
    #expect(attempts.count == 1)
    #expect(attempts[0].payload.body == .init(
        event: .impression,
        origin: .library,
        version: 4
    ))
    #expect(attempts[0].createdAt == fixedNow)
}
```

- [ ] **Step 2: Run RED**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/PublishedContentFeedViewModelTests \
  test
```

Expected RED: missing impression API/dedup state.

- [ ] **Step 3: Implement minimal GREEN impression ownership**

Insert `(publicationID, version, origin)` into the current-response guard synchronously on `@MainActor` before the first suspension, create one immutable `.contentRead` attempt and dispatch it. Keep ordinary failure as bounded non-blocking technical state; do not remove the guard, retry or queue. On `contentVersionChanged`, remove the exact old cover, record `.contentVersionConflict(publicationID:)`, preserve the guard and let the owning `.task(id:)` perform the complete feed reload; never patch or replay locally. Clear/replace the guard only when the visible response is completely replaced.

- [ ] **Step 4: Run GREEN and refactor**

Run the same command again, verify card tap is not an impression trigger, and run `git diff --check`.

- [ ] **Step 5: Commit**

```bash
git add apps/ios/BodyFlow/BodyFlow/Features/Library/PublishedContentFeedViewModel.swift \
  apps/ios/BodyFlow/BodyFlowTests/PublishedContentFeedViewModelTests.swift
git commit -m "feat(ios): record visible content impressions"
```

### Task 17: Add Typed Today Routes And Authenticated Session Ownership

**Files:**
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppRouter.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppRootView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/App/Prompt14SessionOwner.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/AppRouterTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/Prompt14SessionOwnershipTests.swift`

**Interfaces:**
- Consumes: `ContentRoute`, `MascotRoute`, the three Prompt 14 session factories, `AppRoute.tab` and existing progress capability.
- Produces: Today-only typed destinations, explicit route/tab validation and complete shell teardown keyed by authenticated user ID.

- [ ] **Step 1: Write RED route/session tests**

Assert Library and mascot are not tabs, both route cases map to `.today`, detail contains exactly publication ID/origin, no content route carries version/snapshot, mismatched tab navigation is rejected and five paths remain independent.

For session ownership, create controlled content list/detail/mutation, coach, progress and cover operations under user A; request user B while A's asynchronous teardown is suspended; then complete every A operation late. Assert A's synchronous publication gate is invalidated before the teardown's first suspension, no B factory/shell is created until both A lifetimes finish, A's content lifetime and cover loader each end once, A's repository ledger/cache/snapshots are empty, every A task is cancelled or publication-suppressed, and no value/event appears in B's feed/detail/recommendation/coach/progress models. Also assert rapid A→B→C requests create only the latest session after serialized teardown and distinct content actors, coach providers and cover loaders.

```swift
@Test("content and mascot routes cannot enter another tab stack")
@MainActor
func prompt14RoutesStayOnToday() {
    let router = AppRouter()
    let detail = AppRoute.content(.detail(
        publicationID: "00000000-0000-4000-8000-000000000101",
        origin: .library
    ))
    router.navigate(to: detail, in: .progress)
    #expect(router.path(for: .progress).isEmpty)
    router.navigate(to: detail, in: .today)
    #expect(router.path(for: .today) == [detail])
}
```

- [ ] **Step 2: Run RED**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/AppRouterTests \
  -only-testing:BodyFlowTests/Prompt14SessionOwnershipTests \
  test
```

Expected RED: missing route cases/session owner behavior.

- [ ] **Step 3: Implement minimal typed routing and teardown**

Add `LibrarySelection`, `ContentRoute`, `MascotRoute`, `.content` and `.mascot`; require `route.tab == tab` inside `navigate(to:in:)`. Add `.id(userID)` to the authenticated `AppShellView` in `AppRootView`.

`Prompt14SessionOwner` is an `@MainActor` composition object, not a provider. Its initializer calls the three factories exactly once for the current user and exposes only their small protocol capabilities to feature models. Split teardown into `invalidateSynchronously()` and idempotent `endSession()`: the former closes a shared publication gate and cancels owned task/ownership handles without suspension; the latter awaits `PublishedContentSessionLifetime.endSession()` and `ContentCoverLoading.endSession()` and then releases references.

`AppRootView` owns an `@MainActor @Observable Prompt14AuthenticatedShellCoordinator`. Its `.task(id: requestedAuthenticatedUserID)` calls `transition(to:)`. That method increments a transition generation, calls the old owner's `invalidateSynchronously()` before its first `await`, awaits complete old-session teardown, rechecks that the generation/requested user is still current, and only then constructs/publishes the new owner and renderable shell identity. During teardown, root content shows a neutral authenticated-loading state rather than constructing shell B concurrently. Transition to signed-out/onboarding likewise awaits teardown; `AppShellView.onDisappear` is only a defensive synchronous invalidation and is never relied on to await work. `AppShellView` receives the already-created owner, passes its capabilities to child models and remains `.id(userID)`.

Progress remains a separate shell-owned view model; root serialization, the shared closed publication gate and task cancellation/ownership prevent an old result from entering the new shell. Add temporary unavailable `FeatureDetailView` destinations for new route cases only until Tasks 18, 19 and 24 replace them; they must not display fixture success.

- [ ] **Step 4: Reach GREEN and refactor**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/AppRouterTests \
  -only-testing:BodyFlowTests/Prompt14SessionOwnershipTests \
  -only-testing:BodyFlowTests/AppTabTests \
  test
git diff --check
```

Confirm `AppTab.allCases.count == 5` and all controlled late results are suppressed.

- [ ] **Step 5: Commit**

```bash
git add apps/ios/BodyFlow/BodyFlow/App/AppRouter.swift \
  apps/ios/BodyFlow/BodyFlow/App/AppRootView.swift \
  apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift \
  apps/ios/BodyFlow/BodyFlow/App/Prompt14SessionOwner.swift \
  apps/ios/BodyFlow/BodyFlowTests/AppRouterTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/Prompt14SessionOwnershipTests.swift
git commit -m "feat(ios): add prompt 14 typed routes"
```

### Task 18: Build The Library, Saved And Category Feed UI

**Files:**
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Library/LibraryRootView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Library/PublishedContentCard.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/LibraryPresentationTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift`

**Interfaces:**
- Consumes: `PublishedContentFeedViewModel`, `ContentRoute`, and `invalidationCenter.revision(for: .contentCatalog)`.
- Produces: All/Saved/category Library surface and content-card navigation carrying only ID/origin.

- [ ] **Step 1: Write RED presentation and composition tests**

Test localized labels for all eleven fixed categories, exact empty messages for Library/Saved/category, card fields limited to returned cover/title/excerpt/category/reading-time/saved/completed, server order preservation, separate next-page retry and route construction without version/snapshot. Add a pure `LibraryAccessibilityFocusTarget` reducer test: first load focuses the heading, filter change focuses the updated results heading, first-page Retry focuses its result/error summary, invalid-cursor recovery focuses the first-page reload action, and next-page failure focuses the bounded Retry without moving focus into an old card.

```swift
@Test("saved selection maps only to the real saved surface")
func savedSelectionQuery() {
    #expect(LibrarySelection.saved.contentSurface == .saved)
    #expect(LibrarySelection.all.contentSurface == .library)
}

@Test("cards preserve server order and approved fields")
func cardsUseOnlySummaryContract() {
    let cards = LibraryPresentation(feed: Prompt14Fixtures.libraryFeed).cards
    #expect(cards.map(\.publicationID) == Prompt14Fixtures.libraryFeed.items.map(\.publicationID))
    #expect(cards.map(\.title) == Prompt14Fixtures.libraryFeed.items.map(\.title))
}
```

- [ ] **Step 2: Run RED**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/LibraryPresentationTests \
  test
```

Expected RED: missing Library/card/focus presentation types.

- [ ] **Step 3: Implement minimal accessible Library UI**

`LibraryRootView` owns selection/category presentation state and one feed model built with the shell session's recorder, cover loader and invalidation center. Its `.task(id:)` key combines exact query and observed catalog revision. Render full-screen/stale/next-page states, segmented All/Saved, category menu, pull-to-refresh and Load More only for non-null cursor. Every card uses a plain `NavigationLink` to `.content(.detail(publicationID:origin:.library))`; no mutation occurs on tap.

Use semantic tokens, decorative covers, native text wrapping, 44-point controls and stable IDs `library.selection.all`, `library.selection.saved`, `library.category`, `library.card.<publicationID>`, `library.load-more` and `state.retry-next-page`. Drive `AccessibilityFocusState` only from the tested semantic focus target after load, filter change, Retry and invalid-cursor recovery; color never carries selection/error state alone.

- [ ] **Step 4: Run GREEN and refactor**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/LibraryPresentationTests \
  -only-testing:BodyFlowTests/AppRouterTests \
  test
git diff --check
```

Replace the temporary Library destination in `AppShellView` and verify the Library route always enters Today.

- [ ] **Step 5: Commit**

```bash
git add apps/ios/BodyFlow/BodyFlow/Features/Library/LibraryRootView.swift \
  apps/ios/BodyFlow/BodyFlow/Features/Library/PublishedContentCard.swift \
  apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift \
  apps/ios/BodyFlow/BodyFlowTests/LibraryPresentationTests.swift
git commit -m "feat(ios): build the educational library"
```

### Task 19: Load And Authorize Detail Before One Non-Blocking `opened`

**Files:**
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Library/ContentDetailViewModel.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Library/PublishedContentDetailView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Library/BodyFlowMarkdownView.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/ContentDetailViewModelTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift`

**Interfaces:**
- Consumes: route `publicationID`/`origin`, detail provider, contract validator, Markdown parser, content recorder, fixed time/idempotency, `FeatureInvalidationCenter`, session `ContentCoverLoading` and detail revision.
- Produces: `FeatureReadState<RenderablePublishedContentDetail>`, route-lifetime opened guard and native AST renderer.

- [ ] **Step 1: Write the exact opened-sequence RED tests**

Use controlled providers/recorders to prove zero POST before detail completion; GET version N with card version N-1 emits one `opened` at N; opened success reconciles only the returned canonical saved/completed state; rerender/revision refresh/later detail reload/opened failure produces no second attempt; explicit new view-model/navigation produces a new attempt; detail failed/unavailable/cancelled/superseded/contract-invalid/Markdown-invalid produces zero attempts; opened failure keeps the authorized article loaded and has no retry/queue. Add explicit `.contentNotFound` and `.subscriptionRequired` cases that emit zero opened attempts and map to distinct bounded presentations: “Este conteúdo não está mais disponível” with Voltar and Biblioteca actions, and “Conteúdo indisponível para sua assinatura atual” with no purchase/upgrade flow. For an opened `contentVersionChanged`, assert the old `(publicationID, version)` cover is removed, catalog+detail revisions increment once, detail reloads to N+1, and the route-lifetime guard still leaves the recorder at exactly one opened attempt.

```swift
@Test("opened uses only the authorized detail response version")
@MainActor
func openedAfterDetail() async throws {
    let load = Task { await model.load(revision: 0) }
    await detailProvider.waitUntilStarted()
    #expect(await recorder.readAttempts.isEmpty)
    await detailProvider.succeed(with: Prompt14Fixtures.detail(version: 5))
    await load.value
    let attempt = try #require(await recorder.readAttempts.first)
    #expect(attempt.payload.publicationID == routePublicationID)
    #expect(attempt.payload.body.version == 5)
    #expect(attempt.payload.body.origin == .library)
}
```

- [ ] **Step 2: Run RED**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/ContentDetailViewModelTests \
  test
```

Expected RED: missing detail model, route-lifetime event owner and conflict recovery dependencies.

- [ ] **Step 3: Implement minimal GREEN sequence**

On `@MainActor`, load by route publication ID; decode/validate/parse; ensure the load identity is current; commit `.loaded`; and atomically set `openedAttempted = true` before the first event suspension. Then create exactly one immutable `.contentRead` attempt from route ID/origin plus detail response version. Event success reconciles only the returned canonical state for that publication/version and invalidates nothing. Ordinary event failure updates only a bounded `openedEventState`; it cannot replace loaded detail or expose retry. A version conflict is the sole event-failure exception: remove the old cover through the injected loader, record `.contentVersionConflict(publicationID:)`, and reload detail from the provider while preserving `openedAttempted == true`; never create a second event.

Render title as screen heading, category/reading time, saved/completed state and only the BodyFlow AST. `BodyFlowMarkdownView` supplies native heading/list/link semantics. External links are opened only through `OpenURLAction` after absolute HTTPS revalidation and announce “Link externo”; rejected/raw text is never shown. Map not-found and subscription-required to the exact tested neutral states and actions; never show raw targeting/editorial data or a fake commerce action.

- [ ] **Step 4: Run GREEN and refactor**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/ContentDetailViewModelTests \
  -only-testing:BodyFlowTests/BodyFlowMarkdownParserTests \
  -only-testing:BodyFlowTests/FeatureInvalidationTests \
  test
git diff --check
```

Replace the temporary content-detail destination in `AppShellView` and inject the shell's invalidation center and cover loader. Confirm no card version enters `ContentDetailViewModel.init`.

- [ ] **Step 5: Commit**

```bash
git add apps/ios/BodyFlow/BodyFlow/Features/Library/ContentDetailViewModel.swift \
  apps/ios/BodyFlow/BodyFlow/Features/Library/PublishedContentDetailView.swift \
  apps/ios/BodyFlow/BodyFlow/Features/Library/BodyFlowMarkdownView.swift \
  apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift \
  apps/ios/BodyFlow/BodyFlowTests/ContentDetailViewModelTests.swift
git commit -m "feat(ios): load content before opened"
```

### Task 20: Add Save, Unsave, Completion And Version-Conflict Recovery

**Files:**
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Library/ContentDetailViewModel.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Library/PublishedContentDetailView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/ContentDetailViewModelTests.swift`

**Interfaces:**
- Consumes: `FeatureMutationState`, content recorder, invalidation center, session `ContentCoverLoading`, idempotency/time providers.
- Produces: explicit save/unsave and one-way completion actions with exact retry/conflict semantics.

- [ ] **Step 1: Write RED mutation tests**

Test one-at-a-time submission, double-tap suppression, canonical response reconciliation, retry preserving the exact attempt after clock advance, new user intent creating a new key/time, completion hidden/disabled after completion, save/completion success invalidating catalog+detail only, opened success invalidating nothing, and version conflict discarding old attempt/cover then requiring a new explicit action after reload. A cover-loader spy must receive exactly `remove(publicationID: oldID, version: oldVersion)` before reload. Test semantic focus targets after mutation success, recoverable error, Retry result and conflict reload; no outcome is communicated only by color.

```swift
@Test("retry preserves key payload route version and creation time")
@MainActor
func retriesImmutableSaveAttempt() async throws {
    await model.toggleSaved()
    let failed = try #require(model.contentMutationState.attempt)
    clock.advance(by: 3_600)
    await model.retryContentMutation()
    let retried = try #require(await recorder.saveAttempts.last)
    #expect(retried == failed)
}
```

- [ ] **Step 2: Run RED**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/ContentDetailViewModelTests \
  test
```

Expected RED: missing save/completion state, semantic focus and conflict recovery.

- [ ] **Step 3: Implement minimal GREEN mutations**

Build save body without origin/route ID and completed read body with route ID outside JSON. Reconcile only returned `saved`, `completed`, version and response metadata; do not patch feeds or official Today values locally. On conflict, retain failed attempt for diagnostics, remove the exact old cover through the loader already injected in Task 19, record catalog/detail invalidation, end the attempt and disable retry until current detail reloads. Resolve the new detail only from the reloaded detail provider; do not patch its version/state locally.

Use separate 44-point Save/Unsave and Complete controls outside tappable cards. Publish accessible success/error focus once; prevent nested controls.

- [ ] **Step 4: Run GREEN and refactor**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/ContentDetailViewModelTests \
  -only-testing:BodyFlowTests/FeatureInvalidationTests \
  -only-testing:BodyFlowTests/CapabilitySupportTests \
  test
git diff --check
```

Confirm no uncomplete action exists and `opened` failure has no retry path.

- [ ] **Step 5: Commit**

```bash
git add apps/ios/BodyFlow/BodyFlow/Features/Library/ContentDetailViewModel.swift \
  apps/ios/BodyFlow/BodyFlow/Features/Library/PublishedContentDetailView.swift \
  apps/ios/BodyFlow/BodyFlowTests/ContentDetailViewModelTests.swift
git commit -m "feat(ios): add content save and completion"
```

### Task 21: Integrate Safe Covers Into Cards And Detail

**Files:**
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Library/ContentCoverView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Library/PublishedContentCard.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Library/PublishedContentDetailView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/ContentCoverViewModelTests.swift`

**Interfaces:**
- Consumes: session `ContentCoverLoading`, publication/version/cover and actual SwiftUI display size × scale.
- Produces: cancellation-safe cover presentation with neutral first-party placeholder.

- [ ] **Step 1: Write RED cover-presentation tests**

Test nil cover, valid image, expired capability, 404 bounded parent refresh, invalid/external path, oversized body, MIME/dimension failure, view disappearance cancellation, version replacement and late old-session image suppression. Every failure must show the same neutral placeholder and never open an external URL.

- [ ] **Step 2: Run RED**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/ContentCoverViewModelTests \
  -only-testing:BodyFlowTests/ContentCoverLoaderTests \
  test
```

Expected RED: missing presentation owner.

- [ ] **Step 3: Implement minimal GREEN cover view**

`ContentCoverView` computes target pixels from measured points and display scale, validates the path through the loader, starts with `.task(id: coverIdentityAndTarget)`, cancels on identity/size/disappearance and renders a semantic-token placeholder on any bounded failure. Covers are accessibility-hidden when title/excerpt already identify the card. A 404/expiry callback triggers only the owning list/detail refresh, never a global loop.

- [ ] **Step 4: Run GREEN and refactor**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/ContentCoverViewModelTests \
  -only-testing:BodyFlowTests/ContentCoverLoaderTests \
  -only-testing:BodyFlowTests/ContentCoverPathTests \
  -only-testing:BodyFlowTests/ContentCoverDecoderTests \
  -only-testing:BodyFlowTests/SessionCoverCacheTests \
  test
git diff --check
```

Confirm no `AsyncImage`, external URL, URLCache or disk write exists.

- [ ] **Step 5: Commit**

```bash
git add apps/ios/BodyFlow/BodyFlow/Features/Library/ContentCoverView.swift \
  apps/ios/BodyFlow/BodyFlow/Features/Library/PublishedContentCard.swift \
  apps/ios/BodyFlow/BodyFlow/Features/Library/PublishedContentDetailView.swift \
  apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift \
  apps/ios/BodyFlow/BodyFlowTests/ContentCoverViewModelTests.swift
git commit -m "feat(ios): render bounded private covers"
```

### Task 22: Compose Published Recommendations Independently In Today

**Files:**
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Today/TodayRecommendationsViewModel.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Today/TodayRecommendationsSection.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Today/TodayRootView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/TodayRecommendationsTests.swift`

**Interfaces:**
- Consumes: a dedicated content feed model fixed to `.today`, catalog revision and session cover loader.
- Produces: independent Today recommendations section and persistent Library entry.

- [ ] **Step 1: Write RED composition/isolation tests**

Assert exact query `surface=today`, `category=nil`, `limit=3`, `cursor=nil`; server order/max three; no pagination; Today origin for impression/detail; exact empty copy; CTA always visible and opening normal Library; recommendation loading/offline/error/unavailable contained within section; and official `TodayViewModel`/`TodaySnapshot` unchanged when recommendations fail.

```swift
@Test("recommendation failure never replaces official Today state")
@MainActor
func failureIsIsolated() async {
    await officialToday.load(revision: 0)
    await recommendations.load(catalogRevision: 0)
    #expect(officialToday.state == .loaded(BodyFlowTestFixtures.todaySnapshot))
    #expect(recommendations.state == .failed(
        previousValue: nil,
        error: .serviceUnavailable
    ))
}
```

- [ ] **Step 2: Run RED**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/TodayRecommendationsTests \
  test
```

Expected RED: missing recommendation owner/section.

- [ ] **Step 3: Implement minimal GREEN composition**

Own recommendations separately under `AppShellView`, constructing their feed model with the same shell-session recorder, cover loader and invalidation center, and pass them to `TodayRootView` without modifying `TodayPresentation`, `TodaySnapshot` or `TodayProviding`. Add a persistent Library toolbar/entry even when official Today is empty/unavailable. Cards navigate with only publication ID and `.today` origin; visibility invokes the feed impression API.

- [ ] **Step 4: Run GREEN and refactor**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/TodayRecommendationsTests \
  -only-testing:BodyFlowTests/TodayContractTests \
  -only-testing:BodyFlowTests/TodayViewModelTests \
  -only-testing:BodyFlowTests/TodayPresentationTests \
  -only-testing:BodyFlowTests/AppRouterTests \
  test
git diff --check
```

Verify no recommendation score/reason/AI claim.

- [ ] **Step 5: Commit**

```bash
git add apps/ios/BodyFlow/BodyFlow/Features/Today/TodayRecommendationsViewModel.swift \
  apps/ios/BodyFlow/BodyFlow/Features/Today/TodayRecommendationsSection.swift \
  apps/ios/BodyFlow/BodyFlow/Features/Today/TodayRootView.swift \
  apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift \
  apps/ios/BodyFlow/BodyFlowTests/TodayRecommendationsTests.swift
git commit -m "feat(ios): add today content recommendations"
```

### Task 23: Present Server-Owned Mascot State And Personality

**Files:**
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Mascot/MascotExperienceViewModel.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Mascot/MascotPresentation.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/MascotExperienceViewModelTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/MascotPresentationTests.swift`

**Interfaces:**
- Consumes: `CoachExperienceProviding`, `invalidationCenter.revision(for: .coachExperience)`, exact `bodyflow.coach-persona.v1`.
- Produces: read state and pure descriptors for effective persona plus mascot wire state.

- [ ] **Step 1: Write RED source-of-truth and presentation tests**

Test loading/loaded/offline/stale/error/unavailable, cancellation/supersession, one load per coach revision, selected-null/effective-balanced, server option names/descriptions, Focus/Impulse/Zen/Balanced descriptors, four requested state copies, Evolving/Unknown neutral copy, `changed_at` literal formatting and unsupported contract/locale fail-closed. Prove time, XP, weight, streak and activity never change a descriptor.

```swift
@Test("evolving and unknown are explicit neutral states")
func neutralUnsupportedStates() {
    #expect(MascotPresentation.state(.evolving).title == "Estado do mascote em atualização")
    #expect(MascotPresentation.state(.unknown("future")).title == "Estado do mascote em atualização")
    #expect(MascotPresentation.state(.unknown("future")).semanticState != .active)
}

@Test("unsupported contract version fails closed")
@MainActor
func unsupportedVersion() async {
    await model.load(revision: 0)
    #expect(model.state == .failed(
        previousValue: nil,
        error: .unsupportedCoachContract
    ))
}
```

- [ ] **Step 2: Run RED**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/MascotExperienceViewModelTests \
  -only-testing:BodyFlowTests/MascotPresentationTests \
  test
```

Expected RED: missing view model/presentation.

- [ ] **Step 3: Implement minimal GREEN read/presentation behavior**

Use cancellation-safe revision loading. Validate `contractVersion == "bodyflow.coach-persona.v1"` and selectable/effective option consistency before publishing. Map only presentation geometry/tone by effective persona; keep state mapping orthogonal. Use server-provided option names/descriptions, never `CoachPersona.summary`, throughout the Prompt 14 experience. Expose a code-keyed option presentation consumed by Task 24's existing picker integration. `changedAt` may format for display but never feeds a threshold.

- [ ] **Step 4: Run GREEN and refactor**

```bash
set -euo pipefail
bodyflow_task21_require_no_rg_match() {
  local probe_exit
  set +e
  rg "$@"
  probe_exit=$?
  set -e
  case "$probe_exit" in
    0) return 1 ;;
    1) return 0 ;;
    *) return "$probe_exit" ;;
  esac
}
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/MascotExperienceViewModelTests \
  -only-testing:BodyFlowTests/MascotPresentationTests \
  -only-testing:BodyFlowTests/CoachExperienceContractTests \
  test
bodyflow_task21_require_no_rg_match -n \
  'Date\(\)|ProgressProviding|WeightRecording|TodayProviding|transition' \
  apps/ios/BodyFlow/BodyFlow/Features/Mascot
git diff --check
```

- [ ] **Step 5: Commit**

```bash
git add apps/ios/BodyFlow/BodyFlow/Features/Mascot/MascotExperienceViewModel.swift \
  apps/ios/BodyFlow/BodyFlow/Features/Mascot/MascotPresentation.swift \
  apps/ios/BodyFlow/BodyFlowTests/MascotExperienceViewModelTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/MascotPresentationTests.swift
git commit -m "feat(ios): present server-owned mascot state"
```

### Task 24: Build The BodyFlow Mascot Card, Detail And Temporary Art

**Files:**
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Mascot/MascotCardView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Mascot/MascotDetailView.swift`
- Create: `apps/ios/BodyFlow/BodyFlow/Features/Mascot/MascotPlaceholderArtwork.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Today/TodayRootView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Profile/ProfileRootView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Profile/CoachPersonaEditorModel.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Profile/CoachPersonaPickerView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/CoachPersonaEditorModelTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/MascotAccessibilityModelTests.swift`

**Interfaces:**
- Consumes: mascot view model/presentation, `.mascot(.detail)`, reduce-motion environment and coach/content invalidation.
- Produces: independent Today mascot card, snapshot-reloading detail and Debug-only first-party vector placeholder.

- [ ] **Step 1: Write RED composition, motion and persona-invalidation tests**

Assert state/persona text remains equivalent across visual variants; artwork is decorative; semantic sibling announces “Mascote BodyFlow, personalidade <name>, estado <state>”; Evolving/Unknown are explicit; Reduce Motion removes repeating animation; card/detail remain usable without art; detail reloads coach snapshot; and successful existing persona save increments coach/catalog revisions exactly once while failure/cancel changes neither.

Add literal picker tests with deliberately non-localized fixture text: the three returned option names/descriptions are displayed verbatim by code and in server order; `balanced` is never a selectable row; `CoachPersona.displayName`, `CoachPersona.summary` and `CoachPersona.allCases` are not used by the picker; missing/duplicate/unsupported options fail closed instead of falling back to hard-coded summaries.

- [ ] **Step 2: Run RED**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/MascotAccessibilityModelTests \
  -only-testing:BodyFlowTests/CoachPersonaEditorModelTests \
  test
```

Expected RED: missing view composition descriptor, server-option picker input and persona invalidation callback.

- [ ] **Step 3: Implement minimal GREEN UI and invalidation**

Create abstract SwiftUI vector primitives using only BodyFlow semantic colors. Wrap the complete temporary artwork implementation in `#if DEBUG`; Release renders no successful placeholder art. Vary geometry/accent/spacing for Focus/Impulse/Zen and neutral Balanced without changing controls/copy/reward. Stop repeating motion when `bodyFlowReduceMotion` is true.

Own the Today card model separately in `AppShellView`; replace the temporary mascot destination with a detail that owns/reloads a fresh model by coach revision. Feed the validated `CoachExperienceSnapshot.options` into `CoachPersonaEditorModel`/`CoachPersonaPickerView`; iterate those options instead of `CoachPersona.allCases` and show their returned `name`/`description` rather than local display/summary copy. The existing PATCH repository still owns the save; no endpoint changes. Pass an `onPersistedPersonaChanged` callback through the existing persona editor; only a successful changed save records `.coachPersonaChanged`, whose keys are coach experience and content catalog.

- [ ] **Step 4: Run GREEN and refactor**

```bash
set -euo pipefail
bodyflow_task22_require_no_rg_match() {
  local probe_exit
  set +e
  rg "$@"
  probe_exit=$?
  set -e
  case "$probe_exit" in
    0) return 1 ;;
    1) return 0 ;;
    *) return "$probe_exit" ;;
  esac
}
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/MascotAccessibilityModelTests \
  -only-testing:BodyFlowTests/CoachPersonaEditorModelTests \
  -only-testing:BodyFlowTests/MascotExperienceViewModelTests \
  -only-testing:BodyFlowTests/MascotPresentationTests \
  -only-testing:BodyFlowTests/AppRouterTests \
  -only-testing:BodyFlowTests/FeatureInvalidationTests \
  test
bodyflow_task22_require_no_rg_match -n \
  'CoachPersona\.allCases|\.displayName|\.summary' \
  apps/ios/BodyFlow/BodyFlow/Features/Profile/CoachPersonaPickerView.swift
git diff --check
```

Verify no asset catalog, third-party name/reference or recurring speech bubble was added.

- [ ] **Step 5: Commit**

```bash
git add apps/ios/BodyFlow/BodyFlow/Features/Mascot/MascotCardView.swift \
  apps/ios/BodyFlow/BodyFlow/Features/Mascot/MascotDetailView.swift \
  apps/ios/BodyFlow/BodyFlow/Features/Mascot/MascotPlaceholderArtwork.swift \
  apps/ios/BodyFlow/BodyFlow/Features/Today/TodayRootView.swift \
  apps/ios/BodyFlow/BodyFlow/App/AppShellView.swift \
  apps/ios/BodyFlow/BodyFlow/Features/Profile/ProfileRootView.swift \
  apps/ios/BodyFlow/BodyFlow/Features/Profile/CoachPersonaEditorModel.swift \
  apps/ios/BodyFlow/BodyFlow/Features/Profile/CoachPersonaPickerView.swift \
  apps/ios/BodyFlow/BodyFlowTests/CoachPersonaEditorModelTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/MascotAccessibilityModelTests.swift
git commit -m "feat(ios): build the bodyflow mascot experience"
```

### Task 25: Render Literal XP, Levels, Medals And Streaks

**Files:**
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Progress/ProgressComponents.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Progress/ProgressRootView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/ProgressPresentationTests.swift`

**Interfaces:**
- Consumes: corrected optional `ProgressResponse`, existing `ProgressProviding`, selected-tab binding.
- Produces: positional medal rows, supportive streak-zero CTA and bounded missions-unavailable section on top of Task 2's already-correct official loaded/empty distinction.

- [ ] **Step 1: Write RED gamification-presentation tests**

Keep Task 2's passing assertions that `data:null` is `.empty` and minimum non-null `xp=0/level=1/deficit=0` is `.loaded`. Add RED tests that complete values remain literal; duplicate badge strings produce separate positional rows; zero streak shows approved copy and Today CTA; nonzero streak omits recovery copy; the mission section is unavailable; and no ranking/cooperative/next-level UI descriptor exists.

```swift
@Test("duplicate medals retain positional identity")
func duplicateMedalsRemainSeparate() {
    let rows = ProgressPresentation(
        snapshot: Prompt14Fixtures.progress(badges: ["Constância", "Constância"])
    ).medalRows
    #expect(rows.map(\.text) == ["Constância", "Constância"])
    #expect(Set(rows.map(\.id)).count == 2)
}
```

- [ ] **Step 2: Run RED**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/PlanProgressContractTests \
  -only-testing:BodyFlowTests/ProgressViewModelTests \
  -only-testing:BodyFlowTests/ProgressPresentationTests \
  test
```

Expected RED: the inherited nullable-contract/view-model tests stay GREEN while new medal/streak/missions presentation assertions fail for missing behavior.

- [ ] **Step 3: Implement minimal GREEN gamification presentation**

Display `N XP`, `Nível N`, literal current/longest streak and ordered badge text from the already-loaded snapshot. Introduce positional medal identity `(offset, text)` rather than `id: \.self`; use one generic first-party medal treatment without metadata. Add the exact zero-streak copy and a 44-point “Retomar em Hoje” button that changes `selectedTab` only. Render exact missions unavailable copy; add no mission/ranking view model, provider or sample data.

- [ ] **Step 4: Run GREEN and refactor**

```bash
set -euo pipefail
bodyflow_task23_require_no_rg_match() {
  local probe_exit
  set +e
  rg "$@"
  probe_exit=$?
  set -e
  case "$probe_exit" in
    0) return 1 ;;
    1) return 0 ;;
    *) return "$probe_exit" ;;
  esac
}
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/PlanProgressContractTests \
  -only-testing:BodyFlowTests/ProgressViewModelTests \
  -only-testing:BodyFlowTests/ProgressPresentationTests \
  test
bodyflow_task23_require_no_rg_match -n \
  'xpToNext|levelThreshold|levelForXP|computeProgress|MissionDTO|RankingDTO|CooperativeMissionDTO|restoreStreak' \
  apps/ios/BodyFlow/BodyFlow
git diff --check
```

- [ ] **Step 5: Commit**

```bash
git add apps/ios/BodyFlow/BodyFlow/Features/Progress/ProgressComponents.swift \
  apps/ios/BodyFlow/BodyFlow/Features/Progress/ProgressRootView.swift \
  apps/ios/BodyFlow/BodyFlowTests/ProgressPresentationTests.swift
git commit -m "feat(ios): present official gamification values"
```

### Task 26: Add Debug Previews, Bounded Telemetry And Release Structural Gates

**Files:**
- Create: `apps/ios/BodyFlow/BodyFlow/Features/PreviewSupport/Prompt14PreviewSupport.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Core/Telemetry/TelemetryClient.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/Prompt14ReleaseBoundaryTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/Prompt14TelemetryPrivacyTests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowTests/Prompt14PreviewSupportTests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlowTests/Prompt14LaunchConfigurationTests.swift`

**Interfaces:**
- Consumes: Debug scenarios, approved semantic presentation states and existing telemetry allowlist.
- Produces: deterministic previews/test launches and bounded technical classifications only.

- [ ] **Step 1: Write RED privacy/Release/previews tests**

Test previews for Library/detail/recommendation/mascot/progress states; Prompt 14 launch flags are exactly one per launch and ignored by Release; fixture factories/fake stream/temporary art cannot be constructed in Release; new factories create only unavailable providers; trusted origin is nil; loader resolution returns `operationUnavailable` before request construction; an outbound-stream spy remains at zero; and telemetry drops title/excerpt/Markdown/cover capability/badge text/name/email/bearer/health values while accepting only allowlisted screen/outcome plus `evolving|unknown` mascot classification.

```swift
@Test("Prompt 14 telemetry drops content and patient text")
func stripsSensitiveMetadata() {
    let event = TelemetryEvent(
        name: .featureScreenViewed,
        metadata: [
            "screen": "content_detail",
            "title": "private title",
            "body_markdown": "private body",
            "cover_url": "/api/mobile/v1/content/covers/secret",
            "badge_text": "private badge",
        ]
    )
    #expect(event.metadata == ["screen": .string("content_detail")])
}
```

- [ ] **Step 2: Run RED**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/Prompt14TelemetryPrivacyTests \
  -only-testing:BodyFlowTests/Prompt14PreviewSupportTests \
  -only-testing:BodyFlowTests/Prompt14ReleaseBoundaryTests \
  -only-testing:BodyFlowTests/Prompt14LaunchConfigurationTests \
  test
```

Expected RED: missing preview support/telemetry vocabulary or structural assertions.

- [ ] **Step 3: Implement minimal GREEN support**

Keep `Prompt14PreviewSupport` whole-file `#if DEBUG`. Add only necessary screen and bounded state classifications to telemetry; do not emit raw unknown state. Ensure Release dependency construction references only unavailable protocols and `SystemTimeProvider`; scenario strings, fixture repository, fake stream and artwork remain compiled out.

- [ ] **Step 4: Run focused tests and fresh Debug/Release builds**

```bash
set -euo pipefail
BODYFLOW_BOUNDARY_ROOT="$(mktemp -d /tmp/bodyflow-prompt14-boundary.XXXXXX)"

bodyflow_boundary_require_no_rg_match() {
  local probe_exit
  set +e
  rg "$@"
  probe_exit=$?
  set -e
  case "$probe_exit" in
    0) return 1 ;;
    1) return 0 ;;
    *) return "$probe_exit" ;;
  esac
}

BODYFLOW_PROMPT14_RELEASE_SOURCE_SCOPE=(
  apps/ios/BodyFlow/BodyFlow/App
  apps/ios/BodyFlow/BodyFlow/Core/Content
  apps/ios/BodyFlow/BodyFlow/Core/CoachExperience
  apps/ios/BodyFlow/BodyFlow/Core/Progress
  apps/ios/BodyFlow/BodyFlow/Core/Support
  apps/ios/BodyFlow/BodyFlow/Core/Telemetry
  apps/ios/BodyFlow/BodyFlow/Core/Unavailable
  apps/ios/BodyFlow/BodyFlow/Features/Library
  apps/ios/BodyFlow/BodyFlow/Features/Mascot
  apps/ios/BodyFlow/BodyFlow/Features/Profile
  apps/ios/BodyFlow/BodyFlow/Features/Progress
  apps/ios/BodyFlow/BodyFlow/Features/Today
)
BODYFLOW_PROMPT14_ADDED_LINES="$BODYFLOW_BOUNDARY_ROOT/prompt14-added-lines.txt"

xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowTests/Prompt14TelemetryPrivacyTests \
  -only-testing:BodyFlowTests/Prompt14PreviewSupportTests \
  -only-testing:BodyFlowTests/Prompt14ReleaseBoundaryTests \
  -only-testing:BodyFlowTests/Prompt14LaunchConfigurationTests \
  test

xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -derivedDataPath "$BODYFLOW_BOUNDARY_ROOT/debug" \
  -clonedSourcePackagesDirPath "$BODYFLOW_BOUNDARY_ROOT/SourcePackages" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -configuration Release \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$BODYFLOW_BOUNDARY_ROOT/release" \
  -clonedSourcePackagesDirPath "$BODYFLOW_BOUNDARY_ROOT/SourcePackages" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  CODE_SIGNING_ALLOWED=NO build

BODYFLOW_BOUNDARY_BINARY="$BODYFLOW_BOUNDARY_ROOT/release/Build/Products/Release-iphonesimulator/BodyFlow.app/BodyFlow"
test -x "$BODYFLOW_BOUNDARY_BINARY"

set +e
strings "$BODYFLOW_BOUNDARY_BINARY" \
  | rg 'ui-testing-prompt14|DemoPrompt14|DemoContentCoverByteStream|MascotPlaceholderArtwork|prompt14-fixture\.invalid'
BODYFLOW_BOUNDARY_BINARY_PROBE_EXIT=$?
set -e
case "$BODYFLOW_BOUNDARY_BINARY_PROBE_EXIT" in
  0) exit 1 ;;
  1) ;;
  *) exit "$BODYFLOW_BOUNDARY_BINARY_PROBE_EXIT" ;;
esac

git diff --unified=0 0e51adebfa8ef718db87096283154c738d8ea0ae -- \
  "${BODYFLOW_PROMPT14_RELEASE_SOURCE_SCOPE[@]}" \
  | sed -n '/^+++ /d; s/^+//p' > "$BODYFLOW_PROMPT14_ADDED_LINES"
bodyflow_boundary_require_no_rg_match -n \
  'URLSession|URLRequest|HTTPClient|APIClient|Authorization|Bearer|baseURL|APIRequest<|https?://' \
  "$BODYFLOW_PROMPT14_ADDED_LINES"
bodyflow_boundary_require_no_rg_match -n -i \
  '\b(openai|llm)\b|recurring[[:space:]_]*message|mascot[[:space:]_]*message[[:space:]_]*catalog|xpToNext|levelThreshold|levelForXP|computeProgress|calculate(Level|XP|Streak)|awardXP|restoreStreak' \
  apps/ios/BodyFlow/BodyFlow
git diff --check
```

Expected: focused tests and both builds succeed; the unit boundary proves nil origin/no stream call/unavailable providers, the added-line gate covers every Prompt 14 composition/adapter/feature path (including `AppDependencies`, root launch composition and unavailable adapters) without being confused by inherited transport, and the Release binary scan finds no scenario/repository/fake-stream/temporary-art/fixture literal.

- [ ] **Step 5: Refactor/review and commit**

Review that “Indisponível nesta versão” is the only Release Prompt 14 outcome and the mandatory live transport gate remains unimplemented. Then:

```bash
git add apps/ios/BodyFlow/BodyFlow/Features/PreviewSupport/Prompt14PreviewSupport.swift \
  apps/ios/BodyFlow/BodyFlow/Core/Telemetry/TelemetryClient.swift \
  apps/ios/BodyFlow/BodyFlowTests/Prompt14ReleaseBoundaryTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/Prompt14TelemetryPrivacyTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/Prompt14PreviewSupportTests.swift \
  apps/ios/BodyFlow/BodyFlowTests/Prompt14LaunchConfigurationTests.swift
git commit -m "test(ios): harden prompt 14 release privacy"
```

### Task 27: Add UI, Accessibility And Visual-Evidence Journeys

**Files:**
- Create: `apps/ios/BodyFlow/BodyFlowUITests/Prompt14UITestSupport.swift`
- Create: `apps/ios/BodyFlow/BodyFlowUITests/Prompt14LibraryUITests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowUITests/Prompt14TodayMascotUITests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowUITests/Prompt14ProgressUITests.swift`
- Create: `apps/ios/BodyFlow/BodyFlowUITests/Prompt14AccessibilityUITests.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Library/LibraryRootView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Library/PublishedContentDetailView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Library/BodyFlowMarkdownView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Today/TodayRecommendationsSection.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Mascot/MascotCardView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Mascot/MascotDetailView.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Progress/ProgressComponents.swift`
- Modify: `apps/ios/BodyFlow/BodyFlow/Features/Progress/ProgressRootView.swift`

**Interfaces:**
- Consumes: Debug-only Prompt 14 scenarios and stable accessibility identifiers.
- Produces: deterministic XCUI journeys and named PNG/TXT attachments; no test-only success path in Release.

- [ ] **Step 1: Write the UI journeys against a missing support layer (RED)**

Create test files that reference `Prompt14UITestSupport` and its closed scenario/evidence-name enums before defining that support type. Required journeys:

- all five original tabs still open and retain independent stacks;
- Today recommendations loaded/empty/offline/stale/error/unavailable while official Today remains visible;
- Library All/Saved/category/load-more/next-page Retry, invalid-cursor first-page recovery and all neutral empty states;
- detail GET precedes one opened, opened failure leaves full article usable, Markdown failure exposes no raw body, content-not-found exposes Voltar/Biblioteca, subscription-required exposes no commerce flow, save/unsave/completion/conflict work and conflict focus returns to the reloaded detail status;
- cover success/nil/expiry/oversized/MIME/dimension/external-path failure shows bounded placeholder;
- Focus/Impulse/Zen and Balanced, four requested state presentations, Evolving/Unknown neutral presentation, typed mascot detail reload;
- progress complete/null/minimum through their explicit deterministic flags, duplicate medals, streak-zero copy/Today CTA, mission unavailable and no ranking/cooperative element;
- VoiceOver semantics, external-link announcement, headings/lists/link traits, 44-point controls, Dark Mode, Accessibility XXXL, real simulator Increase Contrast, Debug-only Differentiate Without Color override and Reduce Motion. Assert tested focus targets after first load, filter change, mutation success/error and Retry.

- [ ] **Step 2: Run one test and observe compile RED**

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowUITests/Prompt14LibraryUITests/testLibraryLoadsApprovedMarkdownDetail \
  test
```

Expected RED: missing `Prompt14UITestSupport`/scenario type, not an unrelated app failure. This RED proves only the new test harness boundary; it is not counted as proof that the UI journeys themselves fail correctly.

- [ ] **Step 3: Implement the deterministic test support and minimal accessibility corrections**

First define exactly one `--ui-testing-prompt14-*` scenario per launch, preserving the existing `--ui-testing` and Prompt 13 loaded setup. Rerun the single Step 2 selector and require harness GREEN. Then run the complete Prompt 14 UI group before changing production UI. Any failing journey is its own observed integration RED; record the exact assertion/screenshot, apply the smallest correction in the exact permitted view files listed for this task, and rerun that selector GREEN before the whole group. Do not manufacture a UI failure if behavior already reached GREEN under its earlier unit/presentation TDD task.

Use stable IDs, `waitForExistence`, explicit absence assertions and 44×44 frame checks. Add these exact attachment names to a closed allowlist:

`Prompt14AccessibilityUITests` defines the exact selectors `testDarkModeEvidence`, `testAccessibilityXXXLEvidence`, `testIncreaseContrastEvidence`, `testDifferentiateWithoutColorEvidence` and `testReduceMotionEvidence`. The first three consume the real simulator settings established before launch; the latter two launch with their reviewed Debug-only overrides. Each selector emits only its corresponding named PNG/TXT pair so Task 28 can export it from a dedicated result bundle without accepting a default-environment duplicate.

```text
01-today-recommendations.png
02-library-all.png
03-library-saved-empty.png
04-library-category-pagination.png
05-content-detail-markdown.png
06-opened-error-nonblocking.png
07-cover-failure-placeholder.png
08-mascot-focus-active.png
09-mascot-zen-neglected.png
10-mascot-evolving-neutral.png
11-progress-gamification.png
12-streak-zero-missions.png
13-offline-error-retry.png
14-conflict-reload.png
15-dark-mode.png
16-accessibility-xxxl.png
17-increase-contrast.png
18-differentiate-without-color.png
19-reduce-motion.png
20-unavailable.png
21-final-simulator.png
```

Each screenshot attachment gets a separate same-base-name `.txt` XCUI hierarchy attachment. Fix only observed Prompt 14 integration/accessibility failures; do not broaden feature scope. Before Step 4, every changed production view must therefore have a named failing UI selector plus its GREEN rerun in the task record.

- [ ] **Step 4: Run the complete Prompt 14 UI group GREEN**

```bash
set -euo pipefail
BODYFLOW_TASK25_ROOT="$(mktemp -d /tmp/bodyflow-prompt14-ui.XXXXXX)"

bodyflow_task25_restore_simulator() {
  xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 appearance light || true
  xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 content_size large || true
  xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 increase_contrast disabled || true
}

bodyflow_task25_run_variant() {
  local selector="$1"
  xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
    -scheme BodyFlow \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
    -derivedDataPath "$BODYFLOW_TASK25_ROOT/DerivedData" \
    -clonedSourcePackagesDirPath "$BODYFLOW_TASK25_ROOT/SourcePackages" \
    -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
    "-only-testing:$selector" \
    test
}

trap bodyflow_task25_restore_simulator EXIT
bodyflow_task25_restore_simulator

xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -derivedDataPath "$BODYFLOW_TASK25_ROOT/DerivedData" \
  -clonedSourcePackagesDirPath "$BODYFLOW_TASK25_ROOT/SourcePackages" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -only-testing:BodyFlowUITests/Prompt14LibraryUITests \
  -only-testing:BodyFlowUITests/Prompt14TodayMascotUITests \
  -only-testing:BodyFlowUITests/Prompt14ProgressUITests \
  -only-testing:BodyFlowUITests/Prompt14AccessibilityUITests \
  -skip-testing:BodyFlowUITests/Prompt14AccessibilityUITests/testDarkModeEvidence \
  -skip-testing:BodyFlowUITests/Prompt14AccessibilityUITests/testAccessibilityXXXLEvidence \
  -skip-testing:BodyFlowUITests/Prompt14AccessibilityUITests/testIncreaseContrastEvidence \
  -skip-testing:BodyFlowUITests/Prompt14AccessibilityUITests/testDifferentiateWithoutColorEvidence \
  -skip-testing:BodyFlowUITests/Prompt14AccessibilityUITests/testReduceMotionEvidence \
  test

xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 appearance dark
bodyflow_task25_run_variant \
  BodyFlowUITests/Prompt14AccessibilityUITests/testDarkModeEvidence
xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 appearance light

xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 \
  content_size accessibility-extra-extra-extra-large
bodyflow_task25_run_variant \
  BodyFlowUITests/Prompt14AccessibilityUITests/testAccessibilityXXXLEvidence
xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 content_size large

xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 increase_contrast enabled
bodyflow_task25_run_variant \
  BodyFlowUITests/Prompt14AccessibilityUITests/testIncreaseContrastEvidence
xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 increase_contrast disabled

bodyflow_task25_run_variant \
  BodyFlowUITests/Prompt14AccessibilityUITests/testDifferentiateWithoutColorEvidence
bodyflow_task25_run_variant \
  BodyFlowUITests/Prompt14AccessibilityUITests/testReduceMotionEvidence

bodyflow_task25_restore_simulator
trap - EXIT
git diff --check
```

Expected: the non-variant group passes once, each of the five excluded selectors passes exactly once after its real simulator setting or reviewed Debug override is active, the simulator is restored to Light/Large/normal contrast even on failure, and `git diff --check` passes. Task 28 repeats this with fresh result bundles for the final zero-skip evidence gate.

- [ ] **Step 5: Review and commit**

Review UI hierarchy attachments for duplicate/nested actions, clipped text and missing semantics. Confirm screenshots are attachments only; Task 28 curates evidence. Commit all and only Task 27 changes:

```bash
set -euo pipefail
BODYFLOW_TASK25_REQUIRED=(
  apps/ios/BodyFlow/BodyFlowUITests/Prompt14UITestSupport.swift
  apps/ios/BodyFlow/BodyFlowUITests/Prompt14LibraryUITests.swift
  apps/ios/BodyFlow/BodyFlowUITests/Prompt14TodayMascotUITests.swift
  apps/ios/BodyFlow/BodyFlowUITests/Prompt14ProgressUITests.swift
  apps/ios/BodyFlow/BodyFlowUITests/Prompt14AccessibilityUITests.swift
)
BODYFLOW_TASK25_ALLOWED=(
  "${BODYFLOW_TASK25_REQUIRED[@]}"
  apps/ios/BodyFlow/BodyFlow/Features/Library/LibraryRootView.swift
  apps/ios/BodyFlow/BodyFlow/Features/Library/PublishedContentDetailView.swift
  apps/ios/BodyFlow/BodyFlow/Features/Library/BodyFlowMarkdownView.swift
  apps/ios/BodyFlow/BodyFlow/Features/Today/TodayRecommendationsSection.swift
  apps/ios/BodyFlow/BodyFlow/Features/Mascot/MascotCardView.swift
  apps/ios/BodyFlow/BodyFlow/Features/Mascot/MascotDetailView.swift
  apps/ios/BodyFlow/BodyFlow/Features/Progress/ProgressComponents.swift
  apps/ios/BodyFlow/BodyFlow/Features/Progress/ProgressRootView.swift
)
git add -- "${BODYFLOW_TASK25_ALLOWED[@]}"
for required_path in "${BODYFLOW_TASK25_REQUIRED[@]}"; do
  git diff --cached --name-only | rg -Fx "$required_path" >/dev/null
done
BODYFLOW_TASK25_UNEXPECTED="$(
  comm -23 \
    <(git diff --cached --name-only | sort) \
    <(printf '%s\n' "${BODYFLOW_TASK25_ALLOWED[@]}" | sort)
)"
test -z "$BODYFLOW_TASK25_UNEXPECTED"
git diff --cached --name-only
git diff --cached --check
git commit -m "test(ios): cover prompt 14 runtime and accessibility"
```

Before committing, require all five new XCUI files. Production view paths are an allowed subset only: each staged view must have its recorded RED/GREEN, unchanged permitted views do not appear in the stage, and any path outside the allowlist stops the task.

### Task 28: Run The Complete Local Gate And Capture Evidence

**Files:**
- Create: `docs/superpowers/evidence/2026-08-02-bodyflow-ios-library-mascot-gamification/README.md`
- Create: the 21 curated PNGs and 21 matching hierarchy TXT files listed in Task 27 under the same evidence directory.

**Interfaces:**
- Consumes: complete inherited + Prompt 14 unit/UI suite, exact package lock, Debug/Release builds and approved simulator.
- Produces: reproducible local verification evidence and a clean committed branch; no push/PR/TestFlight.

- [ ] **Step 1: Revalidate the immutable environment**

```bash
set -euo pipefail
test "$(pwd)" = "/Users/eduardohenrique/Developer/bodyflow"
test "$(git branch --show-current)" = "codex/bodyflow-ios-library-mascot-gamification-v1"
test -z "$(git status --porcelain)"
git merge-base --is-ancestor 0e51adebfa8ef718db87096283154c738d8ea0ae HEAD
test "$(uname -s)" = "Darwin"
test "$(xcodebuild -version | sed -n '1p')" = "Xcode 26.6"
xcrun simctl list devices available \
  | rg 'iPhone 17 Pro \(27291590-659D-4A29-8F45-CA5CA2D154F9\) \((Booted|Shutdown)\)'
xcrun simctl list runtimes available | rg 'iOS 26\.5'
```

Expected: Xcode 26.6/build 17F113, iOS 26.5 iPhone 17 Pro available, clean worktree before evidence generation.

- [ ] **Step 2: Run one fail-fast automated gate in one shell**

Keep this as one shell block: every task-specific path is declared, validated and consumed inside the same `set -euo pipefail` process, so no empty variable can silently become `/SourcePackages`, `/Build` or an evidence-root path. The main result bundle runs the entire suite except the five environment-sensitive evidence selectors; each of those is then run exactly once under its required variant in a dedicated result bundle. The union is the complete test suite, and every bundle must independently report zero failures and zero skips.

```bash
set -euo pipefail
BODYFLOW_GATE_ROOT="$(mktemp -d /tmp/bodyflow-prompt14-gate.XXXXXX)"
BODYFLOW_RESULT_BUNDLE="$BODYFLOW_GATE_ROOT/BodyFlowPrompt14.xcresult"
BODYFLOW_TEST_ROOT="$BODYFLOW_GATE_ROOT/test"
BODYFLOW_DEBUG_ROOT="$BODYFLOW_GATE_ROOT/debug"
BODYFLOW_RELEASE_ROOT="$BODYFLOW_GATE_ROOT/release"
BODYFLOW_RUN_ROOT="$BODYFLOW_GATE_ROOT/run"
BODYFLOW_ATTACHMENT_ROOT="$BODYFLOW_GATE_ROOT/attachments"
BODYFLOW_VARIANT_ROOT="$BODYFLOW_GATE_ROOT/variants"
BODYFLOW_SOURCE_PACKAGES="$BODYFLOW_GATE_ROOT/SourcePackages"
BODYFLOW_EVIDENCE_ROOT="/Users/eduardohenrique/Developer/bodyflow/docs/superpowers/evidence/2026-08-02-bodyflow-ios-library-mascot-gamification"

for value in \
  "$BODYFLOW_GATE_ROOT" "$BODYFLOW_RESULT_BUNDLE" "$BODYFLOW_TEST_ROOT" "$BODYFLOW_DEBUG_ROOT" \
  "$BODYFLOW_RELEASE_ROOT" "$BODYFLOW_RUN_ROOT" "$BODYFLOW_ATTACHMENT_ROOT" \
  "$BODYFLOW_VARIANT_ROOT" "$BODYFLOW_SOURCE_PACKAGES" "$BODYFLOW_EVIDENCE_ROOT"; do
  test -n "$value"
done

bodyflow_assert_test_summary() {
  local result_bundle="$1"
  local result_summary
  result_summary="$(
    xcrun xcresulttool get test-results summary \
      --schema-version 0.1.0 --compact --path "$result_bundle"
  )"
  printf '%s\n' "$result_summary"
  jq -e '
    .result == "Passed"
    and .failedTests == 0
    and .skippedTests == 0
    and .passedTests == .totalTestCount
  ' <<<"$result_summary"
}

bodyflow_require_no_rg_match() {
  local probe_exit
  set +e
  rg "$@"
  probe_exit=$?
  set -e
  case "$probe_exit" in
    0) return 1 ;;
    1) return 0 ;;
    *) return "$probe_exit" ;;
  esac
}

BODYFLOW_PROMPT14_RELEASE_SOURCE_SCOPE=(
  apps/ios/BodyFlow/BodyFlow/App
  apps/ios/BodyFlow/BodyFlow/Core/Content
  apps/ios/BodyFlow/BodyFlow/Core/CoachExperience
  apps/ios/BodyFlow/BodyFlow/Core/Progress
  apps/ios/BodyFlow/BodyFlow/Core/Support
  apps/ios/BodyFlow/BodyFlow/Core/Telemetry
  apps/ios/BodyFlow/BodyFlow/Core/Unavailable
  apps/ios/BodyFlow/BodyFlow/Features/Library
  apps/ios/BodyFlow/BodyFlow/Features/Mascot
  apps/ios/BodyFlow/BodyFlow/Features/Profile
  apps/ios/BodyFlow/BodyFlow/Features/Progress
  apps/ios/BodyFlow/BodyFlow/Features/Today
)
BODYFLOW_PROMPT14_ADDED_LINES="$BODYFLOW_GATE_ROOT/prompt14-added-lines.txt"

bodyflow_run_accessibility_variant() {
  local variant_name="$1"
  local test_selector="$2"
  local result_bundle="$BODYFLOW_VARIANT_ROOT/$variant_name.xcresult"
  xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
    -scheme BodyFlow \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
    -derivedDataPath "$BODYFLOW_TEST_ROOT" \
    -clonedSourcePackagesDirPath "$BODYFLOW_SOURCE_PACKAGES" \
    -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
    -resultBundlePath "$result_bundle" \
    "-only-testing:$test_selector" \
    test
  bodyflow_assert_test_summary "$result_bundle"
}

bodyflow_copy_attachment_pair() {
  local attachment_root="$1"
  local base_name="$2"
  local extension expected_name exported_name_count exported_name source_path
  for extension in png txt; do
    expected_name="$base_name.$extension"
    exported_name_count="$(
      jq -r --arg name "$expected_name" \
        '.. | objects | select(.suggestedHumanReadableName? == $name) | .exportedFileName' \
        "$attachment_root/manifest.json" \
        | sed '/^$/d' | wc -l | tr -d ' '
    )"
    test "$exported_name_count" -eq 1
    exported_name="$(
      jq -er --arg name "$expected_name" \
        'first(.. | objects | select(.suggestedHumanReadableName? == $name) | .exportedFileName)' \
        "$attachment_root/manifest.json"
    )"
    source_path="$attachment_root/$exported_name"
    test -s "$source_path"
    cp "$source_path" "$BODYFLOW_EVIDENCE_ROOT/$expected_name"
  done
}

git diff --exit-code -- pnpm-workspace.yaml pnpm-lock.yaml
trap 'git diff --exit-code -- pnpm-workspace.yaml pnpm-lock.yaml' EXIT
pnpm --filter @mpp/core test
pnpm --filter @mpp/core typecheck
pnpm --filter @mpp/admin test
pnpm --filter @mpp/admin typecheck
git diff --exit-code -- pnpm-workspace.yaml pnpm-lock.yaml
trap - EXIT

xcrun simctl bootstatus 27291590-659D-4A29-8F45-CA5CA2D154F9 -b
xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 appearance light
xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 content_size large
xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 increase_contrast disabled

xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -derivedDataPath "$BODYFLOW_TEST_ROOT" \
  -clonedSourcePackagesDirPath "$BODYFLOW_SOURCE_PACKAGES" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -resultBundlePath "$BODYFLOW_RESULT_BUNDLE" \
  -skip-testing:BodyFlowUITests/Prompt14AccessibilityUITests/testDarkModeEvidence \
  -skip-testing:BodyFlowUITests/Prompt14AccessibilityUITests/testAccessibilityXXXLEvidence \
  -skip-testing:BodyFlowUITests/Prompt14AccessibilityUITests/testIncreaseContrastEvidence \
  -skip-testing:BodyFlowUITests/Prompt14AccessibilityUITests/testDifferentiateWithoutColorEvidence \
  -skip-testing:BodyFlowUITests/Prompt14AccessibilityUITests/testReduceMotionEvidence \
  test

bodyflow_assert_test_summary "$BODYFLOW_RESULT_BUNDLE"

xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 appearance dark
bodyflow_run_accessibility_variant \
  dark \
  BodyFlowUITests/Prompt14AccessibilityUITests/testDarkModeEvidence
xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 appearance light

xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 \
  content_size accessibility-extra-extra-extra-large
bodyflow_run_accessibility_variant \
  accessibility-xxxl \
  BodyFlowUITests/Prompt14AccessibilityUITests/testAccessibilityXXXLEvidence
xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 content_size large

xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 increase_contrast enabled
bodyflow_run_accessibility_variant \
  increase-contrast \
  BodyFlowUITests/Prompt14AccessibilityUITests/testIncreaseContrastEvidence
xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 increase_contrast disabled

bodyflow_run_accessibility_variant \
  differentiate-without-color \
  BodyFlowUITests/Prompt14AccessibilityUITests/testDifferentiateWithoutColorEvidence
bodyflow_run_accessibility_variant \
  reduce-motion \
  BodyFlowUITests/Prompt14AccessibilityUITests/testReduceMotionEvidence

xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -derivedDataPath "$BODYFLOW_DEBUG_ROOT" \
  -clonedSourcePackagesDirPath "$BODYFLOW_SOURCE_PACKAGES" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -configuration Release \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$BODYFLOW_RELEASE_ROOT" \
  -clonedSourcePackagesDirPath "$BODYFLOW_SOURCE_PACKAGES" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -derivedDataPath "$BODYFLOW_RUN_ROOT" \
  -clonedSourcePackagesDirPath "$BODYFLOW_SOURCE_PACKAGES" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  build

BODYFLOW_RELEASE_BINARY="$BODYFLOW_RELEASE_ROOT/Build/Products/Release-iphonesimulator/BodyFlow.app/BodyFlow"
test -x "$BODYFLOW_RELEASE_BINARY"

set +e
strings "$BODYFLOW_RELEASE_BINARY" \
  | rg 'ui-testing-prompt14|DemoPrompt14|DemoContentCoverByteStream|MascotPlaceholderArtwork|prompt14-fixture\.invalid'
BODYFLOW_BINARY_PROBE_EXIT=$?
set -e
case "$BODYFLOW_BINARY_PROBE_EXIT" in
  0) exit 1 ;;
  1) ;;
  *) exit "$BODYFLOW_BINARY_PROBE_EXIT" ;;
esac

bodyflow_require_no_rg_match -n -i 'whatsapp' apps/ios/BodyFlow/BodyFlow
bodyflow_require_no_rg_match -n -i \
  '\b(openai|llm)\b|recurring[[:space:]_]*message|mascot[[:space:]_]*message[[:space:]_]*catalog|xpToNext|levelThreshold|levelForXP|computeProgress|calculate(Level|XP|Streak)|awardXP|restoreStreak' \
  apps/ios/BodyFlow/BodyFlow
bodyflow_require_no_rg_match -n \
  '(?i)(struct|class|actor|enum|typealias|protocol)[[:space:]]+((mission|ranking|cooperativemission)|[[:alnum:]_]*(mission|ranking|cooperative)[[:alnum:]_]*(dto|provider|providing|repository|service|client|response|request|snapshot|model|store|route|query|command))\b' \
  apps/ios/BodyFlow/BodyFlow
git diff --unified=0 0e51adebfa8ef718db87096283154c738d8ea0ae -- \
  "${BODYFLOW_PROMPT14_RELEASE_SOURCE_SCOPE[@]}" \
  | sed -n '/^+++ /d; s/^+//p' > "$BODYFLOW_PROMPT14_ADDED_LINES"
bodyflow_require_no_rg_match -n \
  'URLSession|URLRequest|HTTPClient|APIClient|Authorization|Bearer|baseURL|APIRequest<|https?://' \
  "$BODYFLOW_PROMPT14_ADDED_LINES"

xcrun simctl install 27291590-659D-4A29-8F45-CA5CA2D154F9 \
  "$BODYFLOW_RUN_ROOT/Build/Products/Debug-iphonesimulator/BodyFlow.app"
xcrun simctl launch 27291590-659D-4A29-8F45-CA5CA2D154F9 \
  com.bodyflow.app --ui-testing --ui-testing-prompt14-loaded

mkdir -p "$BODYFLOW_ATTACHMENT_ROOT/main" "$BODYFLOW_EVIDENCE_ROOT"
xcrun xcresulttool export attachments \
  --path "$BODYFLOW_RESULT_BUNDLE" \
  --output-path "$BODYFLOW_ATTACHMENT_ROOT/main"
test -f "$BODYFLOW_ATTACHMENT_ROOT/main/manifest.json"

BODYFLOW_GENERAL_EVIDENCE_NAMES=(
  01-today-recommendations 02-library-all 03-library-saved-empty
  04-library-category-pagination 05-content-detail-markdown
  06-opened-error-nonblocking 07-cover-failure-placeholder
  08-mascot-focus-active 09-mascot-zen-neglected
  10-mascot-evolving-neutral 11-progress-gamification
  12-streak-zero-missions 13-offline-error-retry 14-conflict-reload
  20-unavailable 21-final-simulator
)
for base_name in "${BODYFLOW_GENERAL_EVIDENCE_NAMES[@]}"; do
  bodyflow_copy_attachment_pair "$BODYFLOW_ATTACHMENT_ROOT/main" "$base_name"
done

bodyflow_export_variant_evidence() {
  local variant_name="$1"
  local evidence_name="$2"
  local variant_bundle="$BODYFLOW_VARIANT_ROOT/$variant_name.xcresult"
  local variant_attachments="$BODYFLOW_ATTACHMENT_ROOT/$variant_name"
  mkdir -p "$variant_attachments"
  xcrun xcresulttool export attachments \
    --path "$variant_bundle" \
    --output-path "$variant_attachments"
  test -f "$variant_attachments/manifest.json"
  bodyflow_copy_attachment_pair \
    "$variant_attachments" \
    "$evidence_name"
}
bodyflow_export_variant_evidence dark 15-dark-mode
bodyflow_export_variant_evidence accessibility-xxxl 16-accessibility-xxxl
bodyflow_export_variant_evidence increase-contrast 17-increase-contrast
bodyflow_export_variant_evidence \
  differentiate-without-color 18-differentiate-without-color
bodyflow_export_variant_evidence reduce-motion 19-reduce-motion

test "$(find "$BODYFLOW_EVIDENCE_ROOT" -maxdepth 1 -type f -name '*.png' | wc -l | tr -d ' ')" -eq 21
test "$(find "$BODYFLOW_EVIDENCE_ROOT" -maxdepth 1 -type f -name '*.txt' | wc -l | tr -d ' ')" -eq 21
for image in "$BODYFLOW_EVIDENCE_ROOT"/*.png; do
  test -s "$image"
  sips -g pixelWidth -g pixelHeight "$image"
done

echo "Gate artifacts: $BODYFLOW_GATE_ROOT"
```

Expected: the complete core/admin backend suites (including Tasks 0, 6 and 8) and every inherited/Prompt 14 unit/UI test pass with zero failures/skips under a fresh test DerivedData root; each dedicated accessibility selector also passes with zero skips after its real/approved variant is configured; three builds report `** BUILD SUCCEEDED **`; Release has no Prompt 14 live/fixture success path; the Debug app is running; and exactly 21 PNG + 21 matching TXT attachments are curated from the correct result bundle. Record actual backend logical-test count, native logical/execution/UI-test counts and durations; never predict counts. The live content audit is not run, and both that clean-audit prerequisite and a successful Release compile remain insufficient without explicit TestFlight authorization.

- [ ] **Step 3: Perform manual visual and interaction inspection across deterministic scenarios**

Inspect:

- all five tabs and independent navigation stacks;
- Today official state while recommendations load/fail independently;
- Library All/Saved/category/load-more and exact empty/error/stale/unavailable states;
- detail title/category/reading time/Markdown/list/link semantics, one opened and non-blocking opened failure;
- save/unsave/completion/conflict and generic not-found handling;
- valid/nil/expired/invalid/oversized cover presentation;
- Focus/Impulse/Zen/Balanced and Inactive/Reactivating/Active/Neglected/Evolving/Unknown mascot presentations;
- literal XP/level/streak/duplicate medals, null/minimum progress, streak-zero return and missions unavailable;
- complete absence of ranking/cooperative UI, recurring generated message, reward math or third-party visual references;
- no clipping, false success, unexpected permission prompt, crash or external navigation from a cover.

For each state family, terminate and relaunch the installed Debug app with exactly one applicable `--ui-testing-prompt14-*` flag from Task 12. Explicitly inspect `stale` and `conflict` rather than inferring them from generic error. Finish by relaunching `--ui-testing-prompt14-loaded` and leave BodyFlow running.

- [ ] **Step 4: Inspect accessibility variants and focus behavior**

Run representative journeys under Dark Mode, Accessibility XXXL, real Increase Contrast, Debug-only Differentiate Without Color and deterministic Reduce Motion:

```bash
set -euo pipefail
xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 appearance dark
xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 content_size accessibility-extra-extra-extra-large
xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 increase_contrast enabled
xcrun simctl terminate 27291590-659D-4A29-8F45-CA5CA2D154F9 com.bodyflow.app || true
xcrun simctl launch 27291590-659D-4A29-8F45-CA5CA2D154F9 \
  com.bodyflow.app --ui-testing --ui-testing-prompt14-differentiate-without-color
xcrun simctl terminate 27291590-659D-4A29-8F45-CA5CA2D154F9 com.bodyflow.app
xcrun simctl launch 27291590-659D-4A29-8F45-CA5CA2D154F9 \
  com.bodyflow.app --ui-testing --ui-testing-prompt14-reduce-motion
xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 increase_contrast disabled
xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 appearance light
xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 content_size large
xcrun simctl terminate 27291590-659D-4A29-8F45-CA5CA2D154F9 com.bodyflow.app
xcrun simctl launch 27291590-659D-4A29-8F45-CA5CA2D154F9 \
  com.bodyflow.app --ui-testing --ui-testing-prompt14-loaded
```

Manually record VoiceOver order, headings/list/link traits, external-link identification, state/persona text equivalence, 44-point targets, semantic contrast and no horizontal scroll at Accessibility XXXL. Exercise load, filter change, mutation success/error and Retry and confirm logical focus lands on the tested semantic target. Confirm color is never the sole state indicator under Differentiate Without Color. Restore Increase Contrast off, Light/Large and the loaded scenario at the end.

- [ ] **Step 5: Review the curated evidence allowlist**

Open all 21 PNGs and their same-base hierarchy TXT attachments. Reject and rerun the relevant UI journey if any image is blank, clipped, duplicated, mismatched to its hierarchy or contains unrelated patient data. The automated gate deliberately has no `simctl screenshot` fallback: a missing `21-final-simulator.png` or hierarchy is a failed UI-evidence test, not permission to create an unmatched file. Do not copy the raw attachment directory or `.xcresult` into Git.

- [ ] **Step 6: Write the evidence README with `apply_patch`**

Record branch/tested SHA, Xcode/runtime/simulator, exact backend GFM-table and native package pins, result-bundle path, actual backend/native test and build counts/durations, every visual/accessibility state inspected, synthetic Debug-only fixture disclosure, Release fail-closed proof, and the separate three-part transport/session pre-TestFlight gate. Record that the live Markdown audit was not executed by this plan and remains a separate read-only TestFlight blocker whose authorized result must be zero incompatible `current` and `scheduled` visibility candidates. Explicitly state that the future audit uses the exact activation-point ordering and emits only its approved technical allowlist, and that no live transport/base URL/session bridge, live content audit, secret, migration, deploy, merge, TestFlight, production or WhatsApp architecture was added.

- [ ] **Step 7: Final diff checks and evidence commit**

```bash
set -euo pipefail
BODYFLOW_EVIDENCE_ROOT="docs/superpowers/evidence/2026-08-02-bodyflow-ios-library-mascot-gamification"
BODYFLOW_EVIDENCE_NAMES=(
  01-today-recommendations 02-library-all 03-library-saved-empty
  04-library-category-pagination 05-content-detail-markdown
  06-opened-error-nonblocking 07-cover-failure-placeholder
  08-mascot-focus-active 09-mascot-zen-neglected
  10-mascot-evolving-neutral 11-progress-gamification
  12-streak-zero-missions 13-offline-error-retry 14-conflict-reload
  15-dark-mode 16-accessibility-xxxl 17-increase-contrast
  18-differentiate-without-color 19-reduce-motion 20-unavailable
  21-final-simulator
)
BODYFLOW_EVIDENCE_PATHS=("$BODYFLOW_EVIDENCE_ROOT/README.md")
for base in "${BODYFLOW_EVIDENCE_NAMES[@]}"; do
  BODYFLOW_EVIDENCE_PATHS+=(
    "$BODYFLOW_EVIDENCE_ROOT/$base.png"
    "$BODYFLOW_EVIDENCE_ROOT/$base.txt"
  )
done
for path in "${BODYFLOW_EVIDENCE_PATHS[@]}"; do test -s "$path"; done
git diff --check
git status --short
git add -- "${BODYFLOW_EVIDENCE_PATHS[@]}"
test "$(git diff --cached --name-only | wc -l | tr -d ' ')" -eq 43
git diff --cached --check
git commit -m "docs(ios): add prompt 14 verification evidence"
test -z "$(git status --porcelain)"
```

Expected: clean worktree. Stop here. Do not push, create a PR, merge, deploy, migrate or use TestFlight without a later explicit authorization.

## Specification-To-Task/Test Coverage Matrix

| Approved specification criterion | Implementation task(s) | Proving test/gate |
| --- | --- | --- |
| Exactly five tabs; Library/mascot in Today typed stack | 17, 18, 24 | `AppRouterTests`, Prompt 14 tab UI journey |
| Content only from real published-content contract shapes | 1, 13 | `PublishedContentContractTests`, `DemoPrompt14RepositoryTests` |
| Today recommendations are separate `surface=today&limit=3` and do not alter Today | 15, 22 | `TodayRecommendationsTests`, inherited `TodayContractTests` |
| Library/Saved exact surfaces, category, query bounds, opaque pagination and invalid-cursor first-page recovery | 1, 15, 18 | literal `0/1/50/51` and empty/`1/512/513` contract tests, feed invalid-cursor tests, Library UI tests |
| Detail route only ID/origin and GET detail authorization | 17, 19 | `AppRouterTests`, `ContentDetailViewModelTests` |
| No opened on tap; one opened after valid detail using detail version | 19 | controlled-provider `ContentDetailViewModelTests`, detail UI journey |
| No opened for failed/unavailable/cancelled/invalid detail | 19 | zero-attempt parameterized detail tests |
| Opened failure non-blocking, no retry/queue/duplicate | 19 | opened-error unit/UI journeys |
| Exact-pinned `swift-markdown` and resolved transitive lock | 4 | `jq` lock assertion and resolved-file-only resolution |
| Approved canonical Markdown subset only; safe literal pipe/directive/Doxygen text loads while current/future unsupported nodes fail closed; no regex/WebView/raw fallback | 5, 7, 8 | reconciled source/node/default-reject `BodyFlowMarkdownParserTests`, exact corpus ASTs and forbidden-source scan |
| Exact backend GFM-table AST pins; table rejected without regex/rewrite while ordinary and escaped pipes remain valid | 0 | manifest/lock assertions and literal `content.test.ts` RED/GREEN cases |
| Backend rejects strikethrough, task-list/checkbox and corpus-defined malformed strong before canonicalization while safe text remains valid | 6 | exact extension/lock assertions, `content.test.ts` and admin/mobile boundary tests |
| Backend measures complete canonical `toMarkdown` including terminal LF; iOS measures received payload after CRLF/CR → LF and never runs the serializer | 6, 7, 8 | three canonicalization-only backend cases, native contract-bound tests and zero-parser-call corpus assertions |
| CMS author entry/edit reject pipe tables at untrusted action and service boundaries before persistence | 0 | `actions.test.ts` and `admin-service.test.ts` save zero-call assertions |
| Minimal version-validation read selects only seven allowed fields, never publication history, targeting, assets or identities | 0 | exact query/mapping/null/error tests in `supabase-repository.test.ts` |
| Legacy source clone, submit, approve and publish fail before mutation; reject remains available; ordinary pipes advance unchanged | 0 | controlled snapshot/mutation-spy matrix in `admin-service.test.ts` |
| Unfiltered source/approve/publish snapshot absence returns bounded `not_found`; source publication/locale/state or approve/publish lifecycle mismatch returns bounded `lifecycle`; neither calls a mutation, including the `in_review` source-to-reject race | 0 | absent/mismatch and unsafe clone-race zero-call tests in `admin-service.test.ts` |
| Submit validates the exact expected revision while the locked RPC remains authoritative for draft-revision stale and lifecycle races | 0 | matching/missing snapshot plus preflight/post-preflight RPC error tests in `admin-service.test.ts` |
| Legacy-invalid detail is revalidated before cover/DTO work; valid detail returns only canonical `normalized`; storage is unchanged | 0, 6 | `content-service.test.ts` and mobile detail route canonical/atomic-error tests |
| Shared-corpus schema allows only 11 `parse_normalized`, 36 `reject_source` and the three named canonicalization-only rows | 8 | decoder combination tests, exact counts and zero native calls for the three editorial-only cases |
| Compatibility with real backend normalization/parser has no unexplained divergence | 0, 6, 7, 8 | shared JSON, `content-ios-compatibility.test.ts` and `MarkdownBackendCompatibilityTests` |
| Live audit is read-only, PII-free and separately authorized; exact current/future activation winners carry `candidate_class`, historical never-winners do not block, and both incompatible counts must be zero | 0, 28 | Task 0 current/scheduled fixture-review runbook, output allowlist and evidence README blocker declaration; no live run in this plan |
| Impression/completion/save exact bodies/version/idempotency | 1, 3, 14, 16, 20 | contract, demo replay, feed and detail mutation tests |
| Version conflict from impression/opened/save/complete invalidates catalog/detail, evicts exact old cover and never replays/reopens/reapplies | 3, 11, 16, 19, 20 | feed/detail invalidation tests with cover spies and one-attempt counters |
| JSON/Markdown/covers and mutation ledgers are session-memory-only; all old-user results are suppressed | 11, 13, 14, 17, 26 | repository generation tests, cache/session tests, controlled shell replacement tests and Release/privacy gate |
| Exact relative cover capability; no external bearer boundary | 9, 12 | `ContentCoverPathTests`, `Prompt14ReleaseBoundaryTests` |
| 10 MiB stream, MIME agreement, abusive dimensions, ImageIO downsampling | 10 | `ContentCoverDecoderTests` |
| 32 MiB/64 deterministic cache, expiry and session clear | 11 | `SessionCoverCacheTests`, `ContentCoverLoaderTests` |
| Cover failure uses neutral placeholder and bounded refresh | 21 | `ContentCoverViewModelTests`, cover UI journey |
| Mascot/persona and picker names/descriptions only from coach snapshot options | 2, 23, 24 | coach contract, mascot view-model and literal server-option picker tests |
| All five real states + unknown; four requested states dedicated | 2, 23, 24 | `CoachExperienceContractTests`, `MascotPresentationTests`, mascot UI journeys |
| Focus/Impulse/Zen visual-only; Balanced neutral | 23, 24 | presentation and accessibility-model tests |
| No local transitions, recurring LLM/catalog or invented message endpoint | 23, 26, 28 | dependency/source scans and mascot tests |
| XP/level/streak/badges literal from nullable `/progress` | 2, 25 | contract, view-model and presentation tests |
| Null is empty; minimum non-null row is loaded | 2, 25 | literal null/minimum progress tests |
| No level formula, badge metadata or XP award | 25, 28 | presentation tests and forbidden-type/source scan |
| Duplicate medals use positional identity | 25 | `ProgressPresentationTests` and progress UI journey |
| Zero streak supportive Today return without fake restoration | 25 | streak-zero unit/UI tests |
| Daily missions unavailable only | 25 | progress presentation/UI test |
| Ranking/cooperative missions absent | 25, 28 | UI absence assertions and forbidden-type scan |
| Loading/empty/offline/stale/error/conflict/retry/unavailable plus content-not-found/subscription-required deterministic | 12, 13, 15, 18, 19, 20, 22, 23, 25, 27 | feature suites plus explicit 404/subscription/stale/conflict launch/UI journeys |
| Injected time for attempts/cover expiry and immutable retry timestamp | 3, 11, 16, 20 | fixed-time cache/feed/detail tests |
| Accessibility, logical focus, Dynamic Type, Dark Mode, 44 points, Increase Contrast, Differentiate Without Color and Reduce Motion | 12, 18, 19, 20, 24, 25, 27, 28 | focus reducers, accessibility unit/UI journeys, real simulator contrast and manual gate |
| Temporary art/fixtures/fake streams first-party Debug-only | 12, 13, 24, 26 | Release boundary tests/build/binary scan |
| Release unavailable with nil origin, no request/stream call, URL/bearer/outbound/fixture success | 12, 26, 28 | unavailable-factory/no-stream spy tests, scoped source gate, Release build and binary scan |
| Auth transport/staging/session bridge remain mandatory separate gate | boundary section, 26, 28 | evidence README and explicit TestFlight prohibition |
| Full backend/native tests, Debug/Release builds, simulator and evidence | 0, 6, 7, 8, 27, 28 | complete core/admin suites, xcresult summary, three builds and 21 curated PNG/hierarchy pairs |
| No live service/audit, secret, migration, deploy, merge, TestFlight, production or WhatsApp | all; especially 0, 12, 26, 28 | diff/source audit and evidence README |

## Plan Completion Checklist

- [ ] Committed Tasks 0 through 5 remain unchanged; this reconciliation starts with a new Task 6 commit and never amends earlier checkpoints.
- [ ] Task 6 backend hardening commits before Task 7 native alignment; Task 7 commits before Task 8 resumes the corpus; Task 9 remains blocked until Task 8 is GREEN and committed.
- [ ] Backend pins remain exact at `mdast-util-from-markdown` 2.0.3, `mdast-util-to-markdown` 2.1.2, `micromark-extension-gfm-table` 2.1.1, `mdast-util-gfm-table` 2.0.0, `micromark-extension-gfm-strikethrough` 2.1.0, `mdast-util-gfm-strikethrough` 2.0.0, `micromark-extension-gfm-task-list-item` 2.1.0 and `mdast-util-gfm-task-list-item` 2.0.0.
- [ ] Pipe table, ordinary pipe, escaped-pipe and safe literal directive/Doxygen behavior is proven at the backend and in the Task 8 shared corpus; no regex, silent repair, serializer port or permissive iOS fallback is introduced.
- [ ] The Task 0 commit changes exactly the twelve allowlisted files, including `admin-service.ts`, `supabase-repository.ts` and its focused test; no migration or audit executable is added.
- [ ] The validation snapshot reads only version ID, publication ID, locale, state, body, updated timestamp and publish timestamp; publication detail/history, targets, assets and identities are never loaded.
- [ ] CMS action/service writes, source clone, submit, approve, publish and mobile detail defense reject table, strikethrough, task-list/checkbox and corpus-defined malformed strong, while reject remains available and safe text remains valid.
- [ ] Editorial source is never silently rewritten; mobile detail returns exactly the revalidated canonical `normalized` body, and invalid legacy content produces no body, cover or partial response.
- [ ] Unfiltered source/approve/publish absence, source publication/locale/state mismatch and approve/publish lifecycle mismatch stop locally with bounded existing errors and zero mutation; an incompatible `in_review` source cannot race its allowed rejection into a successful clone.
- [ ] Submit validates the snapshot corresponding to `expectedUpdatedAt`, passes the original precondition unchanged and leaves conflict decisions to the locked RPC: draft-revision races are `stale`, while lifecycle races retain their lifecycle error.
- [ ] Every production behavior has an observed focused RED before GREEN code.
- [ ] Every task returns GREEN, passes `git diff --check`, receives adherence/quality review and one Conventional Commit.
- [ ] Package resolution remains exact and reproducible from `Package.resolved` with updates disabled.
- [ ] iOS applies its `100...50_000` safety limit after CRLF/CR → LF only, never runs `toMarkdown`, and its source guards do not globally ban `|`, `@` or backslash.
- [ ] Task 8 validates all schema combinations and exact counts `50 = 11 parse_normalized + 36 reject_source + 3 backend_canonicalization_only`; the three named editorial-only rows cause zero native-parser calls and no unexplained divergence remains.
- [ ] Content, coach and progress models match only existing `/api/mobile/v1` contracts.
- [ ] No speculative endpoint, DTO, provider, score, formula, transition or history is introduced.
- [ ] Detail loads/authorizes/validates/parses before its one opened attempt.
- [ ] Cover validation/download/decode/cache/session limits all pass literal boundary tests.
- [ ] User replacement/sign-out ends content and cover sessions, clears every Prompt 14 ledger/cache/value and suppresses all controlled late list/detail/mutation/coach/progress results.
- [ ] Debug/previews/tests alone construct fixtures, fake streams and temporary mascot art.
- [ ] Release remains `operationUnavailable` with no Prompt 14 URL, bearer, request or fixture success.
- [ ] No live Markdown audit is executed by these 29 tasks; the future read-only audit queries no PII and evaluates the real winner at `audit_timestamp` plus every future activation with `version DESC, publish_at DESC`.
- [ ] The audit excludes only versions proven never to win, emits only separated counts plus the approved identifiers/state/`candidate_class` allowlist, and must report zero incompatible `current` and `scheduled` candidates before TestFlight.
- [ ] Any incompatible current or scheduled candidate is remediated only by a new compatible version through the existing editorial workflow; no historical version is mutated or cloned as an incompatible source.
- [ ] Daily missions remain unavailable; ranking/cooperative surfaces remain absent.
- [ ] Full inherited and Prompt 14 unit/contract/integration/UI suites pass with zero failure/skip.
- [ ] Debug and Release builds pass; Release success is not treated as distribution approval.
- [ ] iPhone 17 Pro iOS 26.5 visual/accessibility inspection covers stale/conflict, logical focus, Increase Contrast, Differentiate Without Color and Reduce Motion with 21 PNG/hierarchy pairs.
- [ ] Worktree is clean after the final local evidence commit.
- [ ] No push, PR, merge, migration, deploy, TestFlight, production or WhatsApp action occurs without later authorization.

Tasks 0 through 5 remain committed. After this documentary revision, the
specification status is `awaiting contract reconciliation approval`; await
later explicit authorization before executing Task 6 or any subsequent task.
