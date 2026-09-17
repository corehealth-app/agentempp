# Performe AI — premium UI/UX refinement design

Date: 2026-09-17. Operation: DESIGN_PERFORME_AI_PREMIUM_UIUX_REFINEMENT_V1.
Classification: architectural design only. Direction B — deep premium refinement — is approved.
Recommended interpretation: **B2 — Warm Performance**. This is not a new A/B/C decision.

## 1. Authority, baseline and execution boundary

Repository: `/Users/eduardohenrique/Developer/performe-ai-client-beta-flow-v1`.
Branch: `codex/performe-ai-client-beta-flow-v1`.
Required starting HEAD: `39f446a4c3cf8cfa58d21e030769c417e868e0a9`.
Its parent: `710be04bea8982e0ac23bd70736be0e28cab3efb`.
Its subject: `fix(flow): align mobile public persona and response presentation`.
Starting worktree clean; index empty. Read-only process inspection found no matching concurrent scope writer; this is an observation, not a lock against future edits.
Host: MacBook-Air-de-Eduardo.local / Darwin 25.6 / arm64 / eduardohenrique, classified LOCAL_DEVELOPMENT for this documentation work. The local checkout is not evidence of a deployed release.

Authority order: this approved operation; applicable global AGENTS policy; [beta addendum](../../handoffs/2026-09-14-performe-ai-client-beta-flow-v1-addendum.md); its bound dossier; current beta/onboarding/lifecycle/brand specs, plans and evidence; current code. The dossier is bound at `b4c09e80190fd6ce5c5f59b5193f8a6621554854:docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md`, not copied into this checkout. Its product, iOS, identity, integration and preservation sections were consulted; frozen CI-3 execution instructions are outside this operation. The addendum supersedes old public names and companion-only scope. This operation additionally permits designing a distinct new public asset family without rewriting historical bytes.

Primary current sources:

- [Beta spec](2026-09-14-performe-ai-client-beta-flow-v1.md), [beta plan](../plans/2026-09-14-performe-ai-client-beta-flow-v1.md) and [baseline evidence](../evidence/2026-09-14-performe-ai-client-beta-flow-v1-baseline.md).
- Native source under `apps/ios/BodyFlow/BodyFlow/{App,DesignSystem,Features,Core}`; audited views and visual risks are enumerated in [the current-state audit](../evidence/2026-09-17-performe-ai-premium-uiux-audit.md).
- [Auth/onboarding/Flow staging integration evidence](../evidence/2026-09-14-performe-ai-dedicated-mobile-bff-flow-integration.md), [server-owned onboarding plan](../plans/2026-09-15-performe-ai-server-owned-onboarding.md), [publication lifecycle evidence](../evidence/2026-09-15-performe-ai-onboarding-publication-lifecycle.md) and [public brand evidence](../evidence/2026-09-16-performe-ai-public-brand-patch.md). Historical runtime verification is not repeated here.
- [Current mobile Flow prompt-quality evidence](../evidence/2026-09-17-performe-ai-flow-public-response-quality.md): local prompt correction, not a deployed or newly model-validated response.

This operation writes this spec and its audit, followed by exactly one local documentation commit. No screen, code, asset bytes, dependency, project setting, business rule, schema, cloud resource or account is changed. No implementation slice starts. No push, PR, merge, deploy, production access, TestFlight, App Store, CI-3, OpenRouter or paid completion. No Supabase/Vercel operation is needed.

## 2. Goals, non-goals and preservation contract

Goals: establish one executable visual language; make navigation, reading and action priority coherent; distinguish real data, unavailable capability and local demonstration; integrate Flow without a sixth tab; specify a new identity family and bounded future slices; define visual, accessibility and localization acceptance gates before implementation.

Non-goals: connecting unavailable repositories; new camera/microphone capability; new score, historical chart feed, mission system, workout/recipe generator, notification settings, subscription/paywall or commercial decision; backend prompt/latency changes; streaming; legal activation; distribution; production promotion. Photography is optional, never an implementation dependency.

| Preserve exactly | Permitted future presentation change |
| --- | --- |
| Five tabs, their order, raw values and independent navigation stacks | Localized labels, native tab styling and spacing |
| Target/scheme/module `BodyFlow`, bundle `com.bodyflow.app`, namespaces, Coach/Mascot types | Public visible Performe AI / Flow copy and separately versioned assets |
| Auth, Keychain services, session ownership, refresh/logout/invalidation logic | Form hierarchy, fields' visual treatment, truthful feedback |
| Onboarding DTOs, step sequence, enum codes, server requirements, document/version/hash/action semantics | Grouping, readable labels, progress and consent presentation |
| Mobile API, Flow API, server calculations and persistence/idempotency | Formatting official values, layouts, message reading/composer |
| Persisted keys, telemetry and accessibility technical IDs, signing/entitlements | Labels/hints translated without changing identifiers |
| Historical asset bytes and evidence | New family and approved public callsite selection only |

Refinement never turns a demo into official data by changing copy. Existing Release unavailability remains fail-closed. Public identity is **Performe AI** (product), **Flow** (AI assistant); neither is translated. No professional credential or MPP agent-name claim is introduced.

## 3. References and the chosen B interpretation

The two July BodyFlow images and September Performe AI concept board supplied by the user are visual reference only. Borrow their warm canvas, breathing space, rounded composition, deep teal focus, restrained aqua/coral, meal-review hierarchy and readable numeric emphasis. Do not copy the legacy B symbol, woman/photo, English captions, navigation, fixed score, dragon, recipes, body-composition curves or invented daily metrics.

| Interpretation inside B | Strength / tradeoff | Decision |
| --- | --- | --- |
| B1 — Performance Editorial | Strong typographic hierarchy; can feel more austere and text-heavy | Not selected |
| B2 — Warm Performance | Calm cream reading, deep teal focal surfaces, clear actions, human copy; requires disciplined restraint to avoid cards everywhere | Recommended language throughout this spec |
| B3 — Precision Wellness | Very analytical, compact data presentation; risks density and clinical associations | Not selected |

Principles: meaningful data before decoration; one dominant action per task; groups rather than boxes within boxes; truthful status before optimism; calm confidence without guilt; a coherent light/dark pair, not inversion; native controls before custom chrome; accessibility and localization at every slice, not a last-minute patch.

## 4. Current-state findings and capability gates

The current DS has teal `#006D67`, cream `#F6EFE3`, charcoal `#222528`, coral `#FF7F6B`, gold `#D4AF7A`; six Dynamic Type system styles and spacing 4/8/12/16/24/32 pt, minimum tap target 44 pt. These are a useful foundation, not a reason to replace everything. `BodyFlowCard` applies a 20 pt radius and a faint accent outline to almost every block. System grouped lists, rounded-border fields, SwiftUI buttons and custom UIKit filled controls coexist. Brand strips plus navigation titles plus large content headers compete vertically. Gold replaces teal as the general dark accent; coral serves as error text despite inadequate light contrast. Much screen copy and number formatting remains hard-coded pt-BR despite the existing bilingual catalog infrastructure.

The view code already preserves stale values, authoritative numeric distinctions, explicit consent, separate read/mutation state, idempotent captured attempts, session-bound loads and accessibility IDs. Preserve these foundations. Repeated metadata/dividers, long raw status/protocol labels, equal-weight actions and demo destinations are the visual debt to address; not grounds for changing their contracts.

| Surface at current HEAD | Verified code capability | Design consequence |
| --- | --- | --- |
| Auth / server-owned onboarding / Flow | Real adapters exist when private Release configuration and session transport are valid | Preserve real path; no live revalidation in this design operation |
| Hoje, History, Plano, Progresso, meal detection/registration, hydration, weight, routine | Release injection uses `UnavailableBodyFlowCapabilities` | Design existing loaded DTO presentations in local demos; do not claim runtime integration |
| Library, covers, recommendations, Mascot/coach experience | Release factories remain unavailable; deterministic Debug scenarios exist | Refine bounded/offline/unavailable states; loaded UI is conditional on a future separately scoped integration |
| Registrar/Profile root | Fixture-based presentation defaults; persona repository initially demo-backed, server option gating prevents claiming selectable real options without validation | Preserve explicit demo provenance; no fake identity or notification status presented as authenticated truth |
| Progresso | Snapshot contains current measurements, XP/level/streak/badges/dates; no historical point series or selectable range contract | Current values and official achievements only; trends/range picker DEFER |
| Meal capture | Text plus photo/audio demonstration sources, not actual camera/microphone | Three choices in demo only; real media interaction DEFER |
| Logout / delete / help / privacy destinations | `signOut()` exists in model, but no authenticated logout control was found in current shell/profile; delete/help/legal destination wiring not established | Do not add live actions or promise deletion as part of visual refinement |

Unavailable is not empty, zero, failed consent or insufficient user effort. Flow remains reachable from Hoje even when the Today repository is unavailable; this must not regress.

## 5. Executable design system proposal

Names below are semantic roles for future additions/mapping within the existing DS, not authorization to rename `BodyFlow*`. Values are **proposed design tokens**, not product metrics. Cream, charcoal, primary teal, coral and gold retain current bytes as palette anchors. New roles remove ambiguous dark/error behavior.

### 5.1 Colors and pairings

| Semantic role | Light | Dark | Use / restriction |
| --- | --- | --- | --- |
| background | `#F6EFE3` | `#071E20` | Full-screen canvas |
| surface / card | `#FFFCF6` | `#102D30` | One grouped content surface, no automatic border |
| elevatedSurface / field | `#FFFFFF` | `#193C40` | Sheet, field, transient foreground layer |
| textPrimary | `#222528` | `#F6EFE3` | Main readable content |
| textSecondary | `#4D6260` | `#B3C7C2` | Supporting copy and units |
| textTertiary | `#596E6B` | `#97ACA8` | Metadata; not essential microtext |
| primary / link / selection | `#006D67` | `#55D5C7` | Interactive accent; links also have affordance beyond color |
| onPrimary | `#FFFFFF` | `#071E20` | Filled primary action / own chat bubble |
| secondaryAqua | `#55D5C7` | `#55D5C7` | Decorative highlight on deep teal; not light-background text |
| coralAccent | `#FF7F6B` | `#FF7F6B` | Small decorative accent; not error text or white-label CTA |
| positive | `#006D67` | `#7CDDCA` | Icon + explicit success label |
| warning | `#8A5A00` | `#F2C976` | Icon + warning label; not coral |
| destructive | `#B42332` | `#FF98A3` | Explicit destructive action/error; not all offline messages |
| separatorDecorative | `#D8DED7` | `#355155` | Group separation only, not essential state/control outline |
| controlBoundary | `#627A75` | `#8CA7A1` | Required field/checkbox boundary, 1 pt; focus adds shape/weight |
| disabledFill | `#F0F0E8` | `#193C40` | Noninteractive state, opaque rather than global alpha |
| disabledText | `#596E6B` | `#97ACA8` | Label + explicit reason where needed; no active affordance |
| heroBackground | `#003B3B` | `#003B3B` | Optional single Today focal group / splash |
| onHero / heroSupporting | `#F6EFE3` / `#B3C7C2` | Same | Pair-specific roles, not generic light textSecondary |
| achievement / onAchievement | `#D4AF7A` / `#222528` | Same | Existing official achievement only, never general dark accent |

Local sRGB luminance calculation compared each semantic foreground against all three corresponding theme surfaces. Minimum ratios, displayed rounded but thresholds checked unrounded: light primary text 13.48, secondary 5.69, tertiary 4.75, interactive 5.43, warning 5.19, destructive 5.69, boundary 4.03; dark primary text 10.43, secondary 6.74, tertiary 4.99, interactive 6.66, warning 7.60, destructive 5.83, boundary 4.63. Light white-on-primary 6.21; dark onPrimary-on-aqua 9.65; hero primary 10.88 / supporting 7.03. This validates these opaque pairs only, not implemented screens, overlays, gradients or all custom system-control states.

Disabled label/fill pairs also meet the proposed readable-text target: light 4.74:1, dark 4.99:1, despite inactive-control exemptions. Current coral-on-cream is 2.16:1: insufficient for normal error text. Required future gate: normal readable text >=4.5:1, large text >=3:1, essential custom non-text state/boundary >=3:1 against adjacent colors. Prefer >=4.5 for all app text to avoid ambiguity from resizing. Decorative separators have no essential semantic role; use controlBoundary when recognition depends on an outline. Increase Contrast removes optional translucency and strengthens separation; rerun pair checks on actual rendering. No light semantic foreground is reused on dark hero without its paired role.

### 5.2 Typography, spacing, radius and elevation

| Role | Native style / weight | Constraint |
| --- | --- | --- |
| Large title | `.largeTitle`, bold | One editorial title per root, never three competing titles |
| Screen title | `.title2`, semibold; native navigation title where appropriate | Back navigation remains native |
| Section heading | `.headline`, semibold | Header trait and natural wrap |
| Card title | `.headline`, semibold | No obligatory uppercase eyebrow |
| Body | `.body`, regular | Primary reading / long Flow responses |
| Supporting | `.callout`, regular | Explanation, never hidden safety meaning |
| Metric large | `.largeTitle`, semibold, monospaced digits | Unit separate/read together; vertical reflow at AX sizes |
| Metric small | `.title2`, semibold, monospaced digits | Compare only like dimensions |
| Button | `.headline`, semibold | Minimum height, not fixed height; wrap at AX sizes |
| Caption | `.caption`, regular | Nonessential provenance; accessible expandable detail for long metadata |

Keep system fonts and Dynamic Type. No fixed-point custom font, minimum-scale-factor rescue, shrinking core copy or image-embedded functional title. Wordmark is brand artwork; separately provide the semantic product name. Do not fit large numbers by truncating official precision without a documented formatting contract.

Spacing remains 4/8/12/16/24/32 pt. Baseline horizontal screen gutter 16 pt on compact phones, 24 pt when comfortably available; choose by usable width, not a hard-coded model. Card/field internal 16; label-to-value 4–8; sibling controls 12; groups 24; editorial break 32. Readable auth/form content max width 560 pt as current foundation, still responsive in landscape. Edge backgrounds alone extend under safe areas. Never add fixed top padding for Dynamic Island.

Radius family: 8 pt small selection/status, 12 pt fields/buttons, 20 pt grouped card/hero/sheet content; capsule only for compact meaningful status, not every action. Native sheets/navigation retain system geometry. Message bubbles use 20 pt; no tail shape. No nested elevated card within a card: use rows or a section divider. At most one hero surface per root.

Elevation: level 0 flat canvas/content; level 1 grouped surface separated by fill and spacing, no shadow; level 2 transient sheet/native material. Optional light hero shadow only: black 6% / y 2 / blur 12 pt; dark elevation uses fill difference, not bright glow. Shadow is never the only boundary. Avoid continuous gradients; a subtle aqua/teal brand treatment is limited to approved assets/splash decoration and never behind body text.

### 5.3 Components, iconography, material and motion

| Component contract | Future visual behavior | Preserve |
| --- | --- | --- |
| Primary action | One filled primary, >=44×44 pt hit region, full width for form task | Existing enable/submission semantics and action ID |
| Secondary / tertiary | Outlined or text action with clear label; no equally filled Confirm/Edit/Cancel | Existing separate actions, cancel available where supported |
| Field | Visible persistent label, units, native keyboard/autofill/secure entry; neutral elevated fill + essential boundary | Input parsing/validation, focus and privacy |
| Metric group | Main value + explicit meaning/unit; secondary rows below, AX vertical | Server values, null vs zero and energy/protein distinctions |
| Read state | Title + plain explanation + meaningful available recovery | `FeatureReadState` and previous-value behavior |
| Mutation summary | Status adjacent to task; announce once, success only from receipt | Captured attempt, retry key, expiry / conflict safeguards |
| Selection row | Text + radio/check + selected trait + boundary weight | Enum code and validation; never color alone |
| Content card | Title/excerpt/real authorized cover/metadata; AX separate open action | Publication/version capability, impression and mutation policies |
| Flow message | Plain text, role label, selectable content, long readable paragraphs | Persisted raw content, IDs and state; no new Markdown renderer |

Keep SF Symbols and current tab symbols: house, plus.circle, list.clipboard, chart.line.uptrend.xyaxis, person.crop.circle. Use camera/mic/text only for truthful supported capture state; action icons always have localized labels. Flow guidance uses a neutral information symbol rather than clinical `cross.case`, while keeping `flow.guidance`. New brand symbol is not a custom generic UI icon pack. Validate chosen symbol availability against the actual iOS 18 deployment target.

Native bar material is appropriate for navigation and keyboard-adjacent composer when scrolling content actually passes underneath; static forms/cards use opaque fill. No global glassmorphism, SDK upgrade or forced new OS appearance. Provide opaque equivalent with system transparency/accessibility settings. Native system chrome adapts to OS; do not recreate its tab bar.

Motion proposals: short crossfade <=200 ms on content-state replacement, <=250 ms on user-requested disclosure, no decorative loop or score-counting animation. Reduce Motion removes translation, scale, orbit, auto-scroll animation and animated progress interpolation; final semantic state remains identical. Determinate progress/rings only represent a supplied official percentage or existing onboarding step progress, never estimated LLM work. Default loading is indeterminate with a truthful label, not fake percentages or timed stages. No new artificial delay, polling or time-based commercial rule.

## 6. Screen designs and state contracts

All layouts below apply to both themes, both locales and compact-to-large iPhones. Preserve IDs by moving the existing semantic control, not cloning IDs onto several decorative views. See audit for exact paths and matrix for applicable states.

### 6.1 Splash and session restoration

Deep teal full-bleed background, new symbol centered optically (96 pt proposed baseline), product wordmark below (maximum 240 pt width or available guttered width, intrinsic aspect ratio), generous clear space. Optional single fade only; no looping ribbon and no minimum display time. Avoid a mandatory slogan. Semantic label “Performe AI”; decorative symbol hidden from VoiceOver when the product is already announced. Preserve existing launching/session-neutral root transitions and all restore errors. Progress indicator appears only while the real launch task is pending; no invented retry button on a root without retry behavior. Design native launch composition to match the initial app frame without changing launch mechanics in this task.

### 6.2 Auth

Vertical lockup → one title → brief explanation → fields → inline errors → dominant action → secondary account/recovery actions. Move brand/title out of the current cramped HStack at AX sizes. Keep email/password autofill, secure input, native keyboards and Next/Done order; show field errors next to the field plus one concise operation summary, avoiding duplicate VoiceOver announcements. Sign-in CTA “Entrar” / “Sign in”; sign-up “Criar conta” / “Create account”; recovery “Enviar instruções” / “Send instructions” only if consistent with current action copy, no new resend command.

Keyboard-visible forms scroll to focused field and task action; no fixed bottom button covering fields. Loading replaces CTA label with truthful task label, retains accessible action name and disables duplicate submit. Offline/transport failure preserves typed input and current error mapping; no automatic account switch/relogin loop. Recovery confirmation remains non-enumerating. Email confirmation shows only current supported return/confirmation controls; development confirmation stays Debug-only. No invented social login or production document acceptance at sign-up.

### 6.3 Server-owned onboarding

Keep seven steps exactly: welcome → body data → objective → routine → persona → consent → completion. Header shows product once, localized step count/title and compact progress. Count is derived from existing sequence, not a new completion prediction. Existing restore selects authoritative step/draft; short “Continue de onde parou” / “Continue where you left off” is shown only when a restored draft is known, never inferred from elapsed time.

| Step | Proposed hierarchy | Functional guard |
| --- | --- | --- |
| Welcome | “Vamos começar” / “Let’s get started”; introduce “Flow, seu assistente de IA no Performe AI” / “Flow, your AI assistant in Performe AI”; name/country/timezone grouped | Existing values/locale ownership; searchable native country/timezone sheets; no locale migration |
| Body data | Personal data, body measurements, optional measurements in distinct unboxed groups; units next to fields | Existing biological-sex/birth-date/height/weight/body-fat validation and nil semantics; no health calculation |
| Objective | Equal option rows with one selected indicator | Actual body recomposition/muscle gain/maintenance codes, not the board’s four invented focus categories |
| Routine | Activity, schedule and food organization grouped; time pickers disclose within step | Preserve optional/unconfirmed selections; no silent default or new habit backend |
| Persona | Public title “Estilo do Flow” / “Flow’s style”; server-returned names/descriptions, quiet geometric accent optional | Focus/Impulse/Zen technical codes and server options; no regulated-professional promise or fourth selectable persona |
| Consent | Each current server document, explicit required/optional status, purpose/action, readable body, version/provenance secondary | Never pre-check; preserve exact body/version/hash and acceptance vs acknowledgement vs consent; fail closed on missing requirements |
| Completion | Review the existing answers and accepted documents → one finish CTA | Navigate to Hoje only after authoritative completion; no new jump-to-edit/reset operation |

Document bodies are reading content, not images. Keep document action adjacent to its body and distinct from “Continuar”. Long bodies can scroll naturally without a fixed-height nested trap; no new “must scroll to accept” legal rule. Unknown document keys remain visible rather than assigned invented legal titles. Consent-publication lifecycle remains server-owned; design creates no legal QA set or real legal activation.

### 6.4 Shell and Hoje

Native five-tab shell; no centered Flow button, reordered tabs or custom floating tab overlay. Independent stacks and sheet ownership stay unchanged. Consolidate competing brand strip/navigation/content titles into a single semantic brand anchor on roots; pushed detail uses native title/back. `brand.product-name` remains discoverable once per screen where the current contract expects it. No clipping hack to force header height.

Hoje proposed reading order:

```text
Context: Hoje + localized date (name only if already authoritative)
Main day state: one headline; freshness/availability nearby
Priority metrics: food remaining + net balance, with distinct meanings
Protein / hydration: official values; official percentage when present
Next step: supported pending context, never an invented task
Registration shortcuts: existing route/action only
Flow: persistent, reachable entry independent of Today data
Routine / recommendations / records / block / history details
Native tabs: Hoje | Registrar | Plano | Progresso | Perfil
```

Food remaining excludes workout credit as current contract defines; net balance includes official workout energy. Never merge them into a new “daily score”. Consumed/target/excess/workout/protocol/provenance remain available through in-place disclosure of received fields, not a new endpoint. Do not manufacture a percentage when only numerator/denominator exists; absent official percentage means no ring. Optional compact hero uses hero-specific roles and contains the main day state/metrics, not an image of a number.

Existing pending items are informational unless an existing action route can handle them. “Próximo passo” is a section hierarchy, not a new recommendation engine. No claim “3/5 habits”, steps count, completion quote or workout image borrowed from reference. Registration shortcut destination can reuse existing routes; do not introduce a new lunch record type or automatic write. Flow remains a clear secondary entry when the dominant supported task is available; when Hoje is unavailable, Flow is the useful existing action, above the unavailable-state explanation. Preserve Library access from Hoje and recommendation independence. Mascot summary, when supported, moves below core task information; no deletion of official state/history and no production mascot artwork invented.

Loaded numbers are official DTO values only; demo views remain labeled synthetic/local. Empty/incomplete day is not failure. Stale values remain visible with a localized freshness banner and manual supported retry; missing timestamps are not filled with current device time.

### 6.5 Registrar and Add Meal interpretation

Root: one task title → meal capture entry → other existing actions (treino/peso/hidratação) as a compact grouped list → truthful capability/demo notice. Existing registry destinations/IDs remain, not a replacement nutrition tab. The meal subflow is the strongest application of the reference:

```text
Registrar refeição / Register meal
Capture choice: Foto | Áudio | Texto (truthful capability state)
Draft / supported local sample → analyze task status
Detected proposal: food names, quantities, provenance/warnings
Nutrition summary: official energy / protein / carbs / fat
Primary Confirm | secondary Edit | tertiary Cancel
Receipt or bounded error / expiry / already-confirmed outcome
```

In demo, preserve “amostra local” and do not request media permission. Release media is not supported: do not expose an apparently working camera/mic button. Capability unavailable message is distinct from permission-denied; there is currently no permission-denied capture state to implement. Actual camera/mic/photo uploads require a separate feature decision and integration task, not this future visual slice.

Proposal uses actual server item names and optional totals; no stock chicken photo masquerades as detected meal. No food-image field was established in current proposal DTO: use a neutral decorative food symbol or omit artwork. Four numeric cells wrap vertically at AX sizes. Do not draw macro goal rings from totals alone: use value cells; rings only if an authoritative progress/goal contract later exists. No local nutrient sum, portion recalculation or official result derived from user-edit fields.

Current editor edits the first proposal item; visually clarify which item without silently enabling multi-item editing. Native fields preserve validation/date/type semantics. Confirm is the only dominant write action, preceded by review. Disable duplicates while submission is active; success only on server receipt. Retry reuses captured attempt/key, not a new confirmation; expired/not-pending proposals use existing start-new-proposal recovery and never overwrite confirmed data. Cancellation semantics remain current, including close/discard ownership. Offline does not queue an invented automatic background write.

Workout proposal follows the same hierarchy: official estimate clearly labeled estimated; no route/prescription inventing. Weight/hydration retain existing unit entry, date, quick amounts and parsing; style UIKit controls consistently, with intrinsic height at Dynamic Type sizes rather than their current fixed 48 pt visual frames. No default sample becomes a confirmed workout or weight.

### 6.6 Plano

One title and state → received training summary (type/days/equipment/notes) → received nutrition prescription metadata → generated/valid-until/version secondary → existing detail destination. Use grouped rows rather than each field boxed. Preserve multiple prescription sections and server text verbatim; hide only absent optional fields. No meal schedule, exercise list, weekly completion count, goal card or “active” status derived from client time unless present in supported source. Existing validity is displayed as received; expiry/business activation is not inferred.

Empty means no supplied plan, unavailable means feature not connected, stale means previous data remains with current state banner. Current root and detail duplicate the same data: refine visual hierarchy without eliminating the documented detail reload behavior. Metadata disclosure is in-place and presentational only. Future slice may restyle existing DTO content in demo and unavailable state, not wire a new backend.

### 6.7 Progresso, charts and ranges

Current executable design: primary current measurements (weight/body fat when non-null) → official consistency/current and longest streak → existing XP/level/blocks/badges → official dates → Bloco 7.700 detail. Calm encouragement on streak zero retains current truthful meaning and existing Hoje action; no shame or invented streak reset. Earned badges remain official strings with duplicate/identity policy preserved; no new medal award or mascot leveling calculation.

**DEFER historical trends and time-range controls.** `ProgressSnapshot` has no time-series feed; a current measurement plus update timestamp is not a historical curve. No 7D/4W/3M picker or fabricated weight/body-fat delta. No synthetic graph presented as a current user’s chart. Missing weight/body fat has a clear “Não disponível” / “Not available”, not zero. Official fields can be grouped more meaningfully without recalculating XP/level/streak or building a new score.

Conditional design contract for a separately authorized future historical feed: one series per unit, explicitly labeled date range/timezone/source, valid points only, no interpolation across missing samples; weight and body-fat use separate scales/charts, never imply equality. Line/point shape and direct labels distinguish series, not teal/coral alone; meaningful lines >=3:1. Every chart has localized text summary and an equivalent date/value/unit list accessible to VoiceOver. Range controls exist only for supported queries. This contract is not an implementation slice dependency; current refinement uses numeric summaries instead.

Bloco 7.700 shows supplied target/current/optional percentage/completed blocks/credited total and provenance. Ring only when official percentage exists, semantic value and textual equivalent always visible. Preserve protocol enable/availability and null distinctions; no local block-credit formula.

### 6.8 Perfil, persona, Biblioteca, History and Routine

Profile grouping: identity → supported preference/persona → other genuinely supported account controls, visually separated from reading content. Current fixture name/notifications remain explicitly demonstration, never “Alex”, XP or push-enabled state inferred for an authenticated user. Persona editor uses server validated options; save/cancel/loading/error states remain model-owned, change public coach wording to Flow presentation only. Do not invent user-avatar upload or a `/me` contract.

Flow remains entered from Hoje; a profile informational role line is acceptable, but a new cross-stack chat link is not assumed implemented. Biblioteca remains its existing Hoje destination: Todos/Salvos + category → results summary → authorized cards → manual supported pagination. Do not create a sixth tab or an unimplemented Profile library route. Reading content and critical account actions must never share a promotional card.

Content detail: title/authorized cover/metadata → save/complete actions → status → article. Preserve canonical Markdown renderer, external HTTPS policy, explicit capability/version bounded states, session ownership, opened/impression tracking and idempotent mutations. No carousel requiring remote images, no arbitrary recipe/workout library categories or fabricated content. Cover is decorative and uses existing neutral placeholder/authorization. Retry/pagination errors remain local to relevant task; stale article not silently treated as a new version.

History: existing meal/workout lists and read-only details, clearer value/unit formatting, no swipe delete/edit if unsupported. Routine: supplement/medication lists, schedules, occurrence detail, existing taken/snooze/skipped confirmation and history; preserve patient timezone, occurrence ownership, allowed snooze presets and captured attempt. Refinement never prescribes a drug or changes dosage/timing.

Logout is a model capability without a current authenticated UI callsite; adding/relocating a logout action requires an explicitly scoped wiring decision. Account deletion, support links and persistent privacy/legal views are not established native destinations: **DEFER** rather than ship inert rows or fake confirmation. Document-consent reading remains available only in its existing onboarding journey. Critical confirmation template is specified in the matrix but cannot activate an absent operation.

### 6.9 Flow

Native inline title Flow + concise role “Assistente de IA do Performe AI” / “Performe AI’s AI assistant”; no giant second brand strip or doctor icon. Guidance remains readable but unobtrusive, preserves health limits and is not an AI professional credential. Empty: clear purpose, no automatic suggested-message send or call; composer is the primary action. Existing history displayed oldest-to-newest as returned; user and assistant role labels accessible, user bubble primary/onPrimary, assistant surface/textPrimary. Long text selectable and fully wraps; no truncation, custom Markdown stripping or client rebrand of historical message content.

History loading has contextual status. Sending and awaiting reply use a truthful combined label, for example “Enviando e aguardando o Flow…” / “Sending and waiting for Flow…”. The current `isSending` covers send **and subsequent history read**, so do not manufacture separately timed model phases. Existing persisted `.processing` state can display “Em processamento” / “Processing” when supplied by DTO. No streaming/typewriter animation, fake progress, estimated time remaining or guaranteed instant response. Historical baseline: 7,334 ms pipeline / 8.657 s input-to-output persistence delta; not tap-to-visible measurement and not an SLA. Backend optimization is excluded.

Existing cancel stays available and means stopping the local wait; it is not proof that a remote completion, persistence or cost was cancelled. Proposed accessible wording “Cancelar espera” / “Cancel waiting” must not claim database rollback. Retry stays manual and reuses the saved text/key through model logic; history read recovery must not silently resend. Offline/rate-limit/session/forbidden/generic mappings retained; copy never exposes backend secrets. Current APIs do not expose precise phase/timing metadata: do not create it here.

Composer follows keyboard safe area, 1–5 lines at normal size and intrinsic adaptive sizing at AX; large fonts can move send/cancel below input. Keep 4,000-character send guard; propose visible localized limit explanation when already out of allowed input rather than silently suggesting send succeeded. No change to request limit. Scroll to new last message only when the user is at conversation end or has just sent; do not steal reading position/VoiceOver focus. If presentation requires tracking scroll position, keep it local, not persisted or telemetered. Offer a local “Última mensagem” / “Latest message” navigation control only when scroll position makes it useful, never a new API operation. Reduce Motion uses nonanimated reposition. Announce new response/status once without rereading entire history. Preserve loaded content on recovery and no cross-user message leak during session changes.

## 7. New identity and asset strategy

LOGO DESIGN STATUS: **DIRECTION APPROVED / FINAL BYTES PENDING**.

Creative brief: an abstract **P / rising trajectory** representing deliberate personal progress assisted by intelligence. A single open upper loop and grounded rising stroke create a forward path; the negative space is the P’s recognition cue. Avoid the legacy two opposing B-like swooshes, crossing coral lower lobe, arrow tip, doctor/medical cross, dumbbell, chat bubble, face or robot. Aqua is energy, deep teal is calm confidence; coral is an optional small secondary signal, never necessary to recognize the mark.

Proposed geometric construction for designer exploration, not final asset coordinates: near-square symbol bounding box, clear primary stem/rising diagonal, one open upper counter, consistent rounded-terminal family, silhouette recognizable in one color. Start on a 100-unit conceptual grid; primary visual stroke mass roughly 12–16 units, counter/open gap at least 12 units before optical small-size adjustment; no hairline detail. Forward/upward movement is a visual metaphor, not an analytics arrow promising improvement. Test comparison beside old symbol: if it reads as the old B with a new label, reject it.

Wordmark: exact “Performe AI”, no arbitrary AI superscript or separation suggesting a different product. Premium humanist/system-compatible sans direction, medium/semibold, optically spaced; no mandatory font licensing dependency. The final typography and vector contours belong to visual approval, not automated font-to-path generation here. Product name remains accessible text even when artwork is present. Horizontal lockup: symbol left, wordmark right, shared optical baseline; gap >=one-quarter symbol width; never distort aspect ratio. Clear space around symbol/lockup >=one-quarter symbol width; never use the artwork’s internal padding to fake a button hit target.

Small-size behavior: judge silhouette at 16/24/32/48 pt, and AppIcon at normal Home Screen size. At 16–24 pt use optically simplified mono symbol, no coral sliver/gradient; if counter closes, redraw small-size variant rather than shrink blindly. Minimum proposed wordmark display width 140 pt, subject to actual contour approval; below it use public text plus symbol instead of illegible artwork. Dark/negative variants preserve geometry with approved foreground pairing, not automatic image inversion.

App icon candidate: new symbol only, no product text or Flow label, centered optically on deep teal/opaque canvas. Master 1024×1024 px square; system applies platform mask, do not bake rounded corners. Proposed artwork safe region central 70% of canvas, test optical balance rather than treat it as an Apple-mandated numeric inset. Supply default/dark/tinted candidates compatible with existing asset-catalog pipeline; no new Icon Composer/toolchain migration required. **Final AppIcon requires explicit visual user approval before any catalog selection or replacement.** Preserve the legacy three PNGs and their asset set bytes.

| Future deliverable | Master/export specification | Variants / intended use |
| --- | --- | --- |
| New symbol | Vector near-square master; export preview 1024×1024; optical small-size version | Light/dark full color; mono teal and negative cream; decorative UI with separate label |
| Wordmark | Vector exact product name; intrinsic horizontal bounds; review sheet at 140/240 pt width | Light/dark and mono; splash/auth/editorial brand anchor |
| Horizontal lockup | Vector symbol+wordmark at intrinsic aspect ratio; preview canvas 1600×400 px with clear space, not forced artwork ratio | Light/dark/mono/negative; no text clipping |
| Splash composition | Separate symbol/wordmark resources, proposed layout above; portrait review 1179×2556 px and compact/large logical viewports | Deep teal both themes, optional static wave only after approval |
| AppIcon candidate set | 1024×1024 px candidates, original square masters | Default/dark/tinted; final selection gated by explicit approval |
| Review/manifest | Human-readable version/license/source/approval/roles/geometry/export settings + SHA-256 hashes once bytes exist | Asset family `performe-ai-public-v1`; approved callsites and rollback selection |
| Optional photography | Licensed approved master and crop/focal-point metadata; not produced here | Onboarding only if separately approved; no default stereotype/body-outcome promise |

Future storage proposal: new `PerformeAI…V1` imagesets and separate `PerformeAIAppIconV1` candidate asset set; editable sources/review manifest under a versioned public-brand assets directory chosen in Slice 1. Do not rename old files, mutate old enum entries or overwrite old catalog image bytes. New presentation mapping may select new assets only at approved public root/launch/auth/onboarding surfaces. Current `BodyFlowBrandAsset` is legacy-preserved, with no production Swift callsites found outside its definition in the scoped scan; do not invent a mass callsite migration. Current public brand text already uses Performe AI; current AppIcon still has legacy art.

Manifest records version, source author/license, checksum per final file, role/theme, optical version, approval evidence and explicit public callsite allowlist. No fake hash or approval now. Legacy assets remain for evidence and rollback; no historical image rewriting. Accessibility: decorative symbol hidden if name adjacent; meaningful standalone lockup label “Performe AI”; brand name never translated or duplicated in spoken reading. New Flow avatar, if used, is a labeled brand-symbol treatment, not a new doctor/mascot identity.

## 8. Localization, devices and accessibility

Existing mechanism: `SupportedAppLanguage`, `AppLocalization`, `BrandIdentity`, `Localizable.xcstrings`/`InfoPlist.xcstrings`. Future public UI strings go through catalogs, with no new private ad-hoc translation table or hard-coded public copy. Keep technical keys and IDs even when visible labels change. Catalog coverage must include all DS/state/action/error/a11y copy, interpolation and plural forms; current hard-coded pt-BR debt is not falsely claimed solved.

| Public invariant / example | pt-BR | en |
| --- | --- | --- |
| Tabs, in order | Hoje / Registrar / Plano / Progresso / Perfil | Today / Register / Plan / Progress / Profile |
| Product / assistant | Performe AI / Flow | Performe AI / Flow |
| Waiting (proposed) | Enviando e aguardando o Flow… | Sending and waiting for Flow… |
| Capability unavailable | Indisponível nesta versão | Unavailable in this version |
| Freshness warning | As informações podem estar desatualizadas. | This information may be out of date. |

Format numbers/dates/units using selected language’s existing locale; preserve numeric value/units and backend timezone/date-only semantics. Never reparse an official formatted value to compute progress. Date-only user-day must not shift because device timezone differs. Decimal input acceptance/validation stays compatible with existing contract. Full Portuguese titles and long English safety text must wrap rather than be clipped. Server document and content locale/body are authoritative, not client-machine translated.

Verified project target: iOS 18.0+, `TARGETED_DEVICE_FAMILY = 1`. Current iPhone plist allows portrait and landscape left/right. iPad plist entries alone do not establish an iPad target; iPad is out of scope. Future layout QA: compact 375×667, standard 393×852, large 430×932 **logical portrait test viewports**, not a claim of newly supported hardware; also actual available iPhone simulator with Dynamic Island and both supported landscape rotations. No orientation lock to hide layout bugs. Prefer size/safe-area adaptability rather than specific device offsets.

Accessibility acceptance: VoiceOver headings/reading order/selected state/role/status and no duplicate controls; Dynamic Type all supported categories through AccessibilityXXXL; interactive hit area >=44×44 pt; text/controls contrast as above; Differentiate Without Color adds text/shape/selected trait; Reduce Motion no decorative loop/animated auto-scroll; Increase Contrast and opaque material fallback; semantic chart/list equivalent when applicable; focus returns after sheet dismiss, field errors and supported operation outcome; keyboard avoidance and scroll reachability. Do not force focus on every refresh, notification or response while user is reading. Color, haptic or symbol alone cannot communicate an error or success.

## 9. Visual QA matrix — future acceptance, not executed now

Codes: L loading; E empty; C loaded/content; R recoverable error; O offline; S stale previous value; D disabled/submitting; X destructive/cancellation confirmation; U capability unavailable. State exists only if underlying current model/capability supports it. For non-network screens, O means mapped supported transport feedback during operation, not invented local connectivity detection. Loading before data and mutation loading are independently exercised where present.

Theme×locale baseline for **every applicable row/state**: Light/pt-BR, Light/en, Dark/pt-BR, Dark/en at standard viewport with Large text. Every interactive layout also exercises compact and large viewports, keyboard shown where applicable, AccessibilityXXXL in both themes/locales, VoiceOver semantic order and >=44 pt targets. Intermediate text categories sampled per shared component, plus all-category automated layout coverage in the future DS gate. Reduce Motion/Differentiate Without Color/Increase Contrast tested per component family and per Flow/progress/onboarding screen. This is a required coverage plan, not a screenshot PASS today.

| Screen / component | Applicable states | Additional assertions / exclusions |
| --- | --- | --- |
| Launch/session neutral root | L; C transition | No fake E/O/X; launch timing and session ownership unchanged |
| Sign-in | C/L/R/O/D | Secure keyboard, autofill, errors, account/recovery navigation |
| Sign-up | C/L/R/O/D | Same validation, confirmation journey, no added consent shortcut |
| Recovery / email confirmation | C/L/R/O/D where model supports | Non-enumerating response; Debug-only action absent in Release |
| Onboarding restore/container | L/C/R/O/D/U | Authoritative resume, progress/commands reachable; no forged consent |
| Welcome / country / timezone | C/R/D | Search/list empty results where supported; keyboard/focus and retained codes |
| Body / objective / routine / persona | C/R/D; L/U for server option availability | Optional nil/selection distinctions; real option count/names; no clinical persona |
| Consent | C/R/D/U | Long body, required/optional semantics, all explicit actions, missing docs fail closed |
| Completion | C/L/R/O/D | Server finish before navigation, no new edit/reset actions |
| Shell | C | Five IDs/labels/order, independent stacks restored; portrait/landscape/safe areas |
| Hoje | L/E/C/R/O/S/U | Official metrics/protocol/nulls; Flow reachable even in U; no score |
| Today recommendations / Mascot summary | L/E/C/R/O/S/U | Independent failure, authorized images, no extra impressions or cartoon dependency |
| Registrar root | C/U; existing preview L/E/R/O | Demo/real boundary explicit; no fake writes |
| Capture choices / text / local media samples | C/L/R/O/D/U according to task | No new permissions; truthful supported choice; input preserved |
| Meal/workout proposal and editor | C/L/R/O/D/U | Review/expiry/confirmed/cancelled; same key on retry, no duplicate write; first-item limit |
| Weight/hydration | C/L/R/O/D/U | Native units/input/date/quick amounts, receipt truth, AX intrinsic height |
| Registration sheet/result | C/L/R/O/D/U | Large detent at AX; close and discard ownership; no new destructive-alert business rule |
| Plano root/detail | L/E/C/R/O/S/U | Received sections/metadata, detail reload unchanged, no invented plan |
| Progresso | L/E/C/R/O/S/U | Missing measurements, streak zero, official badges/XP; no unsupported charts/range picker |
| Bloco 7.700 | L/C/R/O/S/U | Nullable fields, official percentage only, textual progress equivalent |
| Perfil / persona editor | C/L/R/D/U; root preview E/O/R | Fixture identity vs real options; save/cancel ownership and safe load invalidation |
| Biblioteca / categories / pagination | L/E/C/R/O/S/U/D as supported | All/Saved/category, next-page local error/cursor recovery, focus and card opening |
| Article / covers / save / complete | L/C/R/O/S/U/D; bounded not-found/version/access states | Canonical Markdown, links, image authorization, idempotent mutations; no new purchase UI |
| History / meal / workout detail | L/E/C/R/O/S/U where read model supports | Nullable fields and read-only details, IDs, no new edit/delete |
| Routine list/detail/history | L/E/C/R/O/S/U where provider supports | Schedule ownership/timezone, actual actions, pagination |
| Routine action/snooze/summary | C/L/R/O/D/U | Existing explicit confirm, allowed presets, conflict reload/manual retry |
| Flow history/empty/composer | L/E/C/R/O/D/U via supported provider error | No auto-send, keyboard, 4,000 guard, persisted roles/IDs, long text |
| Flow send/wait/reply/retry/cancel | L/C/R/O/D + supplied processing/failed message state | No fake phases/streaming; cancel local wait, same-key retry, reader position, relaunch history |
| Future destructive account action template | X/R/D, **DEFER / NOT APPLICABLE to current native UI** | Only when implemented/authorized: explicit named effect, cancel default, no destructive primary-by-default |

No requirement to invent X on read-only screens or E on splash. Current routine/registration confirmation is an existing mutation-review state, not destructive account deletion. Unsupported state is recorded N/A with source reason, not made to look tested. Release unavailable states and local loaded demo states must be captured and labeled separately. Real auth/Flow functional QA or a paid completion requires a later bounded authorization; do not reopen it solely for visual regression.

Future evidence: screenshot + hierarchy/state fixture + SHA/build/theme/locale/size/motion settings; privacy-safe synthetic data only, no secrets/private config/raw message telemetry. Compare action→request→persistence→UI only in separately authorized connected functional gates; local mock UI screenshots alone are not runtime verification.

## 10. Proposed implementation slices — not started

Slices share only the established DS contract; take one reviewed slice at a time. Dark/localization/a11y is included in each, Slice 9 reconciles rather than defers these requirements. No new branch/worktree/provider infrastructure by default. Loaded demo coverage does not authorize real adapter work.

| Slice | Scope / actual code boundary | Dependencies / acceptance |
| --- | --- | --- |
| 0 | Existing DS semantic surfaces/color roles/typographic/spacing/radius/action/state families; shared components | Additive roles, pair checks, all text categories/44 pt; no namespace rename or service change |
| 1 | New approved asset family, manifest and only allowed public presentation mapping | Depends final bytes/review; AppIcon selection separately gated; old hashes preserved |
| 2 | Auth + seven-step onboarding presentation | Slice 0; may use approved text identity before assets; same validation/session/consent tests |
| 3 | Native tab shell + Hoje sections | Slice 0; five stacks/IDs; Flow access survives Today U; official DTO and stale/null semantics |
| 4 | Registrar/proposal/edit/receipts + existing UIKit presentation | Slice 0; same idempotency/confirm/expiry/unit tests; no media permission or adapter integration |
| 5 | Plano root/detail/grouping | Slice 0; metadata/optional sections/reload preserved |
| 6 | Progresso/block/official achievements | Slice 0; no historical chart/range work; no new achievement logic |
| 7 | Perfil/persona + existing Hoje Library/article/cover/history/routine visual convergence | Slice 0; preserve content/link/capability tracking; account feature wiring excluded |
| 8 | Flow visual layout/composer/status/focus/scroll | Slice 0; endpoint/model/persistence/key/cancel unchanged; no prompt/streaming/backend optimization |
| 9 | Cross-screen theme/catalog/a11y consistency | Slices 2–8; asset verification when Slice 1 approved; no new feature to eliminate unavailable states |
| 10 | Full visual regression + documented functional/regression gates | Reviewed slices; signed Release Simulator where runtime needed, codesign strict PASS; no `CODE_SIGNING_ALLOWED=NO` substitute for auth/Keychain runtime |

Every future implementation slice follows approved TDD where behavior/layout policy is testable, focused and neighboring regression gates, typecheck/build appropriate to changed scope, UI state/locale/a11y checks and complete diff review. No CI-3 resurrection. Integration/deployment policy for those later operations must be explicit; this document is **not** their execution authorization.

## 11. Rollback and non-regression strategy

Before any future slice, establish fresh HEAD/clean or understood user-owned changes, no concurrent writer, exact file allowlist and truthful baseline. Keep local theme/layout selection purely presentational; no persisted schema/key migration. Add new DS roles without removing existing API until its approved callers migrate. Preserve server DTOs, numeric semantics, endpoint/auth/session/cancellation ownership, IDs and telemetry payload allowlist.

Asset rollback selects the preserved old family via the approved mapping/catalog selection without overwriting either family; do not secretly restore a public old name to mask a failure. Layout rollback is a scoped reviewed revert of the task-owned presentation change, never `reset --hard`, mass restore or removal of unrelated work. Native project/signing/entitlements are not a visual rollback surface. No backend rollback should be needed because UI refinement changes none.

Future must-pass regressions: auth/restore/account isolation; explicit onboarding and server completion; independent navigation/sheet dismissal/focus; invalidation and stale-data ownership; all proposal phases, same-key retries and duplicate guards; official energy/protein/hydration/block/XP/streak/null values; content capability/version/link/impression policies; persona server options; Flow history/retry/local cancel/session invalidation. Real model text is stochastic and is not falsely certified by a UI fixture.

## 12. Decisions genuinely remaining

| Decision | Impact / safe default until resolved |
| --- | --- |
| **DECISION REQUIRED — final logo contours/wordmark and visual asset approval** | B2 and distinct P/trajectory direction are consolidated; final production bytes are not approved. Keep public text identity; no final SVG/PNG generation/integration in this task |
| **DECISION REQUIRED — final AppIcon visual approval** | Present default/dark/tinted candidates first; do not select new catalog icon or overwrite legacy bytes |
| **DECISION REQUIRED — optional licensed photography approval** | Only if later proposed; safe default is typography/neutral symbol, no photograph and no rights dependency |
| **DECISION REQUIRED — capability expansion beyond existing UI** | Real media, historical series/ranges, account/support/privacy/delete/logout wiring and unavailable repositories require separate functional scope; all DEFER, no fake live controls |
| **DECISION REQUIRED — unknown legal-document friendly labels, if requested** | Do not invent legal meaning; preserve document key/version/purpose and authoritative body until approved presentation naming is supplied |

No additional macro B approval, new price/trial, chart metric definition or production access is required to consider this architectural spec ready. Final assets and future execution authorization are explicit gates, not generic unfinished placeholders.

## 13. Self-review and closeout

Self-review checklist: references translated into coherent B2, not copied architecture; all current visual view files inventoried; each screen/state constrained by source capability; no official value invented; contrast pairings tested locally; real/demo and historical/current evidence separated; no implicit new API/business/legal rule; no BodyFlow mass rename; no changed asset byte or source file; slices not executed; rollback/pending approvals explicit. Final documentation checks and Git identity are recorded in the operation report after the single commit (a commit cannot contain its own resulting SHA).

Current-task tests/typecheck/lint/build/functional QA: not run, documentation-only; historical integration remains the previously verified auth/onboarding/Flow vertical slice, not whole-app verification. Documentation diff/path/coverage/secret/contrast checks are this task’s verification surface. Resource gate: NOT REQUIRED; no heavy build or dependency install. No paid environment created/adopted; cost/environment closeout NOT APPLICABLE. No remote mutation or provider spend. No cleanup deletes preserved evidence.

Expected closeout: PERFORME_AI_PREMIUM_UIUX_DESIGN_SPEC_READY. REBRAND STATUS: PARTIAL. UI/UX REFINEMENT STATUS: DESIGN SPEC READY. IOS INTEGRATION STATUS: VERIFIED for the previously proven vertical slice only, not re-executed here. PRODUCTION STATUS: NOT DEPLOYED. LOGO DESIGN STATUS: DIRECTION APPROVED / FINAL BYTES PENDING. Stop after the documentation commit/report.

## 14. Primary design guidance consulted

These support acceptance criteria, not a claim that the current UI is fully compliant or ready for App Store submission:

- [Apple UI Design Dos and Don’ts](https://developer.apple.com/design/tips/): native usability, readable controls and 44 pt touch regions.
- [Apple Larger Text evaluation](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/larger-text-evaluation-criteria): adaptive layout and actual larger-text testing.
- [WCAG text contrast](https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum): 4.5:1 normal / 3:1 large text.
- [WCAG non-text contrast](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html): essential custom visual cues >=3:1 and color-independent semantics.
- [Apple asset-catalog app icon configuration](https://developer.apple.com/documentation/xcode/configuring-your-app-icon): supported dark/tinted variations in the existing asset-catalog route. No migration to a new icon authoring workflow implied.
