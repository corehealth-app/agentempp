# Command meal interpretation (private, inactive)

The BFF leaf in `apps/admin/src/lib/mobile-api/conversation-meal-interpreter.ts` performs one permissionless model interpretation of the complete command source. It is not called by a public route, does not use the legacy conversational agent, and cannot invoke tools or write registrations, daily state, analytics, or feedback. No provider request was made to qualify this increment.

## API and ownership

`buildConversationMealInterpretationSource(boundCommand, capturedSource)` recomputes the original command binding and validates the owned, frozen `conversation.meal-source.v1` capture. It does not use the legacy verbal-intent gate or recapture media. Text commands include their entire original text. Media commands require the existing explicit `register_consumed_meal` action and include the full captured caption, transcript, or processed visual item array. Captured units must exactly match the derived units; a missing negative caption cannot be hidden by omitting its unit. The packet retains epoch, capture time, asset ID, processed/updated timestamps, and a deterministic hash of the original processing JSON. No clinical context is sent to the model.

`createOpenRouterConversationMealInterpreter(apiKey, injectedComplete?)` is inert until `interpret(source, { attemptId, remainingMs })`. It captures/detaches the source, invocation, and provider callback before awaiting. The caller must supply a DB-minted attempt ID from the durable invocation CAS, not a locally renewed ID. The resulting envelope binds the original owner, command ID, input hash, source hash, and attempt ID; the model cannot choose those fields.

`parseConversationMealInterpretation(raw, binding)` is a closed header decoder for an already SQL-sealed private result. It binds all five identifiers/hashes and detaches/freezes the result. It is not a replacement for validating arbitrary model output against the frozen source. The SQL result hash remains opaque; do not rehash provider costs in JavaScript, whose number serialization can differ from JSONB canonicalization.

## Closed DTO

The model emits exactly `schema`, `decision`, `reason`, `sources`, and `foods`, with schema `conversation.meal-interpretation.v1`. The persisted envelope adds `interpreter_version: conversation.meal-interpreter.v1`, `owner_id`, `command_id`, `attempt_id`, `input_hash`, `source_hash`, `source_units`, and `provider_metadata` (`model`, `prompt_tokens`, `completion_tokens`, nullable `cost_usd`, `latency_ms`). All nested objects are closed and all declared fields are required, including explicit null references.

- Decisions: `reported_meal`, `not_reported`, `clarification_required`.
- Reasons: `explicit_report`, `nominal_food_list`, `explicit_media_action`, `dream`, `future`, `habit`, `negated`, `third_party`, `question`, `mixed`, `ambiguous`.
- Source units: `command_text`, `media_caption`, `media_transcript`, `vision_items`. Each source contains `unit`, `classification`, `spans`, and `visual_indexes`. Classification is `reported`, `nominal_list`, `media_pointer`, `visual`, or one of the negative/ambiguous reasons.
- Each text span contains UTF-16 `[start,end)`, `kind` (`food`, `quantity`, `unit`, `report`, `separator`, `other`), and nullable `food_index`. Each food occurrence contains dense `index`, nullable `name`, `quantity`, `unit` references (`unit`, `start`, `end`), and nullable original `visual_index`.

Text spans partition the entire original string in order, without gaps, overlap, normalization, surrogate splitting, or shortened tokens. Every indexed span is claimed exactly once in the same role and occurrence. Quantity/unit associations cannot cross another occurrence and return. Duplicate occurrences in one text source remain distinct. Repeated whole food names across caption and transcript are ambiguous: this leaf neither adds nor merges them. Every captured visual item/index is accounted for; visual quantities are not invented or promoted to patient-reported quantities.

Technical bounds reuse the command/media/candidate surfaces: 2,000 UTF-16 units for text/transcript, 1,000 for caption, at most 30 foods/visual items and four source units, at most 4,096 nonempty spans per unit (also bounded by its text length), safe integer metadata, finite nonnegative costs, and a 128 KiB packet/result limit. Sources are rejected rather than truncated.

## Semantic limits and provider policy

The prompt considers actual first-person reports and bare nominal lists such as `arroz200g; feijão100g` without requiring a verb. It distinguishes dream, future, habit, negation, third party/quotation, question, mixed discourse, and ambiguity. Backend validators establish mechanical full-source coverage and occurrence association, then conservatively downgrade unsupported positive framing to clarification. A span labeled `other` may contain only inert punctuation/whitespace from the existing separator alphabet (` ,;:.!/`); question marks, quotes, words and numbers still need semantic accounting. The original spans and food references remain unchanged, and this exception never upgrades a model refusal. Invalid references and malformed output fail with a redacted unavailable error. Truncated responses, tool calls, duplicate JSON keys, unknown fields, nonfinite numbers, omissions, and provider failures never become successful interpretations.

The observed explicit report span may include a supported meal prefix with the
current-day adjunct, such as `No café da manhã de hoje, consumi`. This has the
same framing as `No café da manhã, consumi`; it still requires a positive model
judgment, the explicit consumption predicate and complete original-source
coverage. It does not assign a meal slot/date, upgrade a negative model result,
or permit future, habitual, negated, dreamed, third-party or mixed discourse.
A previously sealed ambiguous result remains immutable; qualification of a new
version uses a new synthetic original rather than replaying that old attempt.

`reported_meal` is an internal sourced model judgment, not mathematical proof of consumption or food identity. Lexical screening and parser/model agreement cannot prove arbitrary prose is a food name. Before any writer can use it, actual whole-name food resolution and the separate command/preparation/SQL proof fences must qualify the original spans. Unfamiliar discourse must not become authority through fuzzy catalog matching. These requirements also apply to processed visual names. This leaf contains no `complete_source`, `consumed_meal` proof, nutrition, current clinical authorization, or public presentation authority.

The real seam is the existing `OpenRouterLLM.complete` with the existing `MEAL_TEXT_EXTRACTION_MODEL` (`anthropic/claude-haiku-4.5`), temperature zero, JSON object response, no tool registry/executor, `maxRetries: 0`, and timeout `min(45_000, remainingMs)`. Output is explicitly capped at the existing provider default of 8,192 tokens because the old 800-token food extractor cap cannot represent 30 occurrences plus complete span partitions. An exhausted budget is refused before transport. There is no new model, dependency, pricing assumption, or USD cap. Real provider latency, token consumption, cost, and output conformance remain unverified until an authorized bounded provider QA.

## Durability and integration gates

The caller must read durable results first, claim at most one physical provider attempt by CAS, persist/seal the validated result, and replay it without another provider call. Started/unknown attempts have no automatic TTL retry or reclaimed UUID; lost start/result responses require read-only reconciliation. This leaf does not implement that store or grant a second attempt. Transport orchestration must not treat a returned model result, HTTP 200, or parser agreement as registration success.

Remaining gates are the durable invocation adapter/service and real SDK/REST qualification, whole-name source resolution, calculation/preparation proof assembly, effect/feedback writing under the existing epoch/idempotency fences, current clinical presentation, and eventual public Flow activation. Unit tests use synthetic keys and injected completion responses (including the real constructor seam); they verify no external provider effects. Existing release/native navigation and the encrypted outbox activation gate are unchanged.


### Ambiguous-result screening observation

A completed ambiguous interpretation emits a content-free structural observation
at the source-label materialization/semantic-validation boundary. It records only
closed decision/reason/unit/classification enums, the model food count and span
run counts by the six closed roles. This distinguishes a model ambiguity from a
positive model judgment conservatively screened to ambiguity. It includes no
source text, food names, token labels, offsets, identity, hashes, provider body or
provider metadata. No observation is emitted for accepted positives or malformed
provider output. Observer failure does not change the result or authorize another
model call. The canonical response, immutable stored decision, writer fences and
single-attempt policy are unchanged. An old sealed ambiguity is never retried to
qualify a newer interpretation version.

The optional validator observation also reports a bounded set of closed guard
reason codes from the existing conservative screening predicates. The predicates
and canonical refusal stay unchanged. The interpreter logs only its constructed
safe projection as JSON so nested role counts survive the runtime logger's
inspection depth. Throwing reason/log observers cannot affect validation.
