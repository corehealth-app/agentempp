# BodyFlow iOS Brand, Localization And Readiness Design

**Date:** 2026-08-09

**Status:** approved for implementation planning

**Approved:** 2026-08-10, including the competitive motion, mascot, and
gamification direction

**Stacked branch:** `codex/bodyflow-ios-brand-design-system-v1`

**Stacked base:** `codex/bodyflow-ios-library-mascot-gamification-v1` at
`0ce7f20f22b0e66a6de0544d4a46345181f2fccb`

## Objective

Define the authoritative boundary for reconstructing the approved BodyFlow
identity, localizing the native iOS app, and applying the final visual system
without hiding the technical work that still blocks a real-user beta.

This design authorizes documentation and, after a separate implementation
plan is approved, static brand-asset reconstruction and native visual work. It
does not authorize a merge, migration, deploy, production change, TestFlight
upload, live credential, App Store action, or Android implementation.

## Approved Product Decisions

- The commercial product name is **BodyFlow**.
- The product is app-first. No new architecture, screen, onboarding flow,
  account link, copy, test fixture, or future integration may depend on
  WhatsApp.
- Patient authentication uses email confirmation and email recovery. New app
  accounts start without an automatic link to legacy WhatsApp identities or
  history.
- The product includes a first-party in-app agent/chat experience; native
  registration forms complement that experience rather than replacing it.
- Native iOS is the current delivery platform.
- Android is a separate future workstream with its own architecture, design,
  implementation, QA, release, and store plan. Android is not implied by this
  iOS branch.
- The app shell and first-party UI must support `pt-BR` and `en-US` from the
  design-system phase onward.
- Patient content and official numeric values remain server-owned. The visual
  phase may not invent health, nutrition, routine, entitlement, gamification,
  recommendation, or progress data.
- The client-approved JPEG is the sole available visual source. The user owns
  it and explicitly authorized faithful reconstruction of the brand assets.

## Sources And Precedence

Conflicts are resolved in this order:

1. explicit user decisions recorded in the current BodyFlow app-first thread;
2. the approved JPEG visual board;
3. the BodyFlow V3 visual-identity workpack;
4. approved executable contracts and current iOS behavior;
5. the earlier technical workpack;
6. legacy WhatsApp-era product documents.

The approved board is:

- file: `PHOTO-2026-07-19-13-17-26.jpg`;
- dimensions: `1491x1055` pixels;
- SHA-256:
  `af44d4b2036638720eaaf58c05fa6098f69b21c7639b91bb4a60bc85c64c15b7`.

The board is authoritative for brand silhouette, color territory, visual
hierarchy, light/dark mood, icon direction, coach-card language, dashboard
character, and overall polish. It is not an executable product contract and
is not authoritative for displayed data, calculations, tab names, feature
availability, or backend behavior.

The supporting behavior and motion research is:

- `docs/superpowers/research/2026-08-10-bodyflow-competitive-motion-gamification.md`.

It is authoritative for the approved BodyFlow experience principles, motion
hierarchy, mascot boundaries, accessibility gates, and renderer-selection
process. Competitor products are references for interaction principles only.
Their trade dress, characters, choreography, sounds, copy, reward systems, and
proprietary feature models must not be reproduced.

## Verified Current State

### Correctly Constructed Foundation

The technical stack follows the workpack sequence through Prompt 14. Draft
PRs #4 through #16 form an ordered stack covering security, mobile BFF,
deterministic daily state, media, push/routine foundations, personalities,
CMS, routine domains, entitlements, native scaffold, auth/onboarding, Today,
records, progress, Library, mascot, and gamification presentation.

The Prompt 14 branch is test-heavy, Swift 6-compatible, strict-concurrency
compatible, accessibility-tested, and Release-fail-closed. That is a sound
foundation for visual work.

### Confirmed Visual And Product Gaps

- `AppIcon.appiconset` contains metadata but no image filenames.
- There is no committed BodyFlow logo, symbol, wordmark, splash artwork,
  production mascot artwork, or bundled custom font.
- `MascotPlaceholderArtwork` is explicitly Debug-only.
- The existing design system contains the five approved base colors, basic
  spacing, and system-font aliases, but not the final V3 semantic system or
  component catalog.
- The Xcode project declares only `pt-BR`; no `.xcstrings`, `.strings`,
  `.stringsdict`, `en.lproj`, or `en-US.lproj` resource exists.
- No Android app/module exists.
- The native feature tree has no first-party agent-chat/conversation surface.
- Release uses unavailable capabilities rather than a live authenticated HTTP
  transport. The iOS target has no `URLSession`, Supabase client, StoreKit,
  RevenueCat, or `UserNotifications` integration.
- All stacked app PRs remain draft and unmerged; the stack is preserved but is
  not integrated into `main`.
- Technical Prompt 15 has not been executed.
- Visual prompts 16, 17, 18, 19, 21, and 22 have not been executed as the
  final identity phase.

These items are pending work, not evidence that the completed Prompt 02-14
increments were implemented incorrectly.

## Workpack Corrections

### WhatsApp

Prompt 17's “Vincular conta ao WhatsApp existente” requirement is obsolete and
must be removed. The replacement flow is ordinary app-native sign-up, email
confirmation, sign-in, recovery, onboarding, and patient-scoped session
establishment. No WhatsApp migration or linking UI is part of the new app.

### Prompt Number 20

The V3 package contains prompts 16, 17, 18, 19, 21, and 22, but no Prompt 20.
This design treats 20 as a reserved number. No missing implementation phase or
requirements may be invented from the numbering gap.

### Assets Rule Override

The original V3 workpack prohibited reconstructing a final logo when official
files were absent. The user subsequently confirmed ownership of the approved
board, confirmed that the JPEG is the only source, and authorized this agent
to perform the reconstruction.

The override is narrow:

- reconstruction produces committed static assets;
- SwiftUI/runtime code must not draw or approximate the logo;
- generated variations may not silently replace the approved silhouette;
- the first production asset checkpoint requires human visual approval;
- rejected variants stay outside the production asset catalog.

## Brand Reconstruction

### Chosen Method

Use a hybrid production workflow:

1. isolate and measure the approved symbol and wordmark from the JPEG;
2. reconstruct the BodyFlow symbol as editable vector paths;
3. reconstruct the wordmark as outlined vector geometry so it does not depend
   on an unavailable typeface;
4. derive monochrome, negative, horizontal, symbol-only, light, dark, and
   reduced-size variants from one master geometry;
5. render deterministic raster exports from the approved vector masters;
6. use generated imagery only for the athlete, mascot, coach illustrations,
   educational covers, and other bitmap artwork;
7. compare every candidate with the approved board using aligned overlays,
   silhouette bounds, aspect ratio, dominant colors, and reduced-size review.

Pure text-to-image recreation is rejected for the logo because it cannot hold
geometry consistently across icon, splash, navigation, and store exports.
Runtime SwiftUI drawing is rejected because the brand mark must be an asset,
not application logic.

### Fidelity Contract

The reconstruction must preserve:

- the flowing abstract `B` silhouette;
- the forward/progress arrow language;
- the teal-to-light highlight and coral lower stroke;
- the soft-gold progress accent;
- the italic/forward BodyFlow wordmark stance;
- the premium teal/charcoal icon treatment;
- legibility at small app-icon and tab-scale sizes.

The JPEG is a compressed, flattened board. Without its original vector source,
mathematical identity cannot be proven. Acceptance therefore means faithful
visual equivalence at production display sizes, approved by the user, rather
than claiming source-file identity that cannot be evidenced.

### Required Asset Family

The implementation plan must produce or explicitly reject each of these:

- editable master symbol;
- editable master wordmark outlines;
- horizontal logo;
- symbol-only logo;
- monochrome logo;
- negative logo;
- iOS vector/PDF exports where supported;
- transparent PNG exports at 1x, 2x, and 3x where raster assets are required;
- `1024x1024` App Icon with no transparency;
- App Icon default, dark, and tinted appearances;
- launch/splash composition;
- production mascot base;
- Focus, Impulse, and Zen mascot/coach visual variants;
- one static key pose for every supported mascot personality and lifecycle
  state;
- versioned mascot animation-state manifest with semantic state, event,
  playback behavior, fallback asset, revision, and checksum;
- production animation artboards only after the renderer spike is approved;
- image-source manifest with source, version, dimensions, color space, and
  checksum.

No final asset may retain generated text, a fake nutrition value, a fake
medical claim, a third-party logo, or an embedded credential/identifier.

## Visual System

### Base Palette

- Teal Green: `#006D67`;
- Warm Cream: `#F6EFE3`;
- Charcoal: `#222528`;
- Muted Coral: `#FF7F6B`;
- Soft Gold: `#D4AF7A`.

These base colors remain centralized. Views consume semantic roles rather than
hex literals: app background, elevated surface, primary/secondary text,
primary action, energy action, success/progress, achievement, warning,
separator, disabled, chart series, and focus ring.

### Light And Dark Direction

- Warm Cream leads onboarding, education, forms, profile, and content surfaces.
- Charcoal leads premium dashboards, score, progress, and focused data views.
- Teal is the stable brand/action color.
- Coral conveys energy and action without becoming an error color by default.
- Soft Gold is reserved for progress, premium status, medals, and achievements.
- Dark Mode is a real semantic variant, not a simple inversion.

### Typography

No custom font file is currently licensed and committed. Native UI therefore
uses the Apple system type family with Dynamic Type in this phase. The
wordmark uses outlined vector geometry. Space Grotesk and Inter may replace
system roles only in a separately reviewed asset/license change with committed
font files; they must not be downloaded silently.

### Component Boundary

The final design system must centralize tokens and reusable implementations for:

- app shell, tab bar, and navigation header;
- primary, secondary, ghost, destructive, loading, and disabled buttons;
- cards, metric cards, chart containers, progress cards, and routine rows;
- form fields, validation, media capture, upload, and confirmation states;
- persona, mascot, content, paywall, empty, error, offline, loading, and
  permission-denied presentations;
- badges, pills, banners, sheets, skeletons, and accessible charts.

Cards may not be nested as generic page structure. Controls keep stable
dimensions, minimum `44x44` point hit areas, Dynamic Type, VoiceOver labels,
adequate contrast, and alternatives that do not depend only on color.

## Localization Contract

### Locales

- source/product locale: `pt-BR`;
- required additional locale: `en-US`;
- locale selection follows the operating system; no custom language switcher
  is required for the first implementation unless product later requests it.

### Architecture

- Add one String Catalog as the source of first-party app copy.
- Use stable semantic keys rather than visible Portuguese sentences as keys.
- Localize UI copy, accessibility labels/hints, validation, empty/error/offline
  states, permissions, onboarding, profile, paywall, and notification settings.
- Format dates, numbers, units, kcal, mass, volume, and time with locale-aware
  APIs while preserving numeric values returned by the backend.
- Backend/CMS content keeps its server-provided locale and eligibility rules;
  the app may not machine-translate or silently substitute published content.
- Tests must run representative journeys under both `pt-BR` and `en-US`.
- New user-facing string literals outside approved fixture/test scopes fail the
  localization audit.

## UX And Motion Boundary

The board supplies visual direction, not permission to replace current
contracts. Existing working flows remain authoritative. Visual work may improve
composition, hierarchy, spacing, labels, feedback, and discoverability, but may
not invent a backend operation or recalculate official values.

### Experience Position

BodyFlow combines **calm precision with earned warmth**:

- official data and primary actions remain sober, stable, and deterministic;
- the coach remains clear, useful, and actionable;
- the mascot creates emotional continuity without judging the user;
- celebration is proportional to confirmed progress;
- rest, interruption, and resumption are legitimate states rather than
  failures.

The app must not become a calorie game, a guilt-driven streak system, or an
always-animated dashboard.

### Motion Principles

Every animation must preserve context, confirm an action, explain a state
change, direct attention, acknowledge a meaningful milestone, or express an
authorized mascot state. Motion that only delays navigation, decorates a wait,
repeats in the periphery, or implies a calculation that did not happen is
rejected.

BodyFlow uses four motion tiers:

1. immediate control feedback;
2. bounded component transitions;
3. native navigation transitions;
4. rare milestone celebration.

The same large celebration may not run after every meal, glass of water,
routine item, or message. Official values may transition in place, but the app
may not count through fabricated intermediate values or display fake typing
duration.

Motion uses native SwiftUI for navigation, controls, values, progress, sheets,
and ordinary feedback. It remains interruptible, never blocks the next action,
and preserves scroll position and accessibility focus when content changes.

Short system haptics may reinforce selection, success, warning, and failure,
but never carry information alone. Utility flows are silent by default. Future
celebration audio requires separate approval and a mute path.

### Mascot Contract

The BodyFlow mascot is a companion and progress witness. It is not a medical
authority, calorie judge, punishment system, food police, or replacement for
the coach. It reacts only to approved server-owned state and confirmed events.

Focus, Impulse, and Zen alter posture, pacing, amplitude, and expression while
preserving the same character identity and product semantics. Personality may
not alter calculations, control placement, recommendations, or task
difficulty.

Supported lifecycle behavior is fail-closed:

- `inactive`: restful, with no sadness or deterioration;
- `reactivating`: attentive return and gentle acknowledgement;
- `active`: alert idle and small confirmed-action response;
- `neglected`: quiet pause without hunger, illness, tears, guilt, or alarm;
- `evolving`: rare server-authorized milestone sequence;
- `unknown`: static neutral fallback with ordinary text explanation.

The production vocabulary is `idle_primary`, `idle_alternate`, `acknowledge`,
`success_small`, `milestone`, `reactivating`, `rest`, and `evolving`, plus a
static key pose for every supported state and personality. Idle animation pauses
offscreen, in the background, under resource pressure, and whenever Reduce
Motion applies.

The product must never animate pet suffering, streak loss as personal failure,
fabricated scarcity, or rewards for under-eating, overtraining, or ignoring
recovery.

### Renderer Boundary

Views consume an engine-neutral mascot contract containing semantic state,
personality, event, intensity, playback mode, static fallback, accessibility
label, and server authorization/revision. They do not select animation files
directly. The same manifest is intended to support a future Android renderer
without making this an Android implementation.

Rive is the leading candidate for an interactive production renderer, not an
approved dependency. Before it enters the app, a pinned spike must validate
deterministic state transitions, Swift 6 strict concurrency, lifecycle and
cancellation, Reduce Motion, static fallbacks, VoiceOver isolation, binary
size, startup, memory, CPU, frame delivery, energy, Release fail-closed
behavior, Apple/Android asset compatibility, licensing, update policy, and
vulnerability handling.

If the spike fails, the same contract renders bundled static/vector key poses
with native SwiftUI transitions. Lottie is not the default because the mascot
requires interactive state transitions rather than only linear playback.

### Accessibility, Localization, And Energy

- Reduce Motion replaces movement across axes, scaling, parallax, blur, and
  repeating mascot loops with static poses or short fades.
- VoiceOver never announces idle frames, and animation never creates or removes
  the only accessible control.
- Important feedback always has persistent visual/text state; haptics remain
  optional reinforcement.
- No visible `pt-BR` or `en-US` text may be baked into animation artwork.
- Both locales are exercised before motion evidence is accepted; geometry may
  not assume a fixed label width.
- Mascot core states render without network access and fall back to a valid
  static pose on renderer or memory failure.
- No independent repeating timer is created per card.
- Simulator smoothness is insufficient: renderer approval requires measured
  on-device asset-size, memory, startup, CPU, energy, and frame-delivery
  evidence.

## Delivery Decomposition

The visual program is too broad for one safe implementation plan. It will be
executed as independently reviewable increments:

1. **Brand masters and asset catalog:** reconstruction, exports, App Icon,
   splash, manifest, and visual approval.
2. **Design-system foundation:** semantic colors, typography, spacing, shape,
   elevation, controls, component previews, and asset APIs.
3. **Localization foundation:** String Catalog, `pt-BR`, `en-US`, formatting,
   migration guard, and bilingual smoke tests.
4. **Authentication and onboarding application:** splash, login, recovery,
   onboarding, persona selection, and consent surfaces.
5. **Authenticated-product application:** Today, Register, Routine, Progress,
   Library, Mascot, and Profile using current contracts.
6. **Motion and illustration:** centralized motion/haptic tokens, native
   microinteractions, engine-neutral mascot contract, pinned renderer spike,
   approved mascot states and coach/educational artwork, static fallbacks,
   non-manipulation checks, and `Reduce Motion` evidence.
7. **Design QA:** Light/Dark, both locales, supported device sizes, Dynamic
   Type, VoiceOver, Increase Contrast, Differentiate Without Color, and visual
   comparison against the board.

Each increment receives its own RED/GREEN tests, visual evidence, review, and
commit. It must not absorb the live-transport or release work described below.

## Mandatory Real-Beta Gates

Visual completion does not make the app ready for patients. Before a client can
install a real connected beta, all of these must be completed and evidenced:

1. sequential review and integration of the draft PR stack;
2. authenticated iOS HTTPS transport to the approved staging BFF;
3. Supabase Auth/session bridge, refresh, rotation, sign-out cancellation, and
   Keychain boundary;
4. first-party in-app agent/chat and message/media flow connected to the
   approved patient session and BFF;
5. secure photo/audio upload and private-media retrieval in the native app;
6. real APNs permission, token registration, sandbox delivery, and safe copy;
7. StoreKit/entitlement purchase and restore behavior, or an explicitly
   approved beta entitlement bypass that cannot ship to production;
8. full `pt-BR`/`en-US` localization QA;
9. technical Prompt 15: CI, observability, correlated redacted logs, alerting,
   signing, archive, and TestFlight checklist;
10. staging end-to-end canaries for auth, read/write data, idempotency, media,
    content, agent response, entitlement, and session teardown;
11. explicit human approval for merge, Apple signing, App Store Connect, and
    TestFlight upload.

Production remains untouched until a later explicit authorization.

## Android Boundary

Android is not forgotten, but it is not implemented. A future Android phase
must reuse the versioned BFF contracts, deterministic server values, brand
masters, localization keys where semantically compatible, and asset manifest.
It requires its own Kotlin/Compose architecture, secure storage, media,
notifications, billing, accessibility, Play Console, signing, testing, and
release plan. No Android claim may be made from iOS completion.

## Verification And Acceptance

### Brand Checkpoint

Before the first asset commit is treated as final, present the reconstructed
symbol, wordmark, horizontal logo, App Icon variants, and reduced-size previews
side by side with the approved JPEG. The user approves or rejects the asset set.

### Engineering Checks

- asset catalog validates without missing filenames or duplicate names;
- raster exports have required dimensions, color profile, alpha policy, and
  deterministic checksums;
- SwiftUI uses assets rather than runtime logo geometry;
- user-facing copy passes the localization audit;
- existing contracts, feature behavior, tests, and Release fail-closed rules
  remain intact;
- motion uses centralized semantic events and never reads animation filenames
  directly from feature views;
- mascot idle work stops offscreen and in the background, and every animated
  state has a bundled static fallback;
- renderer choice passes measured on-device performance, energy, accessibility,
  dependency, and Release gates before production adoption;
- Debug and Release build on the Mac/Xcode environment;
- focused unit, presentation, snapshot/UI, and accessibility tests pass;
- no secret, PII, production URL, WhatsApp dependency, or unapproved transport
  enters the visual commits;
- `git diff --check` passes and the worktree is clean after each checkpoint.

### Visual Acceptance

- recognizable visual fidelity to the approved board;
- BodyFlow is the only product identity;
- no Balu, MPP, CoreFlow, blue-dominant, purple-neon, or generic gym theme;
- no clipping, overlap, nested actionable controls, inaccessible hit areas, or
  unreadable text in either locale;
- motion is proportional to the event, preserves context and focus, and does
  not compete with official data or primary actions;
- the mascot never expresses suffering, guilt, fabricated urgency, or a health
  judgment;
- representative motion and static-fallback evidence exists in Light/Dark,
  `pt-BR`/`en-US`, Reduce Motion, and supported accessibility configurations;
- no fabricated values in screenshots or previews presented as real data;
- no final-status claim while any mandatory real-beta gate is open.

## Explicit Non-Goals Of This Specification

- implementing Android;
- merging the stacked PRs;
- wiring production or staging credentials;
- applying migrations;
- deploying Vercel, Supabase, Inngest, APNs, StoreKit, or App Store Connect;
- uploading TestFlight;
- implementing Prompt 15;
- inventing missions, ranking, cooperation, smart shopping, smart workouts,
  body-evaluation logic, or other missing backend contracts;
- claiming pixel/source identity with a vector file that was never supplied.

## Next Gate

After this specification is approved, create a TDD implementation plan only
for increment 1, **Brand masters and asset catalog**. Later increments require
their own plans and approvals. Asset generation and SwiftUI implementation do
not start before that plan is reviewed.
