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
import { computeMetrics, eatingBalance, resolveProtocol } from '@mpp/core'
import { loadCalcConfig } from './calc-config-loader.js'
import { loadDailyTargets } from './calc-targets.js'
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
import {
  composePendingProposal,
  composePostRegistrationMessage,
  composeReevalResultMessage,
  composeStatusMessage,
  embedEduComment,
  isPureRegistrationTurn,
  isPureStatusQueryTurn,
  isReevalToolTurn,
  type RegistrationEntry,
} from './post-registration-message.js'
import {
  makeOnboardingButtonId,
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
import {
  isMealExpressEligible,
  isWorkoutExpressEligible,
  type ExpressInput,
} from './express-mode-detector.js'
import { calcMealMacros, parseUserKcalOverrides } from './meal-pipeline.js'
import { detectFakeWrite } from './fake-write-detector.js'
import { runToolGuard } from './tools/tool-guards.js'
import { detectFalseDuplicationClaim } from './false-duplication-detector.js'
import { detectCorrectionIntent } from './correction-detector.js'
import { reportVisionCoverageIfLow } from './vision-coverage-checker.js'
import { loadVisionPending } from './vision-pending-loader.js'
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
import type { ServiceClient } from '@mpp/db'
import type { OpenRouterEmbeddings, OpenRouterLLM, SystemPromptBlock } from '@mpp/providers'
import type { ChatCompletionMessageParam, ChatCompletionTool } from 'openai/resources/chat/completions'
import { ALL_TOOLS, getToolByName } from './tools.js'
import type { ToolContext, ToolDefinition } from './tools.js'
import { zodToJsonSchema } from './tool-schema.js'
import type { AgentInput, AgentOutput } from './types.js'

export interface PipelineDeps {
  supabase: ServiceClient
  llm: OpenRouterLLM
  /** Limite de iterações de tool calling (segurança). */
  maxToolIterations?: number
  /** Embeddings p/ RAG do método (sub-projeto D). Opcional: sem ele, sem retrieval. */
  embeddings?: OpenRouterEmbeddings
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
  /** Metas calóricas/proteína calculadas determinísticamente (anti-alucinação). */
  dailyTargets: { calories_target: number | null; protein_target: number | null }
  /** Snapshot do dia LOCAL do paciente — consumo + balanço atual. */
  todaySnapshot: {
    calories_consumed: number
    protein_g: number
    carbs_g: number
    fat_g: number
    exercise_calories: number
    daily_balance: number
    deficit_accumulated: number
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
  const start = Date.now()

  // 1. ensure user
  const userId = await ensureUser(deps.supabase, input.from)

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
  )

  // 4. resolve stage
  const stage = resolveStage(ctx.profile)

  // 4. load active prompt + config (filtra regras pelo idioma do paciente — #1)
  const promptRow = await loadActivePrompt(deps.supabase, stage, ctx.locale)
  if (!promptRow) {
    throw new Error(`No active prompt found for stage ${stage}`)
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
      text_preview: (input.text ?? '').slice(0, 80),
    })
    ;(promptRow as { model: string }).model = routed.model
  }

  // 5. call agent (with tool loop)
  // Filtra tools pelo allowed_tools do config (se NULL = todas)
  const allowedTools = (promptRow as { allowed_tools?: string[] | null }).allowed_tools
  const filteredTools =
    allowedTools && allowedTools.length > 0
      ? ALL_TOOLS.filter((t) => allowedTools.includes(t.name))
      : ALL_TOOLS
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
        `Suas últimas respostas foram:\n` +
        lastTwoOuts.map((t, i) => `[${i + 1}] "${t.slice(0, 200).replace(/\n/g, ' ')}"`).join('\n') +
        `\n\n→ NÃO repita aberturas, frases âncora ou bullets de balanço se já estão acima.\n` +
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
  const stableSystem = promptRow.system_prompt
  // RAG (D): método relevante recuperado por turno — bloco VARIÁVEL (não cacheado).
  const methodContext = await retrieveMethodContext(deps, input.text, ctx.profile.currentProtocol)
  const variableSystem = `${methodContext}\n\n## Contexto do usuário\n${formatUserContext(ctx, calcConfig)}${repetitionGuard}`
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

  const messages: ChatCompletionMessageParam[] = ctx.recentMessages.map((m) => ({
    role: m.role,
    content: m.content,
  }))
  messages.push({ role: 'user', content: input.text ?? '(mídia recebida)' })

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
  const max = configMax ?? deps.maxToolIterations ?? 5
  // Flag pra evitar loop infinito no re-prompt de fake registration (1 retry só).
  let fakeWriteRetried = false
  let prematureBlockRetried = false
  let falseDuplicationRetried = false
  // Card determinístico de registro → enviar como UMA mensagem (sem split).
  let deterministicRegistration = false
  // FASE B (Roberto 2026-05-28, botões #4): se virou pending → o caller manda
  // sendInteractive em vez de sendHumanized, e o pipeline NÃO chama o LLM de novo.
  let interactivePayload: NonNullable<AgentOutput['interactive']> | null = null
  for (let iter = 0; iter < max; iter++) {
    const result = await deps.llm.complete({
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
    })
    lastResult = result
    totalPromptTokens += result.promptTokens
    totalCacheRead += result.cacheReadInputTokens ?? 0
    totalCacheCreate += result.cacheCreationInputTokens ?? 0
    totalCompletionTokens += result.completionTokens
    if (result.costUsd != null) {
      totalCost = (totalCost ?? 0) + result.costUsd
    }

    if (result.toolCalls.length === 0) {
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
        (tc) => (tc.name === 'gera_dieta' || tc.name === 'gera_treino') && !tc.error,
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
        patientText: input.text ?? '',
        registrationToolCalled,
        prescriptionToolCalled,
        skipToolCalled,
        mealTypeHint,
      })

      if (fake.isFake && !fakeWriteRetried) {
        fakeWriteRetried = true
        await deps.supabase.from('product_events').insert({
          user_id: userId,
          event: 'llm.fake_write_detected',
          properties: {
            stage,
            kind: fake.kind,
            model: result.model,
            content_preview: content.slice(0, 120),
            inferred_meal_type: fake.inferredMealType ?? null,
          },
        })
        messages.push({ role: 'assistant', content })
        const retryMsg =
          fake.kind === 'skip'
            ? `SISTEMA (não é o paciente): o paciente confirmou que PULOU uma refeição. Você respondeu como se tivesse anotado/registrado MAS não chamou a tool \`marca_refeicao_pulada\`. Chame \`marca_refeicao_pulada(meal_type=${fake.inferredMealType ?? '<inferir do contexto>'})\` AGORA. NÃO chame \`registra_refeicao\` — não há refeição pra registrar. NÃO copie items do histórico — o paciente disse pulei, então a refeição NÃO existe.`
            : fake.kind === 'correction'
              ? 'SISTEMA (não é o paciente): você afirmou ter CORRIGIDO a refeição/treino MAS não chamou a tool. A correção NÃO foi salva — o banco ainda tem a versão antiga. Chame `registra_refeicao` com `replace=true` + `meal_type` (ou `registra_treino` pra exercício) AGORA com os itens corretos. NÃO responda ao paciente sem antes chamar a tool.'
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
        await deps.supabase.from('product_events').insert({
          user_id: userId,
          event: 'llm.premature_block_completion',
          properties: { stage, content_preview: content.slice(0, 140) },
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
        await deps.supabase.from('product_events').insert({
          user_id: userId,
          event: 'llm.false_duplication_caught',
          properties: {
            stage,
            patient_text: (input.text ?? '').slice(0, 200),
            agent_text: content.slice(0, 200),
          },
        })
        messages.push({ role: 'assistant', content })
        messages.push({
          role: 'user',
          content: `SISTEMA (não é o paciente): o paciente NÃO mandou mensagem duplicada. O texto original recebido foi: "${input.text}". Processe COMO VEIO, SEM acusar duplicação. Se há múltiplos itens conectados (ex: "X e Y", "X, Y, Z" ou em linhas separadas), são itens DISTINTOS — registre TODOS. Refaça a resposta agora.`,
        })
        continue
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
      // Últimas 3 msgs do paciente — pra validação semântica em tools (ex:
      // detectar se replace=true em registra_refeicao tem palavra de correção).
      recentUserMessages: ctx.recentMessages
        .filter((m) => m.role === 'user')
        .slice(-3)
        .map((m) => m.content),
    }
    for (const tc of result.toolCalls) {
      const tool = getToolByName(tc.name)
      if (!tool) {
        const err = `Tool '${tc.name}' não encontrada`
        toolCallsSummary.push({ name: tc.name, arguments: {}, error: err })
        messages.push({ role: 'tool', tool_call_id: tc.id, content: JSON.stringify({ error: err }) })
        continue
      }
      let parsed: unknown
      try {
        parsed = JSON.parse(tc.arguments)
      } catch {
        parsed = {}
      }
      try {
        const validated = tool.parameters.parse(parsed)

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
            patientText: input.text ?? '',
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
              // Review M1 + M2: filtra kind=meal pra evitar match espúrio em
              // pendings de training/onboarding/etc; captura error pra
              // diferenciar query-fail de "não tem pending recente".
              const { data: recentPending, error: pendErr } = await deps.supabase
                .from('pending_registrations')
                .select('id, proposal, created_at')
                .eq('user_id', userId)
                .eq('status', 'pending')
                .eq('proposal->>kind', 'meal')
                .gte(
                  'created_at',
                  new Date(Date.now() - 5 * 60 * 1000).toISOString(),
                )
                .order('created_at', { ascending: false })
                .limit(1)
                .maybeSingle()
              if (pendErr) {
                await deps.supabase.from('product_events').insert({
                  user_id: userId,
                  event: 'pipeline.duplicate_check_query_failed',
                  properties: {
                    error_message: pendErr.message ?? String(pendErr),
                    new_items_count: newItemNames.size,
                  },
                })
                // Default seguro: cai no cancel cego (comportamento antigo).
              }
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
            if (!suppressedAsDuplicate) {
              await deps.supabase
                .from('pending_registrations')
                .update({ status: 'cancelled', resolved_at: new Date().toISOString() })
                .eq('user_id', userId)
                .eq('status', 'pending')
            }
          }

          if (buttonsEnabled && !exprResult.eligible) {
            // Cria o pending novo
            const args = validated as {
              meal_type?: string | null
              replace?: boolean
              items: Array<{
                food_name: string
                quantity_g?: number
              }>
            }
            // FIX (Roberto 2026-05-28): a LLM passa só {food_name, quantity_g}.
            // kcal/macros vêm da resolução TACO via calcMealMacros — o mesmo
            // que registra_refeicao usa internamente. Sem isso o pending vinha
            // com 0 kcal (Roberto viu na tela: "0 kcal" em todos os itens).
            // Bug Luciana 2026-06-16: parser de "X cal/kcal/calorias" no texto
            // do paciente. Quando o paciente cita kcal explícita no mesmo
            // trecho de um item, OVERRIDE o lookup TACO. Helper devolve Map
            // food_name → user_kcal; calcMealMacros honra na PRIORIDADE -3.
            const kcalOverrides = parseUserKcalOverrides(input.text ?? '', args.items)
            const itemsWithOverrides = args.items.map((it) => ({
              food_name: it.food_name,
              quantity_g: it.quantity_g ?? 0,
              ...(kcalOverrides.has(it.food_name)
                ? { user_kcal: kcalOverrides.get(it.food_name)! }
                : {}),
            }))
            if (kcalOverrides.size > 0) {
              await deps.supabase.from('product_events').insert({
                user_id: userId,
                event: 'pipeline.user_kcal_override',
                properties: {
                  source: 'express_pending',
                  overrides: Object.fromEntries(kcalOverrides),
                  items_count: args.items.length,
                  patient_text: (input.text ?? '').slice(0, 200),
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
            const proposalItems = resolved.items.map((m) => ({
              name: m.food_name,
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
            }))
            const proposalTotals = {
              kcal: resolved.totals.kcal,
              protein_g: resolved.totals.protein_g,
              carbs_g: resolved.totals.carbs_g,
              fat_g: resolved.totals.fat_g,
            }
            const proposal = {
              kind: 'meal' as const,
              mealType: args.meal_type ?? 'outro',
              items: proposalItems,
              totals: proposalTotals,
              sourceContentType: ctx.lastInboundContentType,
              source_provider_message_id: input.providerMessageId ?? null,
              source_text: input.text ?? null,
              express_eligible: false,
              express_reason: exprResult.reason,
              // Roberto 2026-06-01: salva replace pra handler do tap propagar
              // pro registra_refeicao.execute. Sem isso, correção que veio via
              // botão viraria INSERT em vez de SUBSTITUIR (dupla contagem).
              replace: args.replace === true,
            }
            const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString()
            const { data: pendRow } = await deps.supabase
              .from('pending_registrations')
              .insert({ user_id: userId, proposal, expires_at: expiresAt })
              .select('id')
              .single()
            const pendingId = (pendRow as { id: string } | null)?.id
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
            // Se INSERT falhou, cai pro execute normal (failsafe).
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
            patientText: input.text ?? '',
            workoutType: wArgs.workout_type ?? null,
            durationMin: wArgs.duration_min ?? null,
          })
          const buttonsEnabled =
            (ctx.userMetadata as { buttons_enabled?: boolean } | null)?.buttons_enabled === true

          // FIX (mesmo do registra_refeicao acima): cancela pending em aberto
          // SEMPRE — express ou não — pra evitar duplicação caso tape Sim no antigo.
          if (buttonsEnabled) {
            await deps.supabase
              .from('pending_registrations')
              .update({ status: 'cancelled', resolved_at: new Date().toISOString() })
              .eq('user_id', userId)
              .eq('status', 'pending')
          }

          if (buttonsEnabled && !exprRes.eligible) {
            const proposal = {
              kind: 'workout' as const,
              workoutType: wArgs.workout_type ?? 'treino',
              durationMin: wArgs.duration_min ?? null,
              kcalEst: wArgs.estimated_kcal_from_image ?? null,
              sourceContentType: ctx.lastInboundContentType,
              source_provider_message_id: input.providerMessageId ?? null,
              source_text: input.text ?? null,
              express_eligible: false,
              express_reason: exprRes.reason,
              // guarda os args completos pro handler chamar registraTreino depois
              raw_args: wArgs,
            }
            const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString()
            const { data: pendRow } = await deps.supabase
              .from('pending_registrations')
              .insert({ user_id: userId, proposal, expires_at: expiresAt })
              .select('id')
              .single()
            const pendingId = (pendRow as { id: string } | null)?.id
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
        await deps.supabase.from('tools_audit').insert({
          user_id: userId,
          tool_name: tc.name,
          arguments: jsonify(validated),
          result: jsonify(out),
          duration_ms: Date.now() - toolStart,
          success: true,
        })
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

    // ── FASE 1 (Roberto 2026-05-25): REGISTRO PURO → resposta montada pelo SISTEMA ──
    // Se este turno foi SÓ registra_refeicao/registra_treino (com sucesso) e o
    // paciente NÃO fez pergunta, o sistema compõe a resposta (frase fixa + tabela
    // + card canônico) e PULA a 2ª chamada do LLM — que só re-redigia (e às vezes
    // errava/variava). Coaching/conversa segue com a IA nos demais turnos.
    // Gatilho conservador: qualquer outra tool no turno, ou "?" na msg do paciente,
    // cai no fluxo normal (LLM responde). O card determinístico ainda passa pelo
    // FIX C pós-loop (idempotente) + auditorias.
    const iterEntries = toolCallsSummary.slice(-result.toolCalls.length)
    if (isPureRegistrationTurn(iterEntries, input.text)) {
      const todayStr = getLocalDateString(ctx.timezone)
      const [{ data: snapDet }, { data: progDet }] = await Promise.all([
        deps.supabase
          .from('daily_snapshots')
          .select('calories_consumed, calories_target, protein_g, protein_target, exercise_calories')
          .eq('user_id', userId)
          .eq('date', todayStr)
          .maybeSingle(),
        deps.supabase.from('user_progress').select('deficit_block').eq('user_id', userId).maybeSingle(),
      ])
      if (snapDet) {
        const s = snapDet as {
          calories_consumed: number
          calories_target: number | null
          protein_g: number
          protein_target: number | null
          exercise_calories: number
        }
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
            deficitBlock: (progDet as { deficit_block: number } | null)?.deficit_block ?? 0,
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
      const [{ data: snapDet }, { data: progDet }] = await Promise.all([
        deps.supabase
          .from('daily_snapshots')
          .select('calories_consumed, calories_target, protein_g, protein_target, exercise_calories')
          .eq('user_id', userId)
          .eq('date', todayStr)
          .maybeSingle(),
        deps.supabase
          .from('user_progress')
          .select('deficit_block, current_streak, level, xp_total, blocks_completed')
          .eq('user_id', userId)
          .maybeSingle(),
      ])
      if (snapDet) {
        const s = snapDet as {
          calories_consumed: number
          calories_target: number | null
          protein_g: number
          protein_target: number | null
          exercise_calories: number
        }
        const p = (progDet ?? {}) as {
          deficit_block?: number
          current_streak?: number
          level?: number
          xp_total?: number
          blocks_completed?: number
        }
        finalText = composeStatusMessage(
          {
            caloriesConsumed: s.calories_consumed,
            caloriesTarget: s.calories_target,
            proteinG: Number(s.protein_g),
            proteinTarget: s.protein_target,
            exerciseCalories: s.exercise_calories,
            deficitBlock: p.deficit_block ?? 0,
            protocol:
              (ctx.profile.currentProtocol as
                | 'recomposicao'
                | 'ganho_massa'
                | 'manutencao'
                | null) ?? null,
            last14d: ctx.last14d,
          },
          {
            currentStreak: p.current_streak ?? 0,
            level: p.level ?? 1,
            xpTotal: p.xp_total ?? 0,
            blocksCompleted: p.blocks_completed ?? 0,
          },
        )
        messages.push({ role: 'assistant', content: finalText })
        deterministicRegistration = true // reusa o flag de single-message (card não fragmenta)
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
      const since = new Date(Date.now() - 48 * 3600 * 1000).toISOString()
      const [{ data: revalDue }, { data: profRow }] = await Promise.all([
        deps.supabase
          .from('product_events')
          .select('id')
          .eq('user_id', userId)
          .eq('event', 'reevaluation.due')
          .gte('occurred_at', since)
          .limit(1),
        deps.supabase
          .from('user_profiles')
          .select('current_protocol')
          .eq('user_id', userId)
          .maybeSingle(),
      ])
      if (revalDue && revalDue.length > 0) {
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
            (profRow as { current_protocol?: string | null } | null)?.current_protocol ??
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
    const todayStr = getLocalDateString(ctx.timezone)
    const [{ data: snapFresh }, { data: progFresh }] = await Promise.all([
      deps.supabase
        .from('daily_snapshots')
        .select('calories_consumed, calories_target, protein_g, protein_target, exercise_calories')
        .eq('user_id', userId)
        .eq('date', todayStr)
        .maybeSingle(),
      deps.supabase
        .from('user_progress')
        .select('deficit_block')
        .eq('user_id', userId)
        .maybeSingle(),
    ])
    if (snapFresh) {
      const snapTyped = snapFresh as {
        calories_consumed: number
        calories_target: number | null
        protein_g: number
        protein_target: number | null
        exercise_calories: number
      }
      freshConsumed = snapTyped.calories_consumed
      const progTyped = progFresh as { deficit_block: number } | null
      const canonicalCard = renderBalanceCard({
        caloriesConsumed: snapTyped.calories_consumed,
        caloriesTarget: snapTyped.calories_target,
        proteinG: Number(snapTyped.protein_g),
        proteinTarget: snapTyped.protein_target,
        exerciseCalories: snapTyped.exercise_calories,
        deficitBlock: progTyped?.deficit_block ?? 0,
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
        const proseFix = reconcileBalanceProse(finalText, eb)
        if (proseFix.replacements > 0) {
          finalText = proseFix.text
          await deps.supabase.from('product_events').insert({
            user_id: userId,
            event: 'llm.balance_prose_reconciled',
            properties: { stage, replacements: proseFix.replacements, eating_balance: eb },
          })
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
        if (drMismatch) {
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
      (tc) => (tc.name === 'gera_dieta' || tc.name === 'gera_treino') && !tc.error,
    )
    const skipToolCalled = toolCallsSummary.some(
      (tc) => tc.name === 'marca_refeicao_pulada' && !tc.error,
    )
    const mealTypeHint = inferMealTypeHint(ctx)
    const fakeFinal = detectFakeWrite({
      content: finalText,
      patientText: input.text ?? '',
      registrationToolCalled,
      prescriptionToolCalled,
      skipToolCalled,
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
          content_preview: finalText.slice(0, 120),
          inferred_meal_type: fakeFinal.inferredMealType ?? null,
        },
      })
    }
    // Camada 3 (lado da ENTRADA): o paciente pediu correção, o agente mostrou
    // card, mas nenhuma tool de registro rodou no turno. Cruza intenção do
    // paciente × ação do agente. Log-only (evita falso-positivo afetar paciente);
    // a auditoria usa pra pegar correção silenciosamente não-persistida.
    const patientMsgs = ctx.recentMessages
      .filter((mm) => mm.role === 'user')
      .slice(-3)
      .map((mm) => mm.content)
    const correctionWord = detectCorrectionIntent(patientMsgs)
    if (correctionWord && !registrationToolCalled && hasBalanceCard(finalText)) {
      await deps.supabase.from('product_events').insert({
        user_id: userId,
        event: 'llm.correction_intent_no_write',
        properties: { stage, keyword: correctionWord, content_preview: finalText.slice(0, 120) },
      })
    }
  }

  // Audit anti-alucinação: parseia números na resposta e compara com contexto.
  // Não bloqueia — só loga em product_events pra investigação posterior.
  const m = computeMetrics(ctx.profile, new Date(), calcConfig)
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
    if (sentimentMismatch) {
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

  return {
    text: finalText,
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
    promptTokens: totalPromptTokens,
    completionTokens: totalCompletionTokens,
    costUsd: totalCost,
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
async function checkSubscription(
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

  const { data: sub } = await supabase
    .from('subscriptions')
    .select('status, current_period_end, trial_ends_at')
    .eq('user_id', userId)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle()

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

async function ensureUser(supabase: ServiceClient, wpp: string): Promise<string> {
  const { data: existing } = await supabase
    .from('users')
    .select('id')
    .eq('wpp', wpp)
    .maybeSingle()
  if (existing) return existing.id

  const { data: created, error } = await supabase
    .from('users')
    .insert({ wpp, status: 'active' })
    .select('id')
    .single()
  if (error) throw error

  // cria profile + progress vazios
  await supabase.from('user_profiles').insert({ user_id: created.id })
  await supabase.from('user_progress').insert({ user_id: created.id })

  return created.id
}

const RECENT_MESSAGES_LIMIT = 50
const REENTRY_THRESHOLD_HOURS = 24 * 7 // 7 dias

type RecentMessageRow = {
  direction: string | null
  content: string | null
  content_type?: string | null
  provider_message_id?: string | null
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

export function buildPromptRecentMessages(
  rows: RecentMessageRow[],
  currentProviderMessageIds: string | string[] | null | undefined,
): Array<{ role: 'user' | 'assistant'; content: string }> {
  const currentIds = normalizeCurrentProviderMessageIds(currentProviderMessageIds)
  return rows
    .slice()
    .reverse()
    .filter((m) => m.content)
    .filter((m) => !isRawInteractiveTap(m))
    .filter(
      (m) => !m.provider_message_id || !currentIds.has(m.provider_message_id),
    )
    .map((m) => ({
      role: m.direction === 'in' ? ('user' as const) : ('assistant' as const),
      content: m.content as string,
    }))
}

async function loadContext(
  supabase: ServiceClient,
  userId: string,
  currentProviderMessageIds?: string | string[] | null,
  currentText?: string | null,
): Promise<UserContext> {
  // Cast pra unknown porque tipos auto-gen ainda não conhecem as colunas
  // novas (summary, last_active_at) — adicionadas na migration 0016.
  const { data: user } = await (supabase as unknown as {
    from: (t: string) => {
      select: (s: string) => {
        eq: (col: string, val: string) => { single: () => Promise<{ data: unknown }> }
      }
    }
  })
    .from('users')
    .select(
      'id, name, summary, last_active_at, country, country_confirmed, country_detected_from_wpp, locale, metadata, timezone',
    )
    .eq('id', userId)
    .single()
  const { data: profile } = await supabase
    .from('user_profiles')
    .select('*')
    .eq('user_id', userId)
    .single()
  const { data: msgs } = await supabase
    .from('messages')
    .select('direction, content, content_type, created_at, provider_message_id')
    .eq('user_id', userId)
    .order('created_at', { ascending: false })
    .limit(RECENT_MESSAGES_LIMIT)

  // .slice() ANTES do .reverse() — reverse() muta in-place. Sem o slice, a
  // ordem do `msgs` original fica ASC, e o `lastInboundContentType` (linha
  // ~1412) abaixo passa a pegar a inbound MAIS ANTIGA da janela em vez da
  // mais recente — bug Paulo+Roberto 2026-05-30 (sourceContentType invertido:
  // text→image e image→text).
  const recentMessages = buildPromptRecentMessages(
    (msgs ?? []) as RecentMessageRow[],
    currentProviderMessageIds,
  )

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
  const today = getLocalDateString(userTz)
  const { data: snapToday } = await supabase
    .from('daily_snapshots')
    .select(
      'calories_consumed, protein_g, carbs_g, fat_g, exercise_calories, daily_balance, deficit_accumulated',
    )
    .eq('user_id', userId)
    .eq('date', today)
    .maybeSingle()
  const { data: progress } = await supabase
    .from('user_progress')
    .select(
      'current_streak, longest_streak, xp_total, level, blocks_completed, deficit_block, last_active_date',
    )
    .eq('user_id', userId)
    .maybeSingle()

  // Janela 14 dias — orçamento calórico + DAM (manutenção/ganho_massa).
  // Computa em-memória sobre daily_snapshots fechados.
  const date14dAgo = getLocalDateMinusDays(userTz, 14)
  const { data: last14dRows } = await supabase
    .from('daily_snapshots')
    .select('calories_consumed, calories_target, day_closed')
    .eq('user_id', userId)
    .gte('date', date14dAgo)
    .eq('day_closed', true)
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
    calories_consumed?: number | null
    protein_g?: number | null
    carbs_g?: number | null
    fat_g?: number | null
    exercise_calories?: number | null
    daily_balance?: number | null
    deficit_accumulated?: number | null
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
  const [{ data: bodyVisionRows }, { data: reevaluationDueRows }] = await Promise.all([
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

  return {
    userId,
    userName: userTyped?.name ?? null,
    profile: profileTyped,
    recentMessages,
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
    bodyPhotoState,
    reevaluationDueRecent,
    dailyTargets,
    todaySnapshot: snapTyped
      ? {
          calories_consumed: snapTyped.calories_consumed ?? 0,
          protein_g: Number(snapTyped.protein_g ?? 0),
          carbs_g: Number(snapTyped.carbs_g ?? 0),
          fat_g: Number(snapTyped.fat_g ?? 0),
          exercise_calories: snapTyped.exercise_calories ?? 0,
          daily_balance: snapTyped.daily_balance ?? 0,
          deficit_accumulated: snapTyped.deficit_accumulated ?? 0,
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
    const hour = getLocalHour(ctx.timezone)
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

// ─── Router de modelo (Fase 6 — 2026-06-04) ──────────────────────────────────

let routerFlagCache: { value: boolean; expiresAt: number } | null = null
const ROUTER_FLAG_TTL_MS = 60_000

async function loadRouterFlag(supabase: ServiceClient): Promise<boolean> {
  const now = Date.now()
  if (routerFlagCache && routerFlagCache.expiresAt > now) return routerFlagCache.value
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
// biome-ignore lint/suspicious/noExplicitAny: legacy — see ACT-1 prevention plan 2026-06-16
  const { data } = await (supabase as any)
    .from('global_config')
    .select('value')
    .eq('key', 'router.haiku_enabled')
    .maybeSingle()
  // Default TRUE — Haiku routing fica ligado. Pra desligar: UPDATE global_config
  // SET value='false' WHERE key='router.haiku_enabled'.
  const value =
    data && (data as { value: unknown }).value !== undefined
      ? (data as { value: unknown }).value !== false &&
        (data as { value: unknown }).value !== 'false'
      : true
  routerFlagCache = { value, expiresAt: now + ROUTER_FLAG_TTL_MS }
  return value
}

async function hasOpenPending(supabase: ServiceClient, userId: string): Promise<boolean> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
// biome-ignore lint/suspicious/noExplicitAny: legacy — see ACT-1 prevention plan 2026-06-16
  const { data } = await (supabase as any)
    .from('pending_registrations')
    .select('id')
    .eq('user_id', userId)
    .eq('status', 'pending')
    .limit(1)
  return Array.isArray(data) && data.length > 0
}

async function logModelRouted(
  supabase: ServiceClient,
  userId: string,
  payload: { from: string; to: string; reason: string; stage: string; text_preview: string },
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
): string {
  const m = computeMetrics(ctx.profile, new Date(), calcConfig)
  const sections: string[] = []

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
    sections.push(`### Resumo do paciente\n${ctx.summary}`)
  }

  // País — instrução explícita pro LLM saber se já tem confirmação
  const country = ctx.country ?? 'BR'
  const personaName =
    country === 'US' || country === 'GB' || country === 'CA' || country === 'AU'
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
          : ''),
    )
  } else {
    const guess = ctx.countryDetectedFromWpp
      ? `palpite pelo DDI do WhatsApp: ${ctx.countryDetectedFromWpp}`
      : 'sem palpite (DDI desconhecido)'
    sections.push(
      `### País de residência (NÃO confirmado)\n` +
        `Status: ${guess}. **Pergunte explicitamente** ao paciente onde ele mora ` +
        `(siga a rule "Confirmação de país de residência") e chame a tool ` +
        `\`confirma_pais_residencia\` com o ISO alpha-2 quando ele responder.`,
    )
  }

  // Hora local do paciente — CRÍTICO pra meal_type correto.
  // Sem isso o LLM tem que adivinhar pelos alimentos (ambíguo: pão+ovo serve
  // pra café OU jantar) e classifica errado. Bug real: foto de café às 7h
  // local foi registrada como meal_type=jantar com replace=true porque o
  // LLM achou que era correção do jantar de ontem.
  const tz = ctx.timezone
  const now = new Date()
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
            : 'lanche (madrugada/ceia)'
  sections.push(
    `### Hora local do paciente AGORA (use pra meal_type — NÃO adivinhe pelos alimentos)\n` +
      `**${localStr}** (timezone: ${tz}, hora local = ${localHour}h)\n\n` +
      `⚠️ Se o paciente registrar refeição AGORA, o \`meal_type\` é determinado pela HORA LOCAL, NÃO pelos alimentos:\n` +
      `- 5h–10h59 → \`cafe\` (café da manhã)\n` +
      `- 11h–14h59 → \`almoco\`\n` +
      `- 15h–17h59 → \`lanche\`\n` +
      `- 18h–22h59 → \`jantar\`\n` +
      `- 23h–4h59 → \`lanche\` (ceia/madrugada)\n\n` +
      `**Sugestão pra esta refeição: \`${suggestedMeal}\`**.\n\n` +
      `❌ NÃO use \`replace=true\` em foto NOVA recebida em momento diferente do dia. \`replace=true\` é APENAS quando o paciente disse explicitamente "corrige", "errei", "na verdade era X" etc. Foto enviada de manhã é refeição NOVA do dia, não correção do jantar de ontem.`,
  )

  // Estado factual atual
  const lines = [
    `- Nome: ${ctx.userName ?? '(não informado ainda)'}`,
    `- Sexo: ${ctx.profile.sex ?? 'desconhecido'}`,
    `- Idade: ${m.age ?? '?'}`,
    `- Altura: ${ctx.profile.heightCm ?? '?'} cm`,
    `- Peso: ${ctx.profile.weightKg ?? '?'} kg`,
    `- BF%: ${ctx.profile.bodyFatPercent ?? '?'}`,
    `- Atividade: ${ctx.profile.activityLevel ?? '?'}`,
    `- Treinos/semana: ${ctx.profile.trainingFrequency ?? '?'}`,
    `- Protocolo atual: ${ctx.profile.currentProtocol ?? 'NÃO DEFINIDO (usuário em onboarding)'}`,
  ]
  if (m.bmr != null) lines.push(`- BMR estimado: ${Math.round(m.bmr)} kcal`)
  if (m.bmr != null && m.activityFactor != null) {
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
  if (m.lbm != null) lines.push(`- LBM (massa magra): ${m.lbm.toFixed(1)} kg`)

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
    numericLines.push(`- Exercício hoje: ${s.exercise_calories} kcal queimadas`)
    numericLines.push(
      `- Balanço calórico de hoje: ${s.daily_balance} kcal (negativo=déficit, positivo=superávit)`,
    )
    if (s.deficit_accumulated > 0) {
      numericLines.push(
        `- Déficit acumulado (bloco 7700): ${s.deficit_accumulated} kcal de 7700 — falta ${7700 - s.deficit_accumulated} pra fechar bloco`,
      )
    }
    // day_status (Roberto 2026-05-16) — exposto pro LLM saber se há gap aberto.
    // O cron daily-gap-checker marca 'pending_close' quando manda lembrete
    // sobre refeição esperada que não foi registrada. Daily-closer fecha
    // depois como 'incomplete_no_response' se paciente não responder.
    const snapTyped = s as typeof s & { day_status?: string | null; gap_reminder_sent_at?: string | null }
    if (snapTyped.day_status === 'pending_close') {
      numericLines.push(
        `- ⚠️ DIA PENDENTE: enviamos lembrete sobre refeição não registrada. Se o paciente acabou de mandar/confirmar, registre normal. Se ele falou "pulei", chame marca_refeicao_pulada(meal_type) com a refeição pulada.`,
      )
    } else if (snapTyped.day_status === 'incomplete_no_response') {
      numericLines.push(
        `- ⚠️ DIA INCOMPLETO: paciente não respondeu ao lembrete de refeição faltante. Bloco 7700 NÃO foi creditado por esse dia. Pra creditar retroativo, paciente precisa registrar a refeição que faltou OU confirmar "pulei".`,
      )
    }
  } else {
    numericLines.push(`- Consumo hoje: 0 kcal (nada registrado ainda)`)
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
  sections.push(
    `### Regras importantes\n` +
      `1. NUNCA invente o conteúdo de uma foto. Se a análise visual vier vazia, com erro, ` +
      `ou contiver "[falhou ao baixar/analisar]", peça ao usuário pra reenviar ou descrever por texto.\n` +
      `2. Cadência humana: 1 pergunta por turno. Se for resposta longa, separe em parágrafos com \\n\\n ` +
      `(o sistema quebra em chunks naturais).\n` +
      `3. Não repita o nome do usuário no início de toda resposta — use vocativo no fim ou em ` +
      `momentos de validação emocional, não como prefixo automático.\n` +
      `4. Se usuário pedir "pausar / férias / parar uns dias", chame a tool pausar_agente.`,
  )

  return sections.join('\n\n')
}
