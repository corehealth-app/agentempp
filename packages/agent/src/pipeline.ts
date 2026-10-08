/**
 * Pipeline central de processamento de mensagens.
 *
 * Versão MVP (síncrona, sem buffer/Inngest):
 *   1. ensureUser     — cria user + perfil + progress se não existir
 *   2. loadContext    — perfil, progresso, últimas mensagens
 *   3. resolveStage   — onboarding ou protocolo ativo
 *   4. loadPrompt     — v_active_prompts do stage
 *   5. callAgent      — LLM com tools, loop até finalizar
 *   6. persistTurn    — salva mensagens in/out
 */
import {
  computeMetrics,
  dailyTargetByProtocol,
  dayEnergyBalance,
  eatingBalance,
  type ProfileRow,
  resolveProtocol,
} from '@mpp/core'
import { loadCalcConfig } from './calc-config-loader.js'
import { loadDailyTargets } from './calc-targets.js'
import { throwIfQueryFailed } from './db-query-error.js'
import {
  auditNumericClaims,
  detectDeficitRealMismatch,
  detectPrematureBlockCompletion,
  detectSentimentMismatch,
  reconcileBalanceProse,
} from './numeric-validator.js'
import {
  hasBalanceCard,
  injectCanonicalCard,
  renderBalanceCard,
  replaceLooseBlockMentions,
} from './balance-card.js'
import { getLocalDateMinusDays, getLocalDateString, getLocalHour } from './timezone-utils.js'
import { buildPendingTiming, burstCrossesLocalDate } from './registration-time.js'
import {
  answersFlowQuestion,
  asksExerciseFoodQuestion,
  lastReplyIsSameAnswer,
  renderExerciseFoodAnswer,
  statedWorkoutCalories,
} from './exercise-food-guard.js'
import {
  type FlowDayRow,
  flowDayBalanceInputs,
  flowEnergyContextLines,
} from './flow-energy-context.js'
import { isMultiTimezoneCountry } from './location-timezone.js'
import {
  buildPendingNutritionConfirmationNotes,
  buildPendingPreparationQuestions,
  composePendingProposal,
  composePostRegistrationMessage,
  composeReevalResultMessage,
  composeStatusMessage,
  embedEduComment,
  isPureRegistrationTurn,
  isPureStatusQueryTurn,
  isReevalToolTurn,
  normalizePendingFoodCorrections,
  type MealItem,
  type RegistrationEntry,
} from './post-registration-message.js'
import { reconcilePendingMealEdit, reconcileScopedMealCorrection } from './pending-meal-edit.js'
import {
  cancelOpenPendingRegistrations,
  createPendingRegistration,
  loadRecentConfirmedMealPending,
  loadRecentEditedMealPending,
  loadRecentPendingMeal,
  loadRecentRegisteredMeal,
} from './pending-registration-store.js'
import {
  loadDeterministicDailyState,
  loadReevaluationGate,
} from './pipeline-state-store.js'
import {
  makeOnboardingButtonId,
  flattenLegacyTagsForApp,
  parseOnboardingButtonTag,
  parseOnboardingListTag,
} from './onboarding-button.js'
import {
  generateEducationalComment,
  adaptToolItemsToEduInput,
  type EduCommentInput,
} from './educational-comment.js'
import { loadFilteredSystemPrompt } from './prompt-rules.js'
import { routeModel } from './model-router.js'
import { loadRouterFlag } from './router-flag.js'
import {
  isMealExpressEligible,
  isWorkoutExpressEligible,
  type ExpressInput,
} from './express-mode-detector.js'
import {
  calcMealMacros,
  parseUserKcalOverridesFromMessages,
  requiresVisualPreparationConfirmation,
} from './meal-pipeline.js'
import { detectFakeWrite } from './fake-write-detector.js'
import { runToolGuard } from './tools/tool-guards.js'
import { detectFalseDuplicationClaim } from './false-duplication-detector.js'
import { detectCorrectionIntent } from './correction-detector.js'
import { reportVisionCoverageIfLow } from './vision-coverage-checker.js'
import { loadVisionPending } from './vision-pending-loader.js'
import { attachTrustedVisionNutrition } from './trusted-vision-nutrition.js'
import { shouldBlockUntrustedNutritionLabelRegistration } from './vision-nutrition-guard.js'
import { dedupeMealItems } from './meal-item-dedup.js'
import {
  foodNamesReferToSameItem,
  hasExplicitWholeMealReplacementIntent,
} from './meal-replacement-target.js'
import {
  bodyPhotoSignalFromEventProperties,
  composeReevalBodyPhotoWaitMessage,
  deriveBodyPhotoState,
  formatBodyPhotoContext,
  shouldWaitForBodyPhotosBeforeReeval,
  type BodyPhotoSignal,
  type BodyPhotoState,
} from './reevaluation-body-photos.js'
import type { AgentStage, UserProfile } from '@mpp/core'
import type { Json, ServiceClient } from '@mpp/db'
import type {
  LLMCallParams,
  LLMResult,
  OpenRouterEmbeddings,
  OpenRouterLLM,
  SystemPromptBlock,
} from '@mpp/providers'
import type { ChatCompletionMessageParam, ChatCompletionTool } from 'openai/resources/chat/completions'
import { LEGACY_PERSONA_NAME_PATTERN, projectFlowPublicNames } from './flow-public-names.js'
import {
  asksPrivateMetricQuestion,
  flowMetricLocale,
  projectFlowMetricAnswer,
  projectFlowMetricContext,
  renderOfficialTargets,
} from './flow-public-metrics.js'
import { flowPlainStatusText } from './flow-status-text.js'
import {
  ensureSuggestionShown,
  isPurePlanSuggestionTurn,
  isSingleRequestMessage,
  turnSuggestions,
} from './plan-suggestion-text.js'
import { ALL_TOOLS, getToolByName } from './tools.js'
import type { ToolContext, ToolDefinition } from './tools.js'
import { zodToJsonSchema } from './tool-schema.js'
import { normalizeToolArguments } from './tools/types.js'
import type { AgentInput, AgentOutput, AuthenticatedAgentInput } from './types.js'

export interface PipelineDeps {
  supabase: ServiceClient
  llm: OpenRouterLLM
  /** Limite de iterações de tool calling (segurança). */
  maxToolIterations?: number
  /** Embeddings p/ RAG do método (sub-projeto D). Opcional: sem ele, sem retrieval. */
  embeddings?: OpenRouterEmbeddings
}

export const MOBILE_FLOW_READ_ONLY_TOOLS = [
  'consulta_progresso',
  'consulta_metricas',
  'consulta_resumo_periodo',
  'consulta_reavaliacao_protocolo',
] as const

/**
 * What the mobile Flow may write: drafts of plans, and nothing else. A draft
 * is not a plan — it becomes one only when the patient confirms it in the
 * app. No tool confirms, and `gera_*` never runs on this channel.
 */
export const MOBILE_FLOW_DRAFT_TOOLS = ['propoe_plano_treino', 'propoe_plano_dieta'] as const

/**
 * Um rascunho de plano foi criado neste turno. A resposta então descreve a
 * sugestão ("conferir, ajustar, corrigir…") e não é escrita fantasma: sem isso,
 * palavras da instrução de revisão casavam com CORRECTION_CLAIM (review
 * 2026-09-30 M2) e a retratação apagava a sugestão.
 */
function draftCreatedThisTurn(toolCalls: AgentOutput['toolCalls']): boolean {
  return toolCalls.some(
    (tc) =>
      (MOBILE_FLOW_DRAFT_TOOLS as readonly string[]).includes(tc.name) &&
      (tc.result as { success?: unknown } | undefined)?.success === true,
  )
}

export const MOBILE_FLOW_TOOLS = [
  ...MOBILE_FLOW_READ_ONLY_TOOLS,
  ...MOBILE_FLOW_DRAFT_TOOLS,
] as const

const MOBILE_ONLY_TOOLS = new Set<string>(MOBILE_FLOW_DRAFT_TOOLS)

/**
 * Tools that write the protocol or the goal. When one of them wrote, or
 * refused the goal by its floor, in the turn, "registrado / não foi
 * registrada" in the sentences about the protocol or the goal is about that
 * write (or its refusal), not about a meal: the phantom MEAL-write guard does
 * not read those sentences as a registration claim (review 2026-10-04).
 */
const GOAL_WRITE_TOOLS = new Set<string>(['define_protocolo', 'define_meta_peso'])

/**
 * A return without an exception is not enough: define_meta_peso answers
 * {success:false, error} when sex, current body fat or weight/height are
 * missing. Nothing was written and nothing was refused then, so "Meta
 * registrada" has no tool behind it and the guard must still see it.
 * define_protocolo with the goal dropped returns success:true + goal_saved:false
 * (the protocol WAS written) and counts.
 */
function goalToolRanThisTurn(toolCalls: AgentOutput['toolCalls']): boolean {
  return toolCalls.some((tc) => {
    if (!GOAL_WRITE_TOOLS.has(tc.name) || tc.error) return false
    const result = tc.result as { success?: unknown; refused?: unknown } | undefined
    return result?.success === true || result?.refused === true
  })
}

/**
 * Everything the patient sent in the turn that the pipeline holds as text, for
 * the phantom-write guard: what the patient typed or said (`patientText`,
 * audio transcriptions included) and `text`, which on WhatsApp also carries
 * the automatic analysis of the photos ("Foto [refeição]: …"). When it names a
 * meal or a workout, the exemption of `goalToolRanThisTurn` is off: the goal
 * tool explains nothing about a meal the patient reported in the same turn
 * (third check of 2026-10-04, docs/CALCULO-MPP.md §8b).
 */
function patientTurnTextOf(input: AgentInput, semanticPatientText: string): string {
  const text = input.text ?? ''
  return text === semanticPatientText ? text : `${semanticPatientText}\n${text}`
}

/** Tools that produce a plan or a proposal of one (saved or drafted). */
const PRESCRIPTION_TOOLS = new Set<string>([
  'gera_dieta',
  'gera_treino',
  ...MOBILE_FLOW_DRAFT_TOOLS,
])

export const MOBILE_FLOW_TELEMETRY_INCLUDES_CONTENT = false

/**
 * Flow only: how many history lines one model call carries when the patient's
 * current session has fewer than that. The history is paid at full price on
 * every call (it sits after the per-turn context, so it is never cached): 50
 * lines were ~4,400 of the ~11,000 prompt tokens of a call (staging,
 * 2026-10-04). Only the prompt is windowed — the table read stays at
 * RECENT_MESSAGES_LIMIT, because the deterministic exercise/food answer, the
 * re-entry gap and the body-photo state read the full list. WhatsApp sends
 * everything it reads. See mobileFlowPromptHistory for what is cut.
 */
export const MOBILE_FLOW_PROMPT_HISTORY_LINES = 16

/**
 * Flow only: how far back the current session reaches when it started on the
 * previous local day. A line of a previous calendar day said within this
 * many hours of the turn is never cut from the model's history. With the
 * local day alone as the session, a conversation that crosses midnight lost
 * its lines at 00:00: at 00:05 the 49 lines said between 23:10 and 23:59
 * were all "previous day" and only the newest 16 reached the model (review
 * 2026-10-04: an allergy said 18 lines earlier gave the generator
 * "(nenhuma)"). `0` gives the local-day-only rule back.
 */
export const MOBILE_FLOW_SESSION_HOURS = 6

/**
 * Flow only: the history lines one model call carries. Every line of the
 * patient's current session stays, however many: an allergy or intolerance
 * said earlier in the same session reaches the model only through these
 * lines, and the diet generator receives restrictions only from the model's
 * arguments (review 2026-10-04: with a flat 16-line cut, "sou intolerante a
 * lactose e alérgico a castanhas" said 18 lines before the menu request gave
 * the generator "(nenhuma)"). The session is the patient's current local day
 * plus the MOBILE_FLOW_SESSION_HOURS before the turn (see
 * promptHistoryOutsideSessionLines). What is cut is what came before it: the
 * most recent of those lines fill the window only while the session has
 * fewer than MOBILE_FLOW_PROMPT_HISTORY_LINES. `outsideSession[i]` says
 * whether `lines[i]` is outside the session; the order of the lines is kept.
 */
export function mobileFlowPromptHistory<T>(
  lines: readonly T[],
  outsideSession: readonly boolean[],
): T[] {
  const session = lines.filter((_, index) => outsideSession[index] !== true).length
  let room = Math.max(0, MOBILE_FLOW_PROMPT_HISTORY_LINES - session)
  const kept: T[] = []
  for (let index = lines.length - 1; index >= 0; index -= 1) {
    if (outsideSession[index] === true) {
      if (room === 0) continue
      room -= 1
    }
    kept.unshift(lines[index] as T)
  }
  return kept
}

/**
 * Flow only: the per-turn context (never cached, paid at full price on every
 * call) without what the Flow cannot use — see formatUserContext and the
 * anti-repetition block. `false` gives the Flow the legacy context back.
 */
export const MOBILE_FLOW_LEAN_CONTEXT: boolean = true

/** Event with the numbers of each model call of a Flow turn (no text). */
export const MOBILE_FLOW_CALLS_EVENT = 'llm.flow_calls'
/** Flow only. The answer still carried a name the app never shows (the
 * method's or the physician's): how many were replaced, and how many times
 * the title + first name came without the surname and were NOT replaced.
 * Counts only, no text. */
export const MOBILE_FLOW_PUBLIC_NAMES_EVENT = 'llm.flow_internal_name_replaced'

/**
 * Flow only: model iterations of one turn, guard retries apart. The number
 * used to come only from agent_configs.max_tool_iterations, a row production
 * shares with WhatsApp (database default 5): there the Flow would inherit up
 * to 5 calls of the whole prompt. `Number.POSITIVE_INFINITY` gives the Flow
 * the configured number back.
 */
export const MOBILE_FLOW_MAX_MODEL_ITERATIONS = 2

/**
 * Flow only: when the only tools of the turn are plan-suggestion tools, every
 * one returned its text, the patient's message is a single request
 * (isSingleRequestMessage) and the model wrote nothing next to the tool call,
 * the turn ends there. The second model call only copied that text (~11,000
 * prompt tokens, 500-600 of output, 8-12 s), and when it did not copy, the
 * answer was already replaced by the fixed text of ensureSuggestionShown —
 * the text such a turn now gets. A message that also asks something else
 * keeps the second call: it is the only place that question is answered
 * (review 2026-10-04). So does a message that names two plans or joins two
 * requests, and a reply that names no plan and takes its meaning from the
 * Flow's previous line (third review 2026-10-04). `false` brings the second
 * call back for every turn.
 */
export const MOBILE_FLOW_DIRECT_PLAN_SUGGESTION: boolean = true

/**
 * Flow only: a turn does not end without words because the model spent its
 * iterations asking for tools. When the last allowed iteration was a tool
 * call, the model gets one more call with the tools switched off
 * (tool_choice "none"), to answer with what the tools already returned. The
 * tools stay in the request, so the cached prefix is read as on every call.
 * Under the cap of 2 such a turn ended with an empty text (502 in the
 * service) after two paid calls; where the stage config allows more than 2
 * (database default and production: 5) the model used to answer on its third
 * call (review 2026-10-04). The one turn that does not get the call is a
 * single request (isSingleRequestMessage) with a suggestion already stored:
 * that suggestion is the whole answer. A message that asks for something
 * else too gets the call even with a suggestion stored — without it "Monte
 * uma sugestão de cardápio para amanhã. E quanto falta de proteína hoje?"
 * answered by tool, tool ended on the suggestion and the protein question
 * was dropped (second review 2026-10-04). When the provider fails that call
 * and a suggestion is stored, the suggestion is the answer and the turn does
 * not fail (third review 2026-10-04). The tools being off, a plan the model
 * only asks for on that call is not generated (RC PERF-C15).
 * `false` ends such a turn empty again.
 */
export const MOBILE_FLOW_CLOSING_CALL: boolean = true

/**
 * Flow only: the "pure status" answer leaves as plain text. The app's bubble
 * prints the string as is, so the WhatsApp card showed its asterisks and
 * underscores. `false` gives the Flow the WhatsApp card back.
 */
export const MOBILE_FLOW_PLAIN_STATUS: boolean = true

/**
 * Flow only: time limits. The shared client allows 90 s and one retry per
 * call (181 s, above the app's 180 s request timeout) and a turn had no
 * limit at all: past the route's 300 s the function died with the turn left
 * in "processing", answering 409 until its 10-minute lease ran out.
 * `false` gives the Flow the client defaults back.
 */
export const MOBILE_FLOW_TIME_LIMITS: boolean = true
/** One chat call of a Flow turn (single-call turns measured 6-13 s in all). */
export const MOBILE_FLOW_CHAT_CALL_TIMEOUT_MS = 45_000
/**
 * The model work of a Flow turn, counted from the start of the pipeline.
 * Under the app's request timeout (180 s, MobileFlowChatRepository.swift) and
 * the route's maxDuration (300 s), with room for the reads and writes around
 * the agent. No model call starts past it, and each attempt of a call is cut
 * at it. One thing is not bounded here: the wait BETWEEN the two attempts of
 * a chat call that kept its retry. The client sleeps ~0.5 s by default and up
 * to 60 s when the provider answers 429 with Retry-After, so such a call can
 * end after the deadline; the service's own limit (165 s) is what ends the
 * turn then.
 */
export const MOBILE_FLOW_TURN_DEADLINE_MS = 150_000
/**
 * Message of the error a Flow turn ends with when its deadline has passed:
 * before a call would start, or while a call was running (the client's own
 * timeout error is then the `cause`).
 */
export const MOBILE_FLOW_DEADLINE_ERROR = 'flow turn deadline exceeded'
/**
 * Flow only: with a suggestion already stored in the turn and less than this
 * left of the deadline, no further model call is made — the stored suggestion
 * is the answer (ensureSuggestionShown). The call that copies a suggestion
 * took 8-12 s on staging (2026-10-04): with less left it would be paid for
 * and cut, the turn would fail with 502 and the draft would sit pending with
 * no answer in the chat.
 */
export const MOBILE_FLOW_SUGGESTION_ANSWER_MIN_MS = 12_000
/**
 * A call that failed with no more than this left of the deadline was ended
 * by the deadline: the client's timer and the wall clock are two clocks, and
 * the timer may fire a few milliseconds before the instant computed here.
 */
const MOBILE_FLOW_DEADLINE_SLACK_MS = 250
/** The client's own limit for a call that names none (openrouter.ts). */
const LLM_CLIENT_TIMEOUT_MS = 90_000

/** Milliseconds a Flow turn still has for model work; throws when none. */
function flowTimeLeft(deadlineAt: number): number {
  const left = deadlineAt - Date.now()
  if (left <= 0) throw new Error(MOBILE_FLOW_DEADLINE_ERROR)
  return left
}

/** One model call made inside a Flow tool (the plan generators): numbers only. */
type FlowToolLlmCall = {
  index: number
  model: string
  prompt_tokens: number
  completion_tokens: number
  cache_read_tokens: number
  cache_write_tokens: number
  cost_usd: number | null
  ms: number
  /** Present (1) when the call threw: its time was spent, nothing was read. */
  failed?: 1
}

/**
 * Flow only. The client handed to the tools of a Flow turn. Every model call
 * a tool makes (today: the plan generators) is counted into the turn — it
 * used to be absent from the turn's tokens and cost — and gets no more time
 * than the turn has left. The call itself is not changed in any other way.
 */
function flowToolLlm(
  llm: OpenRouterLLM,
  deadlineAt: number | null,
  calls: FlowToolLlmCall[],
): OpenRouterLLM {
  const complete = async (params: LLMCallParams): Promise<LLMResult> => {
    const bounded =
      deadlineAt === null
        ? params
        : {
            ...params,
            requestTimeoutMs: Math.min(
              params.requestTimeoutMs ?? LLM_CLIENT_TIMEOUT_MS,
              flowTimeLeft(deadlineAt),
            ),
          }
    const startedAt = Date.now()
    const entry = (result: LLMResult | null): FlowToolLlmCall => ({
      index: calls.length,
      model: result?.model ?? params.model,
      prompt_tokens: result?.promptTokens ?? 0,
      completion_tokens: result?.completionTokens ?? 0,
      cache_read_tokens: result?.cacheReadInputTokens ?? 0,
      cache_write_tokens: result?.cacheCreationInputTokens ?? 0,
      cost_usd: result?.costUsd ?? null,
      ms: Date.now() - startedAt,
      ...(result ? {} : { failed: 1 as const }),
    })
    try {
      const result = await llm.complete(bounded)
      calls.push(entry(result))
      return result
    } catch (error) {
      calls.push(entry(null))
      throw error
    }
  }
  return new Proxy(llm, {
    get: (target, property, receiver) =>
      property === 'complete' ? complete : Reflect.get(target, property, receiver),
  })
}

/** One model call of a Flow turn: numbers and the model id, never text. */
type FlowCallUsage = {
  index: number
  model: string
  prompt_tokens: number
  completion_tokens: number
  cache_read_tokens: number
  cache_write_tokens: number
  cost_usd: number | null
  ms: number
  /** History lines sent (the current message and tool exchange excluded). */
  history_lines: number
  /** Characters of each system block, in order (stable, per-turn). */
  system_chars: number[]
  /** Messages sent in this call and the characters of their text. */
  messages: number
  messages_chars: number
  /** Present (1) on the closing call, made with the tools switched off. */
  closing?: 1
  /** Present (1) when the call threw: its time was spent, nothing was read. */
  failed?: 1
}

/** How a Flow turn ended, for its llm.flow_calls event (flags, no text). */
type FlowTurnEnding = {
  /** Answered with the stored suggestion and no second model call. */
  planSuggestionDirect?: boolean
  /** Answered with the stored suggestion because the deadline left no call. */
  suggestionAtDeadline?: boolean
  /** The turn threw: these are the numbers of what it had already spent. */
  turnFailed?: boolean
}

/**
 * Flow only. Writes the per-call numbers of the turn; a failure here never
 * reaches the patient's answer.
 */
async function recordFlowCalls(
  supabase: ServiceClient,
  userId: string,
  stage: string,
  toolsChars: number,
  calls: FlowCallUsage[],
  generatorCalls: FlowToolLlmCall[],
  ending: FlowTurnEnding,
): Promise<void> {
  if (calls.length === 0) return
  try {
    await supabase.from('product_events').insert({
      user_id: userId,
      event: MOBILE_FLOW_CALLS_EVENT,
      properties: {
        stage,
        call_count: calls.length,
        tools_chars: toolsChars,
        calls,
        // Only on the turns that have them, so every other event is unchanged.
        ...(generatorCalls.length > 0 ? { generator_calls: generatorCalls } : {}),
        ...(ending.planSuggestionDirect ? { plan_suggestion_direct: 1 } : {}),
        ...(ending.suggestionAtDeadline ? { plan_suggestion_at_deadline: 1 } : {}),
        ...(ending.turnFailed ? { turn_failed: 1 } : {}),
      },
    })
  } catch {
    // Telemetry only.
  }
}

// Intro da persona master compartilhada (e sua tradução), não texto de resposta.
const LEGACY_PERSONA_INTRODUCTION_PATTERN =
  /^(?:Você é|You are|Eres)\s+(?:o\s+|the\s+)?(?:\*\*)?Dr\.?\s+Robert(?:o)?(?:\s+Menescal)?(?:\*\*)?[^.\n]*(?:\.|$)/gim
const LEGACY_PERSONA_MARKDOWN_SECTION_PATTERN =
  /^## Markdown — uso parcimonioso\r?\n[\s\S]*?(?=^#{1,3} |\n\n---\n\n|(?![\s\S]))/gm

export const mobileFlowSystemPolicy = `
## Canal autenticado Performe AI
Você é Flow, assistente de IA do Performe AI. Seja claro, acolhedor e objetivo.
Esta é a identidade pública deste canal e prevalece sobre a persona legada
das regras compartilhadas, contexto recuperado e apresentações no histórico.
Não reivindique profissão regulamentada nem se apresente como médico,
nutricionista, psicólogo, profissional de saúde ou profissional habilitado.
Não use títulos Dr./Dra. ou a identidade de uma pessoa real como sua credencial.
Nunca escreva "MPP", "Muscular Power Plant", o nome de quem criou o método
nem "método do Dr." seguido de nome, nem quando a pessoa perguntar: são
referências internas. Se perguntarem qual é o método ou quem está por trás
dele, diga só que as orientações seguem o programa do Performe AI.
Responda em texto simples, sem Markdown decorativo, inclusive na apresentação curta.
Não envolva nomes ou dados em asteriscos, underscores, headings ou crases de formatação.
Uma mensagem enviada no chat não autoriza alteração de dados de saúde.
Este canal consulta dados oficiais e pode criar SUGESTÕES de plano de treino
ou de cardápio (rascunhos). Para o paciente, chame-as sempre de "sugestão",
nunca de "proposta". Uma sugestão nunca é o plano do paciente: ela só
passa a valer depois que ele revisa e confirma no app. Não reescreva, não resuma
e não altere uma sugestão no chat: ajustes são feitos pelo paciente em
"Revisar sugestão"; para uma sugestão diferente, crie outra. Você não confirma,
não ativa e não substitui plano nenhum, e a confirmação do paciente não é
revisão de um profissional. Não proponha medicamentos, suplementos ou doses.
Para qualquer outra mutação sensível, explique que é necessária confirmação
explícita no fluxo estruturado do app.
Não diagnostique, não prometa cura, não substitua profissional e não afirme
que uma ação foi concluída sem confirmação determinística do servidor.
Não divulgue metabolismo basal, gasto energético total, massa magra estimada,
fatores de atividade, nomes ou equações de cálculo das metas. Não reconstrua
esses valores a partir do histórico ou de regras recuperadas. Use apenas as
metas oficiais e os balanços públicos fornecidos pelo servidor. Diga
"Gordura corporal" em vez da sigla interna.`

function mobileFlowPromptContext(context: string): string {
  // Only prompt copies: preserve adjacent health restrictions and never
  // mutate shared rules, the patient history or the legacy channel.
  return projectFlowMetricContext(context
    .replace(LEGACY_PERSONA_INTRODUCTION_PATTERN, 'Você é Flow, assistente de IA do Performe AI.')
    .replace(LEGACY_PERSONA_MARKDOWN_SECTION_PATTERN, '')
    .replace(LEGACY_PERSONA_NAME_PATTERN, 'Flow'))
}

export function selectPipelineTools(
  configuredToolNames: string[] | null | undefined,
  channelToolNames?: readonly string[],
): ToolDefinition[] {
  const configured = configuredToolNames?.length ? new Set(configuredToolNames) : null
  const channel = channelToolNames ? new Set(channelToolNames) : null
  return ALL_TOOLS.filter(
    (tool) =>
      (!configured || configured.has(tool.name)) &&
      // Draft tools exist for the app alone: a channel gets them only by
      // naming them in its own set, never through "all tools".
      (channel ? channel.has(tool.name) : !MOBILE_ONLY_TOOLS.has(tool.name)),
  )
}

export type ToolCallAuthorization =
  | { status: 'authorized'; tool: ToolDefinition }
  | { status: 'not_authorized' | 'unknown' }

/**
 * Dispatch boundary. A model tool call runs only when the tool is in the set
 * this request exposed (channel policy ∩ configured tools). The full registry
 * is consulted only to tell a withheld tool from a name that does not exist;
 * it never authorizes a call.
 */
export function authorizeToolCall(
  name: string,
  authorizedTools: readonly ToolDefinition[],
): ToolCallAuthorization {
  const tool = authorizedTools.find((candidate) => candidate.name === name)
  if (tool) return { status: 'authorized', tool }
  return { status: getToolByName(name) ? 'not_authorized' : 'unknown' }
}

/** Telemetry keeps a model-supplied tool name only when it looks like one. */
function telemetryToolName(name: string): string {
  return /^[A-Za-z0-9_]{1,64}$/.test(name) ? name : 'invalid_tool_name'
}

/**
 * The tools a fake-write retry would ask the model to call. The retry is
 * skipped when none of them is authorized for this request, so a channel
 * is never told to call a tool it cannot run.
 */
const FAKE_WRITE_RETRY_TOOLS: Record<
  'registration' | 'correction' | 'diet_fake' | 'training_fake' | 'skip',
  readonly string[]
> = {
  registration: ['registra_refeicao', 'registra_treino'],
  correction: ['registra_refeicao', 'registra_treino'],
  diet_fake: ['gera_dieta', 'propoe_plano_dieta'],
  training_fake: ['gera_treino', 'propoe_plano_treino'],
  skip: ['marca_refeicao_pulada'],
}

/**
 * Retry for a claimed write the request cannot perform (e.g. the read-only
 * mobile Flow): take the claim back instead of asking for a tool.
 */
export const CHAT_WRITE_RETRACTION =
  'SISTEMA (não é o paciente): neste canal nada é registrado, corrigido ou gerado pelo chat, e nenhuma ferramenta de gravação foi chamada neste turno. Sua resposta afirmou ter registrado, corrigido ou gerado algo que NÃO foi salvo. Reescreva sem afirmar registro, correção, cardápio ou plano salvos e oriente o paciente a usar o fluxo de confirmação do app.'

/** The same retraction for any other channel: it never points to an app. */
export const TURN_WRITE_RETRACTION =
  'SISTEMA (não é o paciente): nenhuma ferramenta de gravação foi chamada neste turno. Sua resposta afirmou ter registrado, corrigido ou gerado algo que NÃO foi salvo. Reescreva sem afirmar registro, correção, cardápio ou plano salvos.'

/**
 * Where plans are only proposed (the mobile Flow), an invented plan in the
 * reply is answered by pointing to the proposal tool, never to `gera_*`.
 */
export function draftRetryMessage(
  kind: keyof typeof FAKE_WRITE_RETRY_TOOLS | null | undefined,
  authorizedTools: readonly ToolDefinition[],
): string | null {
  const tool =
    kind === 'diet_fake'
      ? 'propoe_plano_dieta'
      : kind === 'training_fake'
        ? 'propoe_plano_treino'
        : null
  if (!tool || authorizeToolCall(tool, authorizedTools).status !== 'authorized') return null
  const legacy = kind === 'diet_fake' ? 'gera_dieta' : 'gera_treino'
  if (authorizeToolCall(legacy, authorizedTools).status === 'authorized') return null
  return (
    `SISTEMA (não é o paciente): você apresentou um plano no texto sem chamar \`${tool}\`. ` +
    'Nada foi criado. Se o paciente pediu explicitamente e você já tem os dados necessários, chame ' +
    `\`${tool}\` AGORA para criar a SUGESTÃO que ele vai revisar no app. Se faltar algum dado, ` +
    'pergunte e NÃO mostre plano nenhum. Se ele só tirava uma dúvida, responda sem plano.'
  )
}

export function fakeWriteRetryAllowed(
  kind: keyof typeof FAKE_WRITE_RETRY_TOOLS | null | undefined,
  authorizedTools: readonly ToolDefinition[],
): boolean {
  if (!kind) return false
  return FAKE_WRITE_RETRY_TOOLS[kind].some(
    (name) => authorizeToolCall(name, authorizedTools).status === 'authorized',
  )
}

interface ResolvedPipelineOptions {
  historyProvider?: string
  toolNames?: readonly string[]
  systemPolicy?: string
  includeSensitiveTelemetry?: boolean
  /**
   * Flow only. The pipeline puts here how to write the turn's llm.flow_calls
   * numbers while the turn is still running; the entry point calls it when
   * the turn throws, so calls already paid for are recorded on the failure
   * path too. Cleared once the turn has written them itself.
   */
  flowFailure?: { record: (() => Promise<void>) | null }
  /**
   * Flow only. The pipeline puts here the registered name of the account
   * (users.name, the one the context already loads: no extra query) so the
   * entry point can skip the physician's-name projection for an account that
   * carries the surname itself (flow-public-names.ts). Stays null when the
   * turn ends before the context is loaded: no model ran, the text is the
   * system's.
   */
  flowAccount?: {
    name: string | null
    locale: string | null
    dailyTargets: UserContext['dailyTargets'] | null
  }
}

/**
 * RAG (sub-projeto D): recupera as seções do método relevantes ao turno e
 * devolve um bloco pra injetar no system prompt. Degradação graciosa: qualquer
 * falha (sem embeddings, erro de rede, RPC) → retorna '' e o turno segue.
 * Os NÚMEROS já vêm do código (card/engine), então um miss aqui só afeta prosa.
 */
async function retrieveMethodContext(
  deps: PipelineDeps,
  text: string | null | undefined,
  protocol: string | null | undefined,
): Promise<string> {
  if (!deps.embeddings || !text || text.trim().length < 3) return ''
  try {
    const emb = await deps.embeddings.embed(text)
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
// biome-ignore lint/suspicious/noExplicitAny: legacy — see ACT-1 prevention plan 2026-06-16
    const { data } = await (deps.supabase as any).rpc('match_method_chunks', {
      query_embedding: emb,
      match_count: 5,
      filter_protocol: protocol ?? null,
    })
    const chunks = (data ?? []) as Array<{ page_title: string; content: string }>
    if (chunks.length === 0) return ''
    const body = chunks.map((c) => `### ${c.page_title}\n${c.content}`).join('\n\n')
    return `\n\n## Método relevante (recuperado da base — siga estas regras)\n${body}`
  } catch {
    return ''
  }
}

interface UserContext {
  userId: string
  userName: string | null
  profile: UserProfile
  recentMessages: Array<{ role: 'user' | 'assistant'; content: string }>
  /** Flow only: for each line of recentMessages, whether it is outside the
   * current session — before the turn's local day and more than
   * MOBILE_FLOW_SESSION_HOURS before the turn (the history window cuts only
   * those). Absent on the legacy channels. */
  flowOutsideSessionLines?: boolean[]
  /** Resumo persistente do paciente (gerado periodicamente). */
  summary: string | null
  /** Tempo desde a última msg IN, em horas. */
  hoursSinceLastIn: number | null
  /** True se hoursSinceLastIn > 7 dias — pipeline gera reentrada warm. */
  isReentry: boolean
  /** ISO 3166-1 alpha-2 do país residência (palpite ou confirmado). */
  country: string | null
  /** True quando o paciente confirmou explicitamente o país. */
  countryConfirmed: boolean
  /** Palpite original baseado no DDI do WhatsApp. */
  countryDetectedFromWpp: string | null
  /** Locale escolhido pelo paciente (pt-BR, en, es, etc). */
  locale: string | null
  /** Metadata raw de users.metadata (jsonb). Usado pra feature flags
   * (ex: buttons_enabled pra Fase B opção #4) e unit_system. */
  userMetadata: Record<string, unknown> | null
  /** Tipo da última mensagem inbound do paciente (Fase B botões #4 —
   * foto/áudio NUNCA são express, mesmo com texto perfeito de legenda). */
  lastInboundContentType: 'text' | 'audio' | 'image' | null
  /** Sistema de medidas: 'metric' (kg/cm) ou 'imperial' (lb/in). */
  unitSystem: 'metric' | 'imperial' | null
  /** Timezone IANA do paciente (ex: America/Sao_Paulo). Default 'America/Sao_Paulo'. */
  timezone: string
  /** Instante original da ultima mensagem do burst no provider. */
  referenceTimestamp: Date
  /** Metas calóricas/proteína calculadas determinísticamente (anti-alucinação). */
  dailyTargets: { calories_target: number | null; protein_target: number | null }
  /** Flow only: the day row's protocol and stored target, and the targets the
   * profile gives now under each protocol, for the per-protocol day balance
   * (docs/CALCULO-MPP.md §2c). Absent on the legacy channels. */
  flowDayRow?: FlowDayRow | null
  /** Snapshot do dia LOCAL do paciente — consumo + balanço atual. */
  todaySnapshot: {
    calories_consumed: number
    protein_g: number
    carbs_g: number
    fat_g: number
    exercise_calories: number
    daily_balance: number
    deficit_accumulated: number
    day_status: string | null
    gap_reminder_sent_at: string | null
  } | null
  /** Gamificação. */
  userProgress: {
    current_streak: number
    longest_streak: number
    xp_total: number
    level: number
    blocks_completed: number
    /** Déficit acumulado RUMO ao próximo bloco 7700 (reseta quando atinge).
     * Usado no card pós-registro pra recomp: 📊 Bloco: {deficit_block}/7700. */
    deficit_block: number
    last_active_date: string | null
  } | null
  /** Janela 14 dias — orçamento calórico + DAM. Métrica oficial Notion pra
   * manutenção (📊 Orçamento + 📅 DAM ≤ 4) e ganho_massa (📊 Orçamento).
   * Computado sobre daily_snapshots fechados nos últimos 14 dias. */
  last14d: {
    consumed_total: number
    target_total: number
    days_with_data: number
    /** Dias acima da meta (DAM). Limite manutenção: 4. */
    dam: number
  } | null
  /** FIX 4 (Roberto 2026-06-15): última foto de refeição analisada por vision
   *  que AINDA NÃO virou meal_log nem pending. Quando presente, o pipeline
   *  bloqueia marca_refeicao_pulada e força registra_refeicao (foto perdida
   *  bug). null quando vision já virou registro/pending OU não houve vision
   *  de meal nas últimas 24h. */
  visionPending: {
    items: Array<{ name: string; quantity_g_estimate: number; confidence: number }>
    mealContext: string | null
    occurredAt: string
    ageMinutes: number
  } | null
  /** Estado factual das fotos corporais pedidas na reavaliacao recente.
   * Usado para nao pedir novamente frente/lado/costas ja recebidas. */
  bodyPhotoState: BodyPhotoState | null
  /** True quando houve reevaluation.due nas ultimas 48h. */
  reevaluationDueRecent: boolean
}

export async function processMessage(
  deps: PipelineDeps,
  input: AgentInput,
): Promise<AgentOutput> {
  const userId = await ensureUser(deps.supabase, input.from)
  return processResolvedMessage(deps, input, userId)
}

export async function processAuthenticatedMessage(
  deps: PipelineDeps,
  input: AuthenticatedAgentInput,
): Promise<AgentOutput> {
  const flowFailure: NonNullable<ResolvedPipelineOptions['flowFailure']> = { record: null }
  const flowAccount: NonNullable<ResolvedPipelineOptions['flowAccount']> = {
    name: null,
    locale: null,
    dailyTargets: null,
  }
  try {
    const output = await processResolvedMessage(
      deps,
      {
        from: '',
        providerMessageId: input.providerMessageId,
        text: input.text,
        patientText: input.text,
        contentType: 'text',
        provider: 'mobile_flow',
        timestamp: input.timestamp,
      },
      input.userId,
      {
        historyProvider: 'mobile_flow',
        toolNames: MOBILE_FLOW_TOOLS,
        systemPolicy: mobileFlowSystemPolicy,
        includeSensitiveTelemetry: MOBILE_FLOW_TELEMETRY_INCLUDES_CONTENT,
        flowFailure,
        flowAccount,
      },
    )
    const publicOutput = await withFlowPublicNames(deps.supabase, input.userId, output, flowAccount.name)
    const text = projectFlowMetricAnswer(
      publicOutput.text,
      flowAccount.dailyTargets,
      flowAccount.locale,
      draftCreatedThisTurn(publicOutput.toolCalls),
    )
    return text === publicOutput.text ? publicOutput : { ...publicOutput, text }
  } catch (error) {
    // The turn failed (deadline, provider, anything after the first call):
    // what it had already spent is still written, numbers only. The write
    // never throws, and the turn fails with its own error.
    await flowFailure.record?.()
    throw error
  }
}

/**
 * Flow only: the last line of defence on the text the app receives. The
 * policy tells the model never to write the method's names or the
 * physician's; if the answer still carries one of the spellings of the closed
 * vocabulary (flow-public-names.ts), it is replaced. The physician's name is
 * left alone for an account whose registered name carries the surname.
 *
 * The turn writes `llm.flow_internal_name_replaced` with numbers only, never
 * a word of the answer: how many names were replaced, by kind, and how many
 * times the title + first name came WITHOUT the surname — which the filter
 * sees, counts and does not replace (`persona_first_name_only`). An answer
 * with none of those is returned as it came, with no event.
 */
async function withFlowPublicNames(
  supabase: ServiceClient,
  userId: string,
  output: AgentOutput,
  accountName: string | null,
): Promise<AgentOutput> {
  const names = projectFlowPublicNames(output.text, { accountName })
  const seen = names.method + names.personaSelf + names.personaOther + names.personaFirstNameOnly
  if (seen === 0) return output
  try {
    await supabase.from('product_events').insert({
      user_id: userId,
      event: MOBILE_FLOW_PUBLIC_NAMES_EVENT,
      properties: {
        stage: output.stage,
        method_names: names.method,
        persona_self: names.personaSelf,
        persona_other: names.personaOther,
        persona_first_name_only: names.personaFirstNameOnly,
      },
    })
  } catch {
    // Telemetry only.
  }
  return names.text === output.text ? output : { ...output, text: names.text }
}

async function processResolvedMessage(
  deps: PipelineDeps,
  input: AgentInput,
  userId: string,
  options: ResolvedPipelineOptions = {},
): Promise<AgentOutput> {
  const start = Date.now()
  const semanticPatientText = input.patientText ?? input.text ?? ''

  // 2. verifica subscription (gate de acesso)
  const subscriptionStatus = await checkSubscription(deps.supabase, userId)
  if (!subscriptionStatus.canAccess) {
    return buildBlockedResponse(input, subscriptionStatus.reason ?? 'sem assinatura ativa')
  }

  // 3. load context
  const ctx = await loadContext(
    deps.supabase,
    userId,
    input.providerMessageIds ?? input.providerMessageId,
    input.text,
    input.timestamp,
    options.historyProvider,
  )
  // Flow only (processMessage passes no holder): the name the context already
  // carries, for the public-names guard of the entry point.
  if (options.flowAccount) {
    options.flowAccount.name = ctx.userName
    options.flowAccount.locale = flowMetricLocale(semanticPatientText, ctx.locale)
    options.flowAccount.dailyTargets = ctx.dailyTargets
  }

  // 4. resolve stage
  const stage = resolveStage(ctx.profile)

  // 4. load active prompt + config (filtra regras pelo idioma do paciente — #1)
  const promptRow = await loadActivePrompt(deps.supabase, stage, ctx.locale)
  if (!promptRow) {
    throw new Error(`No active prompt found for stage ${stage}`)
  }

  // Um debounce pode, raramente, agrupar mensagens dos dois lados da meia-noite
  // local. Nao existe uma unica data correta para o conjunto; perguntar e mais
  // seguro do que registrar todas no dia da ultima mensagem.
  if (burstCrossesLocalDate(ctx.timezone, input.timestamps ?? [input.timestamp])) {
    await deps.supabase.from('product_events').insert({
      user_id: userId,
      event: 'pipeline.cross_local_midnight_blocked',
      properties: {
        timezone: ctx.timezone,
        message_count: input.timestamps?.length ?? 1,
        local_dates: Array.from(
          new Set(
            (input.timestamps ?? [input.timestamp]).map((timestamp) =>
              getLocalDateString(ctx.timezone, timestamp),
            ),
          ),
        ),
      },
    })
    const text =
      ctx.locale?.startsWith('en')
        ? 'I received these messages across your local midnight. Which items were from yesterday and which were from today?'
        : 'Recebi essas mensagens atravessando a meia-noite no seu horário local. Quais itens foram de ontem e quais foram de hoje?'
    return {
      text,
      preferAudio: false,
      singleMessage: true,
      toolCalls: [],
      stage,
      modelUsed: promptRow.model,
      promptTokens: 0,
      completionTokens: 0,
      costUsd: 0,
      latencyMs: Date.now() - start,
    }
  }

  // C1: exact technical questions use official targets, with no model call
  // or sensitive mutation. Mixed questions keep their other intentions.
  if (options.historyProvider === 'mobile_flow' && asksPrivateMetricQuestion(semanticPatientText)) {
    return {
      text: renderOfficialTargets(ctx.dailyTargets, flowMetricLocale(semanticPatientText, ctx.locale)),
      preferAudio: false,
      singleMessage: true,
      toolCalls: [],
      stage,
      modelUsed: promptRow.model,
      promptTokens: 0,
      completionTokens: 0,
      costUsd: 0,
      latencyMs: Date.now() - start,
    }
  }

  // Flow only. The direct question "I trained — may I eat N kcal more?" is
  // answered by the system, before any model call (iPhone, staging,
  // 2026-10-04: Flow said "Sim! Sua meta já considera esse gasto…"). Food left
  // = target − consumed, WITHOUT exercise (docs/CALCULO-MPP.md §2a). On this
  // channel ctx.dailyTargets is the day row's target, the one Today shows.
  // WhatsApp never enters: processMessage passes no historyProvider.
  // A message with no "?" sent right after a question of Flow ("Está
  // conseguindo comer…?" → "Treinei hoje e dá pra comer mais") is the
  // patient's answer, not the direct question: the model answers it.
  if (
    options.historyProvider === 'mobile_flow' &&
    asksExerciseFoodQuestion(semanticPatientText) &&
    !answersFlowQuestion(semanticPatientText, ctx.recentMessages)
  ) {
    const exerciseFoodAnswer = renderExerciseFoodAnswer(
      {
        caloriesTarget: ctx.dailyTargets.calories_target ?? null,
        caloriesConsumed: ctx.todaySnapshot?.calories_consumed ?? 0,
        exerciseCalories: ctx.todaySnapshot?.exercise_calories ?? 0,
        protocol: ctx.profile.currentProtocol ?? null,
      },
      statedWorkoutCalories(semanticPatientText),
    )
    // The model answers only when Flow's last reply is this very text: the
    // same words again would not help. Other numbers, another day state or
    // any reply in between, and the system answers again.
    if (!lastReplyIsSameAnswer(ctx.recentMessages, exerciseFoodAnswer)) {
      // No patient text in the event (MOBILE_FLOW_TELEMETRY_INCLUDES_CONTENT).
      await deps.supabase.from('product_events').insert({
        user_id: userId,
        event: 'pipeline.deterministic_exercise_food',
        properties: {
          stage,
          protocol: ctx.profile.currentProtocol ?? null,
          has_target: ctx.dailyTargets.calories_target != null,
          has_snapshot: ctx.todaySnapshot != null,
        },
      })
      return {
        text: exerciseFoodAnswer,
        preferAudio: false,
        singleMessage: true,
        toolCalls: [],
        stage,
        modelUsed: promptRow.model,
        promptTokens: 0,
        completionTokens: 0,
        costUsd: 0,
        latencyMs: Date.now() - start,
      }
    }
  }

  // 4b. Router de modelo (Fase 6 redução custo — 2026-06-04): troca Sonnet→Haiku
  // pra turns determinísticos (saudações, status questions, agradecimentos).
  // Feature flag `router.haiku_enabled` em global_config (default true). Logo
  // o promptRow.model passa a refletir a decisão do router.
  const haikuEnabled = await loadRouterFlag(deps.supabase)
  const routed = routeModel(promptRow.model, haikuEnabled, {
    text: input.text,
    contentType: input.contentType ?? 'text',
    stage,
    lastInboundContentType: ctx.lastInboundContentType,
    isReentry: ctx.isReentry,
    hasOpenPending: await hasOpenPending(deps.supabase, userId),
  })
  if (routed.changed) {
    await logModelRouted(deps.supabase, userId, {
      from: promptRow.model,
      to: routed.model,
      reason: routed.reason,
      stage,
      ...(options.includeSensitiveTelemetry === false
        ? {}
        : { text_preview: (input.text ?? '').slice(0, 80) }),
    })
    ;(promptRow as { model: string }).model = routed.model
  }

  // 5. call agent (with tool loop)
  // Filtra tools pelo allowed_tools do config (se NULL = todas)
  const allowedTools = (promptRow as { allowed_tools?: string[] | null }).allowed_tools
  const filteredTools = selectPipelineTools(allowedTools, options.toolNames).map((tool) =>
    options.historyProvider === 'mobile_flow' && tool.name === 'consulta_metricas'
      ? {
          ...tool,
          description: 'Consulta idade, IMC, gordura corporal e metas oficiais de calorias e proteína. Use somente se o dado público necessário não estiver no contexto. Não estime nem recalcule metas.',
        }
      : tool,
  )
  const tools = buildToolSchemas(filteredTools)

  // Detector de repetição: pega últimas 2 OUTs e marca pro LLM evitar
  // repetir trechos. Útil principalmente pra balanço-em-todo-turno.
  const lastTwoOuts = ctx.recentMessages
    .filter((m) => m.role === 'assistant')
    .slice(-2)
    .map((m) => m.content)

  const repetitionGuard =
    lastTwoOuts.length >= 1
      ? `\n\n## Anti-repetição (CRÍTICO)\n` +
        // Flow: the two quoted answers are the last lines of the history the
        // model already receives; quoting them again was paid at full price
        // on every call. The instructions below stay, word for word.
        (MOBILE_FLOW_LEAN_CONTEXT && options.historyProvider === 'mobile_flow'
          ? ''
          : `Suas últimas respostas foram:\n` +
            lastTwoOuts.map((t, i) => `[${i + 1}] "${t.slice(0, 200).replace(/\n/g, ' ')}"`).join('\n') +
            `\n\n`) +
        // Flow: with the quote gone, "acima" pointed at the numeric block and
        // the rules, not at the answers; the instruction names where they are.
        `→ NÃO repita aberturas, frases âncora ou bullets de balanço se já estão ${
          MOBILE_FLOW_LEAN_CONTEXT && options.historyProvider === 'mobile_flow'
            ? 'nas suas últimas respostas do histórico'
            : 'acima'
        }.\n` +
        `→ Se nada de novo aconteceu (user só disse "oi" ou similar), responda CURTO. Não force conteúdo.\n` +
        `→ Varie a saudação. Banco de aberturas curtas (escolha uma quando fizer sentido):\n` +
        `   "Boa.", "Show.", "Beleza.", "Pronto.", "Saquei.", "Recebi.", "Hmm.", (sem nada/direto na resposta)`
      : ''

  // Carrega config editável de cálculos (cache 60s) — afeta metrics e protocol
  const calcConfig = await loadCalcConfig(deps.supabase)

  // System prompt em 2 blocos pra Anthropic prompt caching (sessão 2026-05-16):
  //  1. ESTÁVEL — promptRow.system_prompt (50+ agent_rules + persona) — cacheado
  //  2. VARIÁVEL — contexto do paciente (snapshot, hora, last messages) — sem cache
  // Anthropic Opus 4.7 estava custando $0.77/turno (153k tokens médio).
  // Com cache (90% redução nas leituras), cai pra ~$0.10/turno em conversas seguidas.
  // Modelos não-Anthropic recebem string concatenada normal (caching ignorado).
  const channelSystemPrompt =
    options.historyProvider === 'mobile_flow'
      ? mobileFlowPromptContext(promptRow.system_prompt)
      : promptRow.system_prompt
  const stableSystem = channelSystemPrompt + (options.systemPolicy ?? '')
  // RAG (D): método relevante recuperado por turno — bloco VARIÁVEL (não cacheado).
  const methodContext = await retrieveMethodContext(deps, input.text, ctx.profile.currentProtocol)
  const channelMethodContext =
    options.historyProvider === 'mobile_flow' ? mobileFlowPromptContext(methodContext) : methodContext
  const variableSystem = `${channelMethodContext}\n\n## Contexto do usuário\n${formatUserContext(ctx, calcConfig, input.timestamp, options.historyProvider)}${repetitionGuard}`
  const isAnthropic = /^anthropic\//.test(promptRow.model)
  // TTL 1h em vez de 5min — observado em produção (2026-05-18) hit rate caiu
  // pra 36% pq turnos esparsos (paciente manda msg, espera 30min+, manda
  // outra → cache 5min expira). Com 1h, write custa 2x normal mas hit rate
  // sobe pra 80%+ esperado. Net economia maior.
  const systemPrompt: SystemPromptBlock = isAnthropic
    ? [
        { text: stableSystem, cache: 'ephemeral_1h' },
        { text: variableSystem },
      ]
    : stableSystem + variableSystem

  // Flow sends the current session's lines and only the newest of what came
  // before it (see mobileFlowPromptHistory); the guards above and below keep
  // reading the full ctx.recentMessages.
  const promptHistory =
    options.historyProvider === 'mobile_flow'
      ? mobileFlowPromptHistory(ctx.recentMessages, ctx.flowOutsideSessionLines ?? [])
      : ctx.recentMessages
  const messages: ChatCompletionMessageParam[] = promptHistory.map((m) => ({
    role: m.role,
    content: options.historyProvider === 'mobile_flow' && m.role === 'assistant'
      ? projectFlowMetricContext(m.content)
      : m.content,
  }))
  messages.push({ role: 'user', content: input.text ?? '(mídia recebida)' })

  // Flow only: numbers of each model call, written once at the end of the turn.
  const flowCalls: FlowCallUsage[] | null =
    options.historyProvider === 'mobile_flow' ? [] : null
  // Flow only: the model calls made inside tools (plan generators), the
  // deadline of the turn's model work, and how the turn was answered.
  const flowToolLlmCalls: FlowToolLlmCall[] = []
  const flowDeadlineAt =
    MOBILE_FLOW_TIME_LIMITS && options.historyProvider === 'mobile_flow'
      ? start + MOBILE_FLOW_TURN_DEADLINE_MS
      : null
  let planSuggestionDirect = false
  let flowPlainStatus = false
  // Flow only: the iteration that is the closing call (tools switched off),
  // once one was granted, and whether the deadline ended the turn on a
  // suggestion already stored (see the two constants).
  let flowClosingIteration: number | null = null
  let flowSuggestionAtDeadline = false
  // Flow only: the closing call failed and the turn ended on a suggestion
  // already stored (see the catch of the model call).
  let flowSuggestionAfterFailedClosing = false
  if (options.flowFailure && flowCalls) {
    options.flowFailure.record = () =>
      recordFlowCalls(
        deps.supabase,
        userId,
        stage,
        JSON.stringify(tools).length,
        flowCalls,
        flowToolLlmCalls,
        { turnFailed: true },
      )
  }

  const toolCallsSummary: AgentOutput['toolCalls'] = []
  let totalPromptTokens = 0
  let totalCompletionTokens = 0
  let totalCacheRead = 0
  let totalCacheCreate = 0
  let totalCost: number | null = null
  let lastResult: Awaited<ReturnType<typeof deps.llm.complete>> | null = null
  let finalText = ''

  // max_tool_iterations: prioriza config do DB, fallback pro deps, fallback pra 5
  const configMax = (promptRow as { max_tool_iterations?: number }).max_tool_iterations
  const configuredMax = configMax ?? deps.maxToolIterations ?? 5
  // Flow: capped in code (see the constant). WhatsApp: the configured number.
  const max =
    options.historyProvider === 'mobile_flow'
      ? Math.min(configuredMax, MOBILE_FLOW_MAX_MODEL_ITERATIONS)
      : configuredMax
  // Flag pra evitar loop infinito no re-prompt de fake registration (1 retry só).
  let fakeWriteRetried = false
  let prematureBlockRetried = false
  let falseDuplicationRetried = false
  // Card determinístico de registro → enviar como UMA mensagem (sem split).
  let deterministicRegistration = false
  // FASE B (Roberto 2026-05-28, botões #4): se virou pending → o caller manda
  // sendInteractive em vez de sendHumanized, e o pipeline NÃO chama o LLM de novo.
  let interactivePayload: NonNullable<AgentOutput['interactive']> | null = null
  // A guard retry (fake write, premature block, false duplication; each at
  // most once) re-asks the model for the SAME answer: it gets its own extra
  // iteration instead of consuming the patient's. Staging 2026-09-30: with
  // max_tool_iterations 2, a tool call plus a guard retry left no iteration
  // and the mobile Flow turn ended with no text (502 empty_reply).
  let guardRetries = 0
  for (
    let iter = 0;
    iter < max + guardRetries + (flowClosingIteration === null ? 0 : 1);
    iter++
  ) {
    // Flow only: a suggestion is already stored and the deadline leaves no
    // room for a call that would answer (see the constant). The loop ends
    // here and the stored suggestion is the answer, instead of a failed turn
    // with a pending draft and nothing in the chat.
    if (
      flowDeadlineAt !== null &&
      flowDeadlineAt - Date.now() < MOBILE_FLOW_SUGGESTION_ANSWER_MIN_MS &&
      turnSuggestions(toolCallsSummary).length > 0
    ) {
      flowSuggestionAtDeadline = true
      break
    }
    // Flow only: this iteration is the closing call — the model answers with
    // what it has, and a tool call it still returns is not run.
    const flowClosingNow = flowClosingIteration === iter
    // Measured before the call: `messages` grows after it.
    const flowCallSent = flowCalls
      ? {
          startedAt: Date.now(),
          messages: messages.length,
          messagesChars: messages.reduce(
            (sum, m) => sum + (typeof m.content === 'string' ? m.content.length : 0),
            0,
          ),
        }
      : null
    // Flow only: this call's own limit, never beyond what the turn has left
    // (throws when the turn has nothing left; the service fails the turn).
    const flowCallTimeoutMs =
      flowDeadlineAt === null
        ? null
        : Math.min(MOBILE_FLOW_CHAT_CALL_TIMEOUT_MS, flowTimeLeft(flowDeadlineAt))
    let result: LLMResult
    try {
      result = await deps.llm.complete({
        model: promptRow.model,
        systemPrompt,
        messages,
        temperature: promptRow.temperature,
        maxTokens: promptRow.max_tokens,
        tools,
        cacheTools: isAnthropic, // marca último tool com cache_control pra Anthropic
        cacheToolsTtl: isAnthropic ? 'ephemeral_1h' : undefined, // tools schema é estável, vale 1h
        userId,
        metadata: { Stage: stage, Iteration: String(iter) },
        ...(flowDeadlineAt === null || flowCallTimeoutMs === null
          ? {}
          : {
              requestTimeoutMs: flowCallTimeoutMs,
              // The client's one retry, kept only while a second attempt
              // fits. The client's wait between the two is not counted (see
              // MOBILE_FLOW_TURN_DEADLINE_MS).
              maxRetries: flowDeadlineAt - Date.now() >= 2 * flowCallTimeoutMs ? 1 : 0,
            }),
        ...(flowClosingNow ? { toolChoice: 'none' as const } : {}),
      })
    } catch (error) {
      // WhatsApp: nothing below applies and the error leaves as it came.
      if (flowCalls && flowCallSent) {
        flowCalls.push({
          index: iter,
          model: promptRow.model,
          prompt_tokens: 0,
          completion_tokens: 0,
          cache_read_tokens: 0,
          cache_write_tokens: 0,
          cost_usd: null,
          ms: Date.now() - flowCallSent.startedAt,
          history_lines: promptHistory.length,
          system_chars: [stableSystem.length, variableSystem.length],
          messages: flowCallSent.messages,
          messages_chars: flowCallSent.messagesChars,
          ...(flowClosingNow ? { closing: 1 as const } : {}),
          failed: 1,
        })
      }
      if (flowDeadlineAt !== null) {
        const left = flowDeadlineAt - Date.now()
        // Flow only: the call failed and a suggestion is already stored. With
        // no room left for another call (the same floor as at the top of the
        // loop) the turn answers with that suggestion instead of failing.
        if (
          left < MOBILE_FLOW_SUGGESTION_ANSWER_MIN_MS &&
          turnSuggestions(toolCallsSummary).length > 0
        ) {
          flowSuggestionAtDeadline = true
          break
        }
        // Flow only: the call was cut by the turn's deadline. The turn fails
        // as a deadline — the client's "Request timed out." alone is what a
        // slow provider gives too, and the log could not tell them apart.
        if (left <= MOBILE_FLOW_DEADLINE_SLACK_MS) {
          throw new Error(MOBILE_FLOW_DEADLINE_ERROR, { cause: error })
        }
      }
      // Flow only: the closing call failed with time left and a suggestion is
      // already stored. The call was an extra one, there only to answer what
      // else the message asked; rethrowing failed the whole turn after three
      // paid calls and left the draft pending with nothing in the chat, where
      // the stage config of 2 used to end on the suggestion (third review
      // 2026-10-04). The loop ends as it does at the deadline and the stored
      // suggestion is the answer; the failed call is in llm.flow_calls
      // (`closing` and `failed`). With no suggestion stored the turn has
      // nothing to answer with and fails, as before.
      if (flowClosingNow && turnSuggestions(toolCallsSummary).length > 0) {
        flowSuggestionAfterFailedClosing = true
        break
      }
      throw error
    }
    if (flowCalls && flowCallSent) {
      flowCalls.push({
        index: iter,
        model: result.model,
        prompt_tokens: result.promptTokens,
        completion_tokens: result.completionTokens,
        cache_read_tokens: result.cacheReadInputTokens ?? 0,
        cache_write_tokens: result.cacheCreationInputTokens ?? 0,
        cost_usd: result.costUsd ?? null,
        ms: Date.now() - flowCallSent.startedAt,
        history_lines: promptHistory.length,
        system_chars: [stableSystem.length, variableSystem.length],
        messages: flowCallSent.messages,
        messages_chars: flowCallSent.messagesChars,
        ...(flowClosingNow ? { closing: 1 as const } : {}),
      })
    }
    lastResult = result
    totalPromptTokens += result.promptTokens
    totalCacheRead += result.cacheReadInputTokens ?? 0
    totalCacheCreate += result.cacheCreationInputTokens ?? 0
    totalCompletionTokens += result.completionTokens
    if (result.costUsd != null) {
      totalCost = (totalCost ?? 0) + result.costUsd
    }

    if (result.toolCalls.length === 0 || flowClosingNow) {
      const content = result.content ?? ''

      // GUARD DE ESCRITA FANTASMA — Camada 1 (retry forçado no turno).
      // O LLM às vezes AFIRMA registro (Luciana 2026-05-20: "Almoço registrado…
      // 521 kcal") ou CORREÇÃO (Roberto 2026-05-21: "Corrigido. Feijão 180g…")
      // com card completo MAS sem chamar a tool — nada é salvo. O card em si é
      // canônico (FIX C reescreve do banco); a falha é a tool não rodar. Aqui
      // forçamos 1 retry. Detector puro travado em fake-write-detector.test.ts.
      const registrationToolCalled = toolCallsSummary.some(
        (tc) =>
          (tc.name === 'registra_refeicao' || tc.name === 'registra_treino') && !tc.error,
      )
      const prescriptionToolCalled = toolCallsSummary.some(
        (tc) => PRESCRIPTION_TOOLS.has(tc.name) && !tc.error,
      )
      const skipToolCalled = toolCallsSummary.some(
        (tc) => tc.name === 'marca_refeicao_pulada' && !tc.error,
      )
      // Hint de meal_type pra skip detector quando paciente diz "Pulei" sem
      // especificar (review HIGH SKIP-NO-HINT). Ordem: (1) último gap reminder
      // no histórico do dia, (2) inferência por hora local.
      const mealTypeHint = inferMealTypeHint(ctx)
      const fake = detectFakeWrite({
        content,
        patientText: semanticPatientText,
        registrationToolCalled: registrationToolCalled || draftCreatedThisTurn(toolCallsSummary),
        prescriptionToolCalled,
        skipToolCalled,
        goalToolCalled: goalToolRanThisTurn(toolCallsSummary),
        patientTurnText: patientTurnTextOf(input, semanticPatientText),
        mealTypeHint,
      })

      if (fake.isFake && !fakeWriteRetried) {
        fakeWriteRetried = true
        guardRetries += 1
        await deps.supabase.from('product_events').insert({
          user_id: userId,
          event: 'llm.fake_write_detected',
          properties: {
            stage,
            kind: fake.kind,
            model: result.model,
            ...(options.includeSensitiveTelemetry === false
              ? {}
              : { content_preview: content.slice(0, 120) }),
            inferred_meal_type: fake.inferredMealType ?? null,
          },
        })
        messages.push({ role: 'assistant', content })
        const retryMsg = !fakeWriteRetryAllowed(fake.kind, filteredTools)
          ? options.historyProvider === 'mobile_flow'
            ? CHAT_WRITE_RETRACTION
            : TURN_WRITE_RETRACTION
          : fake.kind === 'skip'
            ? `SISTEMA (não é o paciente): o paciente confirmou que PULOU uma refeição. Você respondeu como se tivesse anotado/registrado MAS não chamou a tool \`marca_refeicao_pulada\`. Chame \`marca_refeicao_pulada(meal_type=${fake.inferredMealType ?? '<inferir do contexto>'})\` AGORA. NÃO chame \`registra_refeicao\` — não há refeição pra registrar. NÃO copie items do histórico — o paciente disse pulei, então a refeição NÃO existe.`
            : fake.kind === 'correction'
              ? 'SISTEMA (não é o paciente): você afirmou ter CORRIGIDO a refeição/treino MAS não chamou a tool. A correção NÃO foi salva — o banco ainda tem a versão antiga. Chame `registra_refeicao` com `replace=true` + `meal_type` (ou `registra_treino` pra exercício) AGORA com os itens corretos. NÃO responda ao paciente sem antes chamar a tool.'
              : draftRetryMessage(fake.kind, filteredTools)
                ? (draftRetryMessage(fake.kind, filteredTools) as string)
                : fake.kind === 'diet_fake'
                ? 'SISTEMA (não é o paciente): você apresentou um CARDÁPIO INVENTADO (com refeições + lista de compras) sem chamar `gera_dieta`. Nada foi salvo, os macros NÃO foram validados, e o paciente vai seguir uma dieta fantasma. Se o paciente PEDIU explicitamente um cardápio, chame `gera_dieta` AGORA. Se o paciente só estava perguntando teoria, responda SEM o cardápio — pergunte se quer que você gere de verdade.'
                : fake.kind === 'training_fake'
                  ? 'SISTEMA (não é o paciente): você apresentou um PLANO DE TREINO INVENTADO (com dias + exercícios + séries) sem chamar `gera_treino`. Nada foi salvo, cron diário não vai entregar nada, e paciente vai treinar com plano fantasma. Se o paciente JÁ confirmou equipamentos + dias/semana + nível, chame `gera_treino` AGORA. Se faltar algum dos 3, PERGUNTE e NÃO mostre o plano.'
                  : 'SISTEMA (não é o paciente): você afirmou ter registrado a refeição/treino MAS não chamou a tool `registra_refeicao` (ou `registra_treino`). Os dados NÃO foram salvos no banco — sua resposta foi inválida. Chame a tool AGORA com os itens corretos que o paciente informou. NÃO responda ao paciente de novo sem antes chamar a tool.'
        messages.push({
          role: 'user',
          content: retryMsg,
        })
        continue
      }

      // Guard de conclusão PREMATURA de bloco (Roberto 2026-05-22): o bloco só
      // credita no fechamento da noite; no meio do dia o déficit está inflado
      // (refeições ainda não feitas). Não deixar a prosa comemorar "bloco fechado
      // hoje" contradizendo o card. 1 retry forçado.
      if (detectPrematureBlockCompletion(content) && !prematureBlockRetried) {
        prematureBlockRetried = true
        guardRetries += 1
        await deps.supabase.from('product_events').insert({
          user_id: userId,
          event: 'llm.premature_block_completion',
          properties: {
            stage,
            ...(options.includeSensitiveTelemetry === false
              ? {}
              : { content_preview: content.slice(0, 140) }),
          },
        })
        messages.push({ role: 'assistant', content })
        messages.push({
          role: 'user',
          content:
            'SISTEMA (não é o paciente): você afirmou que o bloco 7700 fechou/completou. ERRADO — o bloco só credita no FECHAMENTO do dia (à noite); durante o dia ele NÃO fecha (o déficit do meio do dia ainda vai mudar conforme o paciente come). Reescreva SEM dizer que o bloco fechou/completou hoje/agora. Reporte o bloco exatamente como está no card (ex: "X / 7.700, Y%") e, se faltar pouco, diga "faltam Z kcal pra fechar".',
        })
        continue
      }

      // Guard de FALSO POSITIVO de duplicação (Roberto 2026-06-02):
      // LLM acusa "veio duplicada" pra msg que tem múltiplos itens distintos
      // (ex: "45 min musculação e 19 min bicicleta"). Agent_rule sozinha não
      // segurou — defesa em código. Retry forçado pedindo processar como veio.
      if (
        !falseDuplicationRetried &&
        detectFalseDuplicationClaim(content, input.text)
      ) {
        falseDuplicationRetried = true
        guardRetries += 1
        await deps.supabase.from('product_events').insert({
          user_id: userId,
          event: 'llm.false_duplication_caught',
          properties: {
            stage,
            ...(options.includeSensitiveTelemetry === false
              ? {}
              : {
                  patient_text: (input.text ?? '').slice(0, 200),
                  agent_text: content.slice(0, 200),
                }),
          },
        })
        messages.push({ role: 'assistant', content })
        messages.push({
          role: 'user',
          content: `SISTEMA (não é o paciente): o paciente NÃO mandou mensagem duplicada. O texto original recebido foi: "${input.text}". Processe COMO VEIO, SEM acusar duplicação. Se há múltiplos itens conectados (ex: "X e Y", "X, Y, Z" ou em linhas separadas), são itens DISTINTOS — ${authorizeToolCall('registra_refeicao', filteredTools).status === 'authorized' ? 'registre TODOS' : 'trate TODOS como itens distintos, sem afirmar que foram registrados'}. Refaça a resposta agora.`,
        })
        continue
      }

      // The mobile Flow has no WhatsApp buttons/lists: legacy tags become
      // plain text there (see flattenLegacyTagsForApp), never an interactive
      // payload the app would drop, leaving an empty reply.
      if (options.historyProvider === 'mobile_flow') {
        finalText = flattenLegacyTagsForApp(content)
        messages.push({ role: 'assistant', content })
        break
      }

      // Roberto 2026-06-01: botões no onboarding. Se o LLM emitiu tag
      // [BTN:field:opt1=val1|opt2=val2] no texto, transforma em interactive.
      // Só pra fields enum suportados (sex, hunger_level, water_intake,
      // food_organization, current_protocol). Demais perguntas vão texto normal.
      const onbProposal = parseOnboardingButtonTag(content)
      if (onbProposal) {
        const buttons = onbProposal.options.map((o) => ({
          id: makeOnboardingButtonId(onbProposal.field, o.value),
          title: o.label,
        }))
        interactivePayload = { body: onbProposal.body, buttons, pendingId: '' }
        await deps.supabase.from('product_events').insert({
          user_id: userId,
          event: 'pipeline.onboarding_button_sent',
          properties: {
            field: onbProposal.field,
            options: onbProposal.options.map((o) => o.value),
          },
        })
        messages.push({ role: 'assistant', content })
        finalText = '' // envio via interactive, não via sendHumanized
        break
      }

      // Fase 2 (Roberto 2026-06-01): [LIST:...] pra perguntas com 4-10 opções
      // (activity_level: 5; training_frequency: 8). WhatsApp renderiza como
      // botão "Escolher" → dropdown. Mesmo id pattern btn_<field>_<value>.
      const onbListProposal = parseOnboardingListTag(content)
      if (onbListProposal) {
        const buttons = onbListProposal.options.map((o) => ({
          id: makeOnboardingButtonId(onbListProposal.field, o.value),
          title: o.label,
        }))
        interactivePayload = {
          body: onbListProposal.body,
          buttons,
          pendingId: '',
          list: { buttonText: onbListProposal.buttonText },
        }
        await deps.supabase.from('product_events').insert({
          user_id: userId,
          event: 'pipeline.onboarding_list_sent',
          properties: {
            field: onbListProposal.field,
            options: onbListProposal.options.map((o) => o.value),
          },
        })
        messages.push({ role: 'assistant', content })
        finalText = ''
        break
      }

      finalText = content
      messages.push({ role: 'assistant', content })
      break
    }

    // Push assistant message com tool_calls (reconstrução simplificada)
    messages.push({
      role: 'assistant',
      content: result.content ?? '',
      tool_calls: result.toolCalls.map((tc) => ({
        id: tc.id,
        type: 'function',
        function: { name: tc.name, arguments: tc.arguments },
      })),
    })

    // Executa cada tool
    const toolCtx: ToolContext = {
      supabase: deps.supabase,
      userId,
      userWpp: input.from,
      llm: deps.llm,
      userCountry: ctx.country ?? 'BR',
      userTimezone: ctx.timezone,
      providerMessageId: input.providerMessageId,
      referenceTimestamp: input.timestamp,
      currentUserText: semanticPatientText,
      // O turno atual ja contem todo o burst agregado. Nao reutilizar texto
      // historico em guardas semanticas: uma mencao antiga de "jantar" ou
      // "corrige" nao pode autorizar a gravacao atual.
      recentUserMessages: semanticPatientText.trim() ? [semanticPatientText] : [],
      // Set only here, from the server-side channel (never from a payload):
      // plan generators speak as Flow on the mobile channel, and keep the
      // current identity everywhere else.
      ...(options.historyProvider === 'mobile_flow'
        ? {
            // Tools' own model calls are counted into the turn and bounded
            // by its deadline (see flowToolLlm).
            llm: flowToolLlm(deps.llm, flowDeadlineAt, flowToolLlmCalls),
            assistantIdentity: 'flow' as const,
            flowDailyTargets: ctx.dailyTargets,
            // Same inputs as the context, so consulta_progresso and the
            // per-turn context give the model the same day's balance.
            flowDayBalance: flowDayBalanceInputs(ctx.profile, calcConfig, ctx.flowDayRow),
          }
        : {}),
    }
    for (const tc of result.toolCalls) {
      // Authorization comes first: nothing below (argument parsing, the
      // deferred-pending path, execute, audit) runs for a withheld tool.
      const authorization = authorizeToolCall(tc.name, filteredTools)
      if (authorization.status !== 'authorized') {
        const error = authorization.status === 'unknown' ? 'tool_unknown' : 'tool_not_authorized'
        // The model's arguments are never kept for a refused call.
        toolCallsSummary.push({ name: telemetryToolName(tc.name), arguments: {}, error })
        messages.push({
          role: 'tool',
          tool_call_id: tc.id,
          content: JSON.stringify({ success: false, error, retry_tool: false }),
        })
        await deps.supabase.from('product_events').insert({
          user_id: userId,
          event: 'pipeline.tool_call_denied',
          properties: {
            tool: telemetryToolName(tc.name),
            reason: error,
            channel: options.historyProvider ?? 'whatsapp',
          },
        })
        continue
      }
      const tool = authorization.tool
      let parsed: unknown
      try {
        parsed = JSON.parse(tc.arguments)
      } catch {
        parsed = {}
      }
      try {
        const validated = tool.parameters.parse(normalizeToolArguments(tool, parsed))
        const trustedVisionLabels = input.visionNutritionLabels ?? []
        let matchedLabelCount: number | undefined
        if (tc.name === 'registra_refeicao' && trustedVisionLabels.length > 0) {
          const mealArgs = validated as {
            items: Array<{
              food_name: string
              quantity_g: number
              approved_nutrition?: {
                source?: 'product_label'
                kcal: number
                protein_g: number
                carbs_g: number
                fat_g: number
              }
            }>
          }
          mealArgs.items = attachTrustedVisionNutrition(mealArgs.items, trustedVisionLabels)
          matchedLabelCount = mealArgs.items.filter(
            (item) => item.approved_nutrition != null,
          ).length
        }

        if (
          shouldBlockUntrustedNutritionLabelRegistration({
            toolName: tc.name,
            nutritionLabelDetected: input.visionNutritionLabelDetected === true,
            detectedLabelCount: input.visionNutritionLabelDetectedCount,
            trustedLabelCount: trustedVisionLabels.length,
            matchedLabelCount,
          })
        ) {
          const error =
            trustedVisionLabels.length > 0
              ? 'Rótulo confiável, mas sem associação inequívoca a um item da refeição. Não estime: confirme qual item e porção pertencem ao rótulo.'
              : 'Rótulo incompleto ou com baixa confiança. Não registre nem estime ainda; peça kcal, proteína, carboidrato e gordura por porção.'
          toolCallsSummary.push({ name: tc.name, arguments: validated, error })
          messages.push({
            role: 'tool',
            tool_call_id: tc.id,
            content: JSON.stringify({ success: false, error, retry_tool: false }),
          })
          continue
        }

        // ── FASE B BOTÕES (Roberto 2026-05-28, opção #4) ──────────────────────
        // Quando o paciente está no opt-in (users.metadata.buttons_enabled) E o
        // LLM chamou SÓ registra_refeicao (sem mistura com outras tools) E o
        // texto NÃO é express (foto/áudio/vago/sem gramas) → em vez de gravar
        // direto, criamos um pending_registrations + retornamos interactive
        // payload pro caller (process-message) mandar [Sim, registrar] [Editar].
        // Roberto 2026-06-01: removido o bloqueio de `replace !== true` —
        // correção também passa por botão agora, padronizando UX e dando
        // chance do paciente ver o que vai ser SUBSTITUÍDO antes de confirmar
        // (replace é destrutivo).
        if (tc.name === 'registra_refeicao' && result.toolCalls.length === 1) {
          const exprInput: ExpressInput = {
            contentType:
              ctx.lastInboundContentType === 'image'
                ? 'image'
                : ctx.lastInboundContentType === 'audio'
                  ? 'audio'
                  : 'text',
            patientText: semanticPatientText,
            items:
              (validated as { items?: Array<{ food_name: string; quantity_g?: number }> })
                .items ?? [],
          }
          const exprResult = isMealExpressEligible(exprInput)
          // Opt-in por paciente: users.metadata.buttons_enabled === true.
          const buttonsEnabled =
            (ctx.userMetadata as { buttons_enabled?: boolean } | null)?.buttons_enabled === true

          // FIX (Roberto 2026-05-28): cancelar pendings em aberto SEMPRE que
          // o paciente faz nova registra_refeicao — seja express OU não-express.
          // Antes só cancelava no caminho "criar novo pending", então express com
          // pending antigo aberto deixava órfão → paciente tocava Sim no antigo
          // → registrava em DOBRO (express + antigo). UPDATE é no-op se nada bate.
          //
          // FIX Bug #2 (Luciana 2026-06-23, audit 06-24): o cancel cego mata
          // pending VIGENTE quando paciente manda foto + caption em buffers
          // separados. Cenário real: foto pizza (21:33:03) virou pending de 8
          // itens; caption "10g ketchup + 10g maionese" (21:33:30, gap 27s) virou
          // turno separado, LLM interpretou como ADIÇÃO e chamou registra_refeicao
          // com só esses 2 itens. Cancel mata pending de 8, express grava 2 → pizza
          // suma. Layer 1: ANTES do cancel, checa se tool_call atual é SUBSET
          // PRÓPRIO de pending recente (<5min). Se sim, suprime: não cancela, não
          // executa tool. Paciente ainda pode tocar o botão do pending vigente.
          let suppressedAsDuplicate = false
          if (buttonsEnabled) {
            // Review H1 HIGH: se LLM passou replace=true, é correção destrutiva
            // explícita — NÃO suprimir (paciente quer substituir o pending).
            // Antes: suppression ignorava replace=true e cancelaria a intenção
            // de correção silenciosamente.
            const isExplicitReplace = (validated as { replace?: boolean }).replace === true

            const normalizeFoodName = (s: string) =>
              s.toLowerCase().normalize('NFD').replace(/\p{Diacritic}/gu, '').trim()
            const newItemsByName = new Map<string, { quantity_g?: number }>(
              exprInput.items.map((i) => [
                normalizeFoodName(i.food_name),
                { quantity_g: i.quantity_g ?? undefined },
              ]),
            )
            const newItemNames = new Set(newItemsByName.keys())
            if (!isExplicitReplace && newItemNames.size > 0) {
              // Filtra kind=meal e falha fechado: sem essa leitura não é seguro
              // cancelar a proposta anterior nem decidir que o novo burst é distinto.
              const recentPending = await loadRecentPendingMeal(deps.supabase, userId)
              const pend = recentPending as {
                id: string
                proposal: {
                  items?: Array<{ name: string; quantity_g?: number }>
                  sourceContentType?: string
                } | null
                created_at: string
              } | null
              const pendItems = pend?.proposal?.items ?? []
              // Review L1 (audit 06-24): só suprimir quando pending VEIO DE FOTO.
              // O cenário-raiz (Luciana 23/06) é foto pizza + caption tardio. Em
              // padrões texto+texto (paciente repete itens em mensagens
              // separadas), suprimir gera false positive. Reduz superfície de
              // suppression espúria, mantém proteção do caso real.
              //
              // Audit 06-26 sprint pendentes Item 3: estende cobertura pra
              // áudio também (cenário simétrico: paciente manda áudio listando
              // 5 itens, STT processa, depois manda áudio curto "tinha
              // batata também" — sem suppression, virava registro novo
              // duplicando os 5 originais).
              const pendSourceType = pend?.proposal?.sourceContentType ?? null
              const isMediaPending = pendSourceType === 'image' || pendSourceType === 'audio'
              if (pend && isMediaPending && pendItems.length > newItemNames.size) {
                const pendByName = new Map<string, { quantity_g?: number }>(
                  pendItems.map((it) => [
                    normalizeFoodName(it.name),
                    { quantity_g: it.quantity_g },
                  ]),
                )
                const allInPending = Array.from(newItemNames).every((n) =>
                  pendByName.has(n),
                )
                // Review H2 HIGH: se ALGUM item novo tem quantity_g divergente
                // do mesmo item no pending (>20% diff em valor absoluto), tratar
                // como CORREÇÃO de gramatura — não suprimir. Caso real previsto:
                // "arroz foi 200g, esqueci de falar" depois de pending com arroz 50g.
                let hasQuantityDivergence = false
                if (allInPending) {
                  for (const [name, newInfo] of newItemsByName) {
                    const pendInfo = pendByName.get(name)
                    const newQ = newInfo.quantity_g
                    const pendQ = pendInfo?.quantity_g
                    if (
                      typeof newQ === 'number' &&
                      typeof pendQ === 'number' &&
                      pendQ > 0
                    ) {
                      const ratio = Math.abs(newQ - pendQ) / pendQ
                      if (ratio > 0.2) {
                        hasQuantityDivergence = true
                        break
                      }
                    }
                  }
                }
                if (allInPending && !hasQuantityDivergence) {
                  suppressedAsDuplicate = true
                  await deps.supabase.from('product_events').insert({
                    user_id: userId,
                    event: 'pipeline.duplicate_meal_suppressed',
                    properties: {
                      pendingId: pend.id,
                      pending_items_count: pendItems.length,
                      new_items_count: newItemNames.size,
                      new_items: Array.from(newItemNames),
                      gap_ms: Date.now() - new Date(pend.created_at).getTime(),
                      pend_source_content_type: pendSourceType,
                    },
                  })
                  // Marca tool_call como suprimido pro LLM não retentar — mesma
                  // estratégia do deferred_to_button abaixo (linhas ~686-697).
                  toolCallsSummary.push({
                    name: tc.name,
                    arguments: validated,
                    result: {
                      success: true,
                      suppressed_as_duplicate: true,
                      pendingId: pend.id,
                    },
                  })
                  messages.push({
                    role: 'tool',
                    tool_call_id: tc.id,
                    content: JSON.stringify({
                      success: true,
                      suppressed_as_duplicate: true,
                      pendingId: pend.id,
                      message:
                        'Itens já estão no pending recente — aguarde paciente confirmar o botão.',
                    }),
                  })
                  // Review M3 (audit 06-24): em vez de suprimir SILENTE
                  // (paciente fica sem feedback achando que falhou), re-envia o
                  // interactive do pending existente. Caso o paciente tenha
                  // perdido o botão original na timeline, recebe de novo o
                  // mesmo botão (mesma pendingId) com o card inteiro. Tap
                  // posterior ainda funciona porque o pending continua status
                  // 'pending'.
                  // eslint-disable-next-line @typescript-eslint/no-explicit-any
                  const fullProposal = pend.proposal as any
                  if (fullProposal && Array.isArray(fullProposal.items)) {
                    try {
                      const { body, buttons } = composePendingProposal(
                        pend.id,
                        fullProposal,
                      )
                      interactivePayload = { body, buttons, pendingId: pend.id }
                    } catch (e) {
                      // composePendingProposal pode falhar se proposal shape
                      // mudar. Não-fatal: cai no comportamento antigo (silente).
                      // eslint-disable-next-line no-console
                      console.warn(
                        '[pipeline] re-compose suppressed pending falhou (silente):',
                        e,
                      )
                    }
                  }
                  deterministicRegistration = true
                  finalText = ''
                  break
                }
              }
            }
            if (!suppressedAsDuplicate && exprResult.eligible) {
              await cancelOpenPendingRegistrations(deps.supabase, userId)
            }
          }

          if (buttonsEnabled && !exprResult.eligible) {
            // Cria o pending novo
            const args = validated as {
              meal_type?: string | null
              replace?: boolean
              corrections?: unknown
              items: Array<{
                food_name: string
                quantity_g?: number
                approved_nutrition?: {
                  source?: 'product_label'
                  kcal: number
                  protein_g: number
                  carbs_g: number
                  fat_g: number
                }
              }>
            }
            const originalItemCount = args.items.length
            const dedupedArgs = dedupeMealItems(
              args.items.map((item) => ({ ...item, quantity_g: item.quantity_g ?? 0 })),
              { patientText: semanticPatientText },
            )
            args.items = dedupedArgs.items
            if (dedupedArgs.duplicates.length > 0) {
              await deps.supabase.from('product_events').insert({
                user_id: userId,
                event: 'pipeline.pending_items_deduped',
                properties: {
                  meal_type: args.meal_type ?? null,
                  provider_message_id: input.providerMessageId,
                  source_content_type: ctx.lastInboundContentType,
                  original_count: originalItemCount,
                  merged_count: dedupedArgs.items.length,
                  duplicates: dedupedArgs.duplicates.map((duplicate) => ({
                    food_name: duplicate.food_name,
                    repeated: duplicate.repeated,
                    result_g: duplicate.result_g,
                    strategy: duplicate.strategy,
                  })),
                },
              })
            }
            const pendingCorrections = normalizePendingFoodCorrections(args.corrections)
            const correctionSourceNames = pendingCorrections.map((correction) => correction.de)
            const wholeMealReplacement =
              args.replace === true &&
              hasExplicitWholeMealReplacementIntent([
                ...ctx.recentMessages
                  .filter((message) => message.role === 'user')
                  .map((message) => message.content),
                semanticPatientText,
              ])
            const shouldLoadCorrectionContext =
              args.replace === true && pendingCorrections.length > 0 && !wholeMealReplacement
            const [editedPendingRow, confirmedPendingRow, registeredMeal] = await Promise.all([
              loadRecentEditedMealPending(
                deps.supabase,
                userId,
                args.meal_type ?? 'outro',
                input.timestamp,
              ),
              shouldLoadCorrectionContext
                ? loadRecentConfirmedMealPending(
                    deps.supabase,
                    userId,
                    args.meal_type ?? 'outro',
                    input.timestamp,
                    correctionSourceNames,
                  )
                : Promise.resolve(null),
              shouldLoadCorrectionContext
                ? loadRecentRegisteredMeal(
                    deps.supabase,
                    userId,
                    args.meal_type ?? 'outro',
                    input.timestamp,
                    correctionSourceNames,
                  )
                : Promise.resolve(null),
            ])
            const editedPending = editedPendingRow as {
              id: string
              proposal?: { items?: MealItem[] }
            } | null
            const confirmedPending = confirmedPendingRow as {
              id: string
              proposal?: { items?: MealItem[] }
            } | null
            // FIX (Roberto 2026-05-28): a LLM passa só {food_name, quantity_g}.
            // kcal/macros vêm da resolução TACO via calcMealMacros — o mesmo
            // que registra_refeicao usa internamente. Sem isso o pending vinha
            // com 0 kcal (Roberto viu na tela: "0 kcal" em todos os itens).
            // Bug Luciana 2026-06-16: parser de "X cal/kcal/calorias" no texto
            // do paciente. O helper restringe o contexto ao turno atual ou à
            // mensagem imediatamente anterior quando a atual é confirmação
            // curta. Isso evita herdar kcal de uma refeição antiga.
            const kcalOverrideTexts = [
              ...ctx.recentMessages
                .filter((m) => m.role === 'user')
                .map((m) => m.content),
              semanticPatientText,
            ]
            const kcalOverrides = parseUserKcalOverridesFromMessages(kcalOverrideTexts, args.items)
            const itemsWithOverrides = attachTrustedVisionNutrition(
              args.items.map((it) => ({
                ...it,
                quantity_g: it.quantity_g ?? 0,
                ...(kcalOverrides.has(it.food_name)
                  ? { user_kcal: kcalOverrides.get(it.food_name)! }
                  : {}),
              })),
              input.visionNutritionLabels ?? [],
            )
            if (kcalOverrides.size > 0) {
              await deps.supabase.from('product_events').insert({
                user_id: userId,
                event: 'pipeline.user_kcal_override_attached_to_pending',
                properties: {
                  source: 'express_pending',
                  overrides: Object.fromEntries(kcalOverrides),
                  items_count: args.items.length,
                  messages_count: kcalOverrideTexts.filter(Boolean).length,
                  selection_scope: 'current_or_immediate_confirmation',
                },
              })
            }
            const resolved = await calcMealMacros(
              deps.supabase,
              itemsWithOverrides,
              ctx.country ?? 'BR',
              userId,
            )
            const userKcalByName = new Map(
              itemsWithOverrides
                .filter((it) => it.user_kcal != null)
                .map((it) => [it.food_name, it.user_kcal as number]),
            )
            let proposalItems: MealItem[] = resolved.items.map((m) => ({
              name: m.food_name,
              food_db_id: m.matched_taco_id,
              nutrition_source: m.source,
              quantity_g: m.quantity_g,
              display_qty: m.display_qty ?? null,
              display_unit: m.display_unit ?? null,
              kcal: m.kcal ?? 0,
              ...(userKcalByName.has(m.food_name)
                ? { user_kcal: userKcalByName.get(m.food_name)! }
                : {}),
              protein_g: m.protein_g ?? 0,
              carbs_g: m.carbs_g ?? 0,
              fat_g: m.fat_g ?? 0,
              ...(m.preparation_options ? { preparation_options: m.preparation_options } : {}),
            }))
            let proposalTotals = {
              kcal: resolved.totals.kcal,
              protein_g: resolved.totals.protein_g,
              carbs_g: resolved.totals.carbs_g,
              fat_g: resolved.totals.fat_g,
            }
            let quantityEditAdjustments: ReturnType<
              typeof reconcilePendingMealEdit
            >['adjustments'] = []
            let quantityEditAdjustmentPayload: Array<Record<string, string | number>> = []
            const previousItems =
              registeredMeal?.items ??
              editedPending?.proposal?.items ??
              confirmedPending?.proposal?.items ??
              []
            if (previousItems.length > 0) {
              const reconciled = reconcilePendingMealEdit({
                previousItems,
                resolvedItems: proposalItems,
                currentExplicitKcalFoods: new Set(kcalOverrides.keys()),
              })
              proposalItems = reconciled.items
              proposalTotals = reconciled.totals
              quantityEditAdjustments = reconciled.adjustments
              quantityEditAdjustmentPayload = quantityEditAdjustments.map((adjustment) => ({
                food_name: adjustment.food_name,
                previous_quantity_g: adjustment.previous_quantity_g,
                quantity_g: adjustment.quantity_g,
                previous_kcal: adjustment.previous_kcal,
                kcal: adjustment.kcal,
                reason: adjustment.reason,
              }))
              if (quantityEditAdjustments.length > 0) {
                await deps.supabase.from('product_events').insert({
                  user_id: userId,
                  event: 'pipeline.pending_quantity_nutrition_scaled',
                  properties: {
                    edited_pending_id: editedPending?.id ?? null,
                    confirmed_pending_id: confirmedPending?.id ?? null,
                    registered_meal_context: registeredMeal != null,
                    meal_type: args.meal_type ?? 'outro',
                    adjustments: quantityEditAdjustmentPayload,
                  },
                })
              }
            }
            if (shouldLoadCorrectionContext) {
              const scopedCorrection = reconcileScopedMealCorrection({
                previousItems,
                resolvedItems: proposalItems,
                corrections: pendingCorrections,
              })
              if (!scopedCorrection) {
                throw new Error('pending scoped correction context is incomplete or ambiguous')
              }
              proposalItems = scopedCorrection.items
              proposalTotals = scopedCorrection.totals
            }
            const ambiguousPreparationNames = [
              ...new Set(
                proposalItems
                  .map((item) => item.name)
                  .filter(requiresVisualPreparationConfirmation),
              ),
            ]
            const nutritionConfirmationNotes = buildPendingNutritionConfirmationNotes(proposalItems)
            const preparationConfirmationNotes =
              ctx.lastInboundContentType === 'image'
                ? ambiguousPreparationNames.slice(0, 2).map(
                    (name) =>
                      `Confirme o preparo de ${name}: a foto pode confundir frito, grelhado e assado, alterando o cálculo.`,
                  )
                : []
            const confirmationNotes = [
              ...buildPendingPreparationQuestions(proposalItems),
              ...nutritionConfirmationNotes,
              ...preparationConfirmationNotes,
            ].slice(0, 2)
            let correctionWriteItems: MealItem[] | undefined
            if (shouldLoadCorrectionContext) {
              const destinations = pendingCorrections
                .map((correction) => correction.para.trim())
                .filter((destination) => destination && destination.toLowerCase() !== 'nenhum')
              const allDestinationsPresent = destinations.every((destination) =>
                proposalItems.some((item) => foodNamesReferToSameItem(item.name, destination)),
              )
              if (!allDestinationsPresent || destinations.length === 0) {
                throw new Error('pending correction destination missing from proposal')
              }
              correctionWriteItems = proposalItems.filter((item) =>
                destinations.some((destination) =>
                  foodNamesReferToSameItem(item.name, destination),
                ),
              )
            }
            const proposal = {
              kind: 'meal' as const,
              mealType: args.meal_type ?? 'outro',
              items: proposalItems,
              ...(correctionWriteItems ? { writeItems: correctionWriteItems } : {}),
              totals: proposalTotals,
              sourceContentType: ctx.lastInboundContentType,
              source_provider_message_id: input.providerMessageId ?? null,
              ...(options.includeSensitiveTelemetry === false
                ? {}
                : { source_text: semanticPatientText || null }),
              ...(editedPending?.id ? { edited_from_pending_id: editedPending.id } : {}),
              ...(quantityEditAdjustments.length > 0
                ? { quantity_edit_adjustments: quantityEditAdjustmentPayload }
                : {}),
              ...(confirmationNotes.length > 0 ? { confirmationNotes } : {}),
              ...(pendingCorrections.length > 0 ? { corrections: pendingCorrections } : {}),
              express_eligible: false,
              express_reason: exprResult.reason,
              // Roberto 2026-06-01: salva replace pra handler do tap propagar
              // pro registra_refeicao.execute. Sem isso, correção que veio via
              // botão viraria INSERT em vez de SUBSTITUIR (dupla contagem).
              replace: args.replace === true,
              replace_evidence: {
                llm_requested_replace: args.replace === true,
                pending_context_is_authorization: false,
              },
              ...buildPendingTiming(ctx.timezone, input.timestamp),
            }
            const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString()
            const pendingId = await createPendingRegistration(deps.supabase, {
              userId,
              proposal: proposal as unknown as Json,
              expiresAt,
              requestKey: input.providerMessageId ?? null,
            })
            if (pendingId) {
              const { body, buttons } = composePendingProposal(pendingId, proposal)
              interactivePayload = { body, buttons, pendingId }
              await deps.supabase.from('product_events').insert({
                user_id: userId,
                event: 'pipeline.pending_created',
                properties: {
                  pendingId,
                  kind: 'meal',
                  meal_type: proposal.mealType,
                  items_count: proposalItems.length,
                  write_items_count: correctionWriteItems?.length ?? proposalItems.length,
                  corrections_count: pendingCorrections.length,
                  whole_meal_replacement: wholeMealReplacement,
                  express_reason: exprResult.reason,
                },
              })
              // Marca o tool_call como "deferido" pro LLM não retentar
              toolCallsSummary.push({
                name: tc.name,
                arguments: validated,
                result: { success: true, deferred_to_button: true, pendingId },
              })
              messages.push({
                role: 'tool',
                tool_call_id: tc.id,
                content: JSON.stringify({ success: true, deferred_to_button: true, pendingId }),
              })
              // Bypassa o resto: hijack do flag singleMessage + sai do loop iter
              deterministicRegistration = true
              finalText = '' // o envio é via sendInteractive no caller
              break // sai do for-tool loop
            }
          } else if (exprResult.eligible) {
            await deps.supabase.from('product_events').insert({
              user_id: userId,
              event: 'pipeline.express_used',
              properties: {
                meal_type: (validated as { meal_type?: string }).meal_type,
                items_count: exprResult.items_count,
                qty_markers_found: exprResult.qty_markers_found,
              },
            })
          }
        }
        // ── FASE D: registra_treino também via botão ──────────────────────────
        if (
          tc.name === 'registra_treino' &&
          result.toolCalls.length === 1 &&
          (validated as { replace?: boolean }).replace !== true
        ) {
          const wArgs = validated as {
            workout_type?: string
            duration_min?: number | null
            intensity?: string | null
            estimated_kcal_from_image?: number | null
          }
          const exprRes = isWorkoutExpressEligible({
            contentType:
              ctx.lastInboundContentType === 'image'
                ? 'image'
                : ctx.lastInboundContentType === 'audio'
                  ? 'audio'
                  : 'text',
            patientText: semanticPatientText,
            workoutType: wArgs.workout_type ?? null,
            durationMin: wArgs.duration_min ?? null,
          })
          const buttonsEnabled =
            (ctx.userMetadata as { buttons_enabled?: boolean } | null)?.buttons_enabled === true

          // FIX (mesmo do registra_refeicao acima): cancela pending em aberto
          // SEMPRE — express ou não — pra evitar duplicação caso tape Sim no antigo.
          if (buttonsEnabled && exprRes.eligible) {
            await cancelOpenPendingRegistrations(deps.supabase, userId)
          }

          if (buttonsEnabled && !exprRes.eligible) {
            const proposal = {
              kind: 'workout' as const,
              workoutType: wArgs.workout_type ?? 'treino',
              durationMin: wArgs.duration_min ?? null,
              kcalEst: wArgs.estimated_kcal_from_image ?? null,
              sourceContentType: ctx.lastInboundContentType,
              source_provider_message_id: input.providerMessageId ?? null,
              ...(options.includeSensitiveTelemetry === false
                ? {}
                : { source_text: semanticPatientText || null }),
              express_eligible: false,
              express_reason: exprRes.reason,
              // guarda os args completos pro handler chamar registraTreino depois
              raw_args: wArgs,
              ...buildPendingTiming(ctx.timezone, input.timestamp),
            }
            const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString()
            const pendingId = await createPendingRegistration(deps.supabase, {
              userId,
              proposal: proposal as unknown as Json,
              expiresAt,
              requestKey: input.providerMessageId ?? null,
            })
            if (pendingId) {
              const { body, buttons } = composePendingProposal(pendingId, proposal)
              interactivePayload = { body, buttons, pendingId }
              await deps.supabase.from('product_events').insert({
                user_id: userId,
                event: 'pipeline.pending_created',
                properties: {
                  pendingId,
                  kind: 'workout',
                  workout_type: proposal.workoutType,
                  duration_min: proposal.durationMin,
                  express_reason: exprRes.reason,
                },
              })
              toolCallsSummary.push({
                name: tc.name,
                arguments: validated,
                result: { success: true, deferred_to_button: true, pendingId },
              })
              messages.push({
                role: 'tool',
                tool_call_id: tc.id,
                content: JSON.stringify({ success: true, deferred_to_button: true, pendingId }),
              })
              deterministicRegistration = true
              finalText = ''
              break
            }
          } else if (exprRes.eligible) {
            await deps.supabase.from('product_events').insert({
              user_id: userId,
              event: 'pipeline.express_used',
              properties: {
                kind: 'workout',
                workout_type: wArgs.workout_type,
                duration_min: wArgs.duration_min,
              },
            })
          }
        }
        // ── fim da interceptação de botões ────────────────────────────────────

        // FIX 4 (Roberto 2026-06-15): foto noturna perdida — LLM chamou
        // marca_refeicao_pulada DEPOIS de paciente responder disambiguação de
        // foto pendente. Gate determinístico: se há foto de meal analisada
        // pelo vision recente SEM virar registro, REJEITAR skip e forçar
        // registra_refeicao com items da foto.
        //
        // HARDENING H2 (review HIGH 2026-06-16): comparar meal_type do skip
        // com meal_context da foto / ageMinutes — se claramente diferente
        // (foto contexto 'café' + skip 'jantar', OU age > 4h e meal_type
        // diferente), PERMITIR o skip (foto é de outra refeição que o
        // paciente vai resolver depois) e só logar warning.
        const attemptedMeal = (validated as { meal_type?: string }).meal_type ?? null
        if (tc.name === 'marca_refeicao_pulada' && ctx.visionPending != null) {
          const visionContext = (ctx.visionPending.mealContext ?? '').toLowerCase()
          const isVisionAboutCafe = /caf[eé]|manh[ãa]|brunch/.test(visionContext)
          const isVisionAboutAlmoco = /almo[çc]o|lunch/.test(visionContext)
          const isVisionAboutJantar = /jantar|dinner|noite/.test(visionContext)
          const isVisionAboutLanche = /lanche|snack|tarde/.test(visionContext)
          const visionMealType = isVisionAboutCafe
            ? 'cafe'
            : isVisionAboutAlmoco
              ? 'almoco'
              : isVisionAboutJantar
                ? 'jantar'
                : isVisionAboutLanche
                  ? 'lanche'
                  : null
          const ageMinutes = ctx.visionPending.ageMinutes
          // Skip é claramente de OUTRA refeição? (a) vision identifica meal
          // E é diferente do skip; OU (b) age > 4h E o paciente menciona
          // explicitamente o meal_type no texto.
          const clearlyDifferentMeal =
            (visionMealType != null && attemptedMeal != null && visionMealType !== attemptedMeal) ||
            (ageMinutes > 240 && attemptedMeal != null && new RegExp(`\\b${attemptedMeal}\\b`, 'i').test(input.text ?? ''))
          if (clearlyDifferentMeal) {
            // Permite skip; só loga warning pra auditoria.
            await deps.supabase.from('product_events').insert({
              user_id: userId,
              event: 'pipeline.skip_allowed_different_meal',
              properties: {
                attempted_meal_type: attemptedMeal,
                vision_meal_inferred: visionMealType,
                vision_age_minutes: ageMinutes,
              },
            })
          } else {
            await deps.supabase.from('product_events').insert({
              user_id: userId,
              event: 'pipeline.skip_blocked_by_vision',
              properties: {
                attempted_meal_type: attemptedMeal,
                vision_items_count: ctx.visionPending.items.length,
                vision_age_minutes: ageMinutes,
                vision_items_preview: ctx.visionPending.items.map((i) => i.name).slice(0, 5),
              },
            })
            // HARDENING H5 (review HIGH 2026-06-16): trocar JSON.stringify do
            // payload por PROSA — Haiku tende a tratar JSON como dado opaco,
            // não como instrução acionável. Prosa direta + lista textual de
            // items funciona melhor.
            const itemsList = ctx.visionPending.items
              .map((it) => `${it.name} (~${it.quantity_g_estimate}g)`)
              .join(', ')
            const rejectionMsg =
              `SISTEMA: tentativa de marca_refeicao_pulada BLOQUEADA. ` +
              `Você tem foto pendente de registro analisada há ${ageMinutes} min ` +
              `com os items: ${itemsList}. ` +
              `Chame registra_refeicao AGORA com esses items (ajuste meal_type e ` +
              `quantidades conforme a conversa). Só chame marca_refeicao_pulada se ` +
              `o paciente disser LITERALMENTE "pulei"/"não comi"/"joguei fora" NESSA ` +
              `mensagem específica E sobre OUTRA refeição (não a da foto).`
            toolCallsSummary.push({
              name: tc.name,
              arguments: validated,
              error: 'skip_blocked_vision_pending',
            })
            messages.push({
              role: 'tool',
              tool_call_id: tc.id,
              content: rejectionMsg,
            })
            continue
          }
        }

        // ACT-3 prevention plan 2026-06-16: tool guard pós-LLM.
        // Cada tool em GUARDS valida `validated` ANTES do execute. Rejeição
        // emite `tool_rejected_by_guard` + força retry com hint dirigido.
        // Defesa determinística — não depende de prompt obedecer.
        const guardResult = await runToolGuard(tc.name, validated as Record<string, unknown>, {
          supabase: deps.supabase,
          userId,
          userTimezone: toolCtx.userTimezone,
          referenceTimestamp: toolCtx.referenceTimestamp,
          trustedTap: false,
          visionPending: ctx.visionPending,
        })
        if (!guardResult.ok) {
          toolCallsSummary.push({
            name: tc.name,
            arguments: validated,
            error: `guard:${guardResult.reason}`,
          })
          const retryHint =
            guardResult.retry_hint ??
            `SISTEMA: a tool ${tc.name} foi rejeitada pelo guard (${guardResult.reason}). Reformule e tente de novo.`
          messages.push({
            role: 'tool',
            tool_call_id: tc.id,
            content: JSON.stringify({
              error: `guard_rejected:${guardResult.reason}`,
              reason: retryHint,
            }),
          })
          continue
        }

        // Audit 06-25 Bug B Layer 1 (Roberto 25/06 salada sumida): se a
        // tool_call é registra_refeicao com items, comparar cobertura dos
        // items com vision.analyzed recentes (30min). Se overlap < 70% E há
        // ≥3 items vision detectados, emite pipeline.vision_coverage_warning
        // pra audit pegar perda silenciosa. SÓ telemetria por enquanto.
        if (tc.name === 'registra_refeicao') {
          try {
            const items = (validated as { items?: Array<{ food_name: string }> }).items
            if (Array.isArray(items) && items.length > 0) {
              await reportVisionCoverageIfLow(deps.supabase, userId, items)
            }
          } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('[pipeline] vision coverage check failed (non-fatal):', e)
          }
        }

        const toolStart = Date.now()
        const out = await tool.execute(validated, toolCtx)
        toolCallsSummary.push({ name: tc.name, arguments: validated, result: out })
        messages.push({ role: 'tool', tool_call_id: tc.id, content: JSON.stringify(out) })
        if (options.includeSensitiveTelemetry !== false) {
          await deps.supabase.from('tools_audit').insert({
            user_id: userId,
            tool_name: tc.name,
            arguments: jsonify(validated),
            result: jsonify(out),
            duration_ms: Date.now() - toolStart,
            success: true,
          })
        }
      } catch (e) {
        const err =
          e instanceof Error
            ? e.message
            : e && typeof e === 'object'
              ? JSON.stringify(e)
              : String(e)
        toolCallsSummary.push({ name: tc.name, arguments: parsed, error: err })
        messages.push({
          role: 'tool',
          tool_call_id: tc.id,
          content: JSON.stringify({ error: err }),
        })
        if (options.includeSensitiveTelemetry !== false) {
          await deps.supabase.from('tools_audit').insert({
            user_id: userId,
            tool_name: tc.name,
            arguments: jsonify(parsed ?? {}),
            result: null,
            duration_ms: 0,
            success: false,
            error: err,
          })
        }
      }
    }

    // ── FASE 1 (Roberto 2026-05-25): REGISTRO PURO → resposta montada pelo SISTEMA ──
    // Se este turno foi SÓ registra_refeicao/registra_treino (com sucesso) e o
    // paciente NÃO fez pergunta, o sistema compõe a resposta (frase fixa + tabela
    // + card canônico) e PULA a 2ª chamada do LLM — que só re-redigia (e às vezes
    // errava/variava). Coaching/conversa segue com a IA nos demais turnos.
    // Gatilho conservador: qualquer outra tool no turno, ou "?" na msg do paciente,
    // cai no fluxo normal (LLM responde). O card determinístico ainda passa pelo
    // FIX C pós-loop (idempotente) + auditorias.
    const iterEntries = toolCallsSummary.slice(-result.toolCalls.length)
    // Flow only. Every tool of the turn was a plan-suggestion tool and each
    // returned its text: the answer is that stored text between the fixed
    // opening and closing, put in place after the loop by
    // ensureSuggestionShown exactly as for a model that paraphrased. Another
    // tool, a failed or refused one, a suggestion with no text, or a guard
    // retry earlier in the turn: the model answers, as before. So it does
    // when the patient's message is more than one request, or when the model
    // wrote text next to the tool call — the second call is where the other
    // question gets its answer (ensureSuggestionShown still guarantees the
    // stored text is what the chat shows).
    if (
      MOBILE_FLOW_DIRECT_PLAN_SUGGESTION &&
      options.historyProvider === 'mobile_flow' &&
      guardRetries === 0 &&
      isPurePlanSuggestionTurn(toolCallsSummary) &&
      isSingleRequestMessage(semanticPatientText) &&
      (result.content ?? '').trim() === ''
    ) {
      planSuggestionDirect = true
      break
    }
    if (isPureRegistrationTurn(iterEntries, input.text)) {
      const todayStr = getLocalDateString(ctx.timezone)
      const { snapshot: snapDet, progress: progDet } =
        await loadDeterministicDailyState(deps.supabase, userId, todayStr)
      if (snapDet) {
        const s = snapDet
        const registrations: RegistrationEntry[] = iterEntries.map((e) => {
          if (e.name === 'registra_treino') {
            const a = (e.arguments ?? {}) as { workout_type?: string; duration_min?: number }
            const r = (e.result ?? {}) as { kcal_burned?: number; deduped?: boolean }
            return {
              tool: 'registra_treino',
              workoutType: a.workout_type ?? null,
              durationMin: a.duration_min ?? null,
              kcalBurned: r.kcal_burned ?? 0,
              alreadyLogged: r.deduped === true,
            }
          }
          const a = (e.arguments ?? {}) as { meal_type?: string | null }
          const r = (e.result ?? {}) as {
            already_logged?: boolean
            meal?: { items?: RegistrationEntry['items']; totals?: RegistrationEntry['totals'] }
          }
          return {
            tool: 'registra_refeicao',
            mealType: a.meal_type ?? null,
            items: r.meal?.items ?? [],
            totals: r.meal?.totals,
            alreadyLogged: r.already_logged === true,
          }
        })
        finalText = composePostRegistrationMessage({
          registrations,
          card: {
            caloriesConsumed: s.calories_consumed,
            caloriesTarget: s.calories_target,
            proteinG: Number(s.protein_g),
            proteinTarget: s.protein_target,
            exerciseCalories: s.exercise_calories,
            deficitBlock: progDet.deficit_block,
            protocol:
              (ctx.profile.currentProtocol as
                | 'recomposicao'
                | 'ganho_massa'
                | 'manutencao'
                | null) ?? null,
            last14d: ctx.last14d,
          },
        })

        // Roberto 2026-06-01: a Fase 1 (determinístico) tirou o comentário
        // educativo de 2-4 frases que o LLM redigia pós-registro — Roberto
        // sentiu falta. Solução: 1 chamada Haiku PEQUENA só pro comentário,
        // sem refazer tabela/card (continuam determinísticos). Se falhar/
        // timeout, registro segue sem comentário (degradação graciosa).
        const protocol =
          (ctx.profile.currentProtocol as 'recomposicao' | 'ganho_massa' | 'manutencao' | null) ??
          null
        const eduComment = await generateEducationalComment(
          deps.llm,
          {
            kind: registrations[0]?.tool === 'registra_treino'
              ? 'treino'
              : (registrations[0]?.mealType as EduCommentInput['kind']) ?? 'outro',
            // Adapter (P0 audit 2026-06-13): a tool registra_refeicao retorna
            // items com chave `name` (tools.ts:1359), EduCommentInput espera
            // `food_name`. adaptToolItemsToEduInput é função pura testável —
            // ver tool-items-adapter.test.ts pra cobertura do shape real.
            items: adaptToolItemsToEduInput(
              registrations[0]?.items as Parameters<typeof adaptToolItemsToEduInput>[0],
            ),
            totals: registrations[0]?.totals,
            workout:
              registrations[0]?.tool === 'registra_treino'
                ? {
                    type: registrations[0]?.workoutType ?? 'treino',
                    durationMin: registrations[0]?.durationMin,
                    kcalBurned: registrations[0]?.kcalBurned ?? 0,
                  }
                : undefined,
            protocol,
            locale: ctx.locale,
          },
          {
            // ATIVA curated-phrase path (review CRITICAL: sem isso fica
            // dead code e Haiku é sempre chamado).
            supabase: deps.supabase,
            userId,
            state: { protocol },
            // Cascade semântica: resolve foods compostos (aveia em flocos,
            // iogurte zero açúcar) via embedding similarity.
            embeddings: deps.embeddings,
          },
        )
        // embedEduComment é função pura testável (invariante: eduComment
        // não-vazio ⇒ marker presente). Antes era código inline aqui e
        // duplicado em interactive-handler.ts — 52% dos registros saíam
        // sem comentário em prod e não havia teste do invariante.
        finalText = embedEduComment(finalText, eduComment)

        messages.push({ role: 'assistant', content: finalText })
        deterministicRegistration = true
        await deps.supabase.from('product_events').insert({
          user_id: userId,
          event: 'pipeline.deterministic_registration',
          properties: { stage, tools: iterEntries.map((e) => e.name) },
        })
        break
      }
    } else if (isPureStatusQueryTurn(iterEntries, input.text)) {
      // ── #1 STATUS PURO (Roberto 2026-05-27): "como tô / quanto falta / meu
      // bloco" → o sistema responde com o card canônico + linha de progresso,
      // SEM a 2ª chamada do LLM. Mesma fonte de números do registro/FIX C.
      // Gatilho conservador (só consulta_progresso + intenção de status pura);
      // qualquer coaching junto cai no fluxo normal (LLM responde).
      const todayStr = getLocalDateString(ctx.timezone)
      const { snapshot: snapDet, progress: progDet } =
        await loadDeterministicDailyState(deps.supabase, userId, todayStr)
      if (snapDet) {
        const s = snapDet
        const p = progDet
        finalText = composeStatusMessage(
          {
            caloriesConsumed: s.calories_consumed,
            caloriesTarget: s.calories_target,
            proteinG: Number(s.protein_g),
            proteinTarget: s.protein_target,
            exerciseCalories: s.exercise_calories,
            deficitBlock: p.deficit_block,
            protocol:
              (ctx.profile.currentProtocol as
                | 'recomposicao'
                | 'ganho_massa'
                | 'manutencao'
                | null) ?? null,
            last14d: ctx.last14d,
          },
          {
            currentStreak: p.current_streak,
            level: p.level,
            xpTotal: p.xp_total,
            blocksCompleted: p.blocks_completed,
          },
        )
        messages.push({ role: 'assistant', content: finalText })
        deterministicRegistration = true // reusa o flag de single-message (card não fragmenta)
        // Flow: same card, same passes below; only the text handed to the
        // app is rendered plain, at the very end.
        flowPlainStatus = MOBILE_FLOW_PLAIN_STATUS && options.historyProvider === 'mobile_flow'
        await deps.supabase.from('product_events').insert({
          user_id: userId,
          event: 'pipeline.deterministic_status',
          properties: { stage, tools: iterEntries.map((e) => e.name) },
        })
        break
      }
    } else if (isReevalToolTurn(iterEntries, input.text) && stage !== 'coleta_dados') {
      // ── #2 RESULTADO DE REAVALIAÇÃO (Roberto 2026-05-27): paciente respondeu
      // peso/fome → sistema confirma a NOVA meta de forma determinística (números
      // que valem os próximos 14 dias), sem a IA re-redigir. Gatilho ESTREITO:
      // exige reevaluation.due recente (últimas 48h) — nunca dispara no onboarding
      // nem em update casual. Se não for reavaliação real → fluxo normal (LLM).
      const reevaluationGate = await loadReevaluationGate(deps.supabase, userId)
      if (reevaluationGate.due) {
        const bodyPhotoState = ctx.bodyPhotoState ?? deriveBodyPhotoState([], [input.text])
        if (shouldWaitForBodyPhotosBeforeReeval(bodyPhotoState, true)) {
          finalText = composeReevalBodyPhotoWaitMessage(bodyPhotoState)
          messages.push({ role: 'assistant', content: finalText })
          deterministicRegistration = true
          await deps.supabase.from('product_events').insert({
            user_id: userId,
            event: 'pipeline.reeval_waiting_body_photos',
            properties: {
              stage,
              tools: iterEntries.map((e) => e.name),
              received_views: bodyPhotoState.receivedViews,
              missing_views: bodyPhotoState.missingViews,
              unknown_count: bodyPhotoState.unknownCount,
            },
          })
          break
        }
        const cadastra = iterEntries.find((e) => e.name === 'cadastra_dados_iniciais')
        const cr = (cadastra?.result ?? {}) as {
          calories_target_today?: number | null
          protein_target_today_g?: number | null
        }
        finalText = composeReevalResultMessage({
          caloriesTarget: cr.calories_target_today ?? null,
          proteinTarget: cr.protein_target_today_g ?? null,
          protocol:
            reevaluationGate.currentProtocol ??
            ctx.profile.currentProtocol ??
            null,
        })
        messages.push({ role: 'assistant', content: finalText })
        deterministicRegistration = true // reusa o flag de single-message
        await deps.supabase.from('product_events').insert({
          user_id: userId,
          event: 'pipeline.deterministic_reeval',
          properties: { stage, tools: iterEntries.map((e) => e.name) },
        })
        break
      }
    }

    // Flow only: this tool call used the last iteration the turn had. With
    // no suggestion stored for ensureSuggestionShown to show, the turn would
    // end with no words; with one stored and a message that is more than a
    // single request, it would end on the suggestion and drop the other
    // question. One more iteration is granted, once, and it is made with the
    // tools switched off (MOBILE_FLOW_CLOSING_CALL). Its text goes through
    // the same guards as any answer of the model. A single request with its
    // suggestion stored needs no words from the model and gets no call.
    if (
      MOBILE_FLOW_CLOSING_CALL &&
      options.historyProvider === 'mobile_flow' &&
      flowClosingIteration === null &&
      iter + 1 >= max + guardRetries &&
      (turnSuggestions(toolCallsSummary).length === 0 ||
        !isSingleRequestMessage(semanticPatientText))
    ) {
      flowClosingIteration = iter + 1
    }
  }

  if (!lastResult) throw new Error('No completion produced')

  // NOTA: a persistência da OUT é responsabilidade do CHAMADOR (process-message
  // ou engagement-sender), que envia via WhatsApp e persiste com delivery_status
  // REAL (sent / failed). Antes esse insert acontecia aqui sem delivery_status,
  // resultando em rastreio quebrado (msg parecia entregue mesmo quando falhava).
  //
  // O caller deve fazer:
  //   1. await sendHumanized(...)   → captura status
  //   2. await supabase.from('messages').insert({ ..., delivery_status })

  await deps.supabase
    .from('users')
    .update({ updated_at: new Date().toISOString() })
    .eq('id', userId)

  // FIX C (Roberto 2026-05-18, ampliado 19/05): SEMPRE que LLM monta card de
  // balanço, sistema SUBSTITUI pelo card pré-renderizado com dados frescos do
  // banco. Antes só rodava pós-registra_refeicao/registra_treino; agora roda
  // pra qualquer turno onde LLM toca o card (incluindo consulta_progresso,
  // engagement, resposta a "como tá meu progresso?"). Resolve as 11 alucinações
  // de Bloco 7700 que vimos em 7 dias (Roberto 5, Amanda 2, Erika 1, Paulo 2,
  // Luciana 1) — incluindo casos em texto livre sem chamada de tool de registro.
  // Consumo FRESCO (pós-registro deste turno). Usado nos detectores de sentiment
  // e numeric pra evitar falso-positivo do snapshot do INÍCIO do turno (Roberto
  // 2026-05-22: detector acusava "excedente vs déficit" quando o paciente tinha
  // registrado a refeição no próprio turno — a prosa batia com o card, o stale não).
  let freshConsumed: number | null = ctx.todaySnapshot?.calories_consumed ?? null
  if (finalText && hasBalanceCard(finalText)) {
    const todayStr = getLocalDateString(ctx.timezone, input.timestamp)
    const { snapshot: snapFresh, progress: progFresh } =
      await loadDeterministicDailyState(deps.supabase, userId, todayStr)
    if (snapFresh) {
      const snapTyped = snapFresh
      freshConsumed = snapTyped.calories_consumed
      const canonicalCard = renderBalanceCard({
        caloriesConsumed: snapTyped.calories_consumed,
        caloriesTarget: snapTyped.calories_target,
        proteinG: Number(snapTyped.protein_g),
        proteinTarget: snapTyped.protein_target,
        exerciseCalories: snapTyped.exercise_calories,
        deficitBlock: progFresh.deficit_block,
        protocol:
          (ctx.profile.currentProtocol as
            | 'recomposicao'
            | 'ganho_massa'
            | 'manutencao'
            | null) ?? null,
        last14d: ctx.last14d,
      })
      const before = finalText
      finalText = injectCanonicalCard(finalText, canonicalCard)
      if (before !== finalText) {
        const triggerTool = toolCallsSummary.find(
          (tc) =>
            (tc.name === 'registra_refeicao' ||
              tc.name === 'registra_treino' ||
              tc.name === 'consulta_progresso') &&
            !tc.error,
        )
        await deps.supabase.from('product_events').insert({
          user_id: userId,
          event: 'llm.card_replaced',
          properties: { stage, tool: triggerTool?.name ?? 'none' },
        })
      }
      // FIX #2 (Paulo 2026-05-20 17:13): a PROSA fora do card ainda alucinava
      // "Excedente leve de 130 kcal" contradizendo o card canônico. Reconcilia
      // rótulo+magnitude pela MESMA base do card: balanço de COMIDA = consumido
      // − meta (SEM exercício — regra MPP, Roberto 2026-05-21). O exercício vai
      // pro bloco, não pro "Restam". detectSentimentMismatch abaixo usa a mesma
      // base. (Antes usava consumido−meta−exercício, inflava o restante.)
      if (snapTyped.calories_target != null) {
        const eb = eatingBalance(snapTyped.calories_consumed, snapTyped.calories_target)
        // Flow only: the context also gives the model the protocol's day
        // balance (§2c), a second true number whose sign can differ from the
        // food balance. A claim quoting it is not rewritten into "restam".
        // WhatsApp passes nothing: its reconciliation is unchanged.
        const flowDay =
          options.historyProvider === 'mobile_flow'
            ? dayEnergyBalance({
                ...flowDayBalanceInputs(ctx.profile, calcConfig, ctx.flowDayRow),
                caloriesConsumed: snapTyped.calories_consumed,
                caloriesTarget: snapTyped.calories_target,
                exerciseCalories: snapTyped.exercise_calories,
              })
            : null
        const proseFix = reconcileBalanceProse(
          finalText,
          eb,
          flowDay?.basis === 'expenditure' ? { dayBalance: flowDay.balance } : {},
        )
        if (proseFix.replacements > 0) {
          finalText = proseFix.text
          if (options.includeSensitiveTelemetry !== false) {
            await deps.supabase.from('product_events').insert({
              user_id: userId,
              event: 'llm.balance_prose_reconciled',
              properties: { stage, replacements: proseFix.replacements, eating_balance: eb },
            })
          }
        }

        // Detector do erro de "déficit real" (Roberto 2026-05-21): o LLM faz
        // exercício − excedente e esquece o déficit já embutido na meta. O
        // "déficit real do dia" = crédito do bloco = designDeficit − netBalance.
        // Log-only por enquanto (medir antes de reescrever automático).
        const designDeficit =
          ctx.profile.currentProtocol === 'recomposicao' ? (ctx.profile.deficitLevel ?? 500) : 0
        const netBalance =
          snapTyped.calories_consumed - snapTyped.calories_target - snapTyped.exercise_calories
        const drMismatch = detectDeficitRealMismatch(finalText, {
          designDeficit,
          dailyBalance: netBalance,
        })
        if (drMismatch && options.includeSensitiveTelemetry !== false) {
          await deps.supabase.from('product_events').insert({
            user_id: userId,
            event: 'llm.deficit_real_mismatch',
            properties: {
              stage,
              claimed: drMismatch.claimed,
              correct: drMismatch.correct,
              excerpt: drMismatch.excerpt,
            },
          })
        }
      }
    }
  }

  // FIX residual (2026-05-19): menções SOLTAS de Bloco 7700 fora do card
  // (ex: LLM escreve "você está em 3.000 do bloco" no comentário motivacional)
  // não eram cobertas pelo injectCanonicalCard. Esta varredura adicional
  // substitui ocorrências soltas pelo valor real do user_progress.deficit_block.
  if (finalText && ctx.userProgress?.deficit_block != null) {
    const looseReplace = replaceLooseBlockMentions(finalText, ctx.userProgress.deficit_block)
    if (looseReplace.replacements > 0) {
      finalText = looseReplace.text
      await deps.supabase.from('product_events').insert({
        user_id: userId,
        event: 'llm.loose_bloco_replaced',
        properties: { stage, replacements: looseReplace.replacements },
      })
    }
  }

  // SUGESTÃO DE PLANO (Flow do app, audit 2026-09-30): o chat mostra o
  // rascunho gravado, nunca um resumo genérico nem um plano parafraseado. Se o
  // modelo não reproduziu o texto da ferramenta (ou não respondeu nada), a
  // resposta vira esse texto.
  {
    const shown = ensureSuggestionShown(finalText, toolCallsSummary)
    if (shown.replaced) {
      // The event reports a model that did not reproduce the suggestion. On
      // a direct turn, on a turn the deadline ended and on one whose closing
      // call failed, the model was not asked to (or was cut while it did, or
      // never answered): llm.flow_calls says so.
      if (
        !planSuggestionDirect &&
        !flowSuggestionAtDeadline &&
        !flowSuggestionAfterFailedClosing
      ) {
        await deps.supabase.from('product_events').insert({
          user_id: userId,
          event: 'llm.plan_suggestion_rewritten',
          properties: { stage, model_reply_empty: finalText.trim().length === 0 },
        })
      }
      finalText = shown.text
    }
  }

  // GUARD DE ESCRITA FANTASMA — Camadas 2 e 3 (rede de finalização).
  // Checa o TEXTO REAL enviado ao paciente (pós-FIX C). Não bloqueia: registra
  // sinais de alta prioridade pra auditoria 5×/dia investigar/agir.
  {
    const registrationToolCalled = toolCallsSummary.some(
      (tc) => (tc.name === 'registra_refeicao' || tc.name === 'registra_treino') && !tc.error,
    )
    // Camada 2: o retry da Camada 1 falhou (LLM insistiu em não chamar a tool)
    // ou o card veio por caminho não-terminal → o texto final ainda afirma
    // registro/correção sem tool = escrita NÃO persistiu. Sinal crítico.
    const prescriptionToolCalled = toolCallsSummary.some(
      (tc) => PRESCRIPTION_TOOLS.has(tc.name) && !tc.error,
    )
    const skipToolCalled = toolCallsSummary.some(
      (tc) => tc.name === 'marca_refeicao_pulada' && !tc.error,
    )
    const mealTypeHint = inferMealTypeHint(ctx)
    const fakeFinal = detectFakeWrite({
      content: finalText,
      patientText: semanticPatientText,
      registrationToolCalled: registrationToolCalled || draftCreatedThisTurn(toolCallsSummary),
      prescriptionToolCalled,
      skipToolCalled,
      goalToolCalled: goalToolRanThisTurn(toolCallsSummary),
      patientTurnText: patientTurnTextOf(input, semanticPatientText),
      mealTypeHint,
    })
    if (fakeFinal.isFake) {
      await deps.supabase.from('product_events').insert({
        user_id: userId,
        event: fakeFinal.kind === 'skip' ? 'llm.fake_skip_unresolved' : 'llm.fake_write_unresolved',
        properties: {
          stage,
          kind: fakeFinal.kind,
          model: lastResult.model,
          ...(options.includeSensitiveTelemetry === false
            ? {}
            : { content_preview: finalText.slice(0, 120) }),
          inferred_meal_type: fakeFinal.inferredMealType ?? null,
        },
      })
    }
    // Camada 3 (lado da ENTRADA): o paciente pediu correção, o agente mostrou
    // card, mas nenhuma tool de registro rodou no turno. Cruza intenção do
    // paciente × ação do agente. Log-only (evita falso-positivo afetar paciente);
    // a auditoria usa pra pegar correção silenciosamente não-persistida.
    const patientMsgs = semanticPatientText.trim() ? [semanticPatientText] : []
    const correctionWord = detectCorrectionIntent(patientMsgs)
    if (correctionWord && !registrationToolCalled && hasBalanceCard(finalText)) {
      await deps.supabase.from('product_events').insert({
        user_id: userId,
        event: 'llm.correction_intent_no_write',
        properties: {
          stage,
          keyword: correctionWord,
          ...(options.includeSensitiveTelemetry === false
            ? {}
            : { content_preview: finalText.slice(0, 120) }),
        },
      })
    }
  }

  // Audit anti-alucinação: parseia números na resposta e compara com contexto.
  // Não bloqueia — só loga em product_events pra investigação posterior.
  const m = computeMetrics(ctx.profile, input.timestamp, calcConfig)
  if (options.includeSensitiveTelemetry !== false) {
    await auditNumericClaims(
      deps.supabase,
      userId,
      finalText,
      {
        calories_target: ctx.dailyTargets.calories_target,
        protein_target: ctx.dailyTargets.protein_target,
        imc: m.imc,
        bmr: m.bmr,
        tdee: m.bmr != null && m.activityFactor != null ? m.bmr * m.activityFactor : null,
        age: m.age,
        current_streak: ctx.userProgress?.current_streak ?? null,
        level: ctx.userProgress?.level ?? null,
        calories_consumed_today: freshConsumed,
        deficit_block: ctx.userProgress?.deficit_block ?? null,
      },
      { stage, model: lastResult.model },
    )
  }

  // FIX B (Roberto 2026-05-18): sanity semântico — texto diz "déficit" mas
  // balance é positivo (ou vice-versa). Loga 'llm.sentiment_mismatch'. Não
  // bloqueia — paciente já viu o card REAL agora (fix C acima).
  // Usa o balanço de COMIDA (consumido − meta, SEM exercício) — mesma base do
  // card "Restam/Excedente" (regra MPP, Roberto 2026-05-21). Antes usava
  // daily_balance (com exercício), o que divergia do card e gerava falso
  // positivo em dias com exercício abaixo da meta.
  const eatingBalanceForSentiment =
    freshConsumed != null && ctx.dailyTargets.calories_target != null
      ? eatingBalance(freshConsumed, ctx.dailyTargets.calories_target)
      : null
  if (eatingBalanceForSentiment != null) {
    const sentimentMismatch = detectSentimentMismatch(finalText, eatingBalanceForSentiment)
    if (sentimentMismatch && options.includeSensitiveTelemetry !== false) {
      await deps.supabase.from('product_events').insert({
        user_id: userId,
        event: 'llm.sentiment_mismatch',
        properties: {
          stage,
          model: lastResult.model,
          text_says: sentimentMismatch.text_says,
          balance_is: sentimentMismatch.balance_is,
          eating_balance: sentimentMismatch.daily_balance,
          excerpt: sentimentMismatch.excerpt,
        },
      })
    }
  }

  // Métrica de prompt caching (Anthropic): loga evento se houve hit, pra
  // observabilidade da economia. Sem hit (1ª chamada do paciente nos últimos
  // 5min OU modelo não-Anthropic), não loga — evita ruído.
  // Flow only: the per-call numbers go next to it. The write starts here and
  // is awaited after the cache event, so both travel together and the turn
  // gains no extra sequential round trip.
  // From here the turn writes its own numbers: the failure path must not
  // write them a second time.
  if (options.flowFailure) options.flowFailure.record = null
  const flowCallsWritten = flowCalls
    ? recordFlowCalls(
        deps.supabase,
        userId,
        stage,
        JSON.stringify(tools).length,
        flowCalls,
        flowToolLlmCalls,
        { planSuggestionDirect, suggestionAtDeadline: flowSuggestionAtDeadline },
      )
    : null
  if (totalCacheRead > 0 || totalCacheCreate > 0) {
    const hitRate = totalCacheRead / Math.max(totalPromptTokens, 1)
    await deps.supabase.from('product_events').insert({
      user_id: userId,
      event: 'llm.cache_usage',
      properties: {
        model: lastResult.model,
        stage,
        prompt_tokens: totalPromptTokens,
        cache_read_tokens: totalCacheRead,
        cache_creation_tokens: totalCacheCreate,
        hit_rate: +hitRate.toFixed(3),
      },
    })
  }
  if (flowCallsWritten) await flowCallsWritten

  // Flow only: the plan generators' calls belong to the turn's tokens and
  // cost. WhatsApp never fills the list, so its totals are the loop's.
  const toolLlmCost = flowToolLlmCalls.reduce<number | null>(
    (sum, call) => (call.cost_usd == null ? sum : (sum ?? 0) + call.cost_usd),
    null,
  )

  return {
    text: flowPlainStatus ? flowPlainStatusText(finalText) : finalText,
    // Roberto pediu (2026-05-15): NÃO ecoar áudio de volta automaticamente quando
    // paciente manda áudio. Resposta sempre em texto. Áudio do agente só é usado
    // pelo cron de engajamento (random 25%) — não como espelho da entrada.
    preferAudio: false,
    // Card determinístico vai em 1 mensagem (não pode ser quebrado pelo humanizer).
    singleMessage: deterministicRegistration,
    // Fase B botões #4: se houver proposta pendente, o caller envia
    // sendInteractive em vez de sendHumanized.
    ...(interactivePayload ? { interactive: interactivePayload } : {}),
    toolCalls: toolCallsSummary,
    stage,
    modelUsed: lastResult.model,
    promptTokens:
      totalPromptTokens + flowToolLlmCalls.reduce((sum, call) => sum + call.prompt_tokens, 0),
    completionTokens:
      totalCompletionTokens +
      flowToolLlmCalls.reduce((sum, call) => sum + call.completion_tokens, 0),
    costUsd: toolLlmCost == null ? totalCost : (totalCost ?? 0) + toolLlmCost,
    latencyMs: Date.now() - start,
  }
}

// ----------------------------------------------------------------------------
// Helpers
// ----------------------------------------------------------------------------

/** Garante que o valor é JSON-safe (sem Date, undefined, function, etc). */
function jsonify(value: unknown): import('@mpp/db').Json {
  return JSON.parse(JSON.stringify(value)) as import('@mpp/db').Json
}

/**
 * Verifica se o user tem subscription ativa ou trial.
 * Permite acesso sempre que:
 *   - Modo dev (NODE_ENV !== 'production')
 *   - Sem registro de subscription (greenfield, primeiro acesso) — passa
 *   - status = 'active' ou 'trial'
 *
 * Bloqueia se status = 'past_due', 'canceled', 'expired'.
 */
export async function checkSubscription(
  supabase: ServiceClient,
  userId: string,
): Promise<{ canAccess: boolean; reason?: string; status?: string }> {
  // Em dev/staging, libera tudo
  if (process.env.NODE_ENV !== 'production') {
    return { canAccess: true }
  }

  // Bypass via flag
  if (process.env.SUBSCRIPTION_GATE === 'off') {
    return { canAccess: true }
  }

  const { data: sub, error: subscriptionError } = await supabase
    .from('subscriptions')
    .select('status, current_period_end, trial_ends_at')
    .eq('user_id', userId)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle()
  throwIfQueryFailed(subscriptionError, 'subscription lookup failed')

  if (!sub) {
    // Sem registro — primeiro acesso. Permite (worker cria trial depois).
    return { canAccess: true, status: 'no_subscription' }
  }

  if (sub.status === 'active' || sub.status === 'trial') {
    return { canAccess: true, status: sub.status }
  }

  return {
    canAccess: false,
    status: sub.status,
    reason: `subscription ${sub.status}`,
  }
}

function buildBlockedResponse(_input: AgentInput, reason: string): AgentOutput {
  return {
    text: `Sua assinatura precisa ser renovada para continuar usando o coach. Acesse seu painel ou fale com a equipe. (motivo: ${reason})`,
    // Roberto pediu (2026-05-15): NÃO ecoar áudio de volta automaticamente quando
    // paciente manda áudio. Resposta sempre em texto. Áudio do agente só é usado
    // pelo cron de engajamento (random 25%) — não como espelho da entrada.
    preferAudio: false,
    toolCalls: [],
    stage: 'manutencao',
    modelUsed: 'none',
    promptTokens: 0,
    completionTokens: 0,
    costUsd: 0,
    latencyMs: 0,
  }
}

export async function ensureUser(supabase: ServiceClient, wpp: string): Promise<string> {
  const { data, error } = await (
    supabase as unknown as {
      rpc: (
        name: string,
        params: Record<string, unknown>,
      ) => Promise<{ data: unknown; error: { message?: string } | null }>
    }
  ).rpc('ensure_user_initialized', { p_wpp: wpp })

  if (error) {
    throw new Error(error.message ?? 'ensure_user_initialized failed')
  }
  if (typeof data !== 'string' || data.length === 0) {
    throw new Error('ensure_user_initialized returned no user id')
  }
  return data
}

const RECENT_MESSAGES_LIMIT = 50
const REENTRY_THRESHOLD_HOURS = 24 * 7 // 7 dias

type RecentMessageRow = {
  direction: string | null
  content: string | null
  content_type?: string | null
  provider_message_id?: string | null
  created_at?: string | null
}

/** Local day of the current turn, used to date older history rows. */
export type PromptHistoryDay = { timeZone: string; today: string }

/**
 * The local day (YYYY-MM-DD) of a history row when it is BEFORE the turn's
 * day; null for a row of today, of a later day (a concurrent turn across
 * midnight) or with no usable timestamp. YYYY-MM-DD compares in date order.
 */
function previousLocalDay(
  createdAt: string | null | undefined,
  day: PromptHistoryDay,
): string | null {
  if (!createdAt) return null
  const when = new Date(createdAt)
  if (Number.isNaN(when.getTime())) return null
  const rowDay = getLocalDateString(day.timeZone, when)
  return rowDay >= day.today ? null : rowDay
}

// A history row from another local day carries its date, so "hoje" and the
// hour said on that day are not read as today's (audit 2026-09-28, Flow).
function datedHistoryContent(content: string, createdAt: string | null | undefined, day: PromptHistoryDay): string {
  const rowDay = previousLocalDay(createdAt, day)
  if (rowDay === null) return content
  const [year, month, dayOfMonth] = rowDay.split('-')
  return `[Mensagem de ${dayOfMonth}/${month}/${year}, dia anterior — números do dia e horário citados nela não valem para hoje]\n${content}`
}

function normalizeCurrentProviderMessageIds(
  currentProviderMessageIds: string | string[] | null | undefined,
): Set<string> {
  const ids = Array.isArray(currentProviderMessageIds)
    ? currentProviderMessageIds
    : currentProviderMessageIds
      ? [currentProviderMessageIds]
      : []
  return new Set(ids.filter(Boolean))
}

function isRawInteractiveTap(m: RecentMessageRow): boolean {
  if (m.direction !== 'in' || m.content_type !== 'interactive' || !m.content) return false
  return /^(confirm|edit)_[0-9a-f-]{36}$/i.test(m.content.trim())
}

/** The rows that become history lines, oldest first (the current turn excluded). */
function promptHistoryRows(
  rows: RecentMessageRow[],
  currentProviderMessageIds: string | string[] | null | undefined,
): RecentMessageRow[] {
  const currentIds = normalizeCurrentProviderMessageIds(currentProviderMessageIds)
  return rows
    .slice()
    .reverse()
    .filter((m) => m.content)
    .filter((m) => !isRawInteractiveTap(m))
    .filter(
      (m) => !m.provider_message_id || !currentIds.has(m.provider_message_id),
    )
}

export function buildPromptRecentMessages(
  rows: RecentMessageRow[],
  currentProviderMessageIds: string | string[] | null | undefined,
  historyDay?: PromptHistoryDay,
): Array<{ role: 'user' | 'assistant'; content: string }> {
  return promptHistoryRows(rows, currentProviderMessageIds).map((m) => ({
    role: m.direction === 'in' ? ('user' as const) : ('assistant' as const),
    content: historyDay
      ? datedHistoryContent(m.content as string, m.created_at, historyDay)
      : (m.content as string),
  }))
}

/**
 * Flow only. For each line buildPromptRecentMessages returns (same rows, same
 * order): whether it is OUTSIDE the patient's current session — the only
 * lines the Flow's history window may cut. A line is inside the session when
 * it is of the turn's local day, or was said in the MOBILE_FLOW_SESSION_HOURS
 * before `turnAt` (a conversation that crosses local midnight is one
 * session). The date prefix is not decided here: every line of a previous
 * calendar day keeps it, inside the session or not.
 */
export function promptHistoryOutsideSessionLines(
  rows: RecentMessageRow[],
  currentProviderMessageIds: string | string[] | null | undefined,
  historyDay: PromptHistoryDay,
  turnAt: Date,
): boolean[] {
  const sessionStart = turnAt.getTime() - MOBILE_FLOW_SESSION_HOURS * 3_600_000
  return promptHistoryRows(rows, currentProviderMessageIds).map((m) => {
    if (previousLocalDay(m.created_at, historyDay) === null) return false
    // previousLocalDay returned a day, so created_at is a valid timestamp.
    return new Date(m.created_at as string).getTime() < sessionStart
  })
}

export async function loadContext(
  supabase: ServiceClient,
  userId: string,
  currentProviderMessageIds?: string | string[] | null,
  currentText?: string | null,
  referenceTimestamp: Date = new Date(),
  historyProvider?: string,
): Promise<UserContext> {
  // Cast pra unknown porque tipos auto-gen ainda não conhecem as colunas
  // novas (summary, last_active_at) — adicionadas na migration 0016.
  const { data: user, error: userError } = await (supabase as unknown as {
    from: (t: string) => {
      select: (s: string) => {
        eq: (col: string, val: string) => {
          single: () => Promise<{ data: unknown; error: unknown }>
        }
      }
    }
  })
    .from('users')
    .select(
      'id, name, summary, last_active_at, country, country_confirmed, country_detected_from_wpp, locale, metadata, timezone',
    )
    .eq('id', userId)
    .single()
  throwIfQueryFailed(userError, 'user context lookup failed')
  if (!user) throw new Error('user context missing')

  const { data: profile, error: profileError } = await supabase
    .from('user_profiles')
    .select('*')
    .eq('user_id', userId)
    .single()
  throwIfQueryFailed(profileError, 'user profile lookup failed')
  if (!profile) throw new Error('user profile missing')

  const messagesQuery = supabase
    .from('messages')
    .select('direction, content, content_type, created_at, provider_message_id')
    .eq('user_id', userId)
  const { data: msgs, error: messagesError } = historyProvider
    ? await messagesQuery
        .eq('provider', historyProvider)
        .order('created_at', { ascending: false })
        .limit(RECENT_MESSAGES_LIMIT)
    : await messagesQuery
        .order('created_at', { ascending: false })
        .limit(RECENT_MESSAGES_LIMIT)
  throwIfQueryFailed(messagesError, 'recent messages lookup failed')

  // .slice() ANTES do .reverse() — reverse() muta in-place. Sem o slice, a
  // ordem do `msgs` original fica ASC, e o `lastInboundContentType` (linha
  // ~1412) abaixo passa a pegar a inbound MAIS ANTIGA da janela em vez da
  // mais recente — bug Paulo+Roberto 2026-05-30 (sourceContentType invertido:
  // text→image e image→text).
  // Only the app's Flow channel dates older rows; WhatsApp history is unchanged.
  const historyTimeZone = (user as { timezone?: string | null }).timezone ?? 'America/Sao_Paulo'
  const flowHistoryDay: PromptHistoryDay | undefined =
    historyProvider === 'mobile_flow'
      ? { timeZone: historyTimeZone, today: getLocalDateString(historyTimeZone, referenceTimestamp) }
      : undefined
  const recentMessages = buildPromptRecentMessages(
    (msgs ?? []) as RecentMessageRow[],
    currentProviderMessageIds,
    flowHistoryDay,
  )
  // Flow only: which of those lines are outside the current session (see
  // mobileFlowPromptHistory). Absent on the legacy channels.
  const flowOutsideSessionLines = flowHistoryDay
    ? promptHistoryOutsideSessionLines(
        (msgs ?? []) as RecentMessageRow[],
        currentProviderMessageIds,
        flowHistoryDay,
        referenceTimestamp,
      )
    : undefined

  const userTyped = user as
    | {
        id: string
        name: string | null
        summary: string | null
        last_active_at: string | null
        country: string | null
        country_confirmed: boolean | null
        country_detected_from_wpp: string | null
        locale: string | null
        metadata: Record<string, unknown> | null
        timezone: string | null
      }
    | null
  // Calcula gap de tempo desde última msg IN (penúltima, pq a atual já entrou)
  let hoursSinceLastIn: number | null = null
  if (userTyped?.last_active_at) {
    // last_active_at já foi atualizado pela trigger com a msg ATUAL.
    // Gap = penúltima IN.
    const inMsgs = (msgs ?? [])
      .filter((m) => m.direction === 'in' && m.created_at)
      .sort((a, b) => (b.created_at as string).localeCompare(a.created_at as string))
    if (inMsgs.length >= 2) {
      const prevIn = new Date(inMsgs[1]!.created_at as string).getTime()
      const currentIn = new Date(inMsgs[0]!.created_at as string).getTime()
      hoursSinceLastIn = (currentIn - prevIn) / 3600_000
    }
  }
  const isReentry = hoursSinceLastIn != null && hoursSinceLastIn > REENTRY_THRESHOLD_HOURS

  const profileTyped: UserProfile = {
    sex: profile?.sex ?? null,
    birthDate: profile?.birth_date ? new Date(profile.birth_date) : null,
    heightCm: profile?.height_cm != null ? Number(profile.height_cm) : null,
    weightKg: profile?.weight_kg != null ? Number(profile.weight_kg) : null,
    bodyFatPercent: profile?.body_fat_percent != null ? Number(profile.body_fat_percent) : null,
    activityLevel: profile?.activity_level ?? null,
    trainingFrequency: profile?.training_frequency ?? null,
    waterIntake: profile?.water_intake ?? null,
    hungerLevel: profile?.hunger_level ?? null,
    currentProtocol: profile?.current_protocol ?? null,
    goalType: profile?.goal_type ?? null,
    goalValue: profile?.goal_value != null ? Number(profile.goal_value) : null,
    deficitLevel: (profile?.deficit_level as 400 | 500 | 600 | null) ?? null,
    // Campos novos pra critérios de Ganho de Massa (sono ≥6h30 + alimentação).
    bedTime: (profile as { bedtime?: string | null } | null)?.bedtime ?? null,
    wakeTime: profile?.wake_time ?? null,
    foodOrganization:
      ((profile as { food_organization?: 'sim' | 'nao' | null } | null)?.food_organization ??
        null) as 'sim' | 'nao' | null,
  }

  const unitSystemRaw = userTyped?.metadata?.unit_system
  const unitSystem: 'metric' | 'imperial' | null =
    unitSystemRaw === 'metric' || unitSystemRaw === 'imperial' ? unitSystemRaw : null

  // ANTI-ALUCINAÇÃO: carrega metas determinísticas + snapshot do dia + progress.
  // Sem isso o LLM inventa kcal/proteína/streak/balance.
  const calcCfg = await loadCalcConfig(supabase)
  const dailyTargets = await loadDailyTargets(supabase, userId, calcCfg)
  // Data LOCAL do paciente (não UTC). Sem isso, paciente em America/New_York
  // entre 20h-24h local pegava o snapshot do dia seguinte (UTC já rolou).
  const userTz = userTyped?.timezone ?? 'America/Sao_Paulo'
  const today = getLocalDateString(userTz, referenceTimestamp)
  const snapshotColumns =
    'calories_consumed, protein_g, carbs_g, fat_g, exercise_calories, daily_balance, deficit_accumulated, day_status, gap_reminder_sent_at'
  const { data: snapToday, error: snapshotError } = await supabase
    .from('daily_snapshots')
    .select(
      historyProvider === 'mobile_flow'
        ? `${snapshotColumns}, calories_target, protein_target, current_protocol`
        : snapshotColumns,
    )
    .eq('user_id', userId)
    .eq('date', today)
    .maybeSingle()
  throwIfQueryFailed(snapshotError, 'daily snapshot lookup failed')

  const { data: progress, error: progressError } = await supabase
    .from('user_progress')
    .select(
      'current_streak, longest_streak, xp_total, level, blocks_completed, deficit_block, last_active_date',
    )
    .eq('user_id', userId)
    .maybeSingle()
  throwIfQueryFailed(progressError, 'user progress lookup failed')
  if (!progress) throw new Error('user progress missing')

  // Janela 14 dias — orçamento calórico + DAM (manutenção/ganho_massa).
  // Computa em-memória sobre daily_snapshots fechados.
  const date14dAgo = getLocalDateMinusDays(userTz, 14, referenceTimestamp)
  const { data: last14dRows, error: last14dError } = await supabase
    .from('daily_snapshots')
    .select('calories_consumed, calories_target, day_closed')
    .eq('user_id', userId)
    .gte('date', date14dAgo)
    .eq('day_closed', true)
  throwIfQueryFailed(last14dError, 'daily history lookup failed')
  const last14dTyped = (last14dRows ?? []) as Array<{
    calories_consumed: number | null
    calories_target: number | null
    day_closed: boolean | null
  }>
  const last14d = {
    consumed_total: last14dTyped.reduce((s, r) => s + (r.calories_consumed ?? 0), 0),
    target_total: last14dTyped.reduce((s, r) => s + (r.calories_target ?? 0), 0),
    days_with_data: last14dTyped.length,
    dam: last14dTyped.filter(
      (r) => (r.calories_consumed ?? 0) > (r.calories_target ?? 0),
    ).length,
  }
  const snapTyped = snapToday as {
    calories_target?: number | null
    protein_target?: number | string | null
    current_protocol?: string | null
    calories_consumed?: number | null
    protein_g?: number | null
    carbs_g?: number | null
    fat_g?: number | null
    exercise_calories?: number | null
    daily_balance?: number | null
    deficit_accumulated?: number | null
    day_status?: string | null
    gap_reminder_sent_at?: string | null
  } | null
  const progressTyped = progress as {
    current_streak?: number | null
    longest_streak?: number | null
    xp_total?: number | null
    level?: number | null
    blocks_completed?: number | null
    deficit_block?: number | null
    last_active_date?: string | null
  } | null

  const reevaluationSince = new Date(Date.now() - 48 * 3600 * 1000).toISOString()
  const [
    { data: bodyVisionRows, error: bodyVisionError },
    { data: reevaluationDueRows, error: reevaluationDueError },
  ] = await Promise.all([
    supabase
      .from('product_events')
      .select('properties, occurred_at')
      .eq('user_id', userId)
      .eq('event', 'vision.analyzed')
      .gte('occurred_at', reevaluationSince)
      .order('occurred_at', { ascending: false })
      .limit(50),
    supabase
      .from('product_events')
      .select('id')
      .eq('user_id', userId)
      .eq('event', 'reevaluation.due')
      .gte('occurred_at', reevaluationSince)
      .limit(1),
  ])
  throwIfQueryFailed(bodyVisionError, 'body vision history lookup failed')
  throwIfQueryFailed(reevaluationDueError, 'reevaluation status lookup failed')
  const bodySignals = ((bodyVisionRows ?? []) as Array<{
    properties: unknown
    occurred_at: string | null
  }>)
    .map((row) => bodyPhotoSignalFromEventProperties(row.properties, row.occurred_at))
    .filter((signal): signal is BodyPhotoSignal => signal != null)
  const reevaluationDueRecent =
    Array.isArray(reevaluationDueRows) && reevaluationDueRows.length > 0
  const bodyPhotoTexts = recentMessages
    .filter((m) => m.role === 'user')
    .map((m) => m.content)
  if (currentText) bodyPhotoTexts.push(currentText)
  const bodyPhotoState =
    reevaluationDueRecent || bodySignals.length > 0
      ? deriveBodyPhotoState(bodySignals, bodyPhotoTexts)
      : null

  // C5 preserves the day's recorded targets. Flow must use the same targets
  // as Today after a new weight; the legacy channels keep their old context.
  const positiveSnapshotTarget = (value: number | string | null | undefined) => {
    const target = value == null ? null : Number(value)
    return target != null && Number.isFinite(target) && target > 0 ? target : null
  }
  const contextTargets =
    historyProvider === 'mobile_flow'
      ? {
          calories_target:
            positiveSnapshotTarget(snapTyped?.calories_target) ?? dailyTargets.calories_target,
          protein_target:
            positiveSnapshotTarget(snapTyped?.protein_target) ?? dailyTargets.protein_target,
        }
      : dailyTargets
  // Flow only: what the day balance needs to know about the day row, read
  // with the same profile and config as the targets above, so the Flow and
  // the Today screen reach the same verdict (same number) on the day the
  // protocol changed and on a closed day that carries its own protocol.
  const flowProfileRow: ProfileRow = {
    sex: profileTyped.sex,
    birth_date: profile?.birth_date ?? null,
    height_cm: profileTyped.heightCm,
    weight_kg: profileTyped.weightKg,
    body_fat_percent: profileTyped.bodyFatPercent,
    activity_level: profileTyped.activityLevel,
    training_frequency: profileTyped.trainingFrequency,
    water_intake: profileTyped.waterIntake,
    hunger_level: profileTyped.hungerLevel,
    current_protocol: profileTyped.currentProtocol,
    goal_type: profileTyped.goalType,
    goal_value: profileTyped.goalValue,
    deficit_level: profileTyped.deficitLevel,
  }
  const flowDayRow: FlowDayRow | null =
    historyProvider === 'mobile_flow'
      ? {
          protocol: snapTyped?.current_protocol ?? null,
          storedTargetKcal: positiveSnapshotTarget(snapTyped?.calories_target),
          targetByProtocol: dailyTargetByProtocol(flowProfileRow, calcCfg),
        }
      : null

  return {
    userId,
    userName: userTyped?.name ?? null,
    profile: profileTyped,
    recentMessages,
    ...(flowOutsideSessionLines ? { flowOutsideSessionLines } : {}),
    summary: userTyped?.summary ?? null,
    hoursSinceLastIn,
    isReentry,
    country: userTyped?.country ?? null,
    countryConfirmed: !!userTyped?.country_confirmed,
    countryDetectedFromWpp: userTyped?.country_detected_from_wpp ?? null,
    locale: userTyped?.locale ?? null,
    userMetadata: (userTyped?.metadata as Record<string, unknown> | null) ?? null,
    lastInboundContentType: (() => {
      // Última msg inbound: pra Fase B detector express decidir se é foto/áudio.
      const lastIn = (msgs ?? []).find(
        (m) => (m as { direction?: string }).direction === 'in',
      ) as { content_type?: string | null } | undefined
      const ct = lastIn?.content_type ?? null
      if (ct === 'image' || ct === 'audio' || ct === 'text') return ct
      return null
    })(),
    unitSystem,
    timezone: userTyped?.timezone ?? 'America/Sao_Paulo',
    referenceTimestamp,
    bodyPhotoState,
    reevaluationDueRecent,
    dailyTargets: contextTargets,
    flowDayRow,
    todaySnapshot: snapTyped
      ? {
          calories_consumed: snapTyped.calories_consumed ?? 0,
          protein_g: Number(snapTyped.protein_g ?? 0),
          carbs_g: Number(snapTyped.carbs_g ?? 0),
          fat_g: Number(snapTyped.fat_g ?? 0),
          exercise_calories: snapTyped.exercise_calories ?? 0,
          daily_balance: snapTyped.daily_balance ?? 0,
          deficit_accumulated: snapTyped.deficit_accumulated ?? 0,
          day_status: snapTyped.day_status ?? null,
          gap_reminder_sent_at: snapTyped.gap_reminder_sent_at ?? null,
        }
      : null,
    userProgress: progressTyped
      ? {
          current_streak: progressTyped.current_streak ?? 0,
          longest_streak: progressTyped.longest_streak ?? 0,
          xp_total: progressTyped.xp_total ?? 0,
          level: progressTyped.level ?? 1,
          blocks_completed: progressTyped.blocks_completed ?? 0,
          deficit_block: progressTyped.deficit_block ?? 0,
          last_active_date: progressTyped.last_active_date ?? null,
        }
      : null,
    last14d: last14d.days_with_data > 0 ? last14d : null,
    visionPending: await loadVisionPending(supabase, userId),
  }
}

// Audit 06-26 Item 6: loadVisionPending foi extraído para vision-pending-loader.ts
// (deriveVisionPending pura + I/O thin wrapper + 8 testes ponta-a-ponta).
// Implementação byte-a-byte preservada — re-export cobre o call site em
// loadContext (linha ~2010).

/**
 * FIX 2 (review HIGH SKIP-NO-HINT 2026-06-16): infere meal_type quando o
 * paciente diz "Pulei" sem especificar. Sem hint, o retry pro LLM dizia
 * "<inferir do contexto>" — Haiku chutava errado (ex: "almoco" às 22h).
 * Ordem: (1) último gap_reminder do dia em recentMessages, (2) hora local
 * do paciente em janelas MPP (cafe 6-10, almoco 11-14, lanche 15-17,
 * jantar 19-22, ceia 22-3). Retorna null se ambíguo.
 */
function inferMealTypeHint(
  ctx: UserContext,
): 'cafe' | 'almoco' | 'lanche' | 'jantar' | 'ceia' | undefined {
  // (1) gap_reminder explícito nas últimas mensagens assistant. Padrão:
  // "você não registrou X hoje" / "lembrete: ainda falta Y".
  const reminderMealRe =
    /(?:n[ãa]o\s+registrou|n[ãa]o\s+anotou|falta(?:ndo)?|lembrete[^.]*)\s+(?:o\s+)?(caf[ée](?:\s+da\s+manh[ãa])?|almo[çc]o|lanche|jantar|ceia)/i
  const assistantMsgs = ctx.recentMessages
    .filter((m) => m.role === 'assistant')
    .slice(-5)
    .reverse()
  for (const m of assistantMsgs) {
    const match = m.content.match(reminderMealRe)
    if (match) {
      const w = (match[1] ?? '').toLowerCase()
      if (w.startsWith('caf')) return 'cafe'
      if (w.startsWith('almo')) return 'almoco'
      if (w.startsWith('lanch')) return 'lanche'
      if (w.startsWith('jant')) return 'jantar'
      if (w.startsWith('ceia')) return 'ceia'
    }
  }
  // (2) hora local do paciente.
  try {
    const hour = getLocalHour(ctx.timezone, ctx.referenceTimestamp)
    if (hour >= 6 && hour < 11) return 'cafe'
    if (hour >= 11 && hour < 15) return 'almoco'
    if (hour >= 15 && hour < 18) return 'lanche'
    if (hour >= 18 && hour < 22) return 'jantar'
    if (hour >= 22 || hour < 4) return 'ceia'
  } catch {
    // timezone inválido ou getLocalHour falha → não chuta
  }
  return undefined
}

function resolveStage(profile: UserProfile): AgentStage {
  if (!profile.currentProtocol) return 'coleta_dados'
  return profile.currentProtocol
}

async function loadActivePrompt(
  supabase: ServiceClient,
  stage: AgentStage,
  locale?: string | null,
) {
  // Config (model/temp/max_tokens/…) vem da view, que já escolhe a config ativa.
  const { data, error } = await supabase
    .from('v_active_prompts')
    .select('*')
    .eq('stage', stage)
    .single()
  if (error) throw error
  if (!data) return null

  // ECONOMIA DE TOKEN #1: re-agrega o system_prompt filtrando pelo idioma do
  // paciente (helper compartilhado com o engajamento). Fallback pro prompt cheio
  // da view se a query falhar / não retornar regras.
  const filtered = await loadFilteredSystemPrompt(supabase, stage, locale)
  const system_prompt = filtered ?? (data as { system_prompt: string }).system_prompt

  return { ...data, system_prompt } as {
    stage: AgentStage
    model: string
    temperature: number
    max_tokens: number
    system_prompt: string
  }
}

function buildToolSchemas(tools: ToolDefinition[]): ChatCompletionTool[] {
  return tools.map((t) => ({
    type: 'function',
    function: {
      name: t.name,
      description: t.description,
      parameters: zodToJsonSchema(t.parameters),
    },
  }))
}

export async function hasOpenPending(
  supabase: ServiceClient,
  userId: string,
): Promise<boolean> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
// biome-ignore lint/suspicious/noExplicitAny: legacy — see ACT-1 prevention plan 2026-06-16
  const { data, error } = await (supabase as any)
    .from('pending_registrations')
    .select('id')
    .eq('user_id', userId)
    .eq('status', 'pending')
    .limit(1)
  throwIfQueryFailed(error, 'pending lookup failed')
  return Array.isArray(data) && data.length > 0
}

async function logModelRouted(
  supabase: ServiceClient,
  userId: string,
  payload: { from: string; to: string; reason: string; stage: string; text_preview?: string },
): Promise<void> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
// biome-ignore lint/suspicious/noExplicitAny: legacy — see ACT-1 prevention plan 2026-06-16
  await (supabase as any).from('product_events').insert({
    user_id: userId,
    event: 'pipeline.model_routed',
    properties: payload,
  })
}

function formatUserContext(
  ctx: UserContext,
  calcConfig?: import('@mpp/core').CalcConfig,
  referenceTimestamp: Date = ctx.referenceTimestamp,
  historyProvider?: string,
): string {
  const m = computeMetrics(ctx.profile, referenceTimestamp, calcConfig)
  const sections: string[] = []
  // Flow only (2026-10-04, cost): this block is never cached, so every
  // character is paid at full price on every model call. The Flow gets the
  // same context minus what it cannot use — instructions to call tools it
  // does not have, the meal_type table and the photo rules. Profile, date/time
  // and the numeric block are untouched. WhatsApp: legacy text, byte for byte
  // (locked by __golden__/audit-10-04-whatsapp-request-lock.test.ts).
  const flowLean = MOBILE_FLOW_LEAN_CONTEXT && historyProvider === 'mobile_flow'
  const flowPublicMetrics = historyProvider === 'mobile_flow'

  // FIX 4 (Roberto 2026-06-15): foto noturna perdida — LLM chamou
  // marca_refeicao_pulada depois de paciente responder disambiguação. Aviso
  // EXPLÍCITO no topo do prompt sobre foto pendente força o LLM a chamar
  // registra_refeicao. Combinado com hard-guard pós-LLM (rejeita
  // marca_refeicao_pulada quando visionPending != null).
  if (ctx.visionPending) {
    const vp = ctx.visionPending
    const itemsStr = vp.items
      .map(
        (it) =>
          `${it.name} (~${it.quantity_g_estimate}g, conf ${Math.round(it.confidence * 100)}%)`,
      )
      .join(', ')
    sections.push(
      `### ⚠️ FOTO PENDENTE DE REGISTRO\n` +
        `Você analisou foto de refeição há ${vp.ageMinutes} min e ela AINDA NÃO foi registrada nem virou pending.\n` +
        `Items vistos pelo vision: ${itemsStr}.${vp.mealContext ? ` Contexto: ${vp.mealContext}.` : ''}\n` +
        `→ Chame \`registra_refeicao\` com esses items (ajuste com base na resposta do paciente nesta msg).\n` +
        `→ NÃO chame \`marca_refeicao_pulada\` — o sistema vai BLOQUEAR a chamada. ` +
        `A resposta do paciente é pra COMPLETAR a foto, não pra confirmar pulo.\n` +
        `→ Só chame \`marca_refeicao_pulada\` se o paciente disser LITERALMENTE "pulei"/"não comi"/"joguei fora" NESTA mensagem específica E sobre OUTRA refeição (não a da foto).`,
    )
  }

  if (ctx.bodyPhotoState && (ctx.reevaluationDueRecent || ctx.bodyPhotoState.recentSignals.length > 0)) {
    sections.push(formatBodyPhotoContext(ctx.bodyPhotoState))
  }

  // Reentrada warm: instrução pro LLM no topo
  if (ctx.isReentry && ctx.hoursSinceLastIn != null) {
    const days = Math.floor(ctx.hoursSinceLastIn / 24)
    sections.push(
      `### REENTRADA APÓS PAUSA\n` +
        `O usuário voltou após ${days} dia(s) sem mandar mensagem. ` +
        `Cumprimente de volta de forma calorosa e breve, faça um resumo curto de onde paramos ` +
        `(use o "Resumo do paciente" abaixo se disponível) e pergunte como ele está hoje. ` +
        `NÃO recomece o onboarding nem repita perguntas já respondidas.`,
    )
  }

  // Resumo persistente do paciente (gerado por cron LLM)
  if (ctx.summary && ctx.summary.trim().length > 0) {
    sections.push(`### Resumo do paciente\n${flowPublicMetrics ? projectFlowMetricContext(ctx.summary) : ctx.summary}`)
  }

  // País — instrução explícita pro LLM saber se já tem confirmação
  const country = ctx.country ?? 'BR'
  const personaName =
    historyProvider === 'mobile_flow'
      ? 'Flow'
      : country === 'US' || country === 'GB' || country === 'CA' || country === 'AU'
        ? 'Dr. Robert Menescal'
        : 'Dr. Roberto Menescal'
  const countryToLanguage: Record<string, string> = {
    BR: 'pt-BR',
    PT: 'pt-PT',
    US: 'en',
    GB: 'en',
    CA: 'en',
    AU: 'en',
    ES: 'es',
    MX: 'es',
    AR: 'es',
    CL: 'es',
    CO: 'es',
    PE: 'es',
    UY: 'es',
    PY: 'es',
    BO: 'es',
    EC: 'es',
    VE: 'es',
    FR: 'fr',
    DE: 'de',
    IT: 'it',
  }
  // Usa locale escolhido pelo paciente se disponível; senão deriva do país
  const language = ctx.locale ?? countryToLanguage[country] ?? 'pt-BR'
  // unit_system: explícito do paciente OU 'imperial' default pra US/GB OU 'metric' default
  const unitSystem =
    ctx.unitSystem ?? (['US', 'GB'].includes(country) ? 'imperial' : 'metric')
  const unitsLabel =
    unitSystem === 'imperial' ? 'lb / inch (imperial)' : 'kg / cm (métrico)'

  if (ctx.countryConfirmed) {
    const timezoneConfirmed = ctx.userMetadata?.timezone_confirmed === true
    const locationInstruction =
      isMultiTimezoneCountry(country) && !timezoneConfirmed
        ? `\n\n⚠️ O país ${country} tem múltiplos fusos e o timezone ainda não foi confirmado pela localização. Pergunte cidade e estado/região de residência e chame \`confirma_pais_residencia\` com city, region e timezone IANA. Não altere o fuso sem essa resposta.`
        : ''
    if (flowLean) {
      // The legacy text below minus what asks for `confirma_pais_residencia`
      // (a tool the Flow does not have): the "persist the language" clause
      // and the "ask city and state" paragraph. Every kept sentence is the
      // legacy one, word for word.
      sections.push(
        `### Localização e preferências\n` +
          `País: **${country}** (confirmado). Idioma salvo: **${language}**. Unidades: **${unitsLabel}**. ` +
          `Persona: ${personaName}. NÃO pergunte país de novo. ` +
          `\n\n⚠️ **REGRA DE IDIOMA (inviolável):** responda no idioma que o paciente está usando AGORA na última mensagem. ` +
          `Se o paciente pedir explicitamente pra mudar de idioma (ex: "fale em português", "switch to English"), MUDE IMEDIATAMENTE. ` +
          (language !== 'pt-BR' && language !== 'pt-PT'
            ? `Idioma salvo é ${language} — use esse por padrão se o paciente continuar nele. `
            : '') +
          (unitSystem === 'imperial'
            ? `\n\n**Unidades imperial:** quando o paciente informar peso/altura, provavelmente usará lb/inch. Converta internamente pra kg/cm (1 lb=0.4536 kg, 1 inch=2.54 cm) antes de salvar via tool. Devolva metas/balanço em lb/inch. Se ele te der um valor em kg, ACEITE — não peça pra reconverter. `
            : '') +
          (country !== 'BR'
            ? `\n\n⚠️ Sistema otimizado pra Brasil (TACO, alimentos locais BR). Comidas regionais de ${country} podem ter macros imprecisos.`
            : ''),
      )
    } else {
      sections.push(
        `### Localização e preferências\n` +
          `País: **${country}** (confirmado). Idioma salvo: **${language}**. Unidades: **${unitsLabel}**. ` +
          `Persona: ${personaName}. NÃO pergunte país de novo. ` +
          `\n\n⚠️ **REGRA DE IDIOMA (inviolável):** responda no idioma que o paciente está usando AGORA na última mensagem. ` +
          `Se o paciente pedir explicitamente pra mudar de idioma (ex: "fale em português", "switch to English"), MUDE IMEDIATAMENTE e chame \`confirma_pais_residencia\` de novo com o \`language\` atualizado pra persistir. Mantenha o \`country\`. ` +
          (language !== 'pt-BR' && language !== 'pt-PT'
            ? `Idioma salvo é ${language} — use esse por padrão se o paciente continuar nele. `
            : '') +
          (unitSystem === 'imperial'
            ? `\n\n**Unidades imperial:** quando o paciente informar peso/altura, provavelmente usará lb/inch. Converta internamente pra kg/cm (1 lb=0.4536 kg, 1 inch=2.54 cm) antes de salvar via tool. Devolva metas/balanço em lb/inch. Se ele te der um valor em kg, ACEITE — não peça pra reconverter. `
            : '') +
          (country !== 'BR'
            ? `\n\n⚠️ Sistema otimizado pra Brasil (TACO, alimentos locais BR). Comidas regionais de ${country} podem ter macros imprecisos.`
            : '') +
          locationInstruction,
      )
    }
  } else {
    const guess = ctx.countryDetectedFromWpp
      ? `palpite pelo DDI do WhatsApp: ${ctx.countryDetectedFromWpp}`
      : 'sem palpite (DDI desconhecido)'
    if (flowLean) {
      // The Flow cannot store the answer (no `confirma_pais_residencia`), so
      // it is not told to ask: only the status line stays.
      sections.push(`### País de residência (NÃO confirmado)\nStatus: ${guess}.`)
    } else {
      sections.push(
        `### País de residência (NÃO confirmado)\n` +
          `Status: ${guess}. **Pergunte explicitamente** ao paciente onde ele mora ` +
          `(siga a rule "Confirmação de país de residência") e chame a tool ` +
          `\`confirma_pais_residencia\` com o ISO alpha-2 quando ele responder. ` +
          `Se o país tiver múltiplos fusos, pergunte também cidade e estado/região antes de gravar.`,
      )
    }
  }

  // Hora local do paciente — CRÍTICO pra meal_type correto.
  // Sem isso o LLM tem que adivinhar pelos alimentos (ambíguo: pão+ovo serve
  // pra café OU jantar) e classifica errado. Bug real: foto de café às 7h
  // local foi registrada como meal_type=jantar com replace=true porque o
  // LLM achou que era correção do jantar de ontem.
  const tz = ctx.timezone
  const now = referenceTimestamp
  const localTimeFmt = new Intl.DateTimeFormat('pt-BR', {
    timeZone: tz,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    weekday: 'long',
    hour12: false,
  })
  const parts = localTimeFmt.formatToParts(now)
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? ''
  const localHour = Number.parseInt(get('hour'), 10)
  const localStr = `${get('weekday')}, ${get('day')}/${get('month')}/${get('year')} ${get('hour')}:${get('minute')}`
  const suggestedMeal =
    localHour >= 5 && localHour < 11
      ? 'cafe (café da manhã)'
      : localHour >= 11 && localHour < 15
        ? 'almoco (almoço)'
        : localHour >= 15 && localHour < 18
          ? 'lanche (lanche da tarde)'
          : localHour >= 18 && localHour < 23
            ? 'jantar'
            : 'ceia'
  if (flowLean) {
    // The date/time line as it is; the meal_type table, the meal suggestion
    // and the replace warning only serve meal registration, which the Flow
    // chat does not do.
    sections.push(
      `### Hora local do paciente AGORA\n` +
        `**${localStr}** (timezone: ${tz}, hora local = ${localHour}h)`,
    )
  } else {
    sections.push(
      `### Hora local do paciente AGORA (use pra meal_type — NÃO adivinhe pelos alimentos)\n` +
        `**${localStr}** (timezone: ${tz}, hora local = ${localHour}h)\n\n` +
        `⚠️ Se o paciente registrar refeição AGORA, o \`meal_type\` é determinado pela HORA LOCAL, NÃO pelos alimentos:\n` +
        `- 5h–10h59 → \`cafe\` (café da manhã)\n` +
        `- 11h–14h59 → \`almoco\`\n` +
        `- 15h–17h59 → \`lanche\`\n` +
        `- 18h–22h59 → \`jantar\`\n` +
        `- 23h–4h59 → \`ceia\`\n\n` +
        `**Sugestão pra esta refeição: \`${suggestedMeal}\`**.\n\n` +
        `❌ NÃO use \`replace=true\` em foto NOVA recebida em momento diferente do dia. \`replace=true\` é APENAS quando o paciente disse explicitamente "corrige", "errei", "na verdade era X" etc. Foto enviada de manhã é refeição NOVA do dia, não correção do jantar de ontem.`,
    )
  }

  // Estado factual atual
  const lines = [
    `- Nome: ${ctx.userName ?? '(não informado ainda)'}`,
    `- Sexo: ${ctx.profile.sex ?? 'desconhecido'}`,
    `- Idade: ${m.age ?? '?'}`,
    `- Altura: ${ctx.profile.heightCm ?? '?'} cm`,
    `- Peso: ${ctx.profile.weightKg ?? '?'} kg`,
    flowPublicMetrics
      ? `- Gordura corporal: ${ctx.profile.bodyFatPercent == null ? '?' : `${ctx.profile.bodyFatPercent}%`}`
      : `- BF%: ${ctx.profile.bodyFatPercent ?? '?'}`,
    `- Atividade: ${ctx.profile.activityLevel ?? '?'}`,
    `- Treinos/semana: ${ctx.profile.trainingFrequency ?? '?'}`,
    `- Protocolo atual: ${ctx.profile.currentProtocol ?? 'NÃO DEFINIDO (usuário em onboarding)'}`,
  ]
  if (!flowPublicMetrics && m.bmr != null) lines.push(`- BMR estimado: ${Math.round(m.bmr)} kcal`)
  if (!flowPublicMetrics && m.bmr != null && m.activityFactor != null) {
    const tdeeVal = Math.round(m.bmr * m.activityFactor)
    // ⚠️ Pra recomposição, TDEE é INFORMATIVO — meta usa BMR×1.2 − déficit (doc MPP).
    // Mostrar com aviso explícito pra LLM não confundir TDEE com meta.
    if (ctx.profile.currentProtocol === 'recomposicao') {
      lines.push(
        `- TDEE estimado: ${tdeeVal} kcal (apenas referência — NÃO é a meta na recomposição; meta = BMR × 1,2 − déficit, vide seção "Dados numéricos REAIS" abaixo)`,
      )
    } else {
      lines.push(`- TDEE estimado: ${tdeeVal} kcal`)
    }
  }
  if (m.imc != null) lines.push(`- IMC: ${m.imc.toFixed(1)}`)
  if (!flowPublicMetrics && m.lbm != null) lines.push(`- LBM (massa magra): ${m.lbm.toFixed(1)} kg`)

  if (ctx.profile.sex && (ctx.profile.bodyFatPercent != null || m.imc != null)) {
    try {
      const dec = resolveProtocol(ctx.profile, m, calcConfig)
      lines.push(
        `- Decisão automática: protocol=${dec.protocol} canChoose=${dec.canChoose} blockers=[${dec.blockers.join('; ') || 'nenhum'}] goal=${dec.goalType}=${dec.goalValue}`,
      )
    } catch {
      // ignora
    }
  }
  sections.push(lines.join('\n'))

  // ============================================================
  // ANTI-ALUCINAÇÃO — DADOS REAIS DO PACIENTE (USE ESTES VALORES)
  // ============================================================
  // Bug histórico: LLM calculava meta/balanço/streak na cabeça e errava.
  // Solução: passar TODOS os números no contexto + regra inviolável de
  // "nunca calcule" (Persona master). Estes dados são determinísticos,
  // calculados em Postgres + função core, NUNCA contestáveis.
  const numericLines: string[] = []
  if (ctx.dailyTargets.calories_target != null) {
    numericLines.push(`- Meta calórica de hoje: **${ctx.dailyTargets.calories_target} kcal**`)
  }
  if (ctx.dailyTargets.protein_target != null) {
    numericLines.push(`- Meta de proteína de hoje: **${ctx.dailyTargets.protein_target} g**`)
  }
  if (ctx.todaySnapshot) {
    const s = ctx.todaySnapshot
    numericLines.push(
      `- Consumido hoje: ${s.calories_consumed} kcal | ${s.protein_g} g proteína | ${s.carbs_g}g carbo | ${s.fat_g}g gordura`,
    )
    if (historyProvider === 'mobile_flow') {
      // Flow only (iPhone, staging, 2026-10-04): the single unlabeled net
      // balance read as "the workout is already discounted, eat more". Two
      // labeled balances + the rule. Computed over the target printed above,
      // not from the generated column (wrong when the day row has no target).
      numericLines.push(
        ...flowEnergyContextLines({
          caloriesTarget: ctx.dailyTargets.calories_target,
          caloriesConsumed: s.calories_consumed,
          exerciseCalories: s.exercise_calories,
          // The day's balance per protocol (docs/CALCULO-MPP.md §2c).
          ...flowDayBalanceInputs(ctx.profile, calcConfig, ctx.flowDayRow),
          hasSnapshot: true,
        }),
      )
    } else {
      // LEGACY (WhatsApp in production): byte for byte. Locked by
      // __golden__/audit-10-04-whatsapp-context-lock.test.ts.
      numericLines.push(`- Exercício hoje: ${s.exercise_calories} kcal queimadas`)
      numericLines.push(
        `- Balanço calórico de hoje: ${s.daily_balance} kcal (negativo=déficit, positivo=superávit)`,
      )
    }
    if (s.deficit_accumulated > 0) {
      numericLines.push(
        `- Déficit acumulado (bloco 7700): ${s.deficit_accumulated} kcal de 7700 — falta ${7700 - s.deficit_accumulated} pra fechar bloco`,
      )
    }
    // day_status (Roberto 2026-05-16) — exposto pro LLM saber se há gap aberto.
    // O cron daily-gap-checker marca 'pending_close' quando manda lembrete
    // sobre refeição esperada que não foi registrada. Daily-closer fecha
    // depois como 'incomplete_no_response' se paciente não responder.
    if (s.day_status === 'pending_close') {
      numericLines.push(
        `- ⚠️ DIA PENDENTE: enviamos lembrete sobre refeição não registrada. Se o paciente acabou de mandar/confirmar, registre normal. Se ele falou "pulei", chame marca_refeicao_pulada(meal_type) com a refeição pulada.`,
      )
    } else if (s.day_status === 'incomplete_no_response') {
      numericLines.push(
        `- ⚠️ DIA INCOMPLETO: paciente não respondeu ao lembrete de refeição faltante. Bloco 7700 NÃO foi creditado por esse dia. Pra creditar retroativo, paciente precisa registrar a refeição que faltou OU confirmar "pulei".`,
      )
    }
  } else {
    numericLines.push(`- Consumo hoje: 0 kcal (nada registrado ainda)`)
    if (historyProvider === 'mobile_flow') {
      // Flow only: a patient who trained before logging anything still gets
      // the food line and the rule; no net-balance line without a day row.
      numericLines.push(
        ...flowEnergyContextLines({
          caloriesTarget: ctx.dailyTargets.calories_target,
          caloriesConsumed: 0,
          exerciseCalories: 0,
          ...flowDayBalanceInputs(ctx.profile, calcConfig, ctx.flowDayRow),
          hasSnapshot: false,
        }),
      )
    }
  }
  if (ctx.userProgress) {
    const p = ctx.userProgress
    numericLines.push(
      `- Sequência atual: ${p.current_streak} dias consecutivos (recorde ${p.longest_streak}) | XP: ${p.xp_total} (nível ${p.level}) | Blocos 7700 fechados: ${p.blocks_completed}`,
    )
    // Bloco 7700 EM ANDAMENTO — usado pelo card pós-registro (recomp)
    // pra mostrar 📊 Bloco 7700: {N} / 7700 kcal ({pct}%).
    // SEMPRE mostra, mesmo quando 0 — sem isso o LLM alucina (Amanda 2026-05-15
    // viu "Bloco 7700: 57/7700" enquanto real era 0; Paulo viu "0/7700" enquanto
    // real era 874). Validator pega, mas paciente já viu o número errado.
    const pct = Math.round((p.deficit_block / 7700) * 100)
    numericLines.push(
      `- Bloco 7700 em andamento: **${p.deficit_block} kcal de 7700** (${pct}%)${p.deficit_block > 0 ? ` — falta ${7700 - p.deficit_block} kcal pra fechar` : ''}`,
    )
  }
  // Janela 14d — pra manutenção e ganho_massa (Notion: métrica principal).
  if (ctx.last14d && ctx.last14d.target_total > 0) {
    const l = ctx.last14d
    const pct = Math.round((l.consumed_total / l.target_total) * 100)
    numericLines.push(
      `- Orçamento 14 dias: **${l.consumed_total} kcal de ${l.target_total} kcal (${pct}%)** | DAM: ${l.dam}/${l.days_with_data} dias | janela: ${l.days_with_data} dias fechados`,
    )
  }
  if (numericLines.length > 0) {
    sections.push(
      `### Dados numéricos REAIS do paciente (use estes, NÃO INVENTE)\n` +
        `⚠️ Estes valores são canônicos — calculados pelo sistema. NUNCA recalcule meta/balanço/streak na cabeça nem invente números diferentes destes.\n\n` +
        numericLines.join('\n'),
    )
  }

  // Regras hard sobre mídias e respostas
  if (flowLean) {
    // Legacy rules 2 and 3, word for word. Rules 1 and 5 are about photos and
    // rule 4 calls `pausar_agente`: the Flow chat has neither. The heading
    // stays — the Flow goldens use it to delimit the numeric section.
    sections.push(
      `### Regras importantes\n` +
        `1. Cadência humana: 1 pergunta por turno. Se for resposta longa, separe em parágrafos com \\n\\n ` +
        `(o sistema quebra em chunks naturais).\n` +
        `2. Não repita o nome do usuário no início de toda resposta — use vocativo no fim ou em ` +
        `momentos de validação emocional, não como prefixo automático.`,
    )
  } else {
    sections.push(
      `### Regras importantes\n` +
        `1. NUNCA invente o conteúdo de uma foto. Se a análise visual vier vazia, com erro, ` +
        `ou contiver "[falhou ao baixar/analisar]", peça ao usuário pra reenviar ou descrever por texto.\n` +
        `2. Cadência humana: 1 pergunta por turno. Se for resposta longa, separe em parágrafos com \\n\\n ` +
        `(o sistema quebra em chunks naturais).\n` +
        `3. Não repita o nome do usuário no início de toda resposta — use vocativo no fim ou em ` +
        `momentos de validação emocional, não como prefixo automático.\n` +
        `4. Se usuário pedir "pausar / férias / parar uns dias", chame a tool pausar_agente.\n` +
        `5. Foto e legenda no mesmo turno descrevem a MESMA refeição. Use o texto para corrigir ou completar a análise visual, mas nunca some duas vezes o mesmo alimento só porque ele apareceu nas duas fontes.`,
    )
  }

  return sections.join('\n\n')
}
