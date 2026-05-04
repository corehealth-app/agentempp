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
import { computeMetrics, resolveProtocol } from '@mpp/core'
import { loadCalcConfig } from './calc-config-loader.js'
import type { AgentStage, UserProfile } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import type { OpenRouterLLM } from '@mpp/providers'
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
  /** Sistema de medidas: 'metric' (kg/cm) ou 'imperial' (lb/in). */
  unitSystem: 'metric' | 'imperial' | null
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
  const ctx = await loadContext(deps.supabase, userId)

  // 4. resolve stage
  const stage = resolveStage(ctx.profile)

  // 4. load active prompt + config
  const promptRow = await loadActivePrompt(deps.supabase, stage)
  if (!promptRow) {
    throw new Error(`No active prompt found for stage ${stage}`)
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

  const baseSystem = `${promptRow.system_prompt}\n\n## Contexto do usuário\n${formatUserContext(ctx, calcConfig)}${repetitionGuard}`

  const messages: ChatCompletionMessageParam[] = ctx.recentMessages.map((m) => ({
    role: m.role,
    content: m.content,
  }))
  messages.push({ role: 'user', content: input.text ?? '(mídia recebida)' })

  const toolCallsSummary: AgentOutput['toolCalls'] = []
  let totalPromptTokens = 0
  let totalCompletionTokens = 0
  let totalCost: number | null = null
  let lastResult: Awaited<ReturnType<typeof deps.llm.complete>> | null = null
  let finalText = ''

  // max_tool_iterations: prioriza config do DB, fallback pro deps, fallback pra 5
  const configMax = (promptRow as { max_tool_iterations?: number }).max_tool_iterations
  const max = configMax ?? deps.maxToolIterations ?? 5
  for (let iter = 0; iter < max; iter++) {
    const result = await deps.llm.complete({
      model: promptRow.model,
      systemPrompt: baseSystem,
      messages,
      temperature: promptRow.temperature,
      maxTokens: promptRow.max_tokens,
      tools,
      userId,
      metadata: { Stage: stage, Iteration: String(iter) },
    })
    lastResult = result
    totalPromptTokens += result.promptTokens
    totalCompletionTokens += result.completionTokens
    if (result.costUsd != null) {
      totalCost = (totalCost ?? 0) + result.costUsd
    }

    if (result.toolCalls.length === 0) {
      finalText = result.content ?? ''
      messages.push({ role: 'assistant', content: result.content ?? '' })
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
      userCountry: ctx.country ?? 'BR',
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

  return {
    text: finalText,
    preferAudio: input.contentType === 'audio',
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

function buildBlockedResponse(input: AgentInput, reason: string): AgentOutput {
  return {
    text: `Sua assinatura precisa ser renovada para continuar usando o coach. Acesse seu painel ou fale com a equipe. (motivo: ${reason})`,
    preferAudio: input.contentType === 'audio',
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

async function loadContext(supabase: ServiceClient, userId: string): Promise<UserContext> {
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
      'id, name, summary, last_active_at, country, country_confirmed, country_detected_from_wpp, locale, metadata',
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
    .select('direction, content, content_type, created_at')
    .eq('user_id', userId)
    .order('created_at', { ascending: false })
    .limit(RECENT_MESSAGES_LIMIT)

  const recentMessages = (msgs ?? [])
    .reverse()
    .filter((m) => m.content)
    .map((m) => ({
      role: m.direction === 'in' ? ('user' as const) : ('assistant' as const),
      content: m.content as string,
    }))

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
  }

  const unitSystemRaw = userTyped?.metadata?.unit_system
  const unitSystem: 'metric' | 'imperial' | null =
    unitSystemRaw === 'metric' || unitSystemRaw === 'imperial' ? unitSystemRaw : null

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
    unitSystem,
  }
}

function resolveStage(profile: UserProfile): AgentStage {
  if (!profile.currentProtocol) return 'coleta_dados'
  return profile.currentProtocol
}

async function loadActivePrompt(supabase: ServiceClient, stage: AgentStage) {
  const { data, error } = await supabase
    .from('v_active_prompts')
    .select('*')
    .eq('stage', stage)
    .single()
  if (error) throw error
  return data as {
    stage: AgentStage
    model: string
    temperature: number
    max_tokens: number
    system_prompt: string
  } | null
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

function formatUserContext(
  ctx: UserContext,
  calcConfig?: import('@mpp/core').CalcConfig,
): string {
  const m = computeMetrics(ctx.profile, new Date(), calcConfig)
  const sections: string[] = []

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
  if (m.imc != null) lines.push(`- IMC: ${m.imc.toFixed(1)}`)

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
