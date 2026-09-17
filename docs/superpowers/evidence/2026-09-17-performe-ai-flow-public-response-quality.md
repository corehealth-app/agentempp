# Performe AI — Flow public response quality (local)

Operation: IMPLEMENT_PERFORME_AI_FLOW_PUBLIC_RESPONSE_QUALITY_V1.
Approval: implement the approved mobile_flow context/prompt approach using TDD;
no iOS changes and latency baseline only, without optimization.

## Scope and authority

- Host: MacBook-Air-de-Eduardo.local, Darwin 25.6 / arm64, local development.
- Repository: /Users/eduardohenrique/Developer/performe-ai-client-beta-flow-v1.
- Branch: codex/performe-ai-client-beta-flow-v1.
- Starting HEAD / required commit parent: 710be04bea8982e0ac23bd70736be0e28cab3efb.
- Starting worktree clean; index empty. No new branch or worktree.
- Production allowlist: packages/agent/src/pipeline.ts only.
- Related test: packages/agent/src/mobile-authenticated-pipeline.test.ts.
- Third and final changed file: this evidence document.
- No iOS, schema, shared database rule/config, tool, model/provider, deployment,
  retry, cache, streaming, telemetry implementation or dependency changes.
- No push, PR, merge, deploy, real completion, provider mutation or CI-3 execution.
- Supabase and OpenRouter were not accessed in this operation. Production was
  neither accessed nor changed. Existing staging infrastructure was not changed.

Authority: approved request, beta spec/plan and existing baseline/integration
evidence. Historical runtime results below are preserved evidence, not new live
verification of configuration or provider state.

## Root cause and final prompt path

The shared persona master in
supabase/migrations/20260502130000_persona_amigo_coach.sql defines the legacy
doctor as an experienced nutritionist conducting Metodo MPP via WhatsApp, plus
a decorative Markdown section. The previous mobile projection replaced only
the doctor's name. That left the positive professional/method claim and bold
instruction attached to Flow; this explains the observed public response.
Country/persona rules in 20260502180000_i18n_phase2.sql are shared legacy
context, not a mobile-only configuration to mutate.

Actual local assembly path:

1. The mobile-bff Flow chat route reexports the Admin mobile route. That route
   calls processAuthenticatedMessage with the authenticated technical user.
2. processAuthenticatedMessage selects historyProvider=mobile_flow, the existing
   read-only tool allowlist, mobile policy and content-free telemetry options.
3. loadActivePrompt reads v_active_prompts for stage and generation settings.
   prompt-rules.ts selects active general/stage rules retaining pt-BR base,
   the saved language and neutral (null-language) rules, formatting topic/content
   blocks. If no usable rules are
   loaded, the view's system_prompt remains the fallback. Global config used by
   the pipeline supplies deterministic calculation settings, not a new persona.
4. Only mobile_flow projects the known persona introduction into
   "Voce e Flow, assistente de IA do Performe AI", removes the known conflicting
   Markdown instruction section and retains existing legacy-name normalization.
   The other sentences about tone, decisions, internal references and health
   disclaimers remain. No blind filtering of model responses is performed.
5. stableSystem is that channel prompt plus the existing mobile policy, now
   explicitly denying regulated-professional credentials, spontaneous MPP public
   branding/identity and decorative Markdown. Existing health-mutation and
   deterministic-confirmation restrictions remain intact.
6. Optional retrieveMethodContext embeds the turn and queries match_method_chunks
   only when an embedding dependency exists and the text has at least 3 chars.
   Retrieved chunks use "### page_title" boundaries. The same mobile-only input
   projection prevents known persona reintroduction and preserves the next chunk.
   The current mobile route does not provide an embedding dependency; tests
   exercise this optional path defensively, without external embeddings.
7. variableSystem retains user/locale/timezone context, official numeric values,
   repetition guard and rules. Saved history/summary and the incoming user message
   follow the existing assembly path. Policy explicitly overrides inherited
   identity in shared context and historical introductions; history is not edited.
8. Anthropic receives stable and variable system blocks with the existing cache
   setting; other models receive the existing concatenated string. Tests capture
   the real final llm.complete input for both formats. Model, temperature, output
   token budget, tools, iteration limits and deterministic calculations are unchanged.

WhatsApp/non-mobile branches receive their original shared prompt and RAG,
including their legacy names and formatting instructions. MPP remains in internal
contracts/calculations. No global persona or historical channel was rebranded.

## Presentation decision — no iOS change

flow-chat-service.ts persists reply.text unchanged and returns it through the
existing DTO. FlowMessageBubble renders message.content using SwiftUI Text;
the previous runtime displayed the asterisks literally. The repository's
BodyFlowMarkdownView/Parser is for published articles, with a minimum 100 UTF-16
input guard, not an already adopted short-chat renderer. It is not correct to
claim that the repository has no Markdown renderer at all.

Approved choice: an explicit plain-text contract for mobile_flow and removal of
the conflicting known persona Markdown section. No iOS adaptation, homemade
parser, generic markup-stripping regex, new dependency or output masking.
Plain-text instructions cannot guarantee stochastic model compliance; this
operation verifies prompt assembly, not a new live LLM response.

## TDD and regression evidence

- Baseline: Agent 70 files / 1,059 tests PASS; typecheck PASS.
- First RED: focused suite 6 failed / 7 passed. Failures exposed retained positive
  professional/method claims and missing mobile plain-text contract at llm.complete.
- First GREEN: 13/13 focused tests PASS after the bounded prompt projection.
- Optional RAG RED: 1 failed / 13 passed after fixing a fixture's two-character
  input (which correctly bypassed retrieval). It exposed persona reintroduction.
- Optional RAG GREEN: 14/14 PASS after applying the same mobile projection to RAG.
- Review B found an Important boundary issue: a trailing persona Markdown section
  could consume subsequent "###" RAG chunks. Added a two-chunk real-pipeline
  regression before fixing it: RED 1 failed / 14 passed, missing the following
  deterministic calculation chunk. The section boundary now recognizes headings
  of levels 1–3, including the retrieval delimiter. GREEN 15/15 mobile tests.
- Final focused + neighboring rules: 21/21 PASS.
- Final full Agent suite: 70 files / 1,068 tests PASS; exit 0.
- Final typecheck: tsc --noEmit PASS; exit 0.
- Biome related test file: PASS, no fixes or suppressions.
- Whole pipeline Biome: 3 errors / 4 warnings BEFORE and AFTER. Preexisting debt:
  organizeImports, noExplicitAny, whole-file formatting, four noNonNullAssertion
  warnings. This is not reported as a whole-file lint PASS and was not autofixed.
- No tests removed/skipped/weakened; no dependency installation or lockfile change.
- No full app build, Release rebuild or new simulator/functional QA was performed;
  no iOS code changed. Tests use local DB/LLM/embedding stubs and capture the actual
  pipeline boundary, not a canned successful public reply.

Reproducible local commands (repository-root unless stated):

```sh
# From packages/agent, use already-installed executables; no install needed.
./node_modules/.bin/vitest run src/mobile-authenticated-pipeline.test.ts src/prompt-rules.test.ts
./node_modules/.bin/vitest run --reporter=dot
# From repository root:
COREPACK_ENABLE_NETWORK=0 corepack pnpm --filter @mpp/agent typecheck
./node_modules/.bin/biome check packages/agent/src/mobile-authenticated-pipeline.test.ts
./node_modules/.bin/biome check packages/agent/src/pipeline.ts --reporter=json
git diff --check
```

## Independent reviews and diff safety

- Review A (security/health): READY, Critical 0 / Important 0 / Minor 0. Confirmed
  health/credential constraints, input-only projection and server calculations.
- Review B (channel isolation): initially NOT READY, Critical 0 / Important 1.
  After the RED/GREEN chunk-boundary correction: READY, all severities 0.
- Review C: not applicable; no iOS patch.
- Final evidence/diff recheck: both reviews confirmed Critical 0 / Important 0.
  Review A caught a Minor migration filename typo in this document; corrected
  to the actual i18n_phase2 source before the commit.
- Changed-line/evidence scan: 0 provider keys, JWTs, private keys, email addresses
  or signed authentication URLs. Manual diff review and git diff --check PASS.
- Legacy selectors and negative examples intentionally contain legacy names;
  their presence in source/tests is not a positive mobile persona claim.
- Scan scope is changed lines/evidence, not a demand to remove all legacy MPP or
  doctor references from the repository. No credentials, real-user data, QA
  account identifiers/passwords or signed URLs belong in this patch.

## Latency baseline — preserved prior run, not optimized

Source: local private runtime-brand-closeout.md for the final runtime brand gate
of 2026-09-17. No new provider query, completion or performance instrumentation.

| Metric | Preserved observation | Interpretation |
| --- | --- | --- |
| Pipeline latency | 7,334 ms | Existing pipeline aggregate, not a per-step trace |
| Input persistence | 2026-09-17T12:38:36.043Z | Database timestamp |
| Output persistence | 2026-09-17T12:38:44.700Z | Database timestamp |
| Persistence delta | 8.657 s | Not a measured total HTTP request or user-perceived latency |
| Provider TTFT | 1.09 s | Prior OpenRouter observation; not a new measurement |
| Provider routing overhead | 0.25 s | Prior observation; not total inference duration |
| Model | anthropic/claude-sonnet-4.6 | Prior single runtime generation |
| Completions / tokens / cost | 1 / 5,683 prompt + 26 completion / US$0.029718 | Prior gate only |
| User-perceived time from tap | NOT MEASURED | Cannot attribute perceived delay entirely to model |

Per-step app, BFF/auth, pre-provider, inference, persistence and return timings
are NOT MEASURABLE from this evidence alone. No full-path subtraction estimate is
presented as a measured trace. Prior finish reason was stop; no tool loop was
observed. Detailed upstream retry count was not verified. This patch makes no
latency-improvement claim and introduces no optimization.

## Closeout and verification limits

- Current operation completions: 0. Provider spending: none from this operation.
- New paid environments: none; environment/cost closeout: NOT APPLICABLE.
- Prior QA closeout is preserved historical evidence, not rerun here.
- Commit policy: exactly one local commit with the required starting parent and
  subject "fix(flow): align mobile public persona and response presentation";
  only the three allowlisted files may be staged. Commit SHA/tree recorded in
  the final report (cannot self-embed the resulting commit identity).
- No push, PR, merge or deployment. Production remains NOT DEPLOYED by this task.
- REGRESSION STATUS: VERIFIED for the local Agent scope; no new real-model or
  end-to-end runtime claim.
- IOS INTEGRATION STATUS: VERIFIED only for the previously proven vertical slice;
  unchanged and not re-executed in this operation.
- REBRAND STATUS: PARTIAL; other legacy assets/coach/prompts remain NEEDS_REVIEW.
- UI/UX REFINEMENT STATUS: NEXT WORKSTREAM, not started.
- LEGAL ACTIVATION STATUS: BLOCKED; no legal activation was performed.
