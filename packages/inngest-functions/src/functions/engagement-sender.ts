import {
  getLocalDateString,
  getLocalHour,
  getTzOffset,
  loadCalcConfig,
  loadDailyTargets,
} from '@mpp/agent'
import { createMessagingProvider, sendHumanized } from '@mpp/providers'
import { inngest } from '../client.js'
import { createWorkerDeps } from '../lib/env.js'
import { loadHumanizerConfig } from '../lib/runtime-config.js'

/**
 * Worker: envia mensagens proativas de engajamento.
 *
 * Disparado 5×/dia (07:07, 11:16, 14:09, 18:30, 21:27).
 * Para cada usuário ativo:
 *   1. Verifica se já mandou mensagem hoje (skip se sim — evita spam)
 *   2. Verifica horário local: skip se for noite (entre 22h e 06h)
 *   3. Lê estado (XP, streak, último snapshot)
 *   4. LLM gera mensagem com prompt do stage 'engajamento'
 *   5. Envia via messaging provider (console no dev, WA Cloud em prod)
 *   6. Persiste em messages
 */
export const engagementSenderFn = inngest.createFunction(
  { id: 'engagement-sender', retries: 1, concurrency: { limit: 5 } },
  { event: 'engagement.tick' },
  async ({ event, step, logger }) => {
    const { slot } = event.data
    logger.info('Engagement tick', { slot })

    const users = await step.run('list-eligible', async () => {
      const { supabase } = createWorkerDeps()
      const { data } = await supabase
        .from('users')
        .select('id, wpp, name, timezone')
        .eq('status', 'active')
      // Filtra só quem TEM perfil + onboarding completo + protocolo definido
      const ids = (data ?? []).map((u) => u.id)
      if (ids.length === 0) return []
      const { data: profiles } = await supabase
        .from('user_profiles')
        .select('user_id, current_protocol, onboarding_completed')
        .in('user_id', ids)
        .eq('onboarding_completed', true)
        .not('current_protocol', 'is', null)
      const eligibleIds = new Set((profiles ?? []).map((p) => p.user_id))
      return (data ?? []).filter((u) => eligibleIds.has(u.id))
    })

    let sent = 0
    let skipped = 0

    for (const user of users) {
      try {
        const result = await step.run(`engage-${user.id}`, async () =>
          maybeEngageUser(user.id, user.wpp, user.timezone ?? 'America/Sao_Paulo', slot),
        )
        if (result.sent) sent++
        else skipped++
      } catch (e) {
        logger.error('engagement failed', { userId: user.id, error: String(e) })
      }
    }

    return { sent, skipped, total: users.length }
  },
)

async function maybeEngageUser(
  userId: string,
  wpp: string,
  userTimezone: string,
  cronSlotLabel: string,
): Promise<{ sent: boolean; reason?: string }> {
  const { supabase, llm } = createWorkerDeps()

  // Hora local do user — fonte da verdade pra slot e contexto LLM
  const localHour = getLocalHour(userTimezone)
  // Carrega config (cache 60s), deriva slot+hint da hora local
  const engagementConfig = await loadEngagementConfig(supabase)
  const { slot, meal_hint: mealHint } = resolveSlot(localHour, engagementConfig.slots)

  async function logEvent(event: string, properties: Record<string, unknown>) {
    await supabase.from('product_events').insert({
      user_id: userId,
      event,
      properties: { slot, cron_slot: cronSlotLabel, local_hour: localHour, wpp, ...properties },
    })
  }

  // Pausa ativa? respeita
  const { data: u } = await supabase
    .from('users')
    .select('metadata, status')
    .eq('id', userId)
    .maybeSingle()
  const meta = (u as { metadata: Record<string, unknown> | null } | null)?.metadata
  const pausedUntil = meta?.paused_until as string | undefined
  if (pausedUntil && new Date(pausedUntil) > new Date()) {
    await logEvent('engagement.skipped', { reason: 'paused', paused_until: pausedUntil })
    return { sent: false, reason: 'paciente pausado' }
  }

  // Janela ativa do paciente (wake_time → bedtime do user_profiles).
  // Offsets + fallbacks editáveis via /settings/global → engagement.*
  const { data: profileTime } = await supabase
    .from('user_profiles')
    .select('wake_time, bedtime')
    .eq('user_id', userId)
    .maybeSingle()
  const window = activeWindow(
    (profileTime as { wake_time: string | null; bedtime: string | null } | null)?.wake_time,
    (profileTime as { wake_time: string | null; bedtime: string | null } | null)?.bedtime,
    engagementConfig,
  )
  if (!isWithinActiveWindow(localHour, window)) {
    await logEvent('engagement.skipped', {
      reason: 'fora da janela ativa do paciente',
      local_hour: localHour,
      window_start: window.start,
      window_end: window.end,
    })
    return { sent: false, reason: 'fora da janela ativa' }
  }

  // A1: já enviou engajamento hoje? Se sim, pula. (NÃO conta conversa do user.)
  const todayLocal = getLocalDate(userTimezone)
  const startOfDay = `${todayLocal}T00:00:00${tzOffset(userTimezone)}`
  const { count: engagementsToday } = await supabase
    .from('product_events')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', userId)
    .eq('event', 'engagement.sent')
    .gte('created_at', startOfDay)

  if ((engagementsToday ?? 0) > 0) {
    await logEvent('engagement.skipped', {
      reason: 'engajamento já enviado hoje',
      engagements_today: engagementsToday,
    })
    return { sent: false, reason: 'engajamento já enviado hoje' }
  }

  // Carrega config do agente engajamento
  const { data: prompt } = await supabase
    .from('v_active_prompts')
    .select('*')
    .eq('stage', 'engajamento')
    .single()

  if (!prompt || !prompt.model || prompt.temperature == null) {
    return { sent: false, reason: 'sem prompt engajamento' }
  }

  // Estado do user
  const { data: progress } = await supabase
    .from('user_progress')
    .select('*')
    .eq('user_id', userId)
    .maybeSingle()

  // Metas calóricas + balanço de hoje (snapshot do dia local).
  // Sem isso o LLM ALUCINA valores plausíveis ("2.500 kcal, 160g").
  const todayLocalDate = getLocalDate(userTimezone)
  const calcCfg = await loadCalcConfig(supabase)
  const targets = await loadDailyTargets(supabase, userId, calcCfg)
  const { data: snapToday } = await supabase
    .from('daily_snapshots')
    .select('calories_consumed, protein_g, carbs_g, fat_g, exercise_calories, daily_balance')
    .eq('user_id', userId)
    .eq('date', todayLocalDate)
    .maybeSingle()
  const consumedKcal = (snapToday as { calories_consumed?: number } | null)?.calories_consumed ?? 0
  const consumedProtein = (snapToday as { protein_g?: number } | null)?.protein_g ?? 0
  const exerciseKcal = (snapToday as { exercise_calories?: number } | null)?.exercise_calories ?? 0

  // Snapshot do dia anterior — pra "déficit de ontem" no engajamento da manhã
  const yesterdayDate = new Date(`${todayLocalDate}T00:00:00${tzOffset(userTimezone)}`)
  yesterdayDate.setDate(yesterdayDate.getDate() - 1)
  const yesterdayLocalDate = yesterdayDate.toISOString().slice(0, 10)
  const { data: snapYesterday } = await supabase
    .from('daily_snapshots')
    .select('calories_consumed, calories_target, daily_balance')
    .eq('user_id', userId)
    .eq('date', yesterdayLocalDate)
    .maybeSingle()
  const yesterdayBalance = (snapYesterday as { daily_balance?: number } | null)?.daily_balance

  const targetKcal = targets.calories_target ?? '(não calculado — perfil incompleto)'
  const targetProtein = targets.protein_target ?? '(não calculado — perfil incompleto)'

  // C: contexto rico pro LLM — hora local + REFEIÇÃO típica + DADOS REAIS do paciente
  const userContext = `
Hora local do paciente: ${String(localHour).padStart(2, '0')}:00 (timezone ${userTimezone})
Período do dia: ${slot}
Refeição típica desse horário: ${mealHint}

DADOS REAIS DO DIA — USE ESTES VALORES, NÃO INVENTE:
- Meta calórica de hoje: ${targetKcal} kcal
- Meta de proteína de hoje: ${targetProtein}${typeof targetProtein === 'number' ? ' g' : ''}
- Consumido até agora: ${consumedKcal} kcal | ${consumedProtein} g proteína
- Exercício hoje: ${exerciseKcal} kcal queimadas
${yesterdayBalance != null ? `- Balanço de ONTEM (${yesterdayLocalDate}): ${yesterdayBalance} kcal (negativo = déficit, positivo = superávit)` : '- Sem dados de ontem'}

Streak atual: ${progress?.current_streak ?? 0} dias
XP: ${progress?.xp_total ?? 0} (level ${progress?.level ?? 1})
Última atividade: ${progress?.last_active_date ?? 'nunca'}
Blocos completos: ${progress?.blocks_completed ?? 0}
`.trim()

  const result = await llm.complete({
    model: prompt.model,
    systemPrompt: prompt.system_prompt ?? '',
    messages: [
      {
        role: 'user',
        content:
          `${userContext}\n\nGere uma mensagem curta e motivacional pra esse momento. ` +
          `Use a hora local e a refeição típica acima — NÃO assuma horário pelo nome do slot.`,
      },
    ],
    temperature: Number(prompt.temperature),
    // max_tokens vem de agent_configs (editável em /settings/agents).
    // Fallback 500 só quando registro não tem o campo (não deveria ocorrer).
    maxTokens: Number(prompt.max_tokens ?? 500),
    userId,
    metadata: { Stage: 'engajamento', Slot: slot, LocalHour: String(localHour) },
  })

  const text = (result.content ?? '').trim()
  if (!text) {
    await logEvent('engagement.skipped', { reason: 'LLM vazio' })
    return { sent: false, reason: 'LLM vazio' }
  }

  // ENVIA pelo WhatsApp via messaging provider
  const messaging = createMessagingProvider({
    MESSAGING_PROVIDER: process.env.MESSAGING_PROVIDER ?? 'whatsapp_cloud',
    META_PHONE_NUMBER_ID: process.env.META_PHONE_NUMBER_ID,
    META_ACCESS_TOKEN: process.env.META_ACCESS_TOKEN,
    META_APP_SECRET: process.env.META_APP_SECRET,
    META_VERIFY_TOKEN: process.env.META_VERIFY_TOKEN,
  })

  // Humanizer params editáveis via /settings/global → humanizer.*
  const humanizer = await loadHumanizerConfig(supabase)

  let deliveryStatus: 'sent' | 'failed' = 'sent'
  let deliveryError: string | undefined
  try {
    const sendResults = await sendHumanized(messaging, wpp, text, {
      showTyping: false, // engagement não responde a uma msg recebida
      minDelay: humanizer.min_delay_ms,
      maxDelay: humanizer.max_delay_ms,
      charsPerSecond: humanizer.chars_per_second,
    })
    if (sendResults.some((r) => r.status !== 'sent')) {
      deliveryStatus = 'failed'
      deliveryError = sendResults.find((r) => r.error)?.error
    }
  } catch (e) {
    deliveryStatus = 'failed'
    deliveryError = e instanceof Error ? e.message : String(e)
  }

  // Persiste OUT (com delivery_status real)
  await supabase.from('messages').insert({
    user_id: userId,
    direction: 'out',
    role: 'assistant',
    content_type: 'text',
    content: text,
    provider: process.env.MESSAGING_PROVIDER ?? 'whatsapp_cloud',
    agent_stage: 'engajamento',
    model_used: result.model,
    prompt_tokens: result.promptTokens,
    completion_tokens: result.completionTokens,
    cost_usd: result.costUsd,
    latency_ms: result.latencyMs,
    delivery_status: deliveryStatus,
    delivery_error: deliveryError ? { msg: deliveryError } : null,
    raw_payload: { engagement_slot: slot },
  })

  await logEvent(deliveryStatus === 'sent' ? 'engagement.sent' : 'engagement.failed', {
    chars: text.length,
    cost_usd: result.costUsd,
    model: result.model,
    error: deliveryError,
  })

  return { sent: deliveryStatus === 'sent', reason: deliveryError }
}

/**
 * Janela ativa do paciente, derivada de wake_time/bedtime do user_profiles.
 *
 * Política (offsets editáveis via /settings/global → engagement.*):
 *   - start = wake_time + engagement.wake_offset_min  (default 60min)
 *   - end   = bedtime  - engagement.bed_offset_min   (default 60min)
 *   - sem wake → engagement.fallback_wake_hour (default 6h)
 *   - sem bed  → engagement.fallback_bed_hour  (default 22h)
 *   - suporta janelas que cruzam meia-noite (plantonistas: dorme 04h, acorda 12h)
 */
interface ActiveWindow {
  start: number // hora inteira inclusive
  end: number // hora inteira exclusive
  crossesMidnight: boolean
}

interface SlotDef {
  until_hour: number
  slot: string
  meal_hint: string
}

interface EngagementConfig {
  wake_offset_min: number
  bed_offset_min: number
  fallback_wake_hour: number
  fallback_bed_hour: number
  slots: SlotDef[]
}

const DEFAULT_SLOTS: SlotDef[] = [
  { until_hour: 6, slot: 'madrugada', meal_hint: 'madrugada — não envia' },
  { until_hour: 9, slot: 'cafe_da_manha', meal_hint: 'café da manhã (jejum, primeira refeição do dia)' },
  { until_hour: 11, slot: 'meio_da_manha', meal_hint: 'meio da manhã (lanche entre café e almoço, ou check-in pré-almoço)' },
  { until_hour: 14, slot: 'almoco', meal_hint: 'almoço (refeição principal do meio-dia)' },
  { until_hour: 16, slot: 'pos_almoco', meal_hint: 'pós-almoço (digestão, balanço parcial do dia)' },
  { until_hour: 19, slot: 'lanche_tarde', meal_hint: 'lanche da tarde (entre almoço e jantar)' },
  { until_hour: 22, slot: 'jantar', meal_hint: 'jantar (última refeição do dia)' },
  { until_hour: 24, slot: 'noite', meal_hint: 'noite — não envia' },
]

const DEFAULT_ENGAGEMENT_CONFIG: EngagementConfig = {
  wake_offset_min: 60,
  bed_offset_min: 60,
  fallback_wake_hour: 6,
  fallback_bed_hour: 22,
  slots: DEFAULT_SLOTS,
}

function activeWindow(
  wakeTime: string | null | undefined,
  bedtime: string | null | undefined,
  config: EngagementConfig,
): ActiveWindow {
  const wake = parseHour(wakeTime, config.fallback_wake_hour)
  const bed = parseHour(bedtime, config.fallback_bed_hour)
  const wakeOffsetH = config.wake_offset_min / 60
  const bedOffsetH = config.bed_offset_min / 60
  // Arredonda pra hora inteira mais próxima (round half-up)
  const start = Math.round((wake + wakeOffsetH + 24) % 24)
  const end = Math.round((bed - bedOffsetH + 24) % 24)
  const crossesMidnight = start > end
  return { start, end, crossesMidnight }
}

function isWithinActiveWindow(hour: number, w: ActiveWindow): boolean {
  if (w.crossesMidnight) {
    // janela cruza 00h: fora dela é só [end, start)
    return hour >= w.start || hour < w.end
  }
  return hour >= w.start && hour < w.end
}

/**
 * Carrega config do engagement (offsets + fallbacks + slots) do global_config.
 * Cache 60s — mudanças via UI propagam em ≤1min.
 */
let cachedEngagementConfig: { config: EngagementConfig; expiresAt: number } | null = null
const ENGAGEMENT_CACHE_TTL_MS = 60_000

async function loadEngagementConfig(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  svc: any,
): Promise<EngagementConfig> {
  const now = Date.now()
  if (cachedEngagementConfig && cachedEngagementConfig.expiresAt > now) {
    return cachedEngagementConfig.config
  }

  const { data, error } = (await svc
    .from('global_config')
    .select('key, value')
    .like('key', 'engagement.%')) as { data: Array<{ key: string; value: unknown }> | null; error: unknown }

  if (error || !data || data.length === 0) {
    cachedEngagementConfig = {
      config: DEFAULT_ENGAGEMENT_CONFIG,
      expiresAt: now + ENGAGEMENT_CACHE_TTL_MS,
    }
    return DEFAULT_ENGAGEMENT_CONFIG
  }

  const merged: EngagementConfig = { ...DEFAULT_ENGAGEMENT_CONFIG, slots: [...DEFAULT_SLOTS] }
  for (const row of data) {
    const subKey = row.key.replace(/^engagement\./, '')
    if (subKey === 'slots' && Array.isArray(row.value)) {
      // Valida shape básico antes de aceitar
      const slots = (row.value as unknown[]).filter(
        (s): s is SlotDef =>
          typeof s === 'object' &&
          s !== null &&
          typeof (s as SlotDef).until_hour === 'number' &&
          typeof (s as SlotDef).slot === 'string' &&
          typeof (s as SlotDef).meal_hint === 'string',
      )
      if (slots.length > 0) merged.slots = slots
    } else if (subKey in DEFAULT_ENGAGEMENT_CONFIG && subKey !== 'slots') {
      const num = Number(row.value)
      if (Number.isFinite(num)) {
        ;(merged as unknown as Record<string, number>)[subKey] = num
      }
    }
  }

  cachedEngagementConfig = { config: merged, expiresAt: now + ENGAGEMENT_CACHE_TTL_MS }
  return merged
}

/**
 * Resolve slot + meal_hint pra hora local atual usando config dinâmico.
 * Percorre slots (ordenados por until_hour ASC) e retorna o 1º cuja
 * until_hour > hour. Fallback pro último.
 */
function resolveSlot(hour: number, slots: SlotDef[]): { slot: string; meal_hint: string } {
  // Ordena defensivamente — se admin mexer e desordenar, ainda funciona
  const sorted = [...slots].sort((a, b) => a.until_hour - b.until_hour)
  for (const s of sorted) {
    if (hour < s.until_hour) return { slot: s.slot, meal_hint: s.meal_hint }
  }
  const last = sorted[sorted.length - 1]
  return last
    ? { slot: last.slot, meal_hint: last.meal_hint }
    : { slot: 'desconhecido', meal_hint: '' }
}

function parseHour(timeStr: string | null | undefined, fallback: number): number {
  if (!timeStr) return fallback
  const m = timeStr.match(/^(\d{1,2})/)
  if (!m || !m[1]) return fallback
  const h = Number(m[1])
  return Number.isFinite(h) && h >= 0 && h <= 23 ? h : fallback
}

// Helpers de timezone agora vêm de @mpp/agent (timezone-utils.ts).
const getLocalDate = getLocalDateString
const tzOffset = getTzOffset
