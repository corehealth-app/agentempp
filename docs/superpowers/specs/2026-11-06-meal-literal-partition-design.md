# Meal interpretation with literal source partitions

The approved conversational plan requires genuine free-text meal reports to use the existing nutrition services and persist only source-bound facts. R67 proved a model-schema rejection. R68's strict schema request passed that stage, then a real synthetic meal was rejected at `span_range` (2026-11-06T22:16:13.122Z). The exact invalid span is unavailable. The model currently performs character-offset arithmetic; the server correctly refuses invalid ranges. No saved meal or complete Flow is claimed.

This is an implementation decision under the user's autonomous technical authorization, not a new business rule. The user already delegated routine implementation decisions and opted out of repeated technical approval questions. The full approved plan and all 20 delivery areas remain active.

## Approaches and decision

More prompt examples leave numeric offsets probabilistic. Retrying or repairing/clamping model offsets risks extra spend or weakened source proof. Instead, request literal, ordered parts from the model and compute UTF-16 positions on the server, after exact source equality. This is the selected technical approach; it was not separately selected by Roberto.

## Private wire and canonical boundary

Use a private `conversation.meal-literal-partition.v1` model response with the same decision/reason and source classification/visual indexes. Each source contains `parts: [{text, kind, food_index}]`; each food retains its dense index and visual index, but text references are nullable `{unit, part_index}`. Reuse canonical enum/schema components rather than introducing different meanings. Provider schema remains strict, derived with the existing OpenAI helper, with only its documented unsupported numeric/cardinality keywords removed in transit.

The backend validates the complete wire object, exact ordered source-unit membership, bounded arrays, nonempty text parts, and `parts.map(text).join('') === originalSource.text` without trimming or normalization. Each unit's cumulative JavaScript string lengths define its UTF-16 start/end values. Reference indexes must identify a part in that same source; the canonical validator still checks role, occurrence, density, cross-unit binding, complete coverage, Unicode boundaries and semantic consumption. Vision units have no text parts and keep their exact original visual index list. There is no numeric-offset fallback, search-based reassignment, clamping, normalization, repair or second completion.

Convert to the existing `conversation.meal-interpretation.v1` model, then run the canonical validator and existing result binding/SQL persistence. The wire adapter does not alter those checks; the separate contextual-report companion below extends one closed lexical marker. Store only the current canonical format. Existing completed receipts, historical reads, unknown attempts, interpreter version and CAS lifecycle remain unchanged. Failures retain the existing public error and closed diagnostic vocabulary; never log literal text, provider output, indexes, source identities or arbitrary error details.

## Explicit limits

This wire change removes model character arithmetic. It does not prove consumption, nutrient correctness or complete app delivery. The pre-companion canonical marker rejects `No café da manhã, consumi`; the companion must characterize and qualify that semantic correction separately. The combined connected QA must retain the original 63-character case, without fabricating a meal hint or weakening `saved200` acceptance.

No new model, key, dependency, retry, budget, formula, SQL migration or app release is part of this private-wire correction. Use Haiku4.5, strict schema, `require_parameters: true`, 8192 tokens, 45 seconds and zero SDK retries. The approved QA key remains capped at US$1 total with its original expiry. Never retry R66/R67/R68 unknown attempts.

## Evidence and review

Evidence is under the task cache `performe-r68-structured-meal-preview-20261106`: `qa-r68/SAFE-RUNTIME-DIAGNOSTIC.json` and `LITERAL-PARTITION-DESIGN-REVIEW.md`. Builder review requires explicit literal fixtures and separate canonical-validator negative cases, not an invisible conversion of numeric provider mocks. Source equality, Unicode, repeated occurrences, cross-source references, negative/future/habit reports, media pointers, one unknown mark and no repeat provider calls are acceptance gates. Actual provider QA, native UI and TestFlight remain separate.

## Companion increment: explicit leading meal context

The literal adapter alone cannot satisfy the original connected example. A separately characterized companion change will accept only the closed leading contexts “No café da manhã”, “No almoço” and “No jantar”, followed by a predicate that the existing report marker already accepts. It keeps the full original source and all bindings. Negation, habits, future plans, third-party and mixed clauses retain their existing refusal paths. A caller-selected meal still takes precedence; without selection, the existing explicit-meal detector remains authoritative, never the clock.

This is a narrow expansion of the canonical lexical report marker, not a canonical DTO or SQL proof change. There is no duplicate SQL report-marker regex to migrate. The original 63-character milk/whey report without an invented meal hint must be exercised in connected qualification; a changed sentence cannot substitute for that case. All prior literal-partition and canonical rejection tests remain applicable.

The actual registration composition also characterized an existing ASCII word-boundary defect after accented meal names. Correct its terminal boundary in the existing meal-type detector, retain explicit-selection precedence, and reject suffix lookalikes. Do not use the clock to compensate.

## Companion increment: explicit milk volume inside the compact recipe

The provider may legitimately represent the exact phrase as one compact food name with the original quantity/volume references preceding it. The existing compact-recipe path supports total mass but refuses mL. For this exact source association only, retain the original reference order and allow only whitespace and the literal connector “de” between the stated unit and compact name. Convert pure milk with the existing volume/density reference and the literal one-measure whey with its existing estimated, editable portion reference. Preserve source groups and qualify both foods. Do not interpret trailing mixture volume as milk volume, invent a cup, subtract whey from milk volume or relabel it as total mass. Existing approved whole-food corrections retain precedence and must still clarify when their density is unproven.

The existing `mobile_household` provenance already allows one original occurrence to produce multiple inputs; no new persisted rule or SQL migration is required. Characterize the old rejection and verify actual calculation, 200 mL milk/one-scoop displays, duplicate groups, limits and existing total-mass/cup/correction cases before connected QA.
