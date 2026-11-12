# Meal literal partition implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Derive exact UTF-16 offsets from complete literal source partitions before the existing meal validator and writer.

**Architecture:** A private wire schema and deterministic adapter feed the unchanged canonical interpretation. The existing interpreter performs one strict provider request and retains the current result binding, failure diagnostics and durable attempt lifecycle.

**Tech stack:** Existing TypeScript, Zod3, OpenAI helper, OpenRouter wrapper and Vitest. No dependency changes.

**Spec:** `docs/superpowers/specs/2026-11-06-meal-literal-partition-design.md`.

## Constraints and review focus

- Canonical/persisted schema, SQL, model, zero retries, 45s/8192 limits and approved budget stay fixed. Only the companion task below extends the closed report-marker grammar.
- Exact source order/concatenation; no whitespace, accent or Unicode normalization.
- Repeated foods and swapped/cross-unit references must retain their independent occurrence proof.
- Negations, future/habit/third-party and mixed reports must not become registrations.
- Visual evidence and text parts cannot be substituted for each other.
- Unknown attempts remain terminal for provider execution; diagnostics contain only static categories.

## Task 1: Private wire, deterministic adapter and interpreter

Files: create `apps/admin/src/lib/mobile-api/conversation-meal-literal-partition.ts` and its `.test.ts`; modify `conversation-meal-interpreter.ts`, `conversation-meal-interpreter.test.ts` and, only if fixtures require it, `conversation-meal-interpretation-service.test.ts`.

Interfaces: export a strict model-only wire schema and `materializeConversationMealLiteralPartition(raw, originalSource, onFailure?)`, returning the existing `MealInterpretationModelResult`. Reuse `MealInterpretationValidationReason` for optional isolated static diagnostics. The interpreter derives its strict provider format from this wire schema, calls the adapter, then the existing canonical validator. The adapter never writes, calls a provider or adds server identity fields.

- [ ] Write failing explicit literal fixtures: milk/whey supported report; exact UTF-16 prefix lengths with accents/astral text; source mismatch/omission/order; empty parts; split surrogate; extra keys; wrong ref role/index/source; repeated occurrences; vision/text mismatch. Keep old numeric invalid-reference tests against the canonical validator directly with their exact reasons.
- [ ] Confirm RED before implementation. No hidden mock conversion or weakened assertions.
- [ ] Implement bounded wire parsing, complete source equality, per-unit cumulative offsets and index-based references. Preserve every canonical guard and downgrade; retain the unsupported breakfast-prefix case as clarification.
- [ ] Update prompt only for private literal response format; preserve consumption rules. Derive strict schema from the new wire; verify closure/required/nullability and the same narrow provider projection without assuming the old object count.
- [ ] Verify actual interpreter/service composition: one provider call; failure marks unknown once; read/repeat never starts another attempt or commits. Cover invalid raw output, tool/truncation outcomes, concurrent diagnostics and privacy.
- [ ] Run focused literal/interpreter/service/materialization/registration and provider tests, nonincremental types and scoped Biome. Return exact frozen paths, first RED and final results to Root; no independent commit or cloud call.

## Task 2: Integration, connected qualification and closeout

- [ ] Root reviews the complete increment once; obtain one independent focused review. Run appropriate full Admin/Providers/BFF suites and a fresh BFF build with closed graph checks. Recertify only attributed code/edges; never blind-update pins.
- [ ] Commit/push the exact source and source-bound package to the existing staging project. Preserve the canonical app origin until qualification. No old migration or unknown attempt is replayed.
- [ ] Execute one newly named synthetic case with the original breakfast milk/whey report and no fabricated meal hint, actual source codecs and audited temporary entitlement. Require saved200, six sections, exact persisted numbers and lookup without duplicates. Independently close the own grant and Auth session in finally.
- [ ] If rejected, retain evidence and close the exact owned Preview after dependencies end. If successful, retain with owner/expiry for native text Flow QA, rebind the primary Debug app to the real candidate, then qualify editing/reopen/undo and subsequent release separately. Do not mark the full goal complete.

## Companion task: original meal-context regression

- [ ] Characterize the exact original breakfast report and a lunch report as RED. Implement only the closed leading meal contexts in the existing report marker; preserve all other validation and source fidelity.
- [ ] Cover negation, habitual/future/third-party statements and mixed clauses; keep selected-meal precedence and existing explicit-context detection. No new SQL regex, hint fabrication or clock inference.
- [ ] Update only the original known-limitation expectation with its explicit new behavior. Freeze this companion delta separately, then review and qualify it with the literal adapter.
- [ ] Connected QA must use the original “No café da manhã, consumi 200 mL de leite com 1 medida de whey.” source without a fabricated meal hint. Existing unknown attempts remain untouched; require a newly named case and actual saved200/six-section readback.
- [ ] Characterize and fix the accented terminal-boundary defect in the existing meal-type detector; preserve selection precedence and reject suffix lookalikes.

## Companion task: explicit milk volume before the compact recipe

- [ ] Prove current compact-name/preceding-volume rejection as RED. Extend only exact source association using existing pure-milk conversion and whey portion references, with `mobile_household` provenance; no new persisted rule/SQL migration.
- [ ] Verify 206 g calculated milk plus 30 g referenced whey for 200 mL/one measure, with visible 200 mL/one-scoop units through actual registration composition. Preserve whole-food correction precedence, mass/cup behavior and source coverage.
- [ ] Reject trailing mixture volume and unsupported association; cover duplicated legitimate consumptions and item limits. Root reviews the combined increment once and runs broader gates before another provider request.
