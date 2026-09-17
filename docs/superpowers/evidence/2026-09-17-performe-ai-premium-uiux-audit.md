# Performe AI — current visual audit for premium refinement

Operation: DESIGN_PERFORME_AI_PREMIUM_UIUX_REFINEMENT_V1, 2026-09-17.
Source HEAD: `39f446a4c3cf8cfa58d21e030769c417e868e0a9`.
Starting branch/worktree/index verified against the requested baseline. Documentation only; no code, assets, build, provider call or runtime state changed.
Design decisions are in [the spec](../specs/2026-09-17-performe-ai-premium-uiux-refinement-design.md).

## Method and limits

Read current DS and visual view bodies, their presentation helpers, dependency injection, navigation/localization/target configuration and relevant DTOs. Inventory below groups file-owned subviews but names each current SwiftUI View symbol, including Debug-only preview hosts; generic components and UIKit bridges are included. Source-declaration coverage check found 127 View/UIViewRepresentable/UIViewControllerRepresentable symbols across 73 Swift files, with zero names missing from this inventory (including multiline generic declarations). This is inventory coverage, not 127 screens or runtime test coverage. KEEP means preserve current behavior/semantic foundation; REFINE means presentation cleanup; REDESIGN means deeper visual recomposition with the same contract; DEFER means the desired functional capability is not established. A REDESIGN row is not implementation authorization.

Paths below are relative to `apps/ios/BodyFlow/BodyFlow/`. File-owned helper functions are covered by their owning view/file, not new screens. Existing models, factories and DTOs are evidence of capability, not a list of new screens to build. No claim of full live usability compliance follows from a source audit.

Per-row accessibility/theme/localization codes make shared findings explicit:

- A1: native Dynamic Type, scroll, keyboard/focus/validation; preserve secure-entry and announcements; horizontal header can crowd at AX. Theme uses current semantic DS plus native field/system tint; mostly hard-coded pt-BR copy.
- A2: form/selection/consent Dynamic Type, explicit state and IDs; long body or segmented controls need compact/AX reflow review. Current cream/charcoal DS, coral errors and native tint; mostly pt-BR, server-owned option/document copy not client-translated.
- A3: feature-state stack/metric/action Dynamic Type (some AX vertical branches), stale retention and IDs; need full semantic order/contrast validation. Current outlined cards/cream/charcoal/gold dark accent; labels/numeric formatting largely pt-BR.
- A4: registration native/bridged controls, preserved focus/result IDs; fixed visual heights and multi-column controls require AX review. Current DS and UIKit/SwiftUI action styles coexist; mostly pt-BR and raw enum labels.
- A5: content-specific Dynamic Type/AX open actions, canonical link/list semantics, cover hidden as decorative, explicit focus policies. Current DS cards/material/system filters; mostly pt-BR; content body/locale authoritative.
- A6: Flow body font, 44 pt composer actions and role IDs; unconditional animated count-based auto-scroll and long text/keyboard need review. DS bubble pairing/light/dark; flow catalog keys exist, spoken “Você” still hard-coded.
- A7: shell/native chrome preserves stack/identity/IDs; brand strip + clipped child risks vertical pressure; underlying DS theme. Tab labels hard-coded pt-BR despite bilingual infrastructure.
- A8: Debug-only visual evidence host; no Release capability or public runtime feature implied. Uses the owned component’s theme/locale/a11y behavior; preserve isolation.

Regression risks H/M/L refer to functional ownership sensitivity of a future visual patch, not a discovered security severity. None permits changing source semantics.

## Complete screen and component inventory

| Path / view(s) | Function and current state | Components / hierarchy debt | A11y, theme, locale | Classification / regression risk |
| --- | --- | --- | --- | --- |
| `App/AppRootView.swift` — AppRootView | Root launch/auth/confirmation/onboarding/authenticated and neutral-session states | Native state switch; pending/failed restore views have inconsistent presentation; no global screen redesign by inference | A1/A2/A7; session focus/ownership sensitive | KEEP root machine; REFINE state presentation / H |
| `App/AppShellView.swift` — AppShellView | Five native tabs, separate stacks, registration sheets, session-owned models | TabView/NavigationStack/brand wrapper; repeated top chrome; Flow in Today route, not a tab | A7; root IDs and native back behavior | KEEP navigation; REFINE hierarchy / H |
| `App/TabBarAccessibilityConfigurator.swift` — TabBarAccessibilityConfigurator (UIViewControllerRepresentable) | Technical tab ID mapping onto native bar | Invisible configurator, no public design surface; preserve label/ID distinction | A7; target mapping must remain stable | KEEP / H |
| `DesignSystem/Components/ScreenStateView.swift` — BodyFlowBrandIdentityView | Visible Performe AI text anchor | Headline/bold/accent repeated as strip above stacks; not new logo art | A7; `brand.product-name` remains; dark gold accent | REFINE public composition / M |
| Same file — ScreenStateView | Loading/empty/recoverable error/offline/unavailable generic states | GeometryReader/ScrollView/icon/title/message/retry; actionable mapping valuable, error coral weak on cream | A3; preserve state IDs and meaningful retry | REFINE / M |
| Same file — ScreenContentStatePreviewHost | Component state preview | Existing local fixture surface, not connected data | A8 | KEEP / L |
| `Features/Shared/FeatureComponents.swift` — FeatureStateContentStack | Retains previous content with stale banner | VStack/grouping useful; no new state needed | A3 | KEEP / M |
| Same file — BodyFlowCard | Shared 16 pt padding / 20 pt radius / faint outline | Every metric/action framed; uniform outline creates card soup; add explicit surface roles rather than rename type | A3; no intrinsic accessibility role itself | REFINE / M |
| Same file — FixtureMetricRow | Label/value display, AX vertical fallback | Repeated dividers; semantic official value important, do not recompute | A3; combined spoken values need units and locale | REFINE / H |
| Same file — FeatureActionLabel | Icon/title/detail/disclosure and AX vertical layout | Reusable 44 pt affordance; duplicate detail headers compete | A3 | REFINE / M |
| `Features/Shared/FeatureReadStateView.swift` — FeatureReadStateView | Generic read-state to loaded/stale/full-screen presentation | Critical state delegation, not a visual feature; generic View declaration covered here | A3 | KEEP / H |
| `Features/Shared/StaleDataBanner.swift` — StaleDataBanner | Previous-value warning | Orange-tinted grouped banner inconsistent with teal/coral/gold; keep warning text | A3; ID `state.stale-banner`; AX vertical support | REFINE / H |
| `Features/Shared/FeatureDetailView.swift` — FeatureDetailView | Local placeholder detail destination | Demo title/text, not actual data operation; do not sell as a real settings screen | A3 | KEEP demo disclosure; DEFER real feature / M |
| `Features/Auth/SplashView.swift` — SplashView | Launching | Product text + spinner on DS canvas, no new symbol yet | A1; no invented empty/confirmation state | REDESIGN presentation / M |
| `Features/Auth/AuthFieldMessage.swift` — AuthScreenLayout | Auth form container | Title/brand HStack, max 560 pt scroll, fields below; crowded duplicated header | A1 | REDESIGN layout / M |
| Same file — AuthFieldMessage / AuthOperationMessage / AuthValidationSummary | Field, operation and validation feedback | Coral error labels, repeated summaries; avoid duplicate VO announcements, retain error mapping | A1 | REFINE / H |
| `Features/Auth/SignInView.swift` — SignInView | Real-adapter or demo sign-in, submit/error states | RoundedBorder email/password, prominent CTA, separate create/recovery links; standard hierarchy but default system styling mixed | A1 | REDESIGN presentation; KEEP semantics / H |
| `Features/Auth/SignUpView.swift` — SignUpView | Account creation + confirmation | Three secure/autofill fields, loading/validation; no social login or legal-rule changes | A1 | REDESIGN presentation / H |
| `Features/Auth/PasswordRecoveryView.swift` — PasswordRecoveryView | Recovery request and non-enumerating result | Current form/status/actions, no unsupported resend | A1 | REFINE / H |
| `Features/Auth/EmailConfirmationView.swift` — EmailConfirmationView | Await confirmation/return; development action gated | Readable email + explanatory status, privacy-safe captures required | A1; development action absent Release | REFINE / H |
| `Features/Onboarding/OnboardingContainerView.swift` — OnboardingContainerView | Seven-step task/back/continue/finish, server restore | Scroll/progress/header/commands, large step titles; repeated chrome and operation summaries | A2; task cancellation and resume remain | REDESIGN presentation / H |
| Same file — OnboardingDocumentsUnavailableView / OnboardingOperationMessage / OnboardingValidationSummary | Fail-closed requirements/error/validation | Native unavailable text and warning summaries; unify task states, no bypass | A2 | REFINE / H |
| `Features/Onboarding/OnboardingViewSupport.swift` — OnboardingStepHeader / OnboardingFieldIssue | Shared step heading/field error | Large headings and coral issue labels; unit/error spacing inconsistent | A2 | REFINE / H |
| `Features/Onboarding/WelcomeStepView.swift` — WelcomeStepView | Name/country/timezone/locale | Native labeled fields/search destinations; technical codes visible, localized-readable choice limited by source | A2 | REDESIGN grouping / H |
| Same file — CountrySelectionView / TimeZoneSelectionView | Search/select supported country and IANA timezone | Native searchable lists; long names must remain readable, retain technical selected value | A2 | REFINE / H |
| `Features/Onboarding/BodyDataStepView.swift` — BodyDataStepView | Biological sex/birth date/height/weight/optional fat | Segment/date/decimal fields; long form needs grouped sections, not card per field | A2; no client health formulas | REDESIGN grouping / H |
| `Features/Onboarding/ObjectiveStepView.swift` — ObjectiveStepView | Actual three objective enum choices | Selection rows, preserve codes; reference focus categories are not equivalent | A2 | REFINE / H |
| `Features/Onboarding/RoutineStepView.swift` — RoutineStepView | Activity/frequency/water/hunger/wake/bed/organization | Menu/toggle/date controls; long mixed optional form; confirmation/nil differs from explicit zero/no | A2 | REDESIGN grouping / H |
| `Features/Onboarding/PersonaStepView.swift` — PersonaStepView | Server Focus/Impulse/Zen selection | Public coach wording, selection cards and explanatory copy; new focus taxonomy forbidden | A2; retain selected trait/IDs | REFINE public Flow styling / H |
| `Features/Onboarding/ConsentStepView.swift` — ConsentStepView | Server required/optional documents + explicit actions | Long body/key/version/purpose/action per surface; raw technical keys need cautious presentation, not invented legal names | A2; consent action meaning/hash unchanged | REDESIGN reading hierarchy / H |
| `Features/Onboarding/OnboardingCompletionView.swift` — OnboardingCompletionView | Review answers/documents + authoritative finish | Dense received values/CTA; keep review, simplify visual grouping | A2 | REFINE / H |
| `Features/Today/TodayRootView.swift` — TodayRootView | State read, official sections; Release Today unavailable | Native scroll, independent Flow/Library entry; mascot near top; many sections compete | A3/A7; Flow survives U | REDESIGN hierarchy; KEEP capability boundary / H |
| `Features/Today/TodayHeaderSection.swift` — TodayHeaderSection | Day/protocol/update context | Eyebrow + large title + metadata rows; duplicate date/title emphasis, raw protocol labels | A3; no invented user greeting | REFINE / H |
| `Features/Today/TodayAttentionSection.swift` — TodayAttentionSection | Existing pending registration/occurrence information | Lists/raw statuses; not every item has a write/navigation command | A3 | REFINE; DEFER new action mapping / H |
| `Features/Today/TodayEnergySection.swift` — TodayEnergySection / TodayEnergyMetricCard | Food remaining vs net balance, consumed/target/excess/workout/status | Two metric focal cards plus grouped rows; important distinction lost if condensed indiscriminately | A3; calories/protocol official | REDESIGN composition / H |
| `Features/Today/TodayProteinSection.swift` — TodayProteinSection | Official protein totals/target/remaining/percentage/status | Repetitive metric rows, optional goal state; no local percentage derivation | A3 | REFINE / H |
| `Features/Today/TodayHydrationSection.swift` — TodayHydrationSection | Official hydration totals/target/remaining/percentage | Similar to protein; semantic missing target differs from zero | A3 | REFINE / H |
| `Features/Today/TodayRecordsSection.swift` — TodayRecordsSection | Confirmed meals/workouts/provenance | Dense list/metadata; no reference artwork or sample values substitute for DTO | A3 | REFINE / H |
| `Features/Today/TodayRoutineSection.swift` — TodayRoutineSectionView | Supplement/medication occurrence summaries and supported detail links | Multiple framed blocks/raw occurrence statuses, separate treatment semantics | A3 | REFINE / H |
| `Features/Today/TodayBlockCard.swift` — TodayBlockCard | Optional official 7.700 block descriptor | Numerous rows/availability/source; ring only with received percentage | A3 | REFINE / H |
| `Features/Today/TodayRecommendationsSection.swift` — TodayRecommendationsSection / TodayRecommendationCard | Independent content read with up to current supported recommendation limit | Repeated cards; real authorized cover optional, tracking can regress through layout visibility changes | A5 | REFINE / H |
| `Features/Register/RegisterRootView.swift` — RegisterRootView | Fixture commands: meal/workout/weight/hydration | Four cards + local demo disclaimer, not fully integrated Release register | A4 | REDESIGN presentation; KEEP truth / H |
| `Features/Register/RegistrationSheet.swift` — RegistrationSheet | Owns route/task/captured attempts/discard, sheet size/close | Medium sheet, AX large detent, close button; demo title and state ownership critical | A4 | REFINE / H |
| Same file — HydrationRegistrationContent / WeightRegistrationContent / OperationResultSummary | Entry callbacks + local/official receipt/error/retry | Repeated result text; distinguish demo receipt and actual receipt, no fake save | A4 | REFINE / H |
| Same file — WorkoutRegistrationContent / MealRegistrationContent | Draft/proposal/confirmed/editor navigation and task focus | Long scroll, operation summaries; first draft contains explicit demo sample | A4 | REDESIGN composition / H |
| Same file — Prompt13RegistrationReceiptPreview | Debug local receipt samples | Preview-owned submission to deterministic providers only | A8 | KEEP isolation / L |
| `Features/Register/MealCaptureSourceView.swift` — MealCaptureSourceView | Text/photo/audio source choice | Three choices; photo/audio are local samples, not real sensor capture | A4 | REDESIGN chooser; DEFER actual media / H |
| `Features/Register/MealDemonstrationSourceView.swift` — MealDemonstrationSourceView | Explicit local sample submission | Demo notice/action must remain truthful | A4 | REFINE / H |
| `Features/Register/MealTextDraftView.swift` — MealTextDraftView | Multiline draft + analyze | Native text field/task action, default sample not user record | A4; retain blank/submitting guard | REFINE / H |
| `Features/Register/MealProposalView.swift` — MealProposalView | Official items/quantity/nutrients/totals/warnings/expiry + review actions | Verbose rows and equal actions, no confirmed image field; reference meal card cannot invent image/ring goals | A4 | REDESIGN review hierarchy / H |
| `Features/Register/MealProposalEditorView.swift` — MealProposalEditorView | First-item edit, date/type and optional kcal entry | Native Form; one-item capability, silent guard/style debt; do not add multi-item backend semantics | A4 | REFINE; DEFER multi-item feature / H |
| `Features/Register/WorkoutRegistrationView.swift` — WorkoutRegistrationView / WorkoutFieldLabel / WorkoutActionButton / WorkoutIntensityPicker / WorkoutDatePicker / WorkoutTextField | Type/duration/intensity/date request form and UIKit bridges | UIKit text/segments/date/buttons with fixed visual frames, demo defaults | A4; prefer intrinsic height and readable units; retain bridge coordinators | REFINE controls / H |
| `Features/Register/WorkoutProposalView.swift` — WorkoutProposalView / WorkoutProposalActionButton | Review official estimated energy / edit/confirm/cancel and UIKit action bridge | UIKit all filled buttons compete, estimated value must remain labeled | A4 | REDESIGN action hierarchy / H |
| `Features/Register/HydrationRegistrationView.swift` — HydrationRegistrationView / RegistrationBoundedTextField / RegistrationBoundedDatePicker / RegistrationBoundedButton | Quick/custom ml + timestamp and shared entry/action bridges used by weight | UIKit/SwiftUI mix, horizontal quick choices, fixed frames; no consumption proof before receipt | A4 | REFINE / H |
| `Features/Register/WeightRegistrationView.swift` — WeightRegistrationView | Decimal kg + date | Similar fixed control height/units; existing parsing preserved | A4 | REFINE / H |
| `Features/Register/RegistrationOperationSummary.swift` — RegistrationOperationSummary | Error/retry/start-new-proposal/receipt recovery | Generic summary copy; expired/not-pending not equivalent to retry same confirmation | A4 | REFINE / H |
| `Features/Plan/PlanRootView.swift` — PlanRootView / PlanReadContent | State, received plan sections, optional detail reload link | Repeated metadata surfaces and stale/retry stack; Release provider U | A3 | REDESIGN presentation / H |
| `Features/Plan/PlanDetailView.swift` — PlanDetailView | New read of same supported plan | Duplicates content, documented reload must remain; no schedule feed | A3 | REFINE / H |
| `Features/Plan/PlanComponents.swift` — PlanContentView / PlanMetadataCard | Training fields and nutrition prescription metadata | Card/row/divider per section, raw type/version fields visually prominent | A3 | REFINE / H |
| `Features/Progress/ProgressRootView.swift` — ProgressRootView | Official snapshot + block detail | Header/cards, no historical series; Release provider U | A3 | REDESIGN hierarchy; DEFER charts/ranges / H |
| `Features/Progress/ProgressComponents.swift` — ProgressContentView | Official XP/level/streak/blocks/medals/measurements/dates; missions unavailable | Numeric table and multiple cards; reorder visuals calmly but preserve official achievements and zero-streak action | A3; gold contrast foundation useful | REDESIGN hierarchy / H |
| `Features/Progress/Block7700DetailView.swift` — Block7700DetailView | From Today descriptor, retained value/optional fields | Summary card + rows + retry, all persisted values not local credits | A3 | REFINE / H |
| `Features/Profile/ProfileRootView.swift` — ProfileRootView | Fixture identity/notifications, gated persona load/editor | System grouped List; preference placeholder link; not real account settings or push proof | A3; semantic load invalidation | REDESIGN grouping; DEFER account wiring / H |
| `Features/Profile/CoachPersonaPickerView.swift` — CoachPersonaPickerView | Server options/loading/save/cancel/error | Extra brand strip, inset List, material saving overlay; public coach wording | A1/A3; dismissal disabled during save | REFINE / H |
| `Features/Library/LibraryRootView.swift` — LibraryRootView / LibraryContentRow | All/Saved/category/read/pagination/impression and focused recovery | Filter chrome + summary + large card feed; AX filters correctly move into scroll; preserve policies | A5; Release factories U | REDESIGN hierarchy / H |
| `Features/Library/PublishedContentCard.swift` — PublishedContentCard | Authorized publication summary/cover/read-time/status/open | Standard combined link vs AX separate open; card-to-row density may improve but semantics/tracking must remain | A5 | REFINE / H |
| `Features/Library/PublishedContentDetailView.swift` — PublishedContentDetailView | Bounded article, save/complete/opened feedback | Editorial title, actions, metadata, Markdown; no fake content or purchase UI | A5 | REFINE / H |
| `Features/Library/ContentCoverView.swift` — ContentCoverView / ContentCoverPlaceholder | Session/revision authorized image or neutral placeholder | 16:9 cover/radius16 differs from card family; decorative, no reference-photo substitution | A5 | REFINE radius only; KEEP security/ownership / H |
| `Features/Library/BodyFlowMarkdownView.swift` — BodyFlowMarkdownView / MarkdownInlineText | Published article blocks/links/lists/selectable text | Mature semantic hierarchy, not short-chat renderer; preserve canonical parser/link policy | A5 | KEEP renderer; REFINE DS mapping only / H |
| `Features/History/MainHistoryView.swift` — MainHistoryView | Meal/workout read lists, globally empty/stale/retry | Mixed card/flat workout rows; receipts remain read-only | A3 | REFINE / H |
| `Features/History/HistoryMealLogRowView.swift` — HistoryMealLogRowView | Meal name/type/detail link content | Minimal rows, unit/provenance needs consistency without extra field invention | A3 | REFINE / M |
| `Features/History/HistoryMealLogDetailView.swift` — HistoryMealLogDetailView | Optional cached received meal detail | Nullable quantity/energy, primitive decimal-description formatting | A3 | REFINE / H |
| `Features/History/HistoryWorkoutDetailView.swift` — HistoryWorkoutDetailView | Optional cached workout detail | Nullable duration/estimate, plain rows no unsupported edit | A3 | REFINE / H |
| `Features/Routine/RoutineListView.swift` — RoutineListView / RoutineItemRow | Supplement/medication list/state/schedules | System inset List contrasts with Today framed summaries; preserve kind | A3 | REFINE / H |
| `Features/Routine/RoutineDetailView.swift` — RoutineDetailRouteView / RoutineDetailView | Today-origin list ownership, item/schedules/actions/history | Nested card/actions/summary; occurrence context determines permitted actions | A3 | KEEP route ownership; REFINE layout / H |
| `Features/Routine/RoutineActionSheet.swift` — RoutineActionSheet / RoutineActionSummary | Explicit taken/skipped/snooze submit and receipt/error/retry | Scroll/buttons/plain status, task labels not fully coherent | A3 | REFINE / H |
| `Features/Routine/RoutineSnoozeView.swift` — RoutineSnoozeView | Existing preset/custom patient-timezone selection | Multiple equally weighted buttons + wheel; no new schedule policy | A3 | REFINE / H |
| `Features/Routine/RoutineHistoryView.swift` — RoutineHistoryView | Status/timestamp/pagination | Native grouped List, date uses device formatting at callsite; locale/timezone audit gate needed | A3 | REFINE / H |
| `Features/Mascot/MascotCardView.swift` — MascotCardView / MascotSemanticContent | Server persona/semantic state/compact state/route | Large Debug art before metrics, repeated mascot metadata; Release has no temporary art | A3; spoken semantic state must stay | REFINE emphasis; KEEP types/state / H |
| `Features/Mascot/MascotDetailView.swift` — MascotDetailView | Read/refresh/stale state detail | Two framed groups, explicit state provenance; not a generated chatbot persona | A3 | REFINE / H |
| `Features/Mascot/MascotPlaceholderArtwork.swift` — MascotPlaceholderArtwork | Debug-only personality geometry/tone/state | Face/orbit TimelineView repeating motion; not new public brand; never make mandatory Release artwork | A8; Reduce Motion policy already passed in old evidence | KEEP historical/demo art; DEFER replacement / M |
| `Features/FlowChat/FlowChatView.swift` — FlowChatView / FlowMessageBubble | Authenticated history/send/retry/cancel/processing/error; demo provider separate | Plain SwiftUI Text, clinical guidance icon, bubble roles, composer, unconditional animated count scroll; wait covers send+history | A6 | REDESIGN presentation; KEEP model/API/plain text / H |
| `Features/PreviewSupport/Prompt13PreviewSupport.swift` — Prompt13TodayStatePreview / Prompt13MealJourneyPreview / Prompt13MealEditPreview / Prompt13WorkoutProposalPreview / Prompt13RoutineSnoozePreview / Prompt13RoutineHistoryPreview / Prompt13PlanPreview / Prompt13ProgressPreview / Prompt13BlockPreview / Prompt13HistoryPreview | Deterministic local feature-state and journey hosts | Source fixtures/providers, no screenshots newly generated or code altered | A8; exact symbols verified in coverage check | KEEP / L |
| `Features/PreviewSupport/Prompt14PreviewSupport.swift` — Prompt14LibraryPreview / Prompt14DetailPreview / Prompt14RecommendationsPreview / Prompt14MascotPreview / Prompt14ProgressPreview | Deterministic content/cover/persona/progress hosts | Current state definitions retained, not new runtime adapters | A8 | KEEP / L |

UIKit representables nested inside registration files are part of A4, not new business screens: text-field, date-picker, intensity/quick-selection and action-button bridges must keep coordinator callbacks, parsing and IDs. Future visual work cannot remove these as a shortcut without equivalent behavior/regression tests. `FeatureReadState`, `FeatureMutationState`, `RegistrationOperationSummary` policies and native root coordinators remain the behavioral foundation, not speculative redesign targets.

## Non-View visual foundations

| Source | Current behavior / finding | Disposition |
| --- | --- | --- |
| `DesignSystem/BodyFlowColor.swift` | Semantic bg/text but palette constants also used as roles; gold is global dark accent; coral warning insufficient on cream | REFINE additive semantic roles, keep internal enum |
| `DesignSystem/BodyFlowTypography.swift` | Native six style aliases | KEEP Dynamic Type; additive semantic metric/button roles |
| `DesignSystem/BodyFlowSpacing.swift` | 4/8/12/16/24/32 + 44 target | KEEP; separate radius/elevation policy |
| `DesignSystem/BrandIdentity.swift` | Public Performe AI / Flow, catalog-backed brand copy with Portuguese fallback | KEEP names; REFINE complete bilingual presentation coverage |
| `DesignSystem/BodyFlowBrandAsset.swift` | Legacy six image resources/accessibility labels; scoped production scan found no callers beyond definition | KEEP historical bytes/API; new distinct family separately, no blind migration |
| `Resources/Assets.xcassets` | Legacy symbol/wordmark/horizontal/mono/negative/launch and default/dark/tinted AppIcon | KEEP originals; new assets proposed, final icon approval gate |
| `Core/Localization/AppLocalization.swift` and `Resources/*.xcstrings` | Supported pt-BR/en-US mechanism exists; screen adoption incomplete | KEEP mechanism/keys; REFINE catalog coverage, do not rename technical sentinel |
| `App/AppTab.swift` | Correct five raw values/order/IDs; titles hard-coded Portuguese; native SF symbols | KEEP architecture/IDs; REFINE labels via existing catalogs |
| `Resources/Info.plist` / project pbxproj | Performe AI display name, iOS 18 target, iPhone device family; portrait and landscape supported | KEEP deployment/device/signing config; iPad out of scope |
| `Core/Progress/ProgressModels.swift` | Current value snapshot, not historic data series | KEEP; DEFER history/range feature |
| `Core/Plan/PlanModels.swift` / PlanPresentation | Received training/nutrition metadata, not complete meal/exercise programs | KEEP; no invented richer plan |
| `App/AppDependencies.swift` | Real auth/onboarding/Flow conditional on configuration; other Release capabilities/factories unavailable, demo fixtures isolated | KEEP fail-closed distinction; DEFER functional wiring |

## Existing screenshots and hierarchies inspected

Read-only `xcrun simctl list devices booted` returned no booted device. No simulator was started, app installed/launched or authenticated, and no screenshot was fabricated. Current HEAD visual runtime coverage is **NOT VERIFIED**. Existing images below were viewed; existing hierarchy files were consulted for IDs/frames. Their old public names/numbers are historical/deterministic, not current runtime evidence. Do not rewrite their bytes.

| Preserved source | Viewed / consulted baseline | Limit |
| --- | --- | --- |
| `2026-07-26-bodyflow-ios-scaffold` | `01-hoje.png`, `02-registrar.png`, `03-plano.png`, `04-progresso.png`, `05-perfil.png`; README and `accessibility-five-tabs.txt` | July source state, native five tabs, demo labels and repeated grouped cards; not HEAD 39f446 runtime |
| `2026-07-26-bodyflow-ios-auth-onboarding` | `01-sign-in.png`, `03-onboarding-persona.png`; README | Captured July 28/29; old brand and native blue controls visible; not current server-owned legal state |
| `2026-08-02-bodyflow-ios-library-mascot-gamification` | `15-dark-mode.png`, `16-accessibility-xxxl.png`; README and `02-library-all.txt` | README validation dated August 9; deep grouped UI, gold accent/mascot dominance; AX scrolling is preserved historical evidence |
| Current auth/onboarding/brand/Flow repository evidence | Integration descriptions and local prompt-quality report | Previously verified vertical slice; no new app runtime or model-generation verification here |
| User reference boards | Three attached images | Concept only, not baseline screenshot, licensed production asset or functional data |

Paths in the table are children of this evidence directory’s parent. No current Flow screenshot was captured or represented as verified. Light auth/onboarding/five tabs and dark/AX Today are available historical baselines; full dark/locale/all-screen current captures remain for an authorized implementation visual gate. Do not reopen remote QA to fill that gap during this design task.

## Key risks and recommendations

1. Retain five tabs and native stacks; consolidate redundant brand/title chrome without losing ID discoverability or accessibility reading order.
2. Keep current Dynamic Type/spacing/state semantics; reduce uniform bordered-card repetition and equal-weight CTAs.
3. Replace ambiguous dark accent/error usage with tested semantic pairs; coral remains decorative, not normal error text.
4. Label current unavailable/demo boundaries honestly. There is no verified score, historical series, media permission flow, account-settings/deletion UI or complete loaded app Release integration to beautify into existence.
5. New P/trajectory identity is a distinct asset family, not rename/recolor of old B. Final icon visual approval is a separate gate.
6. Flow needs truthful waiting and reader-preserving scroll, not fake streaming or a promise of instantaneous inference. Preserve plain-text, model retry/cancel/persistence contracts and server-owned context.
7. Catalog and locale formatting debt spans all authenticated screens; test pt-BR/en in both themes at compact and AX sizes.

This audit produces no runtime QA PASS. Its findings define bounded future visual work and explicit functional DEFER gates. No remote resource, credential, account, production data or historical asset was mutated. One local documentation commit includes only this audit and the linked spec; resulting SHA/tree are reported after commit.

## Documentation verification and self-review

- Declared visual symbols cross-checked against the current source, including generic multiline and UIKit controller representables: 127 across 73 files, zero inventory omissions.
- Relative Markdown link targets checked for existence; no broken local links in either new document.
- Changed-document credential pattern check: no provider keys, JWT-shaped credentials or private-key blocks; no user account/password/config contents included.
- No generic unfinished placeholders; real decisions explicitly named with impact/safe default. Design token/export dimensions are proposals, not fabricated product metrics.
- Proposed opaque text/control foregrounds evaluated locally by sRGB relative luminance; actual screenshot/overlay/system-control compliance remains a future gate. Disabled light pairing improved during self-review to 4.74:1 instead of retaining the first proposed 4.26:1 pair.
- Manual scope review: no code/assets/API/schema/feature/commercial/production change; current snapshots, loaded demo views and conditional future charts remain explicitly separate.
- Git diff whitespace check and staged two-file allowlist are final precommit gates; commit parent/subject/tree and clean worktree/index are verified after commit.
- Tests/typecheck/lint/build/new functional or visual runtime QA: NOT RUN, documentation-only. No invented PASS from historical reports.
- No paid environment created; closeout NOT APPLICABLE. No cleanup deletion. No remote mutation, push, PR, merge or deployment.
