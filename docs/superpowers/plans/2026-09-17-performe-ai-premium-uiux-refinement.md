# Performe AI Premium UI/UX Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Subagent-driven-development is an alternative only if delegation is subsequently authorized. This document does not authorize execution.

**Goal:** Refine the existing native Performe AI presentation to B2 — Warm Performance, preserving functional behavior and separating verified capabilities from local demonstrations.

**Architecture:** Evolve the existing `BodyFlow*` design system additively, then migrate reviewed presentation callsites in independently testable slices. Keep native navigation, server-owned state and existing models/repositories; add only local presentation policies and Debug/test evidence helpers. Final brand bytes enter through an explicit human approval gate, independently of the text-first UI work.

**Tech Stack:** Swift 6, SwiftUI, existing UIKit representables, iOS 18.0+, Swift Testing, XCTest/XCUITest, existing String Catalogs, asset catalogs and existing SwiftPM dependencies. No dependency/toolchain upgrade, new snapshot package, backend change or media integration.

**Spec:** [Approved design](../specs/2026-09-17-performe-ai-premium-uiux-refinement-design.md), read together with [the complete visual audit](../evidence/2026-09-17-performe-ai-premium-uiux-audit.md).

## Global Constraints

- Direction: B2 — Warm Performance; no new A/B/C selection.
- Public product: **Performe AI**. Public AI assistant: **Flow**. Neither is translated.
- Exactly five tabs: `Hoje / Registrar / Plano / Progresso / Perfil`; `Today / Register / Plan / Progress / Profile`, same order/raw values/stacks.
- Target/scheme/module `BodyFlow`; bundle `com.bodyflow.app`; technical namespaces, persisted keys, telemetry/accessibility IDs and signing/entitlements preserved.
- Auth/Keychain/session restore/logout/invalidation ownership, seven-step server-owned onboarding, Mobile API/Flow API, DTOs, persistence/idempotency and official calculations preserved.
- Keep seven onboarding steps: welcome → body data → objective → routine → persona → consent → completion.
- No new score, historical series/range queries, camera/microphone capture, media upload, account/logout/delete/privacy/support wiring or unavailable capability adapter.
- `anthropic/claude-sonnet-4.6` and all backend settings remain untouched; no paid completion, streaming, prompt/latency optimization, fallback, polling or fake progress.
- iOS 18.0+, iPhone device family 1; preserve portrait and landscape left/right. No iPad scope or project/toolchain migration.
- Dynamic Type through AccessibilityXXXL; interactive targets ≥44×44 pt; normal text ≥4.5:1, large text ≥3:1, essential custom non-text cues ≥3:1; color-independent meaning and Reduce Motion.
- Each slice already supports light/dark and pt-BR/en; Slice 9 reconciles, not postpones, these gates.
- Use `SupportedAppLanguage`, `AppLocalization` and current String Catalogs; no alternate translation system or machine translation of server bodies/options.
- Historical asset/evidence bytes remain identical; new assets require `BRAND_ASSET_APPROVAL_GATE`, including independent explicit AppIcon approval.
- Signed Release Simulator verification uses normal signing and `codesign --verify --deep --strict`; no unsigned-auth workaround.
- Current operation: documentation only, exactly one local documentation commit, no amend/push/PR/merge/deploy, no staging/Production/provider access and no implementation.

---

## 1. Verified baseline and authority

Planning baseline: repo `/Users/eduardohenrique/Developer/performe-ai-client-beta-flow-v1`; branch `codex/performe-ai-client-beta-flow-v1`; HEAD `7ab3e65771d172ad10ee42a7ab1d4e6edba2c775`; parent `39f446a4c3cf8cfa58d21e030769c417e868e0a9`; tree `c6b168c7fe967cdc69f93fad4c68787eb00a9c86`. Worktree/index were empty before this document. Read-only agent status showed previous reviewers completed; scoped open-file inspection found no DS writer and successive Git reads were unchanged. This is a point-in-time observation, not a filesystem lock. Revalidate before every future mutation; divergence from an operation's stated baseline is `STOP_DOCUMENTED`, never auto-reset.

Host observed: `MacBook-Air-de-Eduardo.local`, Darwin 25.6 arm64, user `eduardohenrique`, HOME `/Users/eduardohenrique`, CODEX_HOME unset → `/Users/eduardohenrique/.codex`. LOCAL_DEVELOPMENT for this documentation scope; local source is not proof of a deployed release. Global AGENTS was read; no project/ancestor override applicable to this repo was found. Linked worktree reused; no new branch/worktree. Origin `https://github.com/corehealth-app/agentempp.git`; no upstream assumed and no network Git command needed.

Authority: current operation → approved design/audit → applicable AGENTS → [beta addendum](../../handoffs/2026-09-14-performe-ai-client-beta-flow-v1-addendum.md) binding the dossier at `b4c09e80190fd6ce5c5f59b5193f8a6621554854:docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md` → current code/evidence. Dossier product/preservation/native-capability sections were consulted; old Better Ahead/B-reuse and companion-only instructions are superseded by the explicit addendum/current design, not silently imported. Frozen CI-3 sections do not become execution instructions.

Recent source evidence consulted: [integration](../evidence/2026-09-14-performe-ai-dedicated-mobile-bff-flow-integration.md), [publication lifecycle](../evidence/2026-09-15-performe-ai-onboarding-publication-lifecycle.md), [public brand patch](../evidence/2026-09-16-performe-ai-public-brand-patch.md), [mobile Flow quality](../evidence/2026-09-17-performe-ai-flow-public-response-quality.md). Historical passes and unsigned builds are not fresh verification and do not replace this plan's signed runtime gate. Latency baseline: pipeline 7,334 ms, persistence interval 8.657 s; neither is tap-to-visible latency or a promise.

Local metadata observed: Xcode 27.0 / 27A266a, scheme `BodyFlow`, unit target `BodyFlowTests`, UI target `BodyFlowUITests`, synchronized source/test groups, existing locked SwiftPM dependencies. iPhone 17 Pro / iOS 26.5 Simulator `27291590-659D-4A29-8F45-CA5CA2D154F9` is available and Shutdown. This was listing only; nothing booted, built or tested. Compact/standard/large **logical** rendering sizes are 375×667 / 393×852 / 430×932, not a claim that an available simulator has those exact bounds. Current Flow unit model/repository tests exist; `FlowChatPresentationTests.swift` and `FlowChatUITests.swift` do **not** exist at baseline and are CREATE below.

## 2. Macroplans, dependencies and recommended execution

Three reviewable macroplans in one document; **11 slices / 24 tasks**. No mega-commit. Each task carries a test/review cycle; one future verified commit per completed slice, with intermediate task changes reviewed before advancing. Commit subjects below are proposals, not authorization now.

```text
MACRO A: Foundation & Brand        MACRO B: Core surfaces        MACRO C: Convergence
Slice 0 ─────────────────────────> Slices 2–8 ──────────────────> Slice 9 ──> Slice 10
Slice 1 infrastructure ──> BRAND_ASSET_APPROVAL_GATE ──> public asset integration ─┘
                          (no gate on text-first slices 0, 2–8)
```

Slice 1 final bytes/selection are also a dependency of the **brand-complete** Slice 10 closeout. Without approval, other slices can pass their UI scope, but Slice 1/full-brand gate remain BLOCKED, not waived.

| Batch | Future execution | Reason/checkpoint |
| --- | --- | --- |
| 1 | Slice 0, tasks S0.1–S0.3 | Lock semantic interfaces, contrasts, adaptable shared components and test capture before consumers |
| 2 | S1.1 infrastructure; S1.2 approval preparation; **Slice 8 Flow**; Slice 2 Auth/onboarding | Flow explicitly prioritized; depends on 0, not new asset bytes or a Today adapter. Asset preparation stops before generating/integrating finals |
| 3 | Slice 3 shell/Hoje; Slice 4 Registrar | Review five-stack ownership and data hierarchy, then captured mutation flows |
| 4 | Slice 5 Plano; Slice 6 Progresso | Bounded official snapshots only |
| 5 | Slice 7 Perfil/Library/History/Routine; S1.3 only after approval | Cross-feature visual work without feature wiring |
| 6 | Slice 9 | Reconcile audited adoption, all-language/theme/accessibility gaps, not new architecture |
| 7 | Slice 10 | Full local signed/compiled/visual gates and truthful limits |

This moves Slice 8 from original batch 5 to batch 2 because the request calls it priority and its real code depends only on DS/model contracts. Slice numbering/macro ownership stays unchanged. Independent work after 0: Auth, Flow, Today, Registrar, Plano, Progresso, content, external brand review. Shared `Localizable.xcstrings`, shared DS, `AppRootView`/`AppDependencies`/test helpers are integration choke points: in this same worktree execute serially; no simultaneous writers. Parallel independent reviews or asset approval can occur without source writes. Actual parallel implementation needs later authorization plus isolated branches/worktrees and a catalog merge owner; this plan creates neither.

## 3. FILE MAP

Paths use exact prefixes: **I** = `apps/ios/BodyFlow/BodyFlow/`; **T** = `apps/ios/BodyFlow/BodyFlowTests/`; **U** = `apps/ios/BodyFlow/BodyFlowUITests/`. Every following path expands by its prefix. MODIFY is presentation-only unless explicitly Debug/test harness. H/M/L is regression sensitivity, not security severity. Catalog ownership follows the recommended serialized order 0 → 8 → 2 → 3 → 4 → 5 → 6 → 7 → 9; approved brand entries are integrated by the current catalog owner, never a concurrent writer. No removal/deprecation of public Swift APIs in this plan; deprecated *usage* is noted separately.

| File | Current → planned responsibility | Slice | Action / risk |
| --- | --- | --- | --- |
| I`DesignSystem/BodyFlowColor.swift` | Palette/ambiguous semantic aliases → additive explicit pair roles; preserve palette/old API | 0,9 | MODIFY / M |
| I`DesignSystem/BodyFlowTypography.swift` | Six native aliases → ten named Dynamic Type roles; old aliases retained | 0 | MODIFY / M |
| I`DesignSystem/BodyFlowSpacing.swift` | Six spacings/44 target → same values + width-based gutter helper | 0 | MODIFY / L |
| I`DesignSystem/BodyFlowRadius.swift` | Absent → 8/12/20 geometric role constants | 0 | CREATE / L |
| I`DesignSystem/BodyFlowElevation.swift` | Absent → flat/grouped/native transient policy, optional bounded hero shadow | 0 | CREATE / L |
| I`DesignSystem/BodyFlowMotion.swift` | No shared DS transition durations → bounded durations respecting existing Reduce Motion environment | 0 | CREATE / M |
| I`DesignSystem/BodyFlowPresentationLanguage.swift` | No common UI-locale adapter → pure mapping of current UI environment locale to existing SupportedAppLanguage; no stored preference | 0 | CREATE / M |
| I`DesignSystem/Components/BodyFlowButtonStyle.swift` | Absent → primary/secondary/tertiary/destructive/disabled appearance, no action semantics | 0 | CREATE / M |
| I`DesignSystem/Components/BodyFlowFieldStyle.swift` | Absent → native field chrome modifier, no validation/focus ownership | 0 | CREATE / M |
| I`Features/Shared/FeatureComponents.swift` | Existing state stack/cards/metric/actions → explicit card surface roles and reflow, behavior kept | 0,9 | MODIFY / H |
| I`DesignSystem/Components/ScreenStateView.swift` | State descriptors/brand wrapper → catalog-backed truthful states/semantic surfaces; native root anchor composition | 0,1,3 | MODIFY / H |
| I`Features/Shared/StaleDataBanner.swift` | Stale warning → semantic warning pairing/catalog; preserve banner ID | 0 | MODIFY / H |
| I`Features/Shared/FeatureReadStateView.swift` | State delegation/previous-value ownership → unchanged | all | KEEP / H |
| I`Features/Shared/FeatureDetailView.swift` | Demo destination → keep disclosure; catalog/style only | 7 | MODIFY / M |
| I`Core/Localization/AppLocalization.swift` | Explicit bilingual lookup/formatting locales → unchanged mechanism | all | KEEP / H |
| I`Resources/Localizable.xcstrings` | Partial brand/Flow translations → manually reviewed slice-owned UI/action/accessibility/interpolation entries | 0–9 | MODIFY / M |
| I`Resources/InfoPlist.xcstrings` | Public metadata localization → unchanged unless scan proves approved copy debt | 10 | KEEP / M |
| I`DesignSystem/BrandIdentity.swift` | Exact names/copy → keep names, existing catalog lookup; Flow role rendering at callsite | 1,2,8 | KEEP / M |
| I`DesignSystem/BodyFlowBrandAsset.swift` | Six historical resource mappings → byte/API unchanged | 1 | KEEP / H |
| I`DesignSystem/PerformeAIBrandAsset.swift` | Absent → new optional-resource family mapping; text fallback until approved resources | 1 | CREATE / M |
| I`Resources/Assets.xcassets/PerformeAISymbolLightV1.imageset/Contents.json` | Absent → approved light symbol/export references | 1 | CREATE, gated / M |
| I`Resources/Assets.xcassets/PerformeAISymbolDarkV1.imageset/Contents.json` | Absent → approved dark symbol/export references | 1 | CREATE, gated / M |
| I`Resources/Assets.xcassets/PerformeAISymbolMonoV1.imageset/Contents.json` | Absent → approved monochrome symbol | 1 | CREATE, gated / M |
| I`Resources/Assets.xcassets/PerformeAISymbolNegativeV1.imageset/Contents.json` | Absent → approved negative symbol | 1 | CREATE, gated / M |
| I`Resources/Assets.xcassets/PerformeAIWordmarkLightV1.imageset/Contents.json` | Absent → approved light exact wordmark | 1 | CREATE, gated / M |
| I`Resources/Assets.xcassets/PerformeAIWordmarkDarkV1.imageset/Contents.json` | Absent → approved dark exact wordmark | 1 | CREATE, gated / M |
| I`Resources/Assets.xcassets/PerformeAILockupV1.imageset/Contents.json` | Absent → approved lockup appearance mapping | 1 | CREATE, gated / M |
| I`Resources/Assets.xcassets/PerformeAIAppIconV1.appiconset/Contents.json` | Absent → three separately approved candidates; never mutate AppIcon | 1 | CREATE, separately gated / H |
| `assets/brand/performe-ai-public-v1/manifest.json` | Absent → sources/license/roles/approval/hash/callsite ledger | 1 | CREATE / H |
| `assets/brand/performe-ai-public-v1/review.md` | Absent → exact visual approval records/review exports | 1 | CREATE / M |
| `assets/brand/performe-ai-public-v1/masters/` and `exports/` | Absent → files enumerated in §5, imported only after external creation/explicit approval | 1 | CREATE, gated / H |
| `apps/ios/BodyFlow/BodyFlow.xcodeproj/project.pbxproj` | Current target/signing/icon → **only** AppIcon catalog name may change after separate icon approval | 1 | CONDITIONAL MODIFY / H; all other settings KEEP |
| I`Resources/Info.plist` | Bundle/orientations/Keychain-related build identity → unchanged; no new entitlements file | all | KEEP / H |
| I`Features/Auth/SplashView.swift` | Launch text/spinner → deep teal truthful launch, approved text before asset gate | 2,1 | MODIFY / M |
| I`Features/Auth/AuthFieldMessage.swift` | Form layout/errors/announcements → one vertical title/brand, DS field/error hierarchy/catalog | 2 | MODIFY / H |
| I`Features/Auth/SignInView.swift` | Sign-in form → same fields/actions styled, keyboard reachable | 2 | MODIFY / H |
| I`Features/Auth/SignUpView.swift` | Signup form → same secure/autofill/confirmation behavior styled | 2 | MODIFY / H |
| I`Features/Auth/PasswordRecoveryView.swift` | Recovery → same neutral result, hierarchy/catalog | 2 | MODIFY / H |
| I`Features/Auth/EmailConfirmationView.swift` | Await/return/Debug confirm → truthful state hierarchy, Debug gating unchanged | 2 | MODIFY / H |
| I`Features/Onboarding/OnboardingContainerView.swift` | Seven-step task/commands → semantic grouping/progress, same submit/finish ownership | 2 | MODIFY / H |
| I`Features/Onboarding/OnboardingViewSupport.swift` | Header/issues → semantic text/errors/reflow/catalog | 2 | MODIFY / H |
| I`Features/Onboarding/WelcomeStepView.swift` | Name/country/timezone/search → readable groups, same stored codes | 2 | MODIFY / H |
| I`Features/Onboarding/BodyDataStepView.swift` | Validated body fields → grouped optional/required fields, same units/nil semantics | 2 | MODIFY / H |
| I`Features/Onboarding/ObjectiveStepView.swift` | Three real objectives → readable selection rows, same enums/IDs | 2 | MODIFY / H |
| I`Features/Onboarding/RoutineStepView.swift` | Optional routine selections → reflow/grouping, no silent default | 2 | MODIFY / H |
| I`Features/Onboarding/PersonaStepView.swift` | Server styles → Flow wording, same server option count/names | 2 | MODIFY / H |
| I`Features/Onboarding/ConsentStepView.swift` | Exact documents/actions → readable body/review, required/optional distinction, unchecked controls | 2 | MODIFY / H |
| I`Features/Onboarding/OnboardingCompletionView.swift` | Review/finish → hierarchy only, same authoritative finish | 2 | MODIFY / H |
| I`App/AppRootView.swift` | Root state/session transitions → catalog/DS loading/error **appearance only**, no state switch changes | 2 | MODIFY / H |
| I`App/AppShellView.swift` | Native stacks/tabs/sheets → one brand anchor, catalog labels, same routes/task ownership | 3 | MODIFY / H |
| I`App/AppTab.swift` | Five technical cases/Portuguese title → additive `title(for:)`, preserve old API and IDs | 3 | MODIFY / H |
| I`App/TabBarAccessibilityConfigurator.swift` | Native technical IDs → same IDs, catalog label usage if required | 3 | CONDITIONAL MODIFY / H |
| I`Features/Today/TodayRootView.swift` | DTO presentation + state/entry links → official metric hierarchy, Flow/Library independently reachable | 3 | MODIFY / H |
| I`Features/Today/TodayHeaderSection.swift` | Day/protocol/freshness → one contextual title, secondary provenance | 3 | MODIFY / H |
| I`Features/Today/TodayEnergySection.swift` | Two official energy meanings → paired named metrics/reflow, no merged score | 3 | MODIFY / H |
| I`Features/Today/TodayProteinSection.swift` | Official protein values → semantic values/progress only when supplied | 3 | MODIFY / H |
| I`Features/Today/TodayHydrationSection.swift` | Official water values → same null/percentage semantics, readable units | 3 | MODIFY / H |
| I`Features/Today/TodayAttentionSection.swift` | Received pending information → priority grouping without new task actions | 3 | MODIFY / H |
| I`Features/Today/TodayRecordsSection.swift` | Confirmed records → clearer units/provenance/reading order | 3 | MODIFY / H |
| I`Features/Today/TodayRoutineSection.swift` | Existing occurrence routes → same ownership/context, cohesive surface | 3 | MODIFY / H |
| I`Features/Today/TodayBlockCard.swift` | Official nullable block → same fields/progress, concise emphasis | 3 | MODIFY / H |
| I`Features/Today/TodayRecommendationsSection.swift` | Independent content read/tracking → hierarchy only; no extra task/impression | 3,7 | MODIFY / H |
| I`Features/Mascot/MascotCardView.swift` | Official compact state/debug art → supporting emphasis after core metrics | 3,7 | MODIFY / H |
| I`Features/Mascot/MascotDetailView.swift` | State/provenance detail → same data, shared semantic surfaces | 7 | MODIFY / H |
| I`Features/Mascot/MascotPlaceholderArtwork.swift` | Historical Debug artwork → untouched bytes/state/motion policy | all | KEEP / M |
| I`Features/Register/RegisterRootView.swift` | Fixture actions/disclaimer → grouped existing entry choices, truth preserved | 4 | MODIFY / H |
| I`Features/Register/RegistrationSheet.swift` | Route/mutation/sheet ownership → only hierarchy/detent/focus appearance | 4 | MODIFY / H |
| I`Features/Register/MealCaptureSourceView.swift` | Three local choices → Photo/Audio/Text + explicit local-sample labels; no permission | 4 | MODIFY / H |
| I`Features/Register/MealDemonstrationSourceView.swift` | Local media sample → same explicit demo provenance | 4 | MODIFY / H |
| I`Features/Register/MealTextDraftView.swift` | Draft/analyze → same guard and input, DS form/status | 4 | MODIFY / H |
| I`Features/Register/MealProposalView.swift` | Official proposal/items/totals → value cells, Confirm/Edit/Cancel hierarchy | 4 | MODIFY / H |
| I`Features/Register/MealProposalEditorView.swift` | First-item correction → visually explicit first-item scope, same parsing | 4 | MODIFY / H |
| I`Features/Register/WorkoutRegistrationView.swift` | UIKit/native fields/buttons → intrinsic sizing/style, unchanged coordinators | 4 | MODIFY / H |
| I`Features/Register/WorkoutProposalView.swift` | Estimate/review/UIKit buttons → semantic hierarchy and estimate label | 4 | MODIFY / H |
| I`Features/Register/HydrationRegistrationView.swift` | Quick/custom/date/shared UIKit → adaptive controls, same ml/date behavior | 4 | MODIFY / H |
| I`Features/Register/WeightRegistrationView.swift` | Decimal/date → shared adaptive control style, same kg parsing | 4 | MODIFY / H |
| I`Features/Register/RegistrationOperationSummary.swift` | Bounded recovery/result → catalog/semantic feedback, same allowed recovery | 4 | MODIFY / H |
| I`Features/Plan/PlanRootView.swift` | State/current snapshot → clearer real plan hierarchy | 5 | MODIFY / H |
| I`Features/Plan/PlanDetailView.swift` | Existing detail reload → same reload, shared sections | 5 | MODIFY / H |
| I`Features/Plan/PlanComponents.swift` | `PlanPresentation`/metadata → grouped sections + explicit language formatting argument | 5 | MODIFY / H |
| I`Features/Progress/ProgressRootView.swift` | Snapshot/block route → official values first | 6 | MODIFY / H |
| I`Features/Progress/ProgressComponents.swift` | XP/streak/medals/measurements → same official values/IDs, calmer hierarchy/catalog | 6 | MODIFY / H |
| I`Features/Progress/Block7700DetailView.swift` | Received descriptor → same optional percentage/provenance | 6 | MODIFY / H |
| I`Features/Profile/ProfileRootView.swift` | Fixture identity/persona gated loads → demo-aware grouping, no live settings invented | 7 | MODIFY / H |
| I`Features/Profile/CoachPersonaPickerView.swift` | Server options/save/cancel → Flow appearance/catalog, same ownership | 7 | MODIFY / H |
| I`Features/Library/LibraryRootView.swift` | Filters/cursors/tracking/cover ownership → scoped header/card styling, not refactor of ownership code | 7 | MODIFY / H |
| I`Features/Library/PublishedContentCard.swift` | Authorized cards/actions → clear editorial hierarchy, AX separate open retained | 7 | MODIFY / H |
| I`Features/Library/PublishedContentDetailView.swift` | Bounded article/mutations → same canonical content/actions, style metadata | 7 | MODIFY / H |
| I`Features/Library/ContentCoverView.swift` | Authorized image/cache-state/placeholder → radius/fill only, same bounds/authorization | 7 | MODIFY / H |
| I`Features/Library/BodyFlowMarkdownView.swift` | Canonical renderer/link policy → token mapping only; do not replace renderer | 7 | MODIFY / H |
| I`Features/History/MainHistoryView.swift` | Read-only lists/states → cohesive existing rows | 7 | MODIFY / H |
| I`Features/History/HistoryMealLogRowView.swift` | Meal row → same received fields, locale/style | 7 | MODIFY / M |
| I`Features/History/HistoryMealLogDetailView.swift` | Nullable meal detail → clear units/nil and existing metadata | 7 | MODIFY / H |
| I`Features/History/HistoryWorkoutDetailView.swift` | Nullable workout detail → same estimate/read-only semantics | 7 | MODIFY / H |
| I`Features/Routine/RoutineListView.swift` | Kind/item list → existing schedules, cohesive surfaces | 7 | MODIFY / H |
| I`Features/Routine/RoutineDetailView.swift` | Occurrence/item routes → same actions/context, grouping only | 7 | MODIFY / H |
| I`Features/Routine/RoutineActionSheet.swift` | Explicit confirm/receipt/recovery → one dominant confirmed action, same attempts | 7 | MODIFY / H |
| I`Features/Routine/RoutineSnoozeView.swift` | Existing presets/custom date → adaptive options, same patient timezone | 7 | MODIFY / H |
| I`Features/Routine/RoutineHistoryView.swift` | Paginated received events → explicit existing patient-zone formatting, same cursor | 7 | MODIFY / H |
| I`Features/FlowChat/FlowChatView.swift` | Plain messages/composer/wait → reader-friendly adaptive UI/semantic roles/scroll | 8 | MODIFY / H |
| I`Features/FlowChat/FlowChatPresentation.swift` | Absent → pure can-submit/scroll/role presentation policies | 8 | CREATE / H |
| I`Features/PreviewSupport/FlowChatPreviewSupport.swift` | Absent → deterministic UI-only mock states under whole-file DEBUG | 8 | CREATE / M |
| I`App/AppDependencies.swift` | Real/Unavailable/Demo injection → ONLY Debug demo Flow fixture selection; Release branch untouched | 8 | CONDITIONAL MODIFY / H |
| I`Features/FlowChat/FlowChatModel.swift` / I`Core/FlowChat/` | Guard/key/history/API ownership → unchanged | 8 | KEEP / H |
| I`App/AppLaunchConfiguration.swift` | Debug/release fixture resolution → unchanged; new Flow helper reads args only inside Debug demo boundary | 8 | KEEP / H |
| I`Features/PreviewSupport/Prompt13PreviewSupport.swift` / I`Features/PreviewSupport/Prompt14PreviewSupport.swift` | Existing isolated hosts → reused; no success fixture in Release | all | KEEP / M |
| I`Core/` other than catalog callsites / existing session coordinators | Official contracts/state/caches/calculations → unchanged | all | KEEP / H |

### Test/tool file map (no production helpers hidden in tests)

| File | Responsibility / slice | Action / risk |
| --- | --- | --- |
| T`BodyFlowSemanticColorTests.swift` | Exact hex pairs/contrast/control roles / 0 | CREATE / M |
| T`BodyFlowPremiumRenderingTests.swift` | Native render attachments/all Dynamic Type role layouts / 0,9 | CREATE / M |
| T`PremiumRenderingTestSupport.swift` | Test-only native render/capture helper / 0 | CREATE / L |
| T`BodyFlowComponentPolicyTests.swift` | Radius/spacing/action roles/native control policies / 0 | CREATE / M |
| T`PerformeAIBrandAssetTests.swift` | Missing-resource fallback and approved resource mapping / 1 | CREATE / H |
| T`FlowChatPresentationTests.swift` | Pure can-submit/reader policy / 8 | CREATE / H |
| T`FlowChatPreviewSupportTests.swift` | Debug mock state selection/production exclusion / 8 | CREATE / H |
| U`PremiumUIUXUITestSupport.swift` | Reviewed capture naming/theme/locale/matrix/assertions; produced in foundation so Flow can run before Auth; old evidence allowlist unchanged / 0–10 | CREATE / M |
| U`PremiumAuthOnboardingUITests.swift` | Auth/7-step keyboard/long consent/reset-free resume visual assertions / 2 | CREATE / H |
| U`PremiumCoreSurfacesUITests.swift` | Five tabs/Hoje/Plan/Progress/demo-vs-U local capture / 3,5,6 | CREATE / H |
| U`PremiumRegistrationUITests.swift` | Capture/proposal/correction/confirm/receipt/AX bridges / 4 | CREATE / H |
| U`PremiumContentProfileUITests.swift` | Existing persona/content/history/routine routes and confirmations / 7 | CREATE / H |
| U`FlowChatUITests.swift` | New local Flow state/reader/keyboard/long-history tests / 8 | CREATE / H |
| U`PremiumConvergenceUITests.swift` | Theme/locale/AX/motion/rotations/end-to-end **local** coverage / 9,10 | CREATE / H |
| U`PremiumPerformanceUITests.swift` | XCTest launch/local scrolling/render baselines, no provider calls / 10 | CREATE / M |
| T`AppTabTests.swift`, `LocalizationContractTests.swift`, `ScreenStateTests.swift` | Add bilingual labels/DS-state catalog assertions, retain technical contracts / 0,3,9 | MODIFY / H |
| T`AuthFormStateTests.swift`, `OnboardingPresentationTests.swift`, `PlanPresentationTests.swift`, `ProgressPresentationTests.swift`, `RegistrationPresentationTests.swift`, `HistoryPresentationTests.swift`, `RoutinePresentationTests.swift` | Add catalog/format assertions only for presentation changes; preserve current values/enum policies / owning slice | MODIFY / H |
| Existing T model/contract/session/content/key tests and U`BodyFlowUITests.swift`, Prompt13/14 tests/support | Must-pass regressions; contextual expected visible copy updated only after proving approved behavior, no weaker assertions / all | KEEP or narrowly MODIFY copy assertions / H |
| `scripts/uiux/premium-surface-scan.mjs` | Source/catalog/compiled resource classifications, no credentials/raw telemetry / 10 | CREATE / M |
| `scripts/uiux/premium-surface-scan.test.mjs` | Node built-in scanner positive/negative fixtures / 10 | CREATE / M |
| `docs/superpowers/evidence/2026-09-17-performe-ai-premium-uiux-implementation/README.md` | Future slice evidence ledger, commands/limits/gates, approval and review references / 0–10 | CREATE / L |

No chart implementation file: there is no historical dataset at this HEAD. No navigation/material/progress API rewrite: current native stacks, `ScreenStateView`, existing `ProgressView`, official-percent block presentation and `BodyFlowReduceMotionPolicy` are reused. DEPRECATE usages gradually: coral-as-error, gold-as-global-dark-accent, equal filled review buttons, redundant brand strip/clipping, fixed UIKit visual heights, hard-coded public Portuguese. KEEP API/keys/bytes, do not bulk replace.

## 4. Shared interfaces and test commands

### 4.1 Additive DS contract (produced in Slice 0)

`BodyFlowColor.Role: CaseIterable, Sendable`; `static func hex(_ role: Role, dark: Bool) -> UInt32`; `static func color(_ role: Role) -> Color` through existing dynamic UIColor resolver. These names are the sole new shared role API; old `background`, `primaryText`, etc. remain until reviewed migration. Values are copied from spec, not selected again:

| Role | Light | Dark |
| --- | --- | --- |
| backgroundPrimary | F6EFE3 | 071E20 |
| backgroundSecondary | FFFCF6 | 102D30 |
| surfaceElevated / surfaceInteractive | FFFFFF | 193C40 |
| brandPrimary | 006D67 | 55D5C7 |
| onPrimary | FFFFFF | 071E20 |
| brandSecondary | 55D5C7 | 55D5C7 |
| accentCoral | FF7F6B | FF7F6B |
| textPrimary | 222528 | F6EFE3 |
| textSecondary | 4D6260 | B3C7C2 |
| textTertiary | 596E6B | 97ACA8 |
| borderSubtle | D8DED7 | 355155 |
| controlBoundary | 627A75 | 8CA7A1 |
| feedbackPositive | 006D67 | 7CDDCA |
| feedbackWarning | 8A5A00 | F2C976 |
| feedbackDestructive | B42332 | FF98A3 |
| disabledFill | F0F0E8 | 193C40 |
| disabledText | 596E6B | 97ACA8 |
| heroBackground | 003B3B | 003B3B |
| onHero / heroSupporting | F6EFE3 / B3C7C2 | F6EFE3 / B3C7C2 |
| achievement / onAchievement | D4AF7A / 222528 | D4AF7A / 222528 |

`BodyFlowTypography`: `largeTitle`, `screenTitle`, `sectionTitle`, `cardTitle`, `body`, `supporting`, `metricLarge`, `metricSmall`, `button`, `caption`. LargeTitle `.largeTitle.bold()`, screenTitle `.title2.weight(.semibold)`, headings/buttons `.headline.weight(.semibold)`, supporting `.callout`, metrics `.largeTitle/.title2.weight(.semibold).monospacedDigit()`. Existing `title/headline/callout` retained. No additional fixed-size display font; editorial display uses `largeTitle`.

`BodyFlowSpacing.screenGutter(usableWidth: CGFloat) -> CGFloat`: 16 for usable width <390, otherwise 24; keep xxs/xs/sm/md/lg/xl=4/8/12/16/24/32 and minimumTapTarget=44. Threshold is a presentational compact/comfortable breakpoint, test both sides/landscape; no device-model branch. `BodyFlowRadius.small/field/card: CGFloat = 8/12/20`. `BodyFlowElevation.heroOpacity/heroY/heroBlur = 0.06/2/12`, used only optional light hero; native transient surfaces retain system geometry. `BodyFlowMotion.duration(reduceMotion: Bool, disclosure: Bool) -> Double`: 0 when reduced, otherwise 0.20/0.25 seconds; no animation timer/phases.

`BodyFlowSurfaceRole: Sendable { legacy, card, hero, elevated }`; `BodyFlowCard.init(surface: BodyFlowSurfaceRole = .legacy, @ViewBuilder content: () -> Content)`. `.legacy` preserves old appearance until each owner opts in; `.card` opaque semantic fill/no outline; `.hero` only paired onHero text; `.elevated` field/sheet inner content, not nested cards. End Slice 9 may change default to `.card` only after full caller review; retain legacy role/API for rollback.

`BodyFlowButtonRole { primary, secondary, tertiary, destructive }`; `BodyFlowButtonStyle.init(role: BodyFlowButtonRole)` conforms `ButtonStyle`, reads enabled state and uses **minimum** 44 height, content padding 12/16, radius 12, native tap callbacks unchanged. `.bodyFlowField()` view modifier adds semantic elevated fill/boundary/minimum target to existing labeled native fields; never wraps a second accessibility control or owns parsing. Existing `FixtureMetricRow(title:value:systemImage:)`, `FeatureActionLabel(...)`, `FeatureStateContentStack(showsStaleBanner:content:)`, `ScreenStateView(state:retryAction:accessibilityIdentifier:titleAccessibilityIdentifier:)` signatures retained.

No shared selected-UI-language property was found in current shell code. Consumers use `@Environment(\.locale)` and a new **pure presentation adapter** `BodyFlowPresentationLanguage.resolve(_ locale: Locale) -> SupportedAppLanguage`: language code `en` → `.englishUnitedStates`, otherwise existing Portuguese fallback `.portugueseBrazil`. This invokes the existing lookup/formatting machinery without adding a settings screen, persisted key or server-locale mutation. UI language and authoritative document/content locale are distinct; do not translate or rewrite server bodies to match UI. Any request to synchronize saved server language with global UI language is a separate behavior decision, not silently added here.

### 4.2 Future local command setup — not run in this planning task

Run from repo root only after plan review/execution authorization. Revalidate host/Git/scoped writer first. No credentials required, no `.xcconfig` content read. Use already available locked package checkout cache; if package resolution needs network/downloads, record prerequisite before continuing, no version changes. Revalidate selected Simulator ID each session. Helpers below are temporary shell functions, not installed wrappers/PATH changes:

```sh
UIUX_PROJECT=apps/ios/BodyFlow/BodyFlow.xcodeproj
UIUX_DEST='platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9'
mkdir -p /Users/eduardohenrique/.local/share/performe-ai/premium-uiux
UIUX_RUN_DIR=$(mktemp -d /Users/eduardohenrique/.local/share/performe-ai/premium-uiux/run.XXXXXX)
chmod 700 "$UIUX_RUN_DIR"
uiux_test() {
  local uiux_label="$1"
  shift
  xcodebuild test -project "$UIUX_PROJECT" -scheme BodyFlow \
    -configuration Debug -destination "$UIUX_DEST" \
    -derivedDataPath "$UIUX_RUN_DIR/DerivedData-Debug" \
    -resultBundlePath "$UIUX_RUN_DIR/$uiux_label.xcresult" \
    -disableAutomaticPackageResolution -parallel-testing-enabled NO "$@"
}
uiux_release() {
  local uiux_label="$1"
  xcodebuild build -project "$UIUX_PROJECT" -scheme BodyFlow \
    -configuration Release -destination "$UIUX_DEST" \
    -derivedDataPath "$UIUX_RUN_DIR/DerivedData-$uiux_label" \
    -disableAutomaticPackageResolution
  local uiux_rc=$?
  test "$uiux_rc" -eq 0 || return "$uiux_rc"
  codesign --verify --deep --strict \
    "$UIUX_RUN_DIR/DerivedData-$uiux_label/Build/Products/Release-iphonesimulator/BodyFlow.app"
}
```

Use distinct RED/GREEN/regression labels so `.xcresult` is never overwritten. Expected each test call: TEST SUCCEEDED, selected suites actually executed, zero failures/skips/unexplained expected failures; RED must instead fail on the specified assertion/missing new role, not destination/auth/package setup. A build alone does not prove all tests ran. Inspect Xcode result test list and attachments. Build/sign gate: BUILD SUCCEEDED + codesign exit 0. Preserve prior failures separately; no weaken/skip/snapshot-blind-update. `xcodebuild analyze -project "$UIUX_PROJECT" -scheme BodyFlow -configuration Debug -destination "$UIUX_DEST" -derivedDataPath "$UIUX_RUN_DIR/DerivedData-Debug" -disableAutomaticPackageResolution` is the native compiler/static-analysis gate; no unverified SwiftLint command. Swift typechecking is part of test/build. `git diff --check` always required; changed-only style review, no whole-tree formatting.

Evidence each task: `.xcresult` test list + attachments + red failure reason/green assertions, source SHA, build/sign status, reviewed diff. Repository evidence ledger holds only sanitized summaries and approved synthetic screenshots; private raw bundles remain in `$UIUX_RUN_DIR`. Never commit runtime/private config, user tokens, raw-message telemetry or authentication hierarchy containing credentials. This plan's future `PremiumUIUXUITestSupport` creates fresh names independently; do not broaden the historical support's 13-image allowlist.

### 4.3 Common slice acceptance, baseline and rollback

Before each slice: fresh host/Git/writer baseline, allowlist, existing selected suites, known failures, approved synthetic local fixtures, resource gate before heavy build (disk/memory/material impact; no polling loop). After each task: RED where policy/component testable → smallest code → GREEN → neighboring contracts → reviewed light/dark pt-BR/en captures/AX → no API/ID/extra-call diff. A purely visual layout starts with a failing semantic/layout assertion plus a reviewed current screenshot, not an arbitrary pixel equality assertion.

Every completed slice: focused/relevant UI suites PASS; signed Release build PASS; functional model behavior preserved; applicable light/dark/locales/accessibility matrix PASS; screenshots/hierarchies/evidence; Critical 0 / Important 0 **actual** review, not assumed; no new unexplained failure; exact diff/asset-byte/secret scan; authorized scoped commit then clean index/worktree. A missing connected provider gate remains NOT VERIFIED; it cannot be called a full runtime pass. Only a separately authorized synthetic connected gate may exercise real auth/Flow. No preview/deploy or paid completion is necessary for local visual acceptance.

Future rollback: record `git show --name-only --format=fuller <slice-sha>` and review dependency consumers. On clean/understood worktree use scoped `git revert <slice-sha>` after review; no broad restore/reset. Roll back downstream consumers first if reverting DS; keep earlier standalone verified slices. Slice 1 mapping/catalog can select preserved bytes with approved public-name fallback; never overwrite assets or revive public legacy names to hide failure. No database migration/feature flag required. Each slice's commit subject below identifies its rollback unit.

## 5. Brand deliverables and mandatory STOP

**BRAND_ASSET_APPROVAL_GATE** blocks final logo/wordmark/splash/icon integration. The current direction is approved, **none of these final bytes is approved**. No procedural final SVG, no automatic rerender of historical family, no logo-generation authorization inferred from this plan. External designer/explicit later creative operation supplies these files in `assets/brand/performe-ai-public-v1/`:

| Approval files (relative to that directory) | Exact format/dimensions/variants |
| --- | --- |
| `masters/symbol-light.svg`, `symbol-dark.svg`, `symbol-mono.svg`, `symbol-negative.svg` | Vector near-square, abstract P/trajectory distinct from B; corresponding `exports/*.pdf` vector for native catalog; review `exports/symbol-*-1024.png` 1024×1024; optical 16/24/32/48 pt sheets |
| `masters/wordmark-light.svg`, `wordmark-dark.svg`, `wordmark-mono.svg` | Exact Performe AI, intrinsic horizontal bounds; vector PDF exports; review sheets at 140/240 pt widths; no fixed stretched ratio |
| `masters/lockup-light.svg`, `lockup-dark.svg`, `lockup-mono.svg`, `lockup-negative.svg` | Vector/PDF intrinsic lockup; review PNG 1600×400 canvas with ≥¼-symbol clear space, not forced art ratio |
| `exports/splash-review-standard.png`, `splash-review-compact.png`, `splash-review-large.png` | Standard 1179×2556 px review; compact/large review at 375×667/430×932 logical 2×; **separate** approved negative symbol/wordmark PDFs used at 96 pt/≤240 pt intrinsic width, not screen-as-image |
| `exports/appicon-default-1024.png`, `appicon-dark-1024.png`, `appicon-tinted-1024.png` | 1024×1024 opaque square, no baked corner mask/text; proposed central 70% optical zone; Home Screen review; tinted only if supported/approved for existing pipeline |
| `review.md`, `manifest.json` | Version/source-author/license/font-license/export settings/roles/optical variants/callsite allowlist; explicit user approval reference, **actual** SHA-256 per approved master/export |

User approves the review sheet **and named exact files/variants**, with AppIcon approval explicit separately. Record approval time/reference/files and run `shasum -a 256` on those exact approved files after approval; hashes identify bytes, not proof of approval. Any byte/contour change invalidates its approval. Manifest statuses `pending`/`approved`, no fake hashes/date. Missing optional photography defaults to none; no image license assumption. Import only approved PDFs/PNGs with `Contents.json` settings verified in native build; SVG masters never forced into asset catalog. Do not duplicate splash into a large bitmap.

Historical byte guard: before/after integration compare all tracked `assets/brand/` files existing at planning baseline and all existing files under `I Resources/Assets.xcassets` to `7ab3e657`; exclude only **new** PerformeAI sets/masters/exports. `git diff --name-only 7ab3e657 -- assets/brand apps/ios/BodyFlow/BodyFlow/Resources/Assets.xcassets` must show exclusively new approved files, never old modified/deleted paths. Hash old family before/after actual import. AppIcon build-name change is separately allowed only in S1.3 after icon approval; signing/bundle unchanged.

## MACRO A — FOUNDATION & BRAND

### Task S0.1 — Semantic token pairs and native geometry/type

**Files:** MODIFY I`DesignSystem/BodyFlowColor.swift`, `BodyFlowTypography.swift`, `BodyFlowSpacing.swift`; CREATE I`DesignSystem/BodyFlowRadius.swift`, `BodyFlowElevation.swift`, `BodyFlowMotion.swift`, `BodyFlowPresentationLanguage.swift`; CREATE T`BodyFlowSemanticColorTests.swift`, `BodyFlowComponentPolicyTests.swift`.

**Interfaces:** consumes current palette/native styles and existing Reduce Motion effective value; produces exact DS roles/signatures in §4.1. No removed alias and no cross-feature API.

- [ ] Write table-driven exact-hex tests for every §4.1 role in both themes and these RED assertions; missing roles initially fail compilation for this precise task, not unrelated setup:

```swift
import Foundation
import Testing
@testable import BodyFlow
@Suite struct BodyFlowComponentPolicyTests {
    @Test func geometryAndMotion() {
        #expect(BodyFlowRadius.field == 12)
        #expect(BodyFlowRadius.card == 20)
        #expect(BodyFlowSpacing.minimumTapTarget == 44)
        #expect(BodyFlowSpacing.screenGutter(usableWidth: 375) == 16)
        #expect(BodyFlowSpacing.screenGutter(usableWidth: 390) == 24)
        #expect(BodyFlowMotion.duration(reduceMotion: true, disclosure: true) == 0)
        #expect(BodyFlowMotion.duration(reduceMotion: false, disclosure: false) == 0.2)
        #expect(BodyFlowPresentationLanguage.resolve(Locale(identifier: "en_US")) == .englishUnitedStates)
        #expect(BodyFlowPresentationLanguage.resolve(Locale(identifier: "pt_BR")) == .portugueseBrazil)
    }
}
```

- [ ] Run `uiux_test s0-1-red -only-testing:BodyFlowTests/BodyFlowSemanticColorTests -only-testing:BodyFlowTests/BodyFlowComponentPolicyTests`. Record missing new roles/assertions; setup failure does not count as RED.
- [ ] Implement enum/hex switch with **all** exact pairs from §4.1, retaining old palette constants and aliases. Reuse current dynamic UIColor technique:

```swift
static func color(_ role: Role) -> Color {
    Color(uiColor: UIColor { traits in
        let value = hex(role, dark: traits.userInterfaceStyle == .dark)
        return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                       green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255, alpha: 1)
    })
}
static func screenGutter(usableWidth: CGFloat) -> CGFloat {
    usableWidth < 390 ? md : lg
}
// In BodyFlowMotion:
static func duration(reduceMotion: Bool, disclosure: Bool) -> Double {
    reduceMotion ? 0 : (disclosure ? 0.25 : 0.20)
}
// In BodyFlowPresentationLanguage (import Foundation):
static func resolve(_ locale: Locale) -> SupportedAppLanguage {
    locale.language.languageCode?.identifier == "en"
        ? .englishUnitedStates : .portugueseBrazil
}
```

- [ ] Add local sRGB tests with this actual luminance function, comparing textPrimary/Secondary/Tertiary/brandPrimary/feedback roles on all three theme surfaces ≥4.5, controlBoundary ≥3, onPrimary on brandPrimary ≥4.5, onHero/heroSupporting on hero ≥4.5, disabledText on disabledFill ≥4.5. Decorative coral/aqua/borderSubtle are not asserted as valid text roles:

```swift
import Foundation
private func luminance(_ hex: UInt32) -> Double {
    func linear(_ channel: UInt32) -> Double {
        let c = Double(channel) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear((hex >> 16) & 255)
         + 0.7152 * linear((hex >> 8) & 255) + 0.0722 * linear(hex & 255)
}
private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
    let x = luminance(a), y = luminance(b)
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
}
```

- [ ] Run `uiux_test s0-1-green -only-testing:BodyFlowTests/BodyFlowSemanticColorTests -only-testing:BodyFlowTests/BodyFlowComponentPolicyTests -only-testing:BodyFlowTests/ProgressPresentationTests -only-testing:BodyFlowTests/ScreenStateTests`; exact pairs/unchanged policies PASS. Review all-category font mapping/no fixed point shrink.
- [ ] Record token/contrast table and reviewed allowlist in future evidence README. No slice commit until S0.3 verified; proposed subject `refactor(ui): establish Performe AI semantic design tokens`. Rollback unit Slice0; consumers must be reverted before removing new roles.

### Task S0.2 — Shared surfaces, actions, fields and state feedback

**Files:** CREATE I`DesignSystem/Components/BodyFlowButtonStyle.swift`, `BodyFlowFieldStyle.swift`; MODIFY I`Features/Shared/FeatureComponents.swift`, `StaleDataBanner.swift`, I`DesignSystem/Components/ScreenStateView.swift`, I`Resources/Localizable.xcstrings`; MODIFY T`ScreenStateTests.swift`, `LocalizationContractTests.swift`; extend T`BodyFlowComponentPolicyTests.swift`.

**Interfaces:** consumes §4.1 roles/spacing/type; produces card surface initializer, button style and field modifier in §4.1. Existing retry closure/descriptor/IDs/read state signatures and enums remain intact.

- [ ] Add bilingual RED to `LocalizationContractTests`: explicit calls `try AppLocalization.string("state.retry", for: .englishUnitedStates) == "Try again"` and Portuguese “Tentar novamente”; test state-unavailable has no retry, offline/recoverable have retry, loading has none, existing IDs unchanged. Renderable role policies cover primary vs secondary and disabled without changing enabled semantics.
- [ ] Run `uiux_test s0-2-red -only-testing:BodyFlowTests/LocalizationContractTests -only-testing:BodyFlowTests/ScreenStateTests -only-testing:BodyFlowTests/BodyFlowComponentPolicyTests`; missing catalog/appearance expectations fail, no existing state semantics weakened.
- [ ] Implement `.card` fill/no outline opt-in while `.legacy` preserves current default; keep `FeatureStateContentStack` stale content. Make minimum-height wrapping button labels, for example primary label:

```swift
configuration.label
    .font(BodyFlowTypography.button)
    .padding(.horizontal, BodyFlowSpacing.md)
    .padding(.vertical, BodyFlowSpacing.sm)
    .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
    .foregroundStyle(BodyFlowColor.color(isEnabled ? .onPrimary : .disabledText))
    .background(BodyFlowColor.color(isEnabled ? .brandPrimary : .disabledFill),
                in: RoundedRectangle(cornerRadius: BodyFlowRadius.field))
```

  Secondary uses brandPrimary text + controlBoundary outline on elevatedSurface; tertiary no fill with label/affordance; destructive explicit feedbackDestructive label/control, not coral. Preserve native pressed indication; no alpha that breaks contrast. Field modifier leaves secure/keyboard/autofill binding on original control. `ScreenState` descriptors use existing catalog lookup/string localization in the same switch; never add connectivity detection. Stale warning uses warning foreground on opaque card + text/icon, ID unchanged. Brand wrapper structural consolidation waits for S3.1; no global clipping change here.
- [ ] Add reviewed entries `state.loading.title/detail`, `state.empty.title/detail`, `state.error.title/detail`, `state.offline.title/detail`, `state.unavailable.title`, `state.retry`, `state.stale.detail` in pt-BR/en. Preserve “Indisponível nesta versão” / “Unavailable in this version”; unavailable not empty; do not introduce retry to unsupported state.
- [ ] Run `uiux_test s0-2-green -only-testing:BodyFlowTests/LocalizationContractTests -only-testing:BodyFlowTests/ScreenStateTests -only-testing:BodyFlowTests/FeatureReadStateTests -only-testing:BodyFlowTests/FeatureActionLabelTests -only-testing:BodyFlowTests/BodyFlowComponentPolicyTests`. Expect previous-value/ID/retry contracts and selected translations PASS. Review accessibility role/order/no duplicate actionable field wrapper.
- [ ] Evidence: state/button/field role mapping and read-state regression result; Slice0 commit only after S0.3, same subject/rollback unit.

### Task S0.3 — Native rendering baseline and Slice 0 acceptance

**Files:** CREATE T`PremiumRenderingTestSupport.swift`, `BodyFlowPremiumRenderingTests.swift`, U`PremiumUIUXUITestSupport.swift`; CREATE future evidence README. No production preview-route or auth-root bypass needed for DS snapshots.

**Interfaces:** consumes SwiftUI views/DS; test-only `PremiumRenderingTestSupport.image<V: View>(_:width:dark:size:) -> UIImage`; produces XCTest screenshot attachments, never runtime data or a new app capability. Native `ImageRenderer` snapshots replace any need for a new dependency.

- [ ] Create U`PremiumUIUXUITestSupport.swift` with `import XCTest` and the complete native harness implementation shown in S2.1: launch preferences, identifier lookup, 44×44 assertions, screenshot and hierarchy attachments. Compile it in the UI target as part of the test build. It must exist before any consumer, including priority Slice 8; S2.1 documents and consumes this contract, not a second helper. No Release route or authentication override is introduced.
- [ ] Write a XCTest failing layout assertion for primary long label at AXXXXL/375 width plus `.card` long body/status, and capture **current** baseline before migrating owners. Cover all DynamicTypeSize cases `[.xSmall,.small,.medium,.large,.xLarge,.xxLarge,.xxxLarge,.accessibility1,.accessibility2,.accessibility3,.accessibility4,.accessibility5]` in both themes; screenshots alone are not a clipping assertion.
- [ ] Run `uiux_test s0-3-red -only-testing:BodyFlowTests/BodyFlowPremiumRenderingTests`; confirm missing helper or identified intrinsic-layout defect, not pixel-golden approval failure.
- [ ] Implement test-only helper and attachments with full text/roles and actual native render. UIKit host intrinsic/frame assertions supplement image inspection; ImageRenderer alone is not proof of native tab/composer behavior:

```swift
import SwiftUI
import UIKit
@MainActor enum PremiumRenderingTestSupport {
    static func image<V: View>(_ view: V, width: CGFloat, dark: Bool,
                               size: DynamicTypeSize) -> UIImage {
        let renderer = ImageRenderer(content: view
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.dynamicTypeSize, size)
            .frame(width: width))
        renderer.scale = 2
        guard let image = renderer.uiImage else {
            preconditionFailure("Native test render failed")
        }
        return image
    }
}
// In the XCTest method, for each fixture:
let image = PremiumRenderingTestSupport.image(
    Button("Texto longo de teste / Long test label", action: {})
        .buttonStyle(BodyFlowButtonStyle(role: .primary)),
    width: 375, dark: false, size: .accessibility5)
let attachment = XCTAttachment(image: image)
attachment.name = "s0-components-light-pt-BR-375-AXXXXL"
attachment.lifetime = .keepAlways
add(attachment)
```

  Use **Button** fixtures as well as text/card/field so the style is actually exercised; verify native accessibility label/≥44 frame with UIHostingController-hosted controls. No fabricated baseline golden or blind snapshot update; human-review both images before approving a new golden.
- [ ] Run `uiux_test s0-3-green -only-testing:BodyFlowTests/BodyFlowPremiumRenderingTests -only-testing:BodyFlowTests/BodyFlowComponentPolicyTests -only-testing:BodyFlowTests/BodyFlowSemanticColorTests`, then `uiux_release s0`; expect all selected tests and signed build PASS. Run native analyze command in §4.2; report preexisting warnings separately.
- [ ] Inspect actual captures both languages/themes at 3 logical widths and every font category; Increase Contrast/material fallback/control boundary assertions; Reduce Motion duration 0. Log semantic/pixel differences from reviewed same-size baselines, no cross-device pixel equality.
- [ ] Review Critical 0 / Important 0 only after evidence. Future explicit allowlist stage/commit: production files in S0.1/S0.2 + their tests/support/evidence, subject `refactor(ui): establish Performe AI semantic design tokens`. Verify clean after authorized commit; no commit executed now.

### Task S1.1 — Brand-consumption infrastructure without final bytes

**Files:** CREATE I`DesignSystem/PerformeAIBrandAsset.swift`, T`PerformeAIBrandAssetTests.swift`, `assets/brand/performe-ai-public-v1/manifest.json`, `review.md`. KEEP old catalog/enum/project/settings. No imageset or dummy image.

**Interfaces:** `PerformeAIBrandAsset: String, CaseIterable { symbolLight, symbolDark, symbolMono, symbolNegative, wordmarkLight, wordmarkDark, lockup }`; `var resourceName: String` maps exact PerformeAI…V1 names in FILE MAP; `func isAvailable(in bundle: Bundle = .main) -> Bool` uses UIImage asset lookup. Optional resolution only; text remains Performe AI when resource absent.

- [ ] Write RED: new mapping names exact, `isAvailable` false in bundle without new resources, product fallback exact Performe AI, `BodyFlowBrandAsset` mapping still unchanged. No expectation that unapproved asset exists.
- [ ] Run `uiux_test s1-1-red -only-testing:BodyFlowTests/PerformeAIBrandAssetTests -only-testing:BodyFlowTests/BodyFlowBrandAssetTests`; new type missing is expected RED.
- [ ] Implement new enum/mapping availability without editing old enum, selecting new icon or changing any callsite:

```swift
func isAvailable(in bundle: Bundle = .main) -> Bool {
    UIImage(named: resourceName, in: bundle, compatibleWith: nil) != nil
}
```

  Manifest records family `performe-ai-public-v1`, approvalStatus `pending`, approvedFiles `[]`, publicCallsites `[]`, no fictional hash. `review.md` lists §5 exact pending exports and supplied designer/license requirements. Preserve existing text identity and no image-loading network.
- [ ] Run `uiux_test s1-1-green -only-testing:BodyFlowTests/PerformeAIBrandAssetTests -only-testing:BodyFlowTests/BodyFlowBrandAssetTests -only-testing:BodyFlowTests/BrandIdentityTests`; all PASS with absent resources correctly absent. `uiux_release s1-infrastructure` PASS. Evidence marks infrastructure-ready **not Slice1 complete**.
- [ ] Infrastructure changes remain independently reviewable within Slice1; optional future separate infrastructure commit requires execution-specific agreement if final approval waits. Planned single completed Slice1 subject `feat(brand): integrate approved Performe AI assets`; no premature completed-slice commit/status.

### Task S1.2 — External asset review and explicit approval STOP

**Files:** UPDATE only future `assets/brand/performe-ai-public-v1/review.md`/manifest approval metadata after real user action; no bytes created by this task. **Interfaces:** consumes §5 exact deliverable list; produces named user approval records and actual hashes, not a programmatic approval decision.

- [ ] Prepare review checklist showing distinct P/trajectory beside old B, small-size silhouette, light/dark/mono/negative, exact wordmark and clearspace. Do not run old renderer or procedural SVG generator.
- [ ] **STOP: BRAND_ASSET_APPROVAL_GATE.** Ask user to approve externally supplied named files/sheets in §5, including separate AppIcon default/dark/tinted selection. Until supplied+approved, record BLOCKED with pending file list; do not fill them with placeholder graphics.
- [ ] After actual approval, validate exact dimensions with `sips -g pixelWidth -g pixelHeight <each-approved-PNG>` (substitute each exact §5 filename, not a wildcard over unknown files); inspect vector/PDF intrinsic bounds, author/license/font rights, actual contrast/mono/clearspace. Named missing/rejected variant blocks only its dependent callsite.
- [ ] Run `shasum -a 256 assets/brand/performe-ai-public-v1/masters/symbol-light.svg` and corresponding exact §5 approved files; record actual SHA-256 in manifest with approval reference. This is future local metadata, not approval itself. No auth/token content.
- [ ] Expected evidence: file-to-approval-to-hash allowlist, no legacy byte change; no unit RED for a human decision. Human approved files gate or BLOCKED is the actual test. No commit marking Slice1 complete without S1.3; same proposed subject/rollback unit.

### Task S1.3 — Integrate only approved public resources/catalog selection

**Files:** CREATE new catalog sets and approved PDFs/PNGs listed FILE MAP; MODIFY I`Features/Auth/SplashView.swift`, I`DesignSystem/Components/ScreenStateView.swift` brand composition and approved auth/onboarding brand callsites; MODIFY project **only icon-name setting**, after explicit icon approval. UPDATE manifest/review and T`PerformeAIBrandAssetTests.swift`.

**Interfaces:** consumes S1.1 mapping + S1.2 approved file hashes; produces available new resources and allowlisted public selection. Header semantic name/ID stays `brand.product-name`; decorative images hidden when name adjacent.

- [ ] Write RED requiring approved named resources resolve, exact manifest hashes match bytes, historical baseline paths unchanged, no missing glyph/clipped wordmark at 140/240 pt. Do not run this step before approval. `uiux_test s1-3-red -only-testing:BodyFlowTests/PerformeAIBrandAssetTests` fails missing approved resources, not user approval.
- [ ] Import exact approved exports into new sets, preserve vector PDF where applicable with explicit light/dark appearances; select negative resources on splash with native font/text fallback. Example public composition (only with approved resource):

```swift
VStack(spacing: BodyFlowSpacing.lg) {
    Image("PerformeAISymbolNegativeV1")
        .resizable().scaledToFit().frame(width: 96, height: 96)
        .accessibilityHidden(true)
    Text(BrandIdentity.productName)
        .font(BodyFlowTypography.largeTitle)
        .accessibilityIdentifier("brand.product-name")
}
.foregroundStyle(BodyFlowColor.color(.onHero))
```

  Approved wordmark can replace visual text, but accessible label remains exact and only once. Use intrinsic ratio ≤240 width; splash progress only real pending task. New icon setting `ASSETCATALOG_COMPILER_APPICON_NAME = PerformeAIAppIconV1` only after independent approval; unchanged existing AppIcon bytes/settings otherwise. No new launch delay/mechanics or system launch overhaul.
- [ ] Run `uiux_test s1-3-green -only-testing:BodyFlowTests/PerformeAIBrandAssetTests -only-testing:BodyFlowTests/BodyFlowBrandAssetTests -only-testing:BodyFlowTests/BrandIdentityTests -only-testing:BodyFlowTests/LocalizationContractTests`; `uiux_release s1` PASS with zero asset catalog warnings. Check compiled resources resolve correct variants; historical diff/hash guard §5; actual app launch/icon capture in later authorized local QA, no distribution.
- [ ] Review all approved public callsites/manifest, full matrix and accessibility meaning. Future commit subject `feat(brand): integrate approved Performe AI assets`; rollback only new mapping/selection with approved fallback, never overwrite/delete historical family.

### Task S2.1 — Auth/splash/native keyboard and capture harness

**Files:** MODIFY all six Auth files + I`App/AppRootView.swift` loading/error appearance, catalog; CONSUME U`PremiumUIUXUITestSupport.swift` from S0.3; CREATE U`PremiumAuthOnboardingUITests.swift`; MODIFY T`AuthFormStateTests.swift` for reviewed localized feedback assertions only. KEEP AppFlow/session/Keychain logic.

**Interfaces:** consumes DS + current `AppFlowModel` and auth view initializers; produces same SignIn/SignUp/Recovery/Confirmation contracts. Test helper `launch(arguments: [String], language: String, dark: Bool, category: String) -> XCUIApplication`, `capture(_:app:)`, `element(_:app:)`, `assertTarget(_:)`; native app journey, no injected Release auth success.

- [ ] Write RED UI `testAuthBrandAndTitleDoNotOverlapAXXXXL` and bilingual inline validation/neutral recovery assertions; fields/actions same IDs. Harness implementation:

```swift
import XCTest
@MainActor struct PremiumUIUXUITestSupport {
    let testCase: XCTestCase
    func launch(arguments: [String], language: String, dark: Bool,
                category: String = "UICTContentSizeCategoryL") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + [
            "-AppleLanguages", "(\(language))", "-AppleLocale",
            language == "pt-BR" ? "pt_BR" : "en_US",
            "-AppleInterfaceStyle", dark ? "Dark" : "Light",
            "-UIPreferredContentSizeCategoryName", category]
        app.launch()
        return app
    }
    func element(_ id: String, app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    func assertTarget(_ e: XCUIElement) {
        XCTAssertGreaterThanOrEqual(e.frame.width, 44)
        XCTAssertGreaterThanOrEqual(e.frame.height, 44)
    }
    func capture(_ name: String, app: XCUIApplication) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; testCase.add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-hierarchy"; tree.lifetime = .keepAlways; testCase.add(tree)
    }
}
```

  Verify actual theme/locale via real render/known localized labels; launch preferences alone are not proof. CategoryL belongs regular Large; validate recognized value before claiming font coverage. Capture only empty/synthetic fields; never credentials. Keep old helper names/allowlists unchanged.
- [ ] Run `uiux_test s2-1-red -only-testing:BodyFlowUITests/PremiumAuthOnboardingUITests/testAuthBrandAndTitleDoNotOverlapAXXXXL -only-testing:BodyFlowTests/AuthFormStateTests`; current overlap/locale expectation must be observed or characterize with true baseline first.
- [ ] Refine `AuthScreenLayout` HStack → VStack brand/title/supporting; keep max560/scroll and native fields. Apply field modifier, error feedbackDestructive opaque pairing and ButtonStyle; splash deep teal+text before asset approval, no slogan/fake delay. Example layout:

```swift
VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
    BodyFlowBrandIdentityView()
    Text(title).font(BodyFlowTypography.largeTitle)
    Text(message).font(BodyFlowTypography.body)
    content
}.frame(maxWidth: 560)
```

  Preserve `.textContentType`, SecureField, submit/focus Next/Done and return/recovery actions; auth errors map exact existing cases, form announcements only once. Manually migrate literal copy to `auth.*` catalogs, neutral recovery English naturally non enumerating. Native keyboard avoidance; no fixed CTA over fields. App Root state/tasks untouched; only pending state copy/style localized.
- [ ] Run `uiux_test s2-1-green -only-testing:BodyFlowUITests/PremiumAuthOnboardingUITests -only-testing:BodyFlowTests/AuthFormStateTests -only-testing:BodyFlowTests/AppFlowModelTests -only-testing:BodyFlowTests/AuthenticationSessionStoreTests -only-testing:BodyFlowTests/SecureStorageTests -only-testing:BodyFlowTests/SessionLifecycleCoordinatorTests`; expect all PASS and Debug confirmation only. Add existing `BodyFlowUITests/testPasswordRecoveryUsesNeutralConfirmation`/signup keyboard tests as neighbors when running full target. `uiux_release s2-auth` PASS; no Release fixture.
- [ ] Evidence auth light/dark both locales keyboard error/recovery, AX focus/order/44/increase contrast; inspect compiled development-action absence in Slice 10. Slice2 subject `refactor(ui): refine authentication and onboarding`, commit only after S2.3.

### Task S2.2 — Seven-step grouping, options, progress and authoritative resume

**Files:** MODIFY onboarding container/support/welcome/body/objective/routine/persona listed FILE MAP/catalog; MODIFY T`OnboardingPresentationTests.swift`; extend U`PremiumAuthOnboardingUITests.swift`. KEEP root coordinator/repository/draft/state models.

**Interfaces:** existing `OnboardingContainerView(model: OnboardingFlowModel)`, existing step view bindings and `OnboardingStep.allCases` order. Derived progress uses current position/total, no new completion estimate. Consumes restored-draft fact only if available; no new elapsed timer flag.

- [ ] Write RED UI AX `testOnboardingProgressAndBrandDoNotOverlap` on fresh Debug journey, `testActualObjectivesAndServerStyleCount` and optional nil/unconfirmed vs zero/no preservation assertions in existing models. RED `onboarding.flow-style.title` en “Flow’s style”/pt “Estilo do Flow” missing catalog.
- [ ] Run `uiux_test s2-2-red -only-testing:BodyFlowTests/OnboardingPresentationTests -only-testing:BodyFlowUITests/PremiumAuthOnboardingUITests`; record exact missing title/layout assertion.
- [ ] Implement header/real step progress derived same order:

```swift
let position = (OnboardingStep.allCases.firstIndex(of: model.step) ?? 0) + 1
ProgressView(value: Double(position), total: Double(OnboardingStep.allCases.count))
// Display localized position/total in text; do not change model.step.
```

  Group body personal/measurements/optional with native fields; objective exact real 3 codes; routines retain confirmation semantics and date/picker presets; welcome existing name/country/IANA search codes readable no server locale overwrite; server persona names/descriptions verbatim, localized Flow title/check/selected trait. Add no fourth style. No layout-derived writes. Resume explanation only based existing known restoration; if no exposed fact, omit copy rather than add persisted state.
- [ ] Run `uiux_test s2-2-green -only-testing:BodyFlowTests/OnboardingFlowModelTests -only-testing:BodyFlowTests/OnboardingModelsTests -only-testing:BodyFlowTests/OnboardingPresentationTests -only-testing:BodyFlowTests/MobileOnboardingRepositoryTests -only-testing:BodyFlowUITests/PremiumAuthOnboardingUITests`; expected optional nil/sequence/server options and resumption unchanged. `uiux_release s2-steps` PASS.
- [ ] Evidence welcome/country/timezone/body/objective/routine/persona/progress/resumed state where known; 4 theme-locales +compact/large/keyboard/AX. Same Slice 2 commit/rollback unit; blocked server docs remain truthful, no new QA set.

### Task S2.3 — Consent reading and server completion review

**Files:** MODIFY I`Features/Onboarding/ConsentStepView.swift`, `OnboardingCompletionView.swift`, container feedback/catalog; extend U`PremiumAuthOnboardingUITests.swift`. KEEP legal DTO/body/hash/actions/completion logic.

**Interfaces:** existing explicit document action callbacks/current required flag; completion uses same `OnboardingFlowModel` finish command. No jump-edit/reset, scroll-to-accept condition or new legal title mapping.

- [ ] Write RED UI `testLongConsentBodyAndActionRemainReachableAtAXXXXL`, unchecked required/optional action labels both languages, no automatic advance before mock server finish; local documents labeled QA. Required missing docs→U and no submit remains must-pass baseline, not inverted by design.
- [ ] Run `uiux_test s2-3-red -only-testing:BodyFlowUITests/PremiumAuthOnboardingUITests/testLongConsentBodyAndActionRemainReachableAtAXXXXL`; a real current layout defect must fail; if already correct add missing localized semantic assertion. Don't weaken body/action assertions.
- [ ] Use unbounded naturally wrapping Text of exact server body; required/optional+purpose/action explicit text; provenance/version secondary disclosure, same hash/version payload. Preserve native unchecked selection control. Completion review groups existing answers; dominant finish only existing command:

```swift
Text(document.body ?? "").font(BodyFlowTypography.body)
    .fixedSize(horizontal: false, vertical: true)
// document.body is the already received authoritative body; no translation or replacement.
```

  Unknown friendly title keeps current document key; no invented legal meaning. Disable duplicate finish as model currently requires. Show actual operation progress/error, not optimistic Hoje.
- [ ] Run `uiux_test s2-3-green -only-testing:BodyFlowTests/OnboardingCompletionTests -only-testing:BodyFlowTests/MobileOnboardingRepositoryTests -only-testing:BodyFlowTests/AppFlowModelTests -only-testing:BodyFlowUITests/PremiumAuthOnboardingUITests -only-testing:BodyFlowUITests/BodyFlowUITests/testFreshUserCompletesOnboardingAndReachesToday`; `uiux_release s2` PASS. Existing old consent IDs in historical UITests may need narrow expectation updates **only** if actual current contract uses dynamic document IDs; do not replace server-owned journey with legacy fixture to silence failure. Missing fixture coverage is documented blocker requiring test-only repair review, not root behavior change.
- [ ] Evidence legal body/explicit actions/completion/fail closed in 4 theme-locales, required optional/AX/keyboard focus. Review session/consent diff: Critical 0 / Important 0; future Slice 2 commit subject `refactor(ui): refine authentication and onboarding`, clean after commit; rollback presentation only.

## MACRO B — CORE PRODUCT SURFACES

### Task S3.1 — Native shell, five localized tabs and one brand anchor

**Files:** MODIFY I`App/AppShellView.swift`, `AppTab.swift`, I`DesignSystem/Components/ScreenStateView.swift`; native tab configurator only if labels need forwarding; catalog; MODIFY T`AppTabTests.swift`; CREATE U`PremiumCoreSurfacesUITests.swift`. KEEP routes/session coordinators.

**Interfaces:** additive `AppTab.title(for language: SupportedAppLanguage) -> String`; keep `var title` as Portuguese-compatible API until reviewed callers migrated. Existing cases/order/systemImage/accessibilityIdentifier/rootAccessibilityIdentifier unchanged. `bodyFlowBrandIdentity()` still available; consolidate its callers rather than remove technical discoverability.

- [ ] Add RED in AppTabTests retaining all current assertions, plus:

```swift
@Test func englishLabelsPreserveTechnicalContract() {
    #expect(AppTab.allCases.map { $0.title(for: .englishUnitedStates) } ==
            ["Today", "Register", "Plan", "Progress", "Profile"])
    #expect(AppTab.allCases.map(\.rawValue) ==
            ["today", "register", "plan", "progress", "profile"])
}
```

  Add UI `testRootBrandOnceAndIndependentStacks` with five IDs/selection/back/sheet actions, header does not clip at AX and no toolbar overlap.
- [ ] Run `uiux_test s3-1-red -only-testing:BodyFlowTests/AppTabTests -only-testing:BodyFlowUITests/PremiumCoreSurfacesUITests/testRootBrandOnceAndIndependentStacks`; missing title API/new layout assertion expected.
- [ ] Add catalog `tab.today/register/plan/progress/profile` and use existing explicit localization machinery, e.g. `title(for:)` switch returning `(try? AppLocalization.string("tab.today", for: language)) ?? title` with the existing Portuguese fallback. Feed caller's already selected language; no persisted preference key or server locale change. SwiftUI TabView/NavigationStack are unchanged. Move brand anchor into root content hierarchy once, preserve `brand.product-name`; pushed details keep native title/back. Remove `.clipped()` from wrapper only after actual safe-area/keyboard regression; do not manufacture fixed header heights. Example anchor remains text:

```swift
BodyFlowBrandIdentityView()
    .frame(maxWidth: .infinity, alignment: .leading)
// Existing NavigationStack content and selection bindings stay in place.
```

- [ ] Run `uiux_test s3-1-green -only-testing:BodyFlowTests/AppTabTests -only-testing:BodyFlowTests/AppRouterTests -only-testing:BodyFlowTests/Prompt14SessionOwnershipTests -only-testing:BodyFlowUITests/PremiumCoreSurfacesUITests -only-testing:BodyFlowUITests/BodyFlowUITests/testTodayNavigationPersistsAcrossTabSwitch`; `uiux_release s3-shell` PASS. Validate native selected labels/IDs in both languages/themes/rotations and sheet focus return.
- [ ] Evidence: five screens/stack revisit, brand count/geometry/toolbar, compact/AX layouts. Future Slice3 subject `refactor(ui): refine Today experience`, commit after S3.2; reverting must retain native route/session semantics.

### Task S3.2 — Hoje hierarchy and real metric distinctions

**Files:** MODIFY ten Today view files in FILE MAP and supporting Mascot Card appearance/catalog; extend U`PremiumCoreSurfacesUITests.swift`, T`TodayPresentationTests.swift` for localized formatting only. KEEP model/provider/official descriptors.

**Interfaces:** current `TodayPresentation(snapshot:)`, Today Energy/Protein/Hydration/Block descriptors, `TodayRootView(model:recommendations:mascot:invalidationCenter:)`; no new score DTO. Flow/Library links stay outside dependent loaded Today content. Catalog formatting consumes official Decimal/nullable values, never calculates official percentage.

- [ ] Add RED UI `testFlowEntrySurvivesUnavailableToday`, priority reading order/AX wrap and localized metric labels. Retain energy tests proving food remaining vs daily balance distinct. Use current Prompt13 loaded/incomplete/unavailable/stale/offline cases, not real account numbers. Add screenshot baseline before reordering.
- [ ] Run `uiux_test s3-2-red -only-testing:BodyFlowUITests/PremiumCoreSurfacesUITests -only-testing:BodyFlowTests/TodayPresentationTests`; expected missing hierarchy/localization, never intentional loss of useful Flow entry.
- [ ] Reorder view composition: context/day/freshness → energy two meanings → protein/hydration → pending context → existing shortcuts → recommendations/routine/records/block/history; Flow/Library persistent access remains visible even when unavailable. Move mascot below core information; keep independent recommendation task/tracking. Use `.card` once per meaningful group, no nested card per field. Metric styling example (value already formatted from received data):

```swift
VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
    Text("today.energy.food-remaining").font(BodyFlowTypography.supporting)
    Text(descriptor.remainingFoodText).font(BodyFlowTypography.metricLarge)
    Text("today.energy.food-remaining.detail").font(BodyFlowTypography.caption)
}.foregroundStyle(BodyFlowColor.color(.textPrimary))
```

  `descriptor.remainingFoodText` is current received food-remaining value, no subtraction in view. Distinct balance block includes official exercise semantics. Received percentage only for current progress; nil → text “Not available”, not zero. Day-only/timezone/provenance unchanged. Pending information no new tappable route if none exists. No greeting/name without authoritative source; no score/steps/photo/quote/habit count.
- [ ] Run `uiux_test s3-2-green -only-testing:BodyFlowTests/TodayPresentationTests -only-testing:BodyFlowTests/TodayContractTests -only-testing:BodyFlowTests/TodayViewModelTests -only-testing:BodyFlowTests/TodayRecommendationsTests -only-testing:BodyFlowTests/FeatureInvalidationTests -only-testing:BodyFlowUITests/Prompt13TodayUITests -only-testing:BodyFlowUITests/Prompt14TodayMascotUITests -only-testing:BodyFlowUITests/PremiumCoreSurfacesUITests`; `uiux_release s3` PASS. Existing fixture startup divergence is a test prerequisite, not permission to rewrite root state; use authentic full local journey or reviewed test-only fixture repair under Debug boundary, record separately.
- [ ] Capture loaded/empty/incomplete/error/offline/stale/U, recommendations independent failure and Flow usable; four theme-locales/compact/large/AX. Review no calculation/no extra reads or impressions. Future commit `refactor(ui): refine Today experience`; rollback Slice3 only, downstream screenshot golden changes reviewed explicitly.

### Task S4.1 — Registration entry/capture and truthful capability states

**Files:** MODIFY Register Root/RegistrationSheet/Meal Capture Source/Meal Demonstration Source/Meal Text Draft/catalog; CREATE U`PremiumRegistrationUITests.swift`; extend T`RegistrationPresentationTests.swift` for localized labels only.

**Interfaces:** preserve `MealCaptureChoice` text/photo/audio, `MealCaptureSourceView(select:)`, current sheet routes/callbacks. **Capability classification:** REAL = proposal/receipt/model contracts and server-authoritative API contract exist, not proof of Release wiring; PARTIAL = local text/demo journey and first-item editor; DEFERRED = real photo/mic/capture/upload plus Release registration adapter. At current HEAD **all registration Release repositories are unavailable**, including text; selector UI cannot change that truth.

- [ ] Write RED UI `testCaptureChoicesExposeLocalSampleProvenance` and en labels, keyboard draft retained on error, no media permission dialog, U distinctly not empty; assert existing capture IDs and source callback once. Snapshot current 3 choice arrangement as baseline.
- [ ] Run `uiux_test s4-1-red -only-testing:BodyFlowUITests/PremiumRegistrationUITests/testCaptureChoicesExposeLocalSampleProvenance -only-testing:BodyFlowTests/RegistrationPresentationTests`; new labels/layout assertion fails, not mocked real permission.
- [ ] Style Foto/Áudio/Texto grid only when width/content fits; at AX stacked rows via `ViewThatFits`/DynamicType; labels “Foto — amostra local” / “Photo — local sample”, “Áudio — amostra local” / “Audio — local sample”, “Texto” / “Text”, localized explicit demo notice. Do not replace demo with apparently live “Take photo”. Existing choice callbacks only:

```swift
Button { select(.photo) } label: {
    Label("registration.capture.photo-sample", systemImage: "photo")
        .fixedSize(horizontal: false, vertical: true)
}.buttonStyle(BodyFlowButtonStyle(role: .secondary))
 .accessibilityIdentifier("registration.meal.source.photo")
```

  Root groups four existing actions; `.sheet` task/coordinator retained; draft analyze loading is true current mutation state, no fake intermediate image classifier phases. Unavailable Release sheet truthful, no background write/offline queue. Text input/focus preserves guards/captured attempts.
- [ ] Run `uiux_test s4-1-green -only-testing:BodyFlowTests/RegistrationSheetTests -only-testing:BodyFlowTests/RegistrationSheetTaskCoordinatorTests -only-testing:BodyFlowTests/MealRegistrationModelTests -only-testing:BodyFlowTests/DemoRegistrationRepositoryTests -only-testing:BodyFlowUITests/Prompt13RegistrationUITests -only-testing:BodyFlowUITests/PremiumRegistrationUITests`; `uiux_release s4-entry` PASS. Assert no permission prompt; local proposal only after analyze.
- [ ] Evidence root/capture/text/analyze/error/offline/U/keyboard in 4 theme-locales+AX. Future Slice4 subject `refactor(ui): refine registration experience`, commit after S4.3.

### Task S4.2 — Detected proposal, corrections and confirm/receipt hierarchy

**Files:** MODIFY Meal Proposal/Meal Proposal Editor/Workout Proposal/RegistrationOperationSummary/sheet appearance/catalog; extend U`PremiumRegistrationUITests.swift`. KEEP mutation models/RegistrationSnapshot/proposals.

**Interfaces:** preserve `MealProposalPresentation` items/totals/nullable values/expiry/status, first-item editor, edit/confirm/cancel closures, Workout Proposal estimate. No food image or macro goal DTO. Existing model owns allowed recovery and idempotency.

- [ ] Write RED `testProposalPrimaryConfirmAndLongTotalsAX`, localized energy/estimate/action labels and explicit first-item editing; unchanged must pass same-key retry/duplicate guard and confirmed readonly tests. Four-value cells use official optional totals only; no snapshot introduced progress ring.
- [ ] Run `uiux_test s4-2-red -only-testing:BodyFlowUITests/PremiumRegistrationUITests -only-testing:BodyFlowTests/RegistrationPresentationTests`; expected missing primary hierarchy/localization/AX assertion.
- [ ] Compose actual received items/quantities/warnings → totals cells with units → provenance/expiry secondary → Confirm primary/Edit secondary/Cancel tertiary. Use neutral food symbol or none, not dish photo. Example preserves callbacks/IDs:

```swift
Button("registration.proposal.confirm", action: confirm)
    .buttonStyle(BodyFlowButtonStyle(role: .primary))
    .disabled(isSubmitting)
    .accessibilityIdentifier("registration.proposal.confirm")
Button("registration.proposal.edit", action: edit)
    .buttonStyle(BodyFlowButtonStyle(role: .secondary))
    .disabled(isSubmitting)
    .accessibilityIdentifier("registration.proposal.edit")
```

  Keep current status guards outside buttons; canceled/expired/notpending/confirmed not visually pending. Retry current capture key; summary uses existing retry vs start new recovery; no retransmit confirmed record. Editor first-item label and existing date/type/kcal user input, no local nutrition sum/portion recalculation/extra macros. Nil values not zero; timestamp format does not decide expiry. Workout energy explicit estimated, no protocol inventing.
- [ ] Run `uiux_test s4-2-green -only-testing:BodyFlowTests/MealRegistrationModelTests -only-testing:BodyFlowTests/WorkoutRegistrationModelTests -only-testing:BodyFlowTests/RegistrationPresentationTests -only-testing:BodyFlowUITests/Prompt13RegistrationUITests -only-testing:BodyFlowUITests/PremiumRegistrationUITests`; expected pending/correction/confirm/cancel/expired/already confirmed/receipt recovery contracts PASS. `uiux_release s4-proposals` PASS.
- [ ] Evidence detected/edit/confirm/receipt/error/retry/expiry in 4 theme-locales+AX. Capture before and after receipt, not inferred saved toast. Same Slice4 commit/rollback unit.

### Task S4.3 — UIKit bridges, hydration/weight/workout intrinsic sizing

**Files:** MODIFY Workout Registration/Workout Proposal/Hydration Registration/Weight Registration/sheet visual bridge frames/catalog; extend U`PremiumRegistrationUITests.swift`, T`BodyFlowComponentPolicyTests.swift` intrinsic render assertions. KEEP all coordinator callbacks/parsing/date/snooze policies/IDs.

**Interfaces:** existing UIViewRepresentable make/update/sizeThatFits/Coordinator contracts unchanged; optional `role: BodyFlowButtonRole = .primary` added to local proposal action bridge only to style Confirm/Edit/Cancel. UIFont preferred style with adjustsFontForContentSizeCategory; no shared business logic moved into DS.

- [ ] Write RED `testBridgedControlsExpandAtAXXXXL` for action title, date, selected intensity and quick mL values; frame≥44/fully readable and keyboard reachable. Current fixed 48 visual frames identified; catch actual clip in UITest/native host, not wrong numeric unit.
- [ ] Run `uiux_test s4-3-red -only-testing:BodyFlowUITests/PremiumRegistrationUITests/testBridgedControlsExpandAtAXXXXL`; identified clipping assertion must fail. Selected parsing tests unchanged pass before mutations.
- [ ] Keep minimum constraint 48 if already existing, remove **fixed** visual `.frame(height:48)`/fixed sizeThatFits rescue only where intrinsic height requires. UIKit representables use fitted native height; never change callback mapping:

```swift
func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton,
                  context: Context) -> CGSize? {
    let width = proposal.width ?? uiView.intrinsicContentSize.width
    let fitting = uiView.sizeThatFits(CGSize(width: width,
                                           height: CGFloat.greatestFiniteMagnitude))
    return CGSize(width: width, height: max(48, fitting.height))
}
```

  Field/date/segment bridges use their actual UIKit fitting APIs; no forced 48 return. Buttons semantic role colors resolved UITraitCollection/native font. Reflow intensity/quick amount controls at AX only without changing options. Date/decimal keyboard/parsing unchanged; patient-timezone cannot fallback to server unknown device. Largest detent when accessibility fonts, existing discard ownership/focus preserved.
- [ ] Run `uiux_test s4-3-green -only-testing:BodyFlowTests/HydrationWeightModelTests -only-testing:BodyFlowTests/WorkoutRegistrationModelTests -only-testing:BodyFlowTests/RegistrationSheetTaskCoordinatorTests -only-testing:BodyFlowUITests/Prompt13AccessibilityUITests -only-testing:BodyFlowUITests/PremiumRegistrationUITests`; `uiux_release s4` PASS; analyze read existing MainActor warnings separately, no broad actor refactor.
- [ ] Review all bridges with keyboard/themes/locales/AX, duplicate write/key/regression PASS; evidence 44 frames intrinsic multi-line geometry. Future Slice4 commit `refactor(ui): refine registration experience`, no media/API change; rollback presentation only.

### Task S5.1 — Plano supported metadata/states and detail reload

**Files:** MODIFY Plan Root/Plan Detail/PlanComponents/catalog; MODIFY T`PlanPresentationTests.swift`; extend U`PremiumCoreSurfacesUITests.swift`.

**Interfaces:** additive `PlanPresentation.init(snapshot: PlanSnapshot, language: SupportedAppLanguage = .portugueseBrazil)`; `trainingFields/nutritionSections/isEmpty` IDs/nil policy unchanged; received API Timestamp formatted with existing UTC contract +selected formatting locale. Current root/detail model reload remains.

- [ ] Write RED bilingual labels/date format test on existing plan fixture; keep optional fields omitted vs zero and nutrition sections retained; UI `testPlanGroupsReceivedFieldsAndReloadsDetail`. No new “active” status by the client clock.
- [ ] Run `uiux_test s5-red -only-testing:BodyFlowTests/PlanPresentationTests -only-testing:BodyFlowUITests/PremiumCoreSurfacesUITests/testPlanGroupsReceivedFieldsAndReloadsDetail`; expected catalog/language API/hierarchy failure.
- [ ] Add the language initializer/default and pass already selected language to formatter/copy, current field DTOs unchanged. Group training+each nutrition section with`BodyFlowCard(surface:.card)`, rows not card per field; make version/generated/valid until disclosure secondary, retains all received data and existing reload link. Example:

```swift
ForEach(presentation.trainingFields) { field in
    FixtureMetricRow(title: field.title, value: field.value)
        .accessibilityIdentifier(field.id)
}
```

  No exercises/menu/weekly completion/new goals. Root E/U/S/O/R distinguish correctly. Date format retains backend timezone/day meaning; no expiry calculation.
- [ ] Run `uiux_test s5-green -only-testing:BodyFlowTests/PlanPresentationTests -only-testing:BodyFlowTests/PlanViewModelTests -only-testing:BodyFlowTests/PlanProgressContractTests -only-testing:BodyFlowUITests/Prompt13PlanProgressHistoryUITests -only-testing:BodyFlowUITests/PremiumCoreSurfacesUITests`; `uiux_release s5` PASS. Review root/detail new read occurs exactly as already required.
- [ ] Evidence empty/loaded/stale/error/offline/U, details and metadata expanded in 4 theme-locales+AX; Critical 0 / Important 0. Future commit `refactor(ui): refine Plan experience`; rollback Slice 5 only.

### Task S6.1 — Progresso current values/official achievements, no invented chart

**Files:** MODIFY Progress Root/ProgressComponents/Block7700Detail/catalog; MODIFY T`ProgressPresentationTests.swift`; extend U`PremiumCoreSurfacesUITests.swift`.

**Interfaces:** additive `ProgressPresentation.init(snapshot: ProgressSnapshot, language: SupportedAppLanguage = .portugueseBrazil)` for copy/formatting only; all XP/level/streak/badge identity/current measurements/block/date meaning retained. Current Block descriptor optional percentage continues official source. No `Chart` or range query interface produced.

- [ ] Write RED en measurement/streak/nil copy; UI `testProgressMissingValuesAreNotZeroAndNoRangeSelector` and AX equivalent for official block progress; keep duplicate medal IDs tests unchanged.
- [ ] Run `uiux_test s6-red -only-testing:BodyFlowTests/ProgressPresentationTests -only-testing:BodyFlowUITests/PremiumCoreSurfacesUITests/testProgressMissingValuesAreNotZeroAndNoRangeSelector`; missing localized summary/hierarchy RED, no manufactured time points.
- [ ] Group current weight/body fat → official consistency/streak → official XP/level/blocks/badges → supplied dates. Nil “Não disponível”/“Not available”, 0 streak calm current message+existing Hoje action. Token pair achievement onAchievement remains gold on charcoal, not generic dark accent. Current badge strings verbatim; no childish mascot gating. Progress indicator only supplied percentage:

```swift
if let percentage = descriptor.percentage {
    Text(percentage.formatted() + "%")
    // Existing official percentage renderer/semantic value; no value derived from calories.
}
```

  `descriptor` is existing Block descriptor. Use current localized formatting locale and official percent contract (do not assume 0…1 vs0…100 while feeding ProgressView). No graph/no 7D/4W selector/history delta; **DEFERRED** pending separately authorized dataset. If dataset appears in later baseline, STOP scope change before adding chart; then weight/fat unit-separated series,summary+date/value/unit list, shapes not color, empty/insufficient/ranges only supported queries per approved spec.
- [ ] Run `uiux_test s6-green -only-testing:BodyFlowTests/ProgressPresentationTests -only-testing:BodyFlowTests/ProgressViewModelTests -only-testing:BodyFlowTests/Block7700PresentationTests -only-testing:BodyFlowTests/PlanProgressContractTests -only-testing:BodyFlowUITests/Prompt14ProgressUITests -only-testing:BodyFlowUITests/PremiumCoreSurfacesUITests`; `uiux_release s6` PASS. Preserve official values exactly, no local block/XP formula.
- [ ] Evidence no data/data/minimum/zero streak/duplicate badges/block nil/official percentage/error/stale/U in 4 theme-locales+AX and color independence. Future commit `refactor(ui): refine Progress experience`; rollback Slice 6 only.

### Task S7.1 — Profile/persona supported controls and account exclusions

**Files:** MODIFY Profile Root/Coach Persona Picker/Shared Feature Detail/catalog; CREATE U`PremiumContentProfileUITests.swift`. KEEP fixture/model/session option load ownership.

**Interfaces:** preserve `ProfileRootView` initializer/`ProfilePersonaLoadOwnership` tokens, current Coach Persona Editor save/cancel/options factory. Separate visual groups account identity/preferences vs content vs destructive **only for established controls**. DEFER logout UI despite model`signOut()`, account delete/privacy/support/new Profile Library Flow cross-stack routes. Not a row with no action.

- [ ] Write RED localized Flow style labels/no overlap toolbar at AX; UI `testProfileFixtureProvenanceAndServerOptionGate`. No fabricated push-enabled status/avatar upload or `/me` read. Keep persona late-response/session invalidations must pass.
- [ ] Run `uiux_test s7-1-red -only-testing:BodyFlowUITests/PremiumContentProfileUITests/testProfileFixtureProvenanceAndServerOptionGate`; missing language/visual assertion must fail, no expectation to add delete control.
- [ ] Style existing grouped List with semantic DS and one stack anchor; preserve fixture disclosure name/notifications. Server options not available→existing gated UI, not Focus demo asserted server. Picker uses server names/descriptions unchanged, title “Estilo do Flow”/“Flow’s style”, same save/cancel state. Example controls:

```swift
Button("profile.persona.save") { saveSelection() }
    .disabled(!canSave)
    .accessibilityIdentifier("persona.save")
// Existing saveSelection() owns saveTask, awaits model.save() -> Bool,
// cancellation check and conditional dismiss. Keep that method unchanged.
```

  `isSaving` and `canSave` are existing private view properties, not properties on the model. Preserve existing saveSelection() lifecycle and dismiss logic. Separate destructive confirmation template is N/A current UI; no legal activation/new actions. Existing demo Preferences destination still labeled demo.
- [ ] Run `uiux_test s7-1-green -only-testing:BodyFlowTests/CoachPersonaEditorModelTests -only-testing:BodyFlowTests/Prompt14SessionOwnershipTests -only-testing:BodyFlowTests/Prompt14ReleaseBoundaryTests -only-testing:BodyFlowUITests/BodyFlowUITests/testProfilePersonaChangeIsReflected -only-testing:BodyFlowUITests/PremiumContentProfileUITests`; `uiux_release s7-profile` PASS. Existing fixtures review needed if starts onboarding; never bypass real root in Release.
- [ ] Evidence profile/persona load/save/error/cancel/U and table of DEFER account controls with reason;4 theme-locales+AX/focus. Slice7 subject `refactor(ui): refine Profile experience`, after S7.3.

### Task S7.2 — Library/article/cover editorial presentation with tracking preserved

**Files:** MODIFY Library Root/PublishedContentCard/Published Content Detail/ContentCover/BodyFlow Markdown plus Today Recommendations/Mascot Detail token mapping/catalog; extend U`PremiumContentProfileUITests.swift`. KEEP canonical parser/cache/security/task reducers; no Library god-view refactor.

**Interfaces:** existing Todos/Salvos/category/cursor selection, content model version/access states/save/complete/impression/opened, authorized cover revision/session factory, current Markdown renderer. No new recipe/workout categories, remote photo fetch, arbitrary links or new Profile entry.

- [ ] Add RED `testArticleActionsAndMetadataAtAXXXXL` and bilingual filter/action labels; card separate AX open button and focus order retain. Cover semantic accessibility Hidden true; unauthorized/expired/MIME/dimension states never display stale image as new authorized revision.
- [ ] Run `uiux_test s7-2-red -only-testing:BodyFlowUITests/PremiumContentProfileUITests/testArticleActionsAndMetadataAtAXXXXL -only-testing:BodyFlowTests/LibraryPresentationTests`; missing copy/layout assertion fails, not tracking policy changed.
- [ ] Refine only view-body sections in large Library Root; keep existing task IDs/cursor reducers/authorization relay/visibility policy byte-equivalent where possible. Header/filters→results→cards; accessible filters inside existing AX scroll path. Card uses `.card`; authorized 16:9 cover radius 20 match approved family, neutral placeholder; article title/cover/metadata→save/complete/status→canonical Markdown. No renderer for Flow. Example token mapping:

```swift
Text(summary.title).font(BodyFlowTypography.cardTitle)
    .foregroundStyle(BodyFlowColor.color(.textPrimary))
// Existing open/save/complete callbacks, authorization and publication IDs unchanged.
```

  No additional `.onAppear` tracking; local pagination error separate from initial error, bounded access/version not found correct. Keep HTTPS/link/canonical body semantics; local styles cannot translate server content or grant cover permission.
- [ ] Run `uiux_test s7-2-green -only-testing:BodyFlowTests/LibraryPresentationTests -only-testing:BodyFlowTests/PublishedContentFeedViewModelTests -only-testing:BodyFlowTests/ContentDetailViewModelTests -only-testing:BodyFlowTests/ContentCoverViewModelTests -only-testing:BodyFlowTests/ContentCoverLoaderTests -only-testing:BodyFlowTests/SessionCoverCacheTests -only-testing:BodyFlowTests/BodyFlowMarkdownParserTests -only-testing:BodyFlowTests/MarkdownBackendCompatibilityTests -only-testing:BodyFlowTests/Prompt14TelemetryPrivacyTests -only-testing:BodyFlowUITests/Prompt14LibraryUITests -only-testing:BodyFlowUITests/PremiumContentProfileUITests`; `uiux_release s7-content` PASS.
- [ ] Evidence filters/pagination/stale/bounded version/access/errors/article long text/authorized cover fallback,4 theme-locales+AX/focus; request/tracking counts remain baseline in mocks. Same Slice 7 commit/rollback unit.

### Task S7.3 — Existing History/Routine details and supporting mascot convergence

**Files:** MODIFY four History files/five Routine files/Mascot Card/Mascot Detail/catalog; MODIFY T`HistoryPresentationTests.swift`, `RoutinePresentationTests.swift` localization only; extend U`PremiumContentProfileUITests.swift`. KEEP shared snooze policy/mutation state and historical mascot art.

**Interfaces:** existing read-only History details/nullable fields; Routine kind/schedules/occurrence context/allowed15/30/60+custom/actions/captured key/patient IANA zone. Formatting explicit selected language, existing documented timezone; no device zone fallback for unknown patient.

- [ ] Write RED bilingual value/unit/status labels plus UI `testRoutineActionSheetAndHistoryReadOnlyAX`; assert taken/snooze/skipped requires current explicit confirmation, no unsupported edit/delete. Existing cross-date/IANA/conflict retry assertions must stay strong.
- [ ] Run `uiux_test s7-3-red -only-testing:BodyFlowTests/HistoryPresentationTests -only-testing:BodyFlowTests/RoutinePresentationTests -only-testing:BodyFlowUITests/PremiumContentProfileUITests`; missing localized labels/layout failure.
- [ ] Refine rows/value units/provenance; one grouped surface instead nested cards. Routine explicit action primary, recovery manual, cancel available; patient-zone formatting uses current context, no calculated new dose/date. History detail readonly, nil not zero. Mascot state/provenance accessible but quiet, debug geometry unchanged and not new public Flow doctor. Example formatting given known context:

```swift
let formatter = DateFormatter()
formatter.locale = language.formattingLocale
formatter.timeZone = try patientTimeZone.requireTimeZone()
formatter.dateStyle = .medium
formatter.timeStyle = .short
let displayed = formatter.string(from: timestamp.value)
```

  This uses already documented `PatientTimeZoneContext`; if unavailable, follow existing U policy, never`TimeZone.current`as official context. Formatting helper locals must not reschedule occurrence.
- [ ] Run `uiux_test s7-3-green -only-testing:BodyFlowTests/HistoryPresentationTests -only-testing:BodyFlowTests/HistoryViewModelTests -only-testing:BodyFlowTests/HistoryContractTests -only-testing:BodyFlowTests/RoutinePresentationTests -only-testing:BodyFlowTests/RoutineActionModelTests -only-testing:BodyFlowTests/RoutineSnoozePolicyTests -only-testing:BodyFlowTests/RoutineViewModelTests -only-testing:BodyFlowTests/MascotAccessibilityModelTests -only-testing:BodyFlowUITests/Prompt13RoutineUITests -only-testing:BodyFlowUITests/Prompt13PlanProgressHistoryUITests -only-testing:BodyFlowUITests/PremiumContentProfileUITests`; `uiux_release s7` PASS.
- [ ] Evidence History empty/content/nils/stale/U and Routine taken/skipped/snooze/conflict/receipt/history pagination,4 theme-locales+AX/color independence. Review: Critical 0 / Important 0 with no ownership/API change. Future Slice 7 commit `refactor(ui): refine Profile experience`; rollback presentation only, keep occurrence/history evidence.

### Task S8.1 — Flow truthful feedback, role bubbles/composer and local test states

**Files:** MODIFY I`Features/FlowChat/FlowChatView.swift`, catalog; CREATE I`Features/FlowChat/FlowChatPresentation.swift`, `Features/PreviewSupport/FlowChatPreviewSupport.swift`, T`FlowChatPresentationTests.swift`, `FlowChatPreviewSupportTests.swift`, U`FlowChatUITests.swift`; CONDITIONAL MODIFY **Debug demo branch only** I`App/AppDependencies.swift`. KEEP FlowChatModel/API/repository/protocol/Release injection unchanged.

**Interfaces:** pure `FlowChatPresentation.canSubmit(_ text: String, isSending: Bool) -> Bool`, `isOverLimit(_:) -> Bool`, `roleLabelKey(_ role: FlowMessageRole) -> String.LocalizationValue`; policies use trimmed text/count 4000 matching model, no key generation/send. Test-only `FlowPreviewScenario.resolve(arguments: [String]) -> FlowPreviewScenario?` and `FlowPreviewRepository: FlowChatProviding` implement same signatures; all under DEBUG.

- [ ] Add actual RED tests:

```swift
@Suite struct FlowChatPresentationTests {
    @Test func composerMatchesExistingGuard() {
        #expect(!FlowChatPresentation.canSubmit("  \n ", isSending: false))
        #expect(FlowChatPresentation.canSubmit(String(repeating: "a", count: 4000),
                                              isSending: false))
        #expect(!FlowChatPresentation.canSubmit(String(repeating: "a", count: 4001),
                                               isSending: false))
        #expect(!FlowChatPresentation.canSubmit("Oi", isSending: true))
    }
}
```

  UI `testWaitingCopyDoesNotPromiseStreamingOrRemoteCancellation`, `testLongPlainResponseAndComposerKeyboard` with local mock only. New catalog`flow.responding` proposed combined text, `flow.cancel` local wait meaning, `flow.role.user` “Você”/“You”, `flow.role.assistant` Flow, `flow.role-line` AI assistant, `flow.limit.detail` localized 4000 limit.
- [ ] Run `uiux_test s8-1-red -only-testing:BodyFlowTests/FlowChatPresentationTests -only-testing:BodyFlowUITests/FlowChatUITests`; new policy/missing UItests fail initially; catalog asserts combined copy, not simulated actual brand LLM success.
- [ ] Implement pure policies exactly matching guard, no flow model modification:

```swift
enum FlowChatPresentation {
    static func canSubmit(_ text: String, isSending: Bool) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && value.count <= 4000 && !isSending
    }
    static func isOverLimit(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count > 4000
    }
    static func roleLabelKey(_ role: FlowMessageRole) -> String.LocalizationValue {
        role == .user ? "flow.role.user" : "flow.role.assistant"
    }
}
```

  User bubble brandPrimary/onPrimary, assistant surface/textPrimary radius 20, text selectable/wrapping unchanged raw persisted content. Guide`info.circle` with same`flow.guidance`ID and safety text. Composer existing binding/FocusState/submit callback, minimum 44/send cancel below field at AX, keyboard safe area; no arbitrary fixed bottom. `isSending` label “Enviando e aguardando o Flow…” / “Sending and waiting for Flow…” includes post-send history read; DTO processing only if provided. Cancel “Cancelar espera”/“Cancel waiting” invokes existing cancel, cannot promise remote cost/persistence canceled. Manual retry existing model, no automatic resend, history errors retained. No Markdown parser/typewriter/instant SLA.
- [ ] Build whole-file DEBUG fixture helper with`empty`, `loading`, `processing`, `response`, `error`, `offline`, `longHistory`, `retryOnce` scenarios, exact argument allowlist`--ui-testing-flow-<case>` plus existing`--ui-testing`demo boundary. AppDependencies Debug `.demo` selects helper only when single valid scenario, otherwise existing Demo FlowChat Repository; Release branch never reads arguments. Actor implements existing history/send, deterministic fixed timestamps/IDs/QA content, same key replay and recorded call count. Finite 2-second **mock** delay to observe true `isSending` allowed only test scenario, not production delay/model phase; return one response and then history, no real network. Invalid/multiple args→no scenario, not account switch. `FlowChatPreviewSupportTests` proves argument gating/mock contracts; source/compiled scan proves excluded Release. Local tests reach shell through actual completed Debug journey; if historical completed fixture starts Welcome, finish local onboarding with current server owned mock instead changing completion state.
- [ ] Run `uiux_test s8-1-green -only-testing:BodyFlowTests/FlowChatPresentationTests -only-testing:BodyFlowTests/FlowChatPreviewSupportTests -only-testing:BodyFlowTests/FlowChatModelTests -only-testing:BodyFlowTests/MobileFlowChatRepositoryTests -only-testing:BodyFlowTests/AppDependenciesTests -only-testing:BodyFlowTests/LocalizationContractTests -only-testing:BodyFlowUITests/FlowChatUITests`; `uiux_release s8-feedback` PASS. Assert existing retry key/cancel/session late-response tests unchanged; local mock response not real LLM identity proof.
- [ ] Evidence empty/loading/sending/DTO processing/plain long reply/error/offline/limit/keyboard both locales/themes AX. Historical 7.334 s/8.657 s baseline preserved; user-perceived latency unmeasured until S10 local render baseline. Future Slice 8 subject `refactor(ui): refine Flow experience`, after S8.2.

### Task S8.2 — Reader-preserving scroll/focus and persisted history presentation

**Files:** MODIFY FlowChatView/new FlowChatPresentation; extend T`FlowChatPresentationTests.swift`, U`FlowChatUITests.swift`. KEEP load/send/retry/cancel/invalidate and session owner unchanged; no persisted scroll position/telemetry.

**Interfaces:** pure `FlowChatScrollPolicy.shouldFollow(atEnd: Bool, initiatedSend: Bool) -> Bool` and `shouldAnimate(reduceMotion: Bool) -> Bool`; local view `@State` tracks bottom visibility/own send/last announced message ID, resets with session-owned view. Produces only local navigation/focus policy, no API write.

- [ ] Add RED cases: atEnd == false+send false → false; end true →true; own send true →true; ReduceMotion true →no animation. UI `testNewReplyDoesNotStealHistoricalReadingPosition`, `testCancelAndReopenUsesHistoryWithoutSending`, long history both role labels/accessible status announced once. “Latest message” control only when away from end.
- [ ] Run `uiux_test s8-2-red -only-testing:BodyFlowTests/FlowChatPresentationTests -only-testing:BodyFlowUITests/FlowChatUITests/testNewReplyDoesNotStealHistoricalReadingPosition`; current unconditional `.onChange(count)` animated scroll should fail reader assertion with test fixture, not by changing model data.
- [ ] Implement local policy:

```swift
enum FlowChatScrollPolicy {
    static func shouldFollow(atEnd: Bool, initiatedSend: Bool) -> Bool {
        atEnd || initiatedSend
    }
    static func shouldAnimate(reduceMotion: Bool) -> Bool { !reduceMotion }
}
```

  Track last message visibility via existing ScrollView/LazyVStack geometry preference in local coordinates space with viewport intersection (bottom sentinel at viewport end), not extra .onAppear provider request. Replace unconditional animated scroll with conditional policy; own send set only when existing valid send initiated, cleared after follow/cancel. ReduceMotion uses plain `proxy.scrollTo`, otherwise bounded DS animation. Local Latest message button accessibility ID new `flow.latest-message` only for new presentation control (old IDs technical unchanged); localized “Última mensagem”/“Latest message”. Keep VO reading focus on historical bubble; incoming reply/status announcement once unless user busy reading, no forced AX focus on refresh. No rebranding historical message content.
- [ ] Run `uiux_test s8-2-green -only-testing:BodyFlowTests/FlowChatPresentationTests -only-testing:BodyFlowTests/FlowChatModelTests -only-testing:BodyFlowTests/MobileFlowChatRepositoryTests -only-testing:BodyFlowTests/Prompt14SessionOwnershipTests -only-testing:BodyFlowUITests/FlowChatUITests`; `uiux_release s8` PASS. Reopen view reloads mock repository persisted history without send; full app relaunch mock seed is labeled fixture, not proof of remote durable history. Actual authenticated relaunch needs separate bound gate, no paid completion now.
- [ ] Evidence reader offset before/after incoming reply, manual Latest button, ReduceMotion/VO, keyboard AX, local cancel/reopen and user A/B model invalidation. Review: Critical 0 / Important 0; future Slice 8 commit `refactor(ui): refine Flow experience`. Rollback Slice 8 UI/Debug harness only, not prompt/endpoint/requests.

## MACRO C — CONVERGENCE & FINAL QA

### Task S9.1 — Reconcile actual token/catalog/accessibility adoption across slices

**Files:** MODIFY only audited presentation callers in FILE MAP, catalog, shared-card default/legacy color alias mapping after callers migrated; extend T`BodyFlowPremiumRenderingTests.swift`, `LocalizationContractTests.swift`; CREATE U`PremiumConvergenceUITests.swift`. No architecture repair or new feature.

**Interfaces:** same DS/catalog/semantic IDs and five stacks; consumes captures/review ledgers from all earlier slices. New strings cannot require alternate language storage. Native Accessibility Inspector/VoiceOver observations supplement automated hierarchy checks.

- [ ] Enumerate public literals manually with `rg -n 'Text\("|Label\("|Button\("|navigationTitle\("|accessibilityLabel\("|Locale\(identifier: "pt_BR"\)' apps/ios/BodyFlow/BodyFlow/{App,DesignSystem,Features}`. Classify each literal as existing catalog key, public localizable debt, proper name, server body, Debug-only, technical ID. Do not mass extract or replace all BodyFlow/MPP. Starting examples requiring slice-owned review: AppTab Portuguese labels; ScreenState descriptors/retry; Auth errors/summary; onboarding header/fields/selected state; Today/Plan/Progress/History/Routine/registration titles and formatting; Flow spoken“Você”. Extend patterns for interpolated strings and UIKit `configuration.title`, not only Text calls. Store file/line/classification/copy owner in evidence.
- [ ] Write RED `testEveryReviewedPublicCatalogKeyHasBothLanguages` calling existing lookup for all keys introduced per slice; `testAllTabsAndStateFamiliesAXXXXL` asserts no clipped core copy/overlapping control/hit region deficit. DynamicType render cases all 12 categories/four theme-locales. Do not fix RED by removing key/weakening assertion.
- [ ] Run `uiux_test s9-red -only-testing:BodyFlowTests/LocalizationContractTests -only-testing:BodyFlowTests/BodyFlowPremiumRenderingTests -only-testing:BodyFlowUITests/PremiumConvergenceUITests`; record missing entry or identified layout/contrast problem, not generic“looks wrong”.
- [ ] Fix only identified missed role/translation/layout callsites, compare actual light/dark rendered pair contrast; avoid global alpha/translucency. Consolidate legacy aliases only after consumer review, e.g. `background = color(.backgroundPrimary)`, `surface = color(.backgroundSecondary)`, `primaryText = color(.textPrimary)`, `secondaryText = color(.textSecondary)`, `accent = color(.brandPrimary)`; palette constants remain identical. Warning alias maps feedbackWarning, true error callers already explicit destructive. Default Card`.card` only after review of remaining`.legacy`callers. Use role pairing not copy inverse theme. All DS actual material fallback in Increase Contrast/ReduceTransparency; DifferentiateWithoutColor icon/text/check selected weight, ReduceMotion no animation scroll/orbit/translation. No hard coded brand renaming from persisted message/article.
- [ ] Add en natural copy/format/plural assertions and local day-vs-device zone tests where presentation helper changed; no official reparse/calculation. UI tests rotate left/right, compact native available phone vs logical renders clearly labeled. Local keyboard show/hide/return/sheets focus. VoiceOver manual: read headings/groups/selection/values/units/status once/back close; don't force focus on background refresh. Accessibility audit can be automated with`try app.performAccessibilityAudit()` on each local state; findings must be investigated, not broadly ignored.
- [ ] Run `uiux_test s9-green -only-testing:BodyFlowTests/LocalizationContractTests -only-testing:BodyFlowTests/BodyFlowPremiumRenderingTests -only-testing:BodyFlowTests/BodyFlowSemanticColorTests -only-testing:BodyFlowUITests/PremiumConvergenceUITests -only-testing:BodyFlowUITests/Prompt13AccessibilityUITests -only-testing:BodyFlowUITests/Prompt14AccessibilityUITests -only-testing:BodyFlowUITests/FlowChatUITests`; `uiux_release s9` PASS. All applicable row/state cells §6 reviewed, no architecture deferred from earlier slices.
- [ ] Evidence source copy ledger/all-categories/theme-locale/VO/motion/color/keyboard/contrast actual screens; Critical 0 / Important 0 review. Future commit `refactor(ui): converge themes accessibility and localization`; rollback Slice 9 only, investigate affected consumer before reverting default aliases. Unapproved brand still BLOCKED independently.

### Task S10.1 — Full regression, signed Release and compiled/public-resource scans

**Files:** CREATE `scripts/uiux/premium-surface-scan.mjs`, `.test.mjs`; extend U`PremiumConvergenceUITests.swift`; UPDATE future evidence README/manifest only with actual results. No product code patch under final QA; discovered regression returns to owning slice TDD/task review.

**Interfaces:** Node built-in scanner CLI `node scripts/uiux/premium-surface-scan.mjs --app <signed-app-path> --baseline 7ab3e65771d172ad10ee42a7ab1d4e6edba2c775`; output sanitized JSON counts/classifications/files/hash metadata only; exit nonzero on missing approved public identity/legacy public copy/modified historical asset/missing required translation/Debug fixture leak, never credential values. Technical BodyFlow module/bundle/asset IDs are allowlisted by context, not generic string deletion.

- [ ] Write Node built-in RED fixtures: public“Uso do BodyFlow” must fail; `com.bodyflow.app` internal must pass; public“Dr. Roberto”/“Dr. Robert” must fail; approved PerformeAI/Flow must pass; new unapproved PerformeAI asset must fail approval manifest; modified old asset must fail hash; missing entry/language fail; debug Flow fixture marker in Release fail. Malformed/missing APP path/catalog/error must fail closed, no count-zero success by empty scan. `node --test scripts/uiux/premium-surface-scan.test.mjs` missing module initially RED.
- [ ] Implement scanner using `fs`, `crypto`, `child_process` Node built ins; read source/catalog/approved manifest and **compiled .lproj Localizable.strings/stringsdict and Info.plist** with`plutil -convert json -o -` selected files (not private configuration). Enumerate asset catalog build resource mappings; invoke compiled resource unit checks/native build warnings, check`Assets.car`named resources using available asset metadata or UIImage resolution tests, never raw car strings alone as brand pass. Compare historical Git blob files at baseline byte level, not copied approval hash. Use classification ledger for legacy technical names; scan binary`strings` as secondary candidate finder, not complete proof or automatic rename. Forbidden legacy copy regex recognizes whitespace/period variants; raw Flow history and historical Debug/evidence are excluded with documented source reason, not blanket ignore public views.

```js
// Illustrative scanner core; production CLI validates inputs before using this.
const legacyPublic = /(?:Uso do|Mascote|coach)\s+BodyFlow|Dr\.\s*(?:Roberto|Robert)\b/i;
function checkPublicCopy(text) {
  return { legacyPublic: legacyPublic.test(text),
           productPresent: text.includes('Performe AI') };
}
// Tests must additionally classify plain BodyFlow visible labels, not only these phrases.
```

- [ ] Run `node --test scripts/uiux/premium-surface-scan.test.mjs` GREEN; then `uiux_test s10-unit -only-testing:BodyFlowTests` and `uiux_test s10-ui -only-testing:BodyFlowUITests` serially. Expect selected unit/UI all PASS/zero skipped/unexplained expected failures, no paid network. Debug fixtures pure local; stage/Production accounts not used. Native analyze §4.2; no TS/backend tests necessary unless unexpected outside scope change(which STOP).
- [ ] Run `uiux_release s10`; check same built bundle identifier/display name/selected icon/final manifest and code-sign strict PASS. `codesign -d --entitlements :- "$UIUX_RUN_DIR/DerivedData-s10/Build/Products/Release-iphonesimulator/BodyFlow.app"` inspect only expected Keychain/application identity, sanitize output record; never print configuration/secrets. Signing identity normal existing toolchain; no automatic certificate/profile creation/entitlement rewrite. If sign/Keychain gate fails, BLOCKED, do not force an unsigned override.
- [ ] Run exact scanner against built bundle:

```sh
node scripts/uiux/premium-surface-scan.mjs \
  --app "$UIUX_RUN_DIR/DerivedData-s10/Build/Products/Release-iphonesimulator/BodyFlow.app" \
  --baseline 7ab3e65771d172ad10ee42a7ab1d4e6edba2c775
git diff --check
```

  Expected approved brand/catalog/compiled resources/technical allowlist PASS, historical bytes identical, no private config values/Debug Flow host. No “zero bodyflow binary” requirement that would destroy technical identifiers. No claim that binary scan proves raw stochastic reply identity.
- [ ] Local Release Simulator smoke only unconfigured/fail closed launch/auth feedback without accounts or requests; signed app install/launch uses named Simulator and bundle only after codesign PASS. If private **staging**config/authenticated functional QA needed,STOP ask separate bounded authorization exact project/user/request budget before config/invocation; do not inherit past E2E allowances. Production ref `xuxehkhdvjivitduarvb` prohibited; staging `xitugspwfxkcluxvrdeg` not accessed in this plan. Current UIUX code work cannot activate QA legal sets/entitlements/agent configs/keys. Real model completion count must stay 0.
- [ ] Evidence compiled Info/catalog/resources/public copy ledger/byte hashes/codesign/test counts/full state coverage, review: Critical 0 / Important 0. Final QA commit waits for S10.2; proposed `test(ui): complete Performe AI visual regression gates`. Rollback scanner/test only Slice10; failing product patch returned to owning commit.

### Task S10.2 — Complete visual/evidence/performance baseline and honest closeout

**Files:** CREATE U`PremiumPerformanceUITests.swift`; UPDATE evidence README with screenshots/hierarchies/settings/coverage/reviews/performance; approve image goldens only after manual visual review, not by automatic update. No heavy images/network call added.

**Interfaces:** native XCTest metrics/attachments, existing local mock datasets and same app bounds/settings. Produces measured local UI baseline, not backend/LLM optimization or commercial SLA. Future`measure`test iterations are fixtures only, zero actual completion/provider requests.

- [ ] Add concrete XCTest launch baseline and timed existing feed/chat scrolling tests:

```swift
@MainActor final class PremiumPerformanceUITests: XCTestCase {
    func testLocalLaunchBaseline() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-fresh-auth"]
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)
                .matching(identifier: "screen.auth.sign-in").firstMatch
                .waitForExistence(timeout: 5))
            app.terminate()
        }
    }
}
```

  Add feed scroll/run with current Prompt 14 deterministic dataset and Flow's 50 message fixture(current history limit 50), long plain response full wrap. Use`XCTClockMetric`/`XCTMemoryMetric` for the operation after loading, no extra HTTP mock send for render metric. Measure five iterations same host/runtime/settings before and after, record mean/range rather than invent SLA. Instruments manual check main thread/render hot spots only if observed material regression; no LLM latency optimization. Captured 7.334 s/8.657 s remains unchanged historical context.
- [ ] Run `uiux_test s10-performance -only-testing:BodyFlowUITests/PremiumPerformanceUITests`; expected metric artifacts+no inexplicable launch/layout failure. Measurements without available pre-change baseline are labeled baseline only, not improvement/regression proof. Performance assertion RED applies only when specific measurable UI regression characterized, not arbitrary budget invented after data.
- [ ] Execute §6 screenshot matrix/reveal all critical controls before capture; compare **same** width/theme/locale/category/state baseline vs new. Review hierarchy/clipping/truncation/contrast/action priority/nil/stale/U/demo provenance. Different device images need consistent hierarchy, not pixel identity. Native full screens and test-only logical renders labeled separately. Record each unsupported state N/A with source, never “PASS” on empty attachment.
- [ ] Inspect each PNG/hierarchy and sign off review results: Critical 0 / Important 0 before the future final commit. Keep goldens versioned by SHA/fixture/settings; new visual diff needs actual review approval. For real connected journeys not authorized, write NOT VERIFIED separately; local mock action/request count/receipt/UI checks prove only local model contracts. Asset approval missing→Slice1/full brand acceptance BLOCKED even if UI ready.
- [ ] Re-run `uiux_release s10-final`; `git diff --check`; review only allowlisted scanner/tests/evidence additions since last slice and no accidental production change. Authorized future commit `test(ui): complete Performe AI visual regression gates`; report all 11 slice SHAs, actual tests/matrix/remaining DEFER, final clean Git. No push/deploy/distribution inferred. Stop local test Simulators owned by this execution once finished, preserve evidence; no broad Simulator deletion/reset.
- [ ] Closeout no paid infra/provider usage; local artifacts retained by review condition and no other worktree cleanup. Final statuses distinguish UI visual verified scope, full brand approval, rebrand PARTIAL(legacy out of scope), production NOT DEPLOYED, legal activation BLOCKED. No auth E2E/runtime LLM success claim from mock reply.

## 6. Test and screenshot matrix — required future evidence

**Every applicable row/state** at standard logical viewport/Large: Light pt-BR, Light en, Dark pt-BR, Dark en (four cells). Every interactive layout additionally compact/large +AXXXXL in both locales/themes, keyboard where applicable, VO order/44 hit regions, portrait/landscape. All 12 text categories automated per DS family; intermediate categories sampled for screen families. IncreaseContrast/ReduceTransparency, DifferentiateWithoutColor, ReduceMotion per component family plus Flow/onboarding/progress. State codes are copied from spec: L: loading, E: empty, C: content, R: recoverable, O: offline, S: stale previous data, D: disabled/submitting, X: existing confirmation/cancellation, U: unavailable. No fabricated state.

| Screen / exact fixture context | Applicable states | Task / concrete future suite | Required captures / regression focus |
| --- | --- | --- | --- |
| Launch/session neutral | L,C transition | S2.1; PremiumAuthOnboardingUITests | Splash text/new approved mark; no fake empty/retry/delay; root ownership |
| Sign-in | C,L,R,O,D | S2.1; PremiumAuthOnboardingUITests +AppFlow/session/auth suites | Login light/dark/error, keyboard/secure autofill/submit focus |
| Signup | C,L,R,O,D | S2.1; PremiumAuthOnboardingUITests | Confirmation journey/error/secure focus no overlap |
| Recovery/confirmation | C,L,R,O,D where existing | S2.1; PremiumAuthOnboardingUITests | Non enumerating confirmation; Debug-only button absent Release |
| Onboarding restore/container | L,C,R,O,D,U | S2.2; Onboarding Flow/Mobile Repository +UI | Server step/draft/commands/progress/fail closed |
| Welcome/country/timezone | C,R,D; supported search empty | S2.2; PremiumAuthOnboardingUITests | Welcome/search selection native keyboard codes |
| Body/objective/routine/persona | C,R,D; L/U for server options | S2.2; Onboarding models/presentation +UI | Required/optional nil,3 objectives/server styles/AX selection |
| Consent | C,R,D,U | S2.3; Onboarding Completion/Mobile Repository +UI | Legal body required optional explicit actions/uncheck/no invented labels |
| Completion | C,L,R,O,D | S2.3; PremiumAuthOnboardingUITests | Review/server finish before root transition |
| Five-tab shell | C | S3.1; AppTab/Router +PremiumCoreSurfacesUITests | Five tabs order/labels/IDs/stack restore/sheet focus/rotations |
| Hoje | L,E,C,R,O,S,U | S3.2; Today Contract/Presentation/Model +UI | Loaded,empty,error,offline,stale,U; food remaining vs balance; nil |
| Recommendations/mascot | L,E,C,R,O,S,U | S3.2/S7.2; Prompt14TodayMascot +content/model tests | Independent failure/tracking authorized cover/quiet official state |
| Registrar root | C,U; preview L/E/R/O | S4.1; PremiumRegistrationUITests | Entry/capture,explicit local provenance/U not success |
| Text/local photo/audio choices | C,L,R,O,D,U by provider | S4.1; Prompt13Registration/Premium Registration | Capture/analyze input retained/no permission/no external upload |
| Meal/workout proposal/editor | C,L,R,O,D,U | S4.2; models/Prompt13Registration/Premium Registration | Detected/edit/confirm/cancel/expiry/already confirmed; same key retry |
| Hydration/weight/bridges | C,L,R,O,D,U | S4.3; Hydration Weight/Workout +UI | Input date/units/quick choices AX intrinsic height; receipt truth |
| Registration result/sheet | C,L,R,O,D,U | S4.1–3; Task Coordinator +UI | Confirm receipt/error recovery/close/discard task ownership |
| Plano/root/detail | L,E,C,R,O,S,U | S5.1; Plan model/contracts +Core UI | Empty/loaded/metadata/optional/refresh detail |
| Progresso | L,E,C,R,O,S,U | S6.1; Progress/Prompt14Progress +Core UI | No data/data/streak0/nil/duplicate official badges; no chart/range |
| Bloco7.700 | L,C,R,O,S,U | S6.1; Block7700Presentation +Core UI | Official percent present/absent+text/meaning/provenance |
| Perfil/persona | C,L,R,D,U; root preview E/O/R | S7.1; Persona Editor/session +Content Profile UI | Main/demo identity/gated options/save/cancel/focus |
| Biblioteca/filter/pagination | L,E,C,R,O,S,U,D where existing | S7.2; Feed model/Prompt14Library +Content Profile UI | All/Saved/category/cursor/error local/stale/covers |
| Article/cover/save/complete | L,C,R,O,S,U,D; bounded version/access/not found | S7.2; Content/Cover/Markdown +UI | Long canonical body/link policy/authorization/receipt status |
| History/meal/workout detail | L,E,C,R,O,S,U where existing | S7.3; History model/contracts +UI | Readonly lists/detail nil/provenance,no edit/delete |
| Routine/list/detail/history | L,E,C,R,O,S,U where existing | S7.3; Routine Model/Snooze/Prompt13Routine +UI | Occurrence ownership/kind/timezone/history pagination |
| Routine action/snooze | C,L,R,O,D,U | S7.3; Routine Action +Content Profile UI | Explicit confirm/presets/receipt/conflict manual recovery |
| Flow history/empty/composer | L,E,C,R,O,D,U via error | S8.1; Flow Presentation/Model/Repository +FlowChatUITests | Empty/keyboard/4000 guard/long plain history/role labels |
| Flow send/wait/reply/retry/cancel | L,C,R,O,D +DTO processing/failed | S8.1–2; Flow Model/FlowChatUITests | Processing/response/error/local cancel/same key/reader position/reopen |
| Future account destructive template | X,R,D **DEFER/N/A** | No implementation task | N/A: no current native action/wiring; no inert row/confirmation |
| Historical trends/range chart | **DEFER/N/A** | S6.1 asserts absence | N/A: ProgressSnapshot has no history series; future chart summary/list/shapes contract not implemented |

Minimum naming: `s<slice>-<screen>-<state>-<theme>-<locale>-<width>x<height>-<category>-<fixture-kind>-<source-sha>.png` +same base`-hierarchy.txt` and ledger row. Settings entry also actual runtime/device/safe area/rotation/motion/contrast/build/sign/fixture. Current historical screens retained not golden at current HEAD; capture pre-change actual baseline in each future task. Missing old baseline→record new baseline only.

Pixel comparison: same deterministic fixture/settings/device; mask only known non deterministic OS clock/status regions with documented review, never mask clipped text/error/status. Semantic tests assert title/action/units/provenance/roles/IDs/reachability and expected state; screenshot image alone is not receipt/persistence. Release captures label actual unavailable/fail closed state, never use Debug success fixture with Release caption. Signed real auth/Flow functional gate additionally requires future authorization; no automatic new run/completion.

## 7. Self-review, coverage traceability and execution handoff

| Approved spec requirement | Concrete implementing task(s) |
| --- | --- |
| §1 authority/baseline/boundaries | Plan §1/§4.3; every task preflight; S10.1/2 limits |
| §2 goals/non-goals/preservation | Global Constraints/FILE MAP KEEP; S3.1 native 5 tabs; S2 auth/server; S4 official attempts; S8 API preservation |
| §3B2 principles/reference interpretation | S0 roles/components; S2 vertical forms; S3 official hierarchy; S4 real meal review; S6 no invented score |
| §4 capability table/demo/U/Flow reachability | S3.2 U entry, S4.1 classification, S5/S6 bounded data, S7 unsupported account DEFER |
| §5.1 all semantic colors/pair contrast | S0.1 exact table+tests; S0.2 components; S9 actual rendered contrast |
| §5.2 type/spacing/radius/elevation | S0.1 native aliases/constants; S0.3 all categories; all owner opt-in; S9 convergence |
| §5.3 actions/fields/metrics/states/icons/material/motion | S0.2/3; S2 form; S4 bridge/review; S8 info/reader; S9 native opaque/motion |
| §6.1 splash/real restore | S2.1 +S1.3 asset dependency; App Root machine KEEP |
| §6.2 auth | S2.1 neutral recovery/native focus/keychain regression |
| §6.3 all seven steps/legal/resume | S2.2/3; no doc lifecycle writes/new legal title mapping |
| §6.4 shell/Hoje/distinct metrics/independent entries | S3.1/2; no score/daily calculation/provider integration |
| §6.5 registration/edit/expiry/captured key/UIKit | S4.1/2/3; no media/new macro goals/multi item calculation |
| §6.6 plan | S5.1 official sections/detail reload/nil/timezone |
| §6.7 progress/block/conditional chart contract | S6.1 current values/absence of unsupported charts; conditional future contract explicit DEFER |
| §6.8 profile/content/history/routine | S7.1/2/3; supported routes only/new account wiring DEFER |
| §6.9 Flow/composer/status/scroll/long content/history | S8.1/2; truthful combined wait/plain text/cancel local/history models |
| §7 new identity/distinct bytes/manifest/approval/icon | S1.1/2/3 and §5 exact files/license/hash; only human approves final bytes |
| §8 catalog/device/AX/input/timezone | S0.3; each owner locale checks; S4 bridges/S7 timezone; S9 all categories/rotations |
| §9 every applicable state/matrix/evidence | Every task screenshot gate; §6 row task mapping; S9/S10 captures/real vs demo |
| §10 bounded 11 slices/TDD/signing | Macro A/B/C: 24 tasks; §4 commands; S10 signed codesign gate |
| §11 rollback/all nonregression families | §4.3+per-slice commit units; neighbor selectors in each task; full S10 unit/UI |
| §12 remaining decisions/safe defaults | S1.2 human STOP/icon STOP; no photo; no feature expansion; unknown legal titles kept |
| §13 self review/truthful status/closeout | This section/S10.2 evidence/commit guards; no paid infra |
| §14 primary design guidance | Approved spec references retained; no unverified new platform recommendation |

Highest-risk surfaces: explicit long consent/server finish; native auth keyboard+Keychain/session root; registration UIKit bridges/confirmation/retries; Library large view tracking/cover ownership; Flow local cancel/history/key/reader focus. Rollback commits isolate them; no DS consumer migration without its contract/UI tests.

Task review checklist: all FILE MAP existing paths verified or CREATE explicit; exact new interfaces defined before consumers; actual UIKit/coordinator/actions preserved; no official calculation/client expiry business rule; no new API/adapter/support/delete/logout/media/chart; no brand bytes fake approval; all unsupported states recorded N/A with source reasons; no placeholder steps or non contextual mass string scan; no technical ID/telemetry migration.

Planning-task verification is documentary only: approved spec/audit read fully; current files/interfaces/targets/source capabilities consulted; no xcodebuild test/build/analyze/UI capture performed, no brand generated/integrated, no providers contacted. Future commands specify expected results, **not** report existing PASS. Content/diff/path/type/placeholder/scope checks are the relevant current gates. Resource gate NOT REQUIRED; no paid environment created/adopted; cost closeout NOT APPLICABLE.

After reviewed plan: first executable batch is Slice 0 three tasks, no asset approval needed; future code operation must supply current HEAD and reviewed allowlist. Do not start implementation now. A later worker can use executing-plans inline; delegation is an explicit later choice, not automatic dispatch.

Current operation authorized commit: exactly one documentation commit, parent `7ab3e65771d172ad10ee42a7ab1d4e6edba2c775`, subject `docs(uiux): plan Performe AI premium refinement`, stage only this plan (and directly necessary documentary evidence if created), no amend/push/PR/merge/deploy. Resulting SHA/tree are reported after commit, not self-embedded. Worktree/index must be clean after commit; no historical state/worktree cleanup.

Expected planning status `PERFORME_AI_PREMIUM_UIUX_IMPLEMENTATION_PLAN_READY`; UI/UX REFINEMENT STATUS `IMPLEMENTATION PLAN READY`; LOGO DESIGN STATUS `DIRECTION APPROVED / FINAL BYTES PENDING`; REBRAND STATUS `PARTIAL`; PRODUCTION STATUS `NOT DEPLOYED`. Stop after plan report.
