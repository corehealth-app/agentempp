# Original command meal feedback service (private)

`createSupabaseConversationMealFeedbackService(db, dependencies?)` exposes:

- `ensureOriginal({ auth, command, receipt })`: optional enrichment only after an actual mandatory command effect receipt. Read an existing immutable receipt first; if absent, prepare and seal from the stored original observation.
- `readOriginal({ auth, command, receipt })`: immutable receipt read only. It never loads source, clinical policy, day, education, or creates feedback.

Both return `registration.feedback.v1`, `registration.feedback.v2`, or `null`. Names intentionally describe **original historical** feedback. A public current clinical presentation/mask is a separate future gate. No route, native reader, capability flag, registration, daily initialization, food/training/analytics effect, LLM, or calculator is activated by this module.

## Binding and read order

The actual defaults are `createSupabaseConversationMealFeedbackStore` and `loadFeedbackV2ClinicalContext`; dependencies allow focused tests without external effects. Construction performs no I/O. The authenticated domain owner, original command and mandatory `conversation.meal-effect.v1` receipt are recomputed/validated and detached before awaiting. Identity gaps fail to `null` before reads. Store callbacks and the clinical loader are captured before the first await. Authentication tokens are retained only for the private clinical call and are not passed to the feedback store or returned/logged.

The effect parser is the unchanged shared parser exported by the command feedback store. It binds owner, command, input hash, provider identity, selected meal kind, date/timezone and distinct actual log IDs. The service binds the original source receipt to that exact mandatory effect receipt, reparses `parseFeedbackV2Capture`, and checks original proposal/event/date/log identities before any optional clinical read. Returned feedback is parsed with its explicit v1/v2 action, detached and frozen.

Read order is receipt → original source → optional clinical/day proof → one seal. A saved v1/v2 first winner returns before source or clinical work; legacy is preserved without migration. Stale epoch/event conflict stops. `original_context_unavailable` returns `null`; there is no generic T2C capture, current-source substitute, or later recapture to manufacture an original context.

## Original facts and optional clinical proof

All item names, quantities, sources, per-log nutrition, meal totals, date and registration identity come from the actual saved original observation and pure `prepareRegistrationFeedbackV2`. Locale comes only from that observation's clinical body: the existing valid profile locale `en-US` selects English; `pt-BR`, missing or unsupported values use Portuguese. Mutable client/current account locale cannot rewrite a historical receipt. Education is the existing deterministic template with `preferencesKnown: false`; no relationship summary is treated as a confirmed preference.

The original captured clinical policy is projected through the existing validated C11 public-policy projector. It is explicitly historical policy, never a new current authority or a current capability header. The real qualified clinical bridge may read the current C11/day surface solely to prove equivalence with that original observation. Its policy must equal the original policy, and `proveFeedbackV2Day` must confirm the day/log/snapshot/progress association again before numeric day/block facts are included.

If current C11 changed, a numeric day read fails, the policy differs, or the day no longer matches, the service withholds the optional day and its progress numbers. It may still seal original factual feedback with the original policy and `day: null`. It does not mislabel current values as historical or replace original clinical facts. The original pause/incomplete policy and the shared pure preparer protect goals, block, protocol and education. Profile/calculated targets are never promoted into official saved snapshot goals.

## Seal, recovery and failure isolation

Only the command feedback store's optional seal is called. Commit/replay/legacy results retain SQL first-winner behavior. An explicit refusal yields `null`. A thrown seal response is an unknown outcome: perform exactly one immutable receipt read, with no second seal, source/clinical reload, recalculation, registration or provider call. A failed recovery returns `null`.

Every optional failure, including constructor/configuration failure, is contained. No private clinical/provider detail is logged or returned. `null` means feedback unavailable and must never turn the already-saved mandatory meal into failure. The caller must obtain and bind the mandatory effect independently before invoking this service; the service does not establish success by HTTP200 or fabricate an effect.

## Qualification limits

Unit tests cover read-first v1/v2, read-only replay, unavailable original, owner/event gaps, source mismatch, callback/input detachment, original locale, pause, missing goals, current drift, incompatible day, real default store/default loader, actual qualified C11 read-model composition, and single-read lost-seal reconciliation. They use synthetic data and SDK/reader mocks; no provider, PG, cloud or native runtime is involved.

Actual SDK/REST qualification of the complete saved registration → original capture → real current C11/day/block proof → feedback seal/replay remains root-owned. A complete first-save display must include actual official day/block when proof is available; historical replay must return the immutable winner. Current clinical presentation/masking is mandatory before any eventual public route or native/history activation. This leaf is not that public presentation surface.
