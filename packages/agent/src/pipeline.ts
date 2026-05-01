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

  // 4. load active prompt
  const promptRow = await loadActivePrompt(deps.supabase, stage)
  if (!promptRow) {
    throw new Error(`No active prompt found for stage ${stage}`)
  }

  // 5. call agent (with tool loop)
  const tools = buildToolSchemas(ALL_TOOLS)
  const baseSystem = `${promptRow.system_prompt}\n\n## Contexto do usuário\n${formatUserContext(ctx)}`

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

  const max = deps.maxToolIterations ?? 5
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
    const toolCtx: ToolContext = { supabase: deps.supabase, userId, userWpp: input.from }
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

  // 6. persistir mensagens
  await deps.supabase.from('messages').insert([
    {
      user_id: userId,
      direction: 'in',
      role: 'user',
      content_type: input.contentType,
      content: input.text ?? null,
      media_url: input.mediaUrl ?? null,
      provider: input.provider,
      provider_message_id: input.providerMessageId,
      raw_payload: { from: input.from, contentType: input.contentType, text: input.text },
      created_at: input.timestamp.toISOString(),
    },
    {
      user_id: userId,
      direction: 'out',
      role: 'assistant',
      content_type: 'text',
      content: finalText,
      provider: input.provider,
      agent_stage: stage,
      model_used: lastResult.model,
      prompt_tokens: totalPromptTokens,
      completion_tokens: totalCompletionTokens,
      cost_usd: totalCost,
      latency_ms: Date.now() - start,
    },
  ])

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

async function loadContext(supabase: ServiceClient, userId: string): Promise<UserContext> {
  const { data: user } = await supabase
    .from('users')
    .select('id, name')
    .eq('id', userId)
    .single()
  const { data: profile } = await supabase
    .from('user_profiles')
    .select('*')
    .eq('user_id', userId)
    .single()
  const { data: msgs } = await supabase
    .from('messages')
    .select('direction, content, content_type')
    .eq('user_id', userId)
    .order('created_at', { ascending: false })
    .limit(20)

  const recentMessages = (msgs ?? [])
    .reverse()
    .filter((m) => m.content)
    .map((m) => ({
      role: m.direction === 'in' ? ('user' as const) : ('assistant' as const),
      content: m.content as string,
    }))

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

  return {
    userId,
    userName: user?.name ?? null,
    profile: profileTyped,
    recentMessages,
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

function formatUserContext(ctx: UserContext): string {
  const m = computeMetrics(ctx.profile)
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

  // Se onboarding completo, computa decisão de protocolo (info para o LLM contextualizar)
  if (ctx.profile.sex && (ctx.profile.bodyFatPercent != null || m.imc != null)) {
    try {
      const dec = resolveProtocol(ctx.profile, m)
      lines.push(
        `- Decisão automática: protocol=${dec.protocol} canChoose=${dec.canChoose} blockers=[${dec.blockers.join('; ') || 'nenhum'}] goal=${dec.goalType}=${dec.goalValue}`,
      )
    } catch {
      // ignora
    }
  }
  return lines.join('\n')
}
