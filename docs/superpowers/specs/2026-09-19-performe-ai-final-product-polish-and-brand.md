# Performe AI — final product polish and brand specification

Date: 2026-09-19. Operation:
`PREPARE_PERFORME_AI_FINAL_BRAND_AND_PRODUCT_POLISH_V1`.

## 1. Purpose, authority and stop condition

This document closes the verified local UI/UX refinement workstream and defines
the final product-polish and brand-approval phase for **Performe AI**, whose
public assistant is **Flow**. It is a documentary specification, not permission
to integrate artwork, change product behavior or open a new feature scope.

The visual direction is already approved: **B2 — Warm Performance**. This
operation ends when the specification, approval package and documentary evidence
are committed locally. It must stop before importing any final logo/AppIcon byte,
running connected staging QA, producing a TestFlight build or touching a remote
provider.

Baseline revalidated before writing:

- Repository: `/Users/eduardohenrique/Developer/performe-ai-client-beta-flow-v1`.
- Branch: `codex/performe-ai-client-beta-flow-v1`.
- HEAD: `0e6f530f6bff5c2be5388523d020390a44d17e8d`.
- Tree: `5766028c85875e698aea545397b017838b732a6d`.
- Host: `MacBook-Air-de-Eduardo.local`, Darwin arm64, local development.
- Worktree clean, index empty and no scoped build/source writer observed.

The applicable sources are the approved
[premium UI/UX design](2026-09-17-performe-ai-premium-uiux-refinement-design.md),
its [implementation plan](../plans/2026-09-17-performe-ai-premium-uiux-refinement.md),
the [current visual audit](../evidence/2026-09-17-performe-ai-premium-uiux-audit.md)
and the [Slice 10 evidence](../evidence/2026-09-17-performe-ai-premium-uiux-implementation/README.md).

## 2. Current verified state

| Area | Current status | Meaning |
| --- | --- | --- |
| Slices 0, 2–10 | **VERIFIED LOCAL** | Design system, Auth/onboarding, five core tabs, Flow, convergence and final local QA passed |
| Slice 1 | **PARTIAL** | Optional brand-consumption infrastructure exists; final brand bytes are absent and unapproved |
| Regression | **VERIFIED** | Final local result: 1,206 unit tests / 1,421 executions and 151 UI tests passed |
| Signed Release | **VERIFIED LOCAL** | Simulator Release signed normally; strict codesign and native analyze passed |
| Production | **NOT DEPLOYED** | This branch/commit is not a Production release |
| Remote integration | **NOT REVALIDATED** | Current local pass is not a fresh staging-auth/Today/Flow assertion |
| VoiceOver manual | **NOT FULLY VERIFIED** | Native semantics and automated audits passed; interactive focus/rotor narration remains outstanding |
| Brand asset gate | **PENDING_EXTERNAL_ASSETS** | Direction is approved; no final file, hash, callsite or AppIcon is approved |

The internal target/module/bundle names remain technical `BodyFlow` /
`com.bodyflow.app`. Public identity remains Performe AI / Flow. Historical
BodyFlow asset bytes remain preservation evidence, not public artwork to reuse.

## 3. Visual target — B2 Warm Performance

The final product should feel premium, calm and capable: wellness plus
performance, warm cream/neutral foundations, deep teal structure, luminous aqua
for selective energy and subtle coral only for bounded feedback. Information is
clear, cards are controlled and whitespace is intentional.

The following are explicit anti-targets:

- aggressive gym/fitness aesthetics;
- hospital or clinical-product presentation;
- childlike gamification;
- fake scores, fake charts, synthetic trends or predictive claims;
- decorative density that competes with official data;
- a reused or redrawn historical BodyFlow “B”.

The final mark must be a distinct abstract **P / trajectory / movement** symbol,
communicating performance plus intelligence. It must survive 16–32 pt, remain
strong as an AppIcon and avoid generic dumbbells, arrows, chat faces or medical
symbols. No procedural SVG or placeholder is acceptable.

## 4. Capability-truth policy

Product polish changes presentation, not capability. It may refine composition,
spacing, semantic color, typography, card grouping, CTA hierarchy, approved
brand placement and screenshot selection. It may not introduce:

- historical datasets, charts, 7D/4W/3M ranges or predictions;
- camera, microphone, media upload, push, billing or subscriptions;
- account deletion, avatar upload, invented preferences or inert support rows;
- new backend data, APIs, calculations, goals, exercises or meal plans;
- fake streaming, fake typing or a clinical profession for Flow.

Photo and Audio remain clearly labeled **local sample** while not connected.
Server-owned values, legal documents and plan content remain authoritative;
polish must not rewrite them to make a screenshot look more attractive.

## 5. Final eight-screen showcase

The showcase uses a fixed two-row narrative:

| Top row | Bottom row |
| --- | --- |
| 01 Splash / Launch | 05 Register |
| 02 Welcome / Onboarding | 06 Plan |
| 03 Today / Dashboard | 07 Progress |
| 04 Flow | 08 Profile / Library |

Journey: **enters → understands → sees the day → talks → records → follows the
plan → tracks progress → manages the experience**.

Current evidence is retained under
`/Users/eduardohenrique/.local/share/performe-ai/premium-uiux/slice10.bqfdGN`.
UUID filenames below are mapped to human-readable test attachments by
`s10-visual-attachments/manifest.json`. They are current QA evidence, not the
final marketing/showcase exports.

### 01 — Splash / Launch

- **Current evidence:** signed Release and strict codesign passed. There is no
  stable direct Splash screenshot in Slice 10 because launch must not be delayed;
  `release-smoke.png` records the first stable post-launch Auth surface.
- **Hierarchy:** final symbol → Performe AI wordmark → native truthful loading
  indicator only while real restore work is pending.
- **Strengths:** root state machine, signing and fail-closed behavior are already
  verified; no artificial delay exists.
- **Current inconsistencies:** the final symbol/wordmark and AppIcon do not
  exist. Text-only identity cannot establish the intended launch moment.
- **Spacing/type/density/CTA:** keep a sparse deep-teal canvas, optical centering
  and no CTA/copy paragraph. Avoid screen-sized raster artwork.
- **Light/dark:** use approved negative/light assets on deep teal; do not infer a
  variant from an unapproved file.
- **Brand dependency:** mandatory final symbol and wordmark; AppIcon is a
  separately approved deliverable.
- **Classification:** `BLOCKED_BY_BRAND_ASSET`.

### 02 — Welcome / Onboarding

- **Current evidence:** `B68C671F-2094-4183-9125-279EB933D8EA.png`
  (English onboarding, Accessibility XXXL) plus full pt-BR/en, light/dark and
  Dynamic Type automated coverage.
- **Hierarchy:** Performe AI → step/progress → concise Welcome/proposition →
  existing seven-step inputs/actions. Flow is introduced as the assistant, not
  as a clinician.
- **Strengths:** truthful seven-step server-owned flow, localized copy,
  scrollability and large-type resilience are verified.
- **Current inconsistencies:** the top identity is text-only; the showcase lacks
  a regular-size final-brand capture. At extreme type sizes the brand, step and
  title correctly expand but dominate the first viewport.
- **Spacing/type/density/CTA:** preserve scroll at accessibility sizes; for the
  showcase, rebalance regular-size brand/proposition/CTA so the first action is
  visible without compressing content or using fixed heights.
- **Light/dark:** recheck symbol/wordmark contrast and field surfaces after
  approved assets enter.
- **Brand dependency:** final symbol/wordmark required for the final capture.
- **Classification:** `POLISH_BEFORE_ROBERTO` and
  `BLOCKED_BY_BRAND_ASSET`.

### 03 — Today / Dashboard

- **Current evidence:** `E2FBB387-4381-444C-8366-04E01370501B.png`
  (loaded pt-BR) and
  `E133B934-CB1F-4550-8F91-3954C6CEF2AF.png`
  (pt-BR Accessibility XXXL), with state/theme/locale coverage.
- **Hierarchy:** day context → official energy → protein/hydration → pending
  information → next steps/routine/recommendations → independent Flow/Library.
- **Strengths:** official meanings are separated; no invented score or steps;
  Flow and Library remain reachable independently of Today state.
- **Current inconsistencies:** two large utility entries, a floating refresh and
  several metric sections compete near the top. Long loaded content becomes
  visually dense before secondary guidance.
- **Spacing/type/density/CTA:** make the day context and official energy the
  primary composition; keep Flow as the primary adjacent action and Library
  secondary. Reduce repeated equal-weight card framing without removing official
  rows or state provenance.
- **Light/dark:** keep opaque surfaces and semantic contrast; retest refreshed,
  stale, missing and loaded states after composition changes.
- **Brand dependency:** shell anchor can remain textual during polish, but the
  final showcase needs the approved compact brand treatment.
- **Classification:** `POLISH_BEFORE_ROBERTO`; final capture
  `BLOCKED_BY_BRAND_ASSET`.

### 04 — Flow

- **Current evidence:** `AF679FCB-EA8C-4184-A64F-12778F88A37C.png`
  (local deterministic response), light/dark response matrices, keyboard,
  cancel/retry, historical reader and Accessibility XXXL captures.
- **Hierarchy:** navigation title → role line/safety guidance → user bubble →
  Flow response → waiting/processing/error feedback → composer/send.
- **Strengths:** plain-text rendering, persistence, reader position, cancel,
  retry, 4,000-character limit and native composer semantics are verified.
- **Current inconsistencies:** the deterministic capture contains QA markers and
  is not showcase copy. Short conversations leave a large neutral void; guidance
  carries similar weight to the conversation.
- **Spacing/type/density/CTA:** tighten the role/guidance block, keep a calm
  reading column, preserve distinct user/Flow roles and keep the composer
  visually anchored without covering the native tab bar.
- **Light/dark:** verify bubble pairs, disabled send, processing and error states
  after the final composition.
- **Brand dependency:** a compact approved symbol may support the Flow role, but
  must not become another agent name or replace accessible “Flow”.
- **Classification:** `MUST_FIX_BEFORE_ROBERTO` for connected, non-QA
  evaluation evidence; `POLISH_BEFORE_ROBERTO` for composition;
  `BLOCKED_BY_BRAND_ASSET` only for final branded capture.

### 05 — Register

- **Current evidence:** `D330B335-34CA-43F4-BD41-F1C7F8EB46FC.png`
  (capture choices) and proposal/confirmation/receipt matrices.
- **Hierarchy:** Photo / Audio / Text → explicit local-sample boundary →
  received proposal → official values/provenance → Confirm primary, Edit
  secondary, Cancel tertiary.
- **Strengths:** Photo/Audio truthfulness is explicit; proposal, edit,
  confirmation, idempotency and result ownership remain distinct.
- **Current inconsistencies:** the chooser repeats “demonstration/local” at
  several levels and the modal/backdrop compete with the root action. Dense
  proposals can make secondary actions visually equal to confirmation.
- **Spacing/type/density/CTA:** use one concise provenance notice, preserve native
  sheet affordances and establish Confirm as the only primary action. Never add
  real-camera or microphone styling while those capabilities are absent.
- **Light/dark:** verify sheet/backdrop separation, native controls and proposal
  warnings in both themes.
- **Brand dependency:** not required to polish the workflow; required only for
  the final shell/showcase capture.
- **Classification:** `POLISH_BEFORE_ROBERTO`; connected capability boundary
  must be confirmed during P7.

### 06 — Plan

- **Current evidence:** `1E12D97D-9C10-4AA0-84C3-D4DF61BB8DE2.png`
  (English light) plus four locale/theme captures and an Accessibility XXXL
  detail.
- **Hierarchy:** received training plan → received nutrition prescription →
  generated/validity/version metadata → existing detail/reload.
- **Strengths:** no invented exercises, goals or menus; nil/zero/date semantics
  and server-owned content are preserved.
- **Current inconsistencies:** dense label/value rows and long values reduce
  scanability; raw server values or a server language differing from the client
  locale can look unfinished but must not be silently translated.
- **Spacing/type/density/CTA:** strengthen section titles, group metadata as
  secondary information and preserve multiline values. Use a staging dataset
  suitable for evaluation; if it exposes raw technical copy, classify that as a
  data/readiness blocker rather than inventing client content.
- **Light/dark:** verify dividers, secondary labels and detail/reload states.
- **Brand dependency:** not required for owner polish; required for the final
  shell/showcase capture.
- **Classification:** `POLISH_BEFORE_ROBERTO`; unsuitable connected content is
  `MUST_FIX_BEFORE_ROBERTO` through data readiness, not a fake UI mapping.

### 07 — Progress

- **Current evidence:** `7B48273D-61BD-4A31-AC84-7ACE7E46F08C.png`
  (English light) plus locale/theme, missing-value and Bloco 7.700 captures.
- **Hierarchy:** current measurements → official consistency → XP/level/
  completed blocks/reported deficit → achievements → Bloco 7.700 when present.
- **Strengths:** current/official values are readable; missing is not zero; no
  fake history, chart, range selector or prediction exists.
- **Current inconsistencies:** equal white cards and repeated metric rows create
  a ledger feel. XP and achievements can compete with current measurements.
- **Spacing/type/density/CTA:** keep current measurements first, reduce equal
  emphasis across secondary metrics and make the existing Block route the only
  optional disclosure when available.
- **Light/dark:** retain semantic value contrast and color-independent medal/
  consistency meaning.
- **Brand dependency:** not required for owner polish; required for final shell
  and showcase capture.
- **Classification:** `POLISH_BEFORE_ROBERTO`. Charts/history remain
  `CAN_FOLLOW_AFTER_FIRST_FEEDBACK` only as a future product decision backed by
  a real dataset, not part of this plan.

### 08 — Profile / Library

- **Current evidence:** `1D73B96D-6BCE-448B-A9B4-A2ED8749F1F5.png`
  (Flow style at Accessibility XXXL) and
  `729B1B9F-E97E-40BA-B9A9-239D736B43BC.png`
  (published Library), plus content-detail and error-state captures.
- **Hierarchy:** identity → server-owned Flow style → Library/content →
  existing preferences/profile organization. Profile and Library remain
  existing destinations, not a new combined feature.
- **Strengths:** server persona choices, content authorization, saved state,
  Markdown, cover ownership and reload behavior are preserved.
- **Current inconsistencies:** extreme-size persona copy becomes visually
  dominant, while regular Library filters occupy a large first viewport. QA
  covers/titles such as synthetic content are evidence, not showcase material.
- **Spacing/type/density/CTA:** make identity and current Flow style concise,
  reduce filter chrome at regular sizes, keep published content editorial and
  preserve native scroll at large type.
- **Light/dark:** recheck persona selection, filters, cover placeholder and
  editorial detail after final brand integration.
- **Brand dependency:** final symbol/compact lockup is required for the profile
  identity and final showcase; content imagery must come only from authorized
  staging content or remain a neutral placeholder.
- **Classification:** `MUST_FIX_BEFORE_ROBERTO` for non-QA connected content;
  `POLISH_BEFORE_ROBERTO` for composition;
  `BLOCKED_BY_BRAND_ASSET` for final identity/capture.

## 6. Cross-screen decision ledger

### MUST_FIX_BEFORE_ROBERTO

1. Integrate only explicitly approved brand assets and separately approved
   AppIcon candidates; no historical B reuse.
2. Remove QA/debug fixture content from the evaluation journey and eight final
   captures. Local-sample disclosures remain wherever capability is still local.
3. Pass connected staging Auth/onboarding and verify connected Today and Flow
   with no Production dependency.
4. Use evaluation-ready received Plan/content data. Do not hide a raw-data issue
   with invented client copy.
5. Re-run local regression, signed Release and strict codesign after brand/polish
   integration.

### POLISH_BEFORE_ROBERTO

1. Complete the regular-size Splash/Welcome brand pass.
2. Rebalance Today action and metric hierarchy.
3. Refine Flow role/guidance spacing, message rhythm and composer composition.
4. Clarify Register modal/provenance/CTA hierarchy.
5. Reduce Plan and Progress ledger density without removing official values.
6. Condense Profile identity/persona and Library filter chrome.
7. Approve one representative light and dark capture for every showcase surface.

### CAN_FOLLOW_AFTER_FIRST_FEEDBACK

1. Fine-grained motion/elevation tuning that does not affect clarity or
   accessibility.
2. Additional editorial-cover art direction after content rights and staging
   content are established.
3. Copy nuance based on Roberto feedback, provided capability truth and
   server-owned values remain unchanged.
4. Any future history/chart concept only after a real dataset and separate
   product decision; it is not latent scope.

### BLOCKED_BY_BRAND_ASSET

1. Final Splash composition and all three AppIcon candidates.
2. Final Welcome identity and compact authenticated-shell brand anchor.
3. Final Profile identity treatment.
4. The authoritative eight-screen branded showcase and visual approval sheet.

## 7. Final brand deliverables and approval gate

Exact required files are maintained in
`assets/brand/performe-ai-public-v1/review.md` and mirrored as required paths in
`manifest.json`. They comprise:

- 11 SVG masters: four symbols, three wordmarks and four lockups;
- six vector PDF exports: four symbols and two wordmarks;
- three PNG splash review sheets: compact, standard and large;
- three 1024×1024 PNG AppIcon candidates, with tinted required only if genuinely
  supported and separately approved.

Approval requires all of the following:

1. named author/source, version, export settings, ownership and license evidence;
2. exact-file review beside the historical B and at 16/24/32/48 pt;
3. light/dark/mono/negative consistency, intrinsic bounds and clear space;
4. Home Screen/AppIcon review with no baked corner mask or text;
5. explicit user approval naming each accepted file and variant;
6. actual SHA-256 recorded only after approval, plus an exact public-callsite
   allowlist;
7. any changed byte invalidates that file's prior approval.

Until all applicable checks pass:

- `approvalStatus` remains `pending`;
- `approvedFiles` and `publicCallsites` remain empty;
- no asset catalog, AppIcon setting, splash or public callsite is changed.

## 8. Final polish acceptance criteria

The final product-polish pass is accepted only when:

- all eight surfaces preserve existing capabilities, data ownership and
  navigation;
- hierarchy and CTA priority match sections 5–6;
- regular and Accessibility XXXL layouts remain readable/scrollable with native
  targets at least 44×44 pt;
- pt-BR/en and light/dark representative states pass;
- no public BodyFlow/Dr. Roberto/Dr. Robert/MPP identity or Debug fixture leaks;
- no synthetic score, chart, streaming or unavailable capability is presented;
- approved asset bytes match their manifest hashes and historical bytes remain
  unchanged;
- final local unit/UI regression, Release, codesign, analyze and compiled/public
  scanner pass;
- the final showcase uses representative, rights-safe, non-QA content.

This acceptance is still not Production or TestFlight approval.

## 9. Roberto readiness

A Roberto evaluation build requires:

- [ ] approved brand assets integrated and manifest/callsites verified;
- [ ] all eight showcase compositions accepted in light and dark;
- [ ] local regression and compiled/public scanner green;
- [ ] connected staging Auth/onboarding green;
- [ ] connected Today and Flow green with one truthful end-to-end journey;
- [ ] normal Release signing and strict codesign valid;
- [ ] only synthetic/test-appropriate legal QA documents where needed;
- [ ] no Production dependency;
- [ ] deferred capabilities explicitly labeled in the UI/release notes;
- [ ] no QA fixture markers in the candidate build or showcase.

TestFlight, if later required, remains a separate authorization and distribution
gate.

## 10. Exact next execution sequence

The next workstream is intentionally limited to eight reviewable phases:

| Phase | Scope | Exit gate |
| --- | --- | --- |
| P1 | Validate and integrate explicitly approved brand assets; AppIcon separate | Manifest hashes/callsites exact; historical assets unchanged |
| P2 | Final Splash + Welcome brand pass | Compact/standard/large review and Auth/onboarding regression |
| P3 | Today + Flow composition polish | Owner tests, message states and current/AX visual review |
| P4 | Register + Plan polish | Capability-truth, proposal/data and owner regression |
| P5 | Progress + Profile/Library polish | No invented history/settings; owner regression |
| P6 | Full eight-screen visual review | pt-BR/en, light/dark, regular/AX, Critical 0 / Important 0 |
| P7 | Connected staging QA | Auth/onboarding/Today/Flow verified; no Production and no uncontrolled external send |
| P8 | Roberto evaluation-build preparation | Signed candidate, readiness checklist complete; TestFlight still separate |

No phase may absorb a new feature. A discovered capability/data gap returns to
its owner as a separate decision rather than being disguised as visual polish.

## 11. Resulting status

- UI/UX refinement: **CORE REFINEMENT VERIFIED LOCAL**.
- Final product polish: **PLANNED**.
- Logo design: **DIRECTION APPROVED / FINAL BYTES PENDING**.
- Brand asset gate: **PENDING_EXTERNAL_ASSETS**.
- Regression: **VERIFIED**.
- Production: **NOT DEPLOYED**.
- Remote integration: **NOT REVALIDATED**.
- VoiceOver manual: **NOT FULLY VERIFIED**.

## 12. Addendum — visual direction v2 (2026-10-03, approved by Eduardo)

After two physical acceptance rounds (02/10 `05f4f7c`, 03/10 `606d5d6`) Eduardo
rejected the contained "Warm Performance" result as "simple, monochromatic,
without effects" and approved, in full, the direction v2 proposal
(`docs/handoffs/2026-10-03-performe-ios-visual-direction-v2-proposal.md`,
blocks E + F + H + G). This addendum supersedes the following limits of this
spec and of the 2026-09-17 refinement spec; everything not listed stays.

| Superseded limit | Direction v2 |
|---|---|
| Motion ≤ 200 ms content / ≤ 250 ms disclosure; no decorative loop | Added kinds: `sweep` 600 ms spring (ring/meter filling to an official value), navigation 250–300 ms, celebrations ≤ 1.5 s. All finite and event-driven; Reduce Motion removes them. A placeholder or decoration that restarts by itself remains forbidden (it stalls XCTest and the device). |
| "Avoid continuous gradients" | One gradient surface per screen (`BodyFlowHeroCard`: `heroBackground` → `heroGradientEnd`); the splash may animate a mesh gradient for ≤ 3 s. Increase Contrast / Reduce Transparency flatten it. No gradient behind body text outside the hero. |
| Palette B2 (5 colors) | Additive domain colors: energy, protein, carbs, fat, hydration, exercise, block, progress (light/dark, ≥ 4.5:1 as text on the three surfaces). The five B2 colors are unchanged. |
| "No charts / ranges" in Progress | Swift Charts over **real** `daily_snapshots`/weight series with a fixed 14-day window. Scores, projections and estimates remain forbidden. |

Capability truth (§4) is unchanged: every ring, meter and chart draws an
official value the server sent; nothing is interpolated into a different
number, and a missing value is shown as missing.
