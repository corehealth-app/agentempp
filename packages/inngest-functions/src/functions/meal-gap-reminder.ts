/**
 * Lembretes proativos de gap de refeição (Amanda 2026-06-11 sugeriu via áudio).
 *
 * Cron a cada hora cheia em janela ativa (10-19h BRT padrão). Para cada
 * paciente com `users.metadata.proactive_reminders = true` (opt-in):
 *   - Calcula gap em horas desde último meal_log
 *   - Se gap >= 4h E paciente não está dormindo (last_active < 90min)
 *     E não recebeu lembrete nas últimas 4h E ainda não passou de 2 lembretes
 *     hoje E está abaixo de 60% da meta de proteína
 *     → envia mensagem determinística (SEM LLM, custo zero)
 *
 * Texto curto, neutro, sem moralizar. Variação simples por horário (manhã/tarde).
 *
 * Limites:
 *   - 2 lembretes/dia máximo
 *   - Nunca antes das 10h ou depois das 20h local
 *   - Cooldown de 4h entre lembretes
 *   - Skip se paciente mandou mensagem nas últimas 60min (já está engajado)
 */
import { getLocalDateString, getLocalDayUtcBounds, getLocalHour } from '@mpp/agent'
import type { ServiceClient } from '@mpp/db'
import { createMessagingProvider } from '@mpp/providers'
import { inngest } from '../client.js'
import { createWorkerDeps } from '../lib/env.js'
import { buildOutboundMessageRows } from './outbound-message-rows.js'
import { persistOutboundMessage } from './outbound-message-persistence.js'
import { classifyGapReminderDelivery } from './daily-gap-delivery.js'
import { isProactiveReminderHour } from './proactive-reminder-policy.js'

const GAP_MIN_HOURS = 4
const COOLDOWN_HOURS = 4
const MAX_PER_DAY = 2
const SKIP_IF_USER_MSG_LAST_MIN = 60

const REMINDERS: Record<string, string[]> = {
  morning: [
    'Oi, {name}! Já são {hour}h e ainda não vi nenhuma refeição registrada hoje. Comeu algo?',
    'Bom dia, {name}. Lembrete leve: tá perto do almoço e o café ainda não apareceu por aqui. Manda quando comer.',
    '{name}, já faz {gap}h desde sua última refeição. Hora de uma fruta ou um lanche proteico?',
  ],
  afternoon: [
    '{name}, já faz {gap}h desde sua última refeição registrada. Que tal um lanche com proteína?',
    'Oi {name}, lembrete amigável: passou da hora do lanche da tarde. Comeu algo?',
    '{name}, sua proteína hoje está em {protein_pct}%. Um shake ou iogurte ajudam a recuperar.',
  ],
  evening: [
    '{name}, tô vendo que ainda faltam {protein_remaining}g de proteína pra meta hoje. Jantar reforçado ajuda.',
    '{name}, jantar não apareceu ainda. Manda quando comer pra eu fechar o dia direitinho.',
  ],
}

function pickReminder(
  slot: 'morning' | 'afternoon' | 'evening',
  referenceTimestamp: Date,
): string {
  const pool = REMINDERS[slot] ?? REMINDERS.morning ?? ['Lembrete']
  const idx = Math.floor(referenceTimestamp.getTime() / 60000) % pool.length
  return pool[idx] ?? 'Lembrete'
}

function renderText(template: string, vars: Record<string, string | number>): string {
  return template.replace(/\{(\w+)\}/g, (_, k) => String(vars[k] ?? ''))
}

export const mealGapReminderFn = inngest.createFunction(
  { id: 'meal-gap-reminder', retries: 1, concurrency: { limit: 1 } },
  // Roda globalmente a cada hora; cada paciente é filtrado no próprio fuso.
  { cron: '0 * * * *' },
  async ({ event, step, logger }) => {
    const { supabase } = createWorkerDeps()
    const eventTimestamp = new Date(event.ts ?? Date.now())
    const referenceTimestamp = Number.isFinite(eventTimestamp.getTime())
      ? eventTimestamp
      : new Date()
    const eventKey = event.id ?? `proactive:${referenceTimestamp.toISOString()}`

    // 1. Lista pacientes opt-in
    const optInPatients = await step.run('list-opt-in', async () => {
      const { data, error } = await supabase
        .from('users')
        .select('id, wpp, name, timezone, metadata')
        .eq('status', 'active')
      if (error) throw new Error(error.message ?? 'proactive users lookup failed')
      const rows = ((data ?? []) as Array<{
        id: string
        wpp: string
        name: string | null
        timezone: string | null
        metadata: Record<string, unknown> | null
      }>).filter(
        (u) => (u.metadata as { proactive_reminders?: boolean } | null)?.proactive_reminders === true,
      )
      return rows
    })

    if (optInPatients.length === 0) {
      logger.info('nenhum paciente opt-in pra lembretes proativos')
      return { sent: 0, total: 0 }
    }

    let sent = 0
    for (const u of optInPatients) {
      const prepared = await step.run(`proactive-prepare-${u.id}`, async () =>
        preparePatientReminder(
          supabase,
          u.id,
          u.name ?? '',
          u.timezone ?? 'America/Sao_Paulo',
          referenceTimestamp,
          `${eventKey}:${u.id}`,
        ),
      )
      if (prepared.status !== 'ready') continue

      const delivery = await step.run(`proactive-send-${u.id}`, async () => {
        const messaging = createMessagingProvider({
          MESSAGING_PROVIDER: process.env.MESSAGING_PROVIDER ?? 'whatsapp_cloud',
          META_PHONE_NUMBER_ID: process.env.META_PHONE_NUMBER_ID,
          META_ACCESS_TOKEN: process.env.META_ACCESS_TOKEN,
          META_APP_SECRET: process.env.META_APP_SECRET,
          META_VERIFY_TOKEN: process.env.META_VERIFY_TOKEN,
        })
        try {
          const result = await messaging.sendText(u.wpp, prepared.text)
          return classifyGapReminderDelivery([result], new Date().toISOString())
        } catch (error) {
          return {
            sent: false as const,
            error: error instanceof Error ? error.message : String(error),
          }
        }
      })

      if (!delivery.sent) {
        logger.warn('proactive reminder delivery failed', {
          userId: u.id,
          error: delivery.error,
        })
        continue
      }

      await step.run(`proactive-persist-${u.id}`, async () => {
        const provider = process.env.MESSAGING_PROVIDER ?? 'whatsapp_cloud'
        const [row] = buildOutboundMessageRows({
          userId: u.id,
          provider,
          contentType: 'text',
          stage: 'engajamento',
          modelUsed: null,
          promptTokens: null,
          completionTokens: null,
          costUsd: null,
          latencyMs: null,
          metadata: {
            source: 'proactive_reminder',
            dedupe_key: prepared.dedupeKey,
            local_date: prepared.localDate,
            slot: prepared.slot,
          },
          deliveries: [
            {
              content: prepared.text,
              providerMessageId: delivery.providerMessageId,
              status: 'sent',
            },
          ],
        })
        if (!row) throw new Error('proactive outbound row missing')
        await persistOutboundMessage(supabase, row)

        const { data: existingEvent, error: existingEventError } = await supabase
          .from('product_events')
          .select('id')
          .eq('event', 'proactive.reminder_sent')
          .filter('properties->>dedupe_key', 'eq', prepared.dedupeKey)
          .limit(1)
        if (existingEventError) {
          throw new Error(existingEventError.message ?? 'proactive event lookup failed')
        }
        if ((existingEvent ?? []).length === 0) {
          const { error: eventError } = await supabase.from('product_events').insert({
            user_id: u.id,
            event: 'proactive.reminder_sent',
            occurred_at: delivery.sentAt,
            properties: {
              dedupe_key: prepared.dedupeKey,
              slot: prepared.slot,
              gap_hours: prepared.gapHours,
              protein_pct: prepared.proteinPct,
              local_hour: prepared.localHour,
              local_date: prepared.localDate,
              ok: true,
            },
          })
          if (eventError) {
            throw new Error(eventError.message ?? 'proactive event persistence failed')
          }
        }
        return { persisted: true }
      })
      sent++
    }

    return { sent, total: optInPatients.length }
  },
)

type PreparedProactiveReminder =
  | {
      status: 'ready'
      text: string
      slot: 'morning' | 'afternoon' | 'evening'
      gapHours: number
      proteinPct: number
      localHour: number
      localDate: string
      dedupeKey: string
    }
  | { status: 'skipped'; reason: string }

async function preparePatientReminder(
  supabase: ServiceClient,
  userId: string,
  name: string,
  timezone: string,
  referenceTimestamp: Date,
  dedupeKey: string,
): Promise<PreparedProactiveReminder> {
  const nowMs = referenceTimestamp.getTime()
  const localHour = getLocalHour(timezone, referenceTimestamp)
  if (!isProactiveReminderHour(localHour)) {
    return { status: 'skipped', reason: 'fora_janela_ativa' }
  }

  // Skip se paciente mandou msg nos últimos N min (já engajado)
  const sinceUserMsg = new Date(nowMs - SKIP_IF_USER_MSG_LAST_MIN * 60 * 1000).toISOString()
  const { data: recentUserMsg, error: recentUserMessageError } = await supabase
    .from('messages')
    .select('id')
    .eq('user_id', userId)
    .eq('direction', 'in')
    .gte('created_at', sinceUserMsg)
    .limit(1)
  if (recentUserMessageError) {
    throw new Error(recentUserMessageError.message ?? 'recent user message lookup failed')
  }
  if (Array.isArray(recentUserMsg) && recentUserMsg.length > 0) {
    return { status: 'skipped', reason: 'usuario_engajado_recentemente' }
  }

  // Cooldown — não enviar se já enviei lembrete nas últimas N horas
  const sinceCooldown = new Date(nowMs - COOLDOWN_HOURS * 60 * 60 * 1000).toISOString()
  const { data: recentRem, error: recentReminderError } = await supabase
    .from('product_events')
    .select('id, occurred_at')
    .eq('user_id', userId)
    .eq('event', 'proactive.reminder_sent')
    .filter('properties->>ok', 'eq', 'true')
    .gte('occurred_at', sinceCooldown)
  if (recentReminderError) {
    throw new Error(recentReminderError.message ?? 'proactive cooldown lookup failed')
  }
  if (Array.isArray(recentRem) && recentRem.length > 0) {
    return { status: 'skipped', reason: 'cooldown' }
  }

  // Quota diária — máximo MAX_PER_DAY
  const localDate = getLocalDateString(timezone, referenceTimestamp)
  const { startIso, endExclusiveIso } = getLocalDayUtcBounds(timezone, localDate)
  const { data: dayRem, error: dayReminderError } = await supabase
    .from('product_events')
    .select('id')
    .eq('user_id', userId)
    .eq('event', 'proactive.reminder_sent')
    .filter('properties->>ok', 'eq', 'true')
    .gte('occurred_at', startIso)
    .lt('occurred_at', endExclusiveIso)
  if (dayReminderError) {
    throw new Error(dayReminderError.message ?? 'proactive daily quota lookup failed')
  }
  if (Array.isArray(dayRem) && dayRem.length >= MAX_PER_DAY) {
    return { status: 'skipped', reason: 'quota_diaria_atingida' }
  }

  // Gap de refeição
  const { data: lastMeal, error: lastMealError } = await supabase
    .from('meal_logs')
    .select('created_at')
    .eq('user_id', userId)
    .order('created_at', { ascending: false })
    .limit(1)
  if (lastMealError) throw new Error(lastMealError.message ?? 'last meal lookup failed')
  const lastMealAt = (lastMeal?.[0]?.created_at as string | undefined) ?? null
  const gapHours = lastMealAt
    ? (nowMs - new Date(lastMealAt).getTime()) / 3600000
    : 99
  if (gapHours < GAP_MIN_HOURS) {
    return { status: 'skipped', reason: 'gap_insuficiente' }
  }

  // Snapshot proteína hoje
  const { data: snap, error: snapshotError } = await supabase
    .from('daily_snapshots')
    .select('protein_g, protein_target')
    .eq('user_id', userId)
    .eq('date', localDate)
    .maybeSingle()
  if (snapshotError) {
    throw new Error(snapshotError.message ?? 'proactive snapshot lookup failed')
  }
  const proteinTarget = Number(snap?.protein_target ?? 0)
  const proteinConsumed = Number(snap?.protein_g ?? 0)
  const proteinPct =
    proteinTarget > 0 ? Math.round((proteinConsumed / proteinTarget) * 100) : 0
  const proteinRemaining =
    proteinTarget > 0 ? Math.max(0, Math.round(proteinTarget - proteinConsumed)) : 0

  // Só envia se proteína abaixo de 60% — sinal real de baixa ingestão
  if (proteinPct >= 60) {
    return { status: 'skipped', reason: 'proteina_ok' }
  }

  // Escolhe slot por hora local
  const slot: 'morning' | 'afternoon' | 'evening' =
    localHour < 12 ? 'morning' : localHour < 17 ? 'afternoon' : 'evening'
  const tpl = pickReminder(slot, referenceTimestamp)
  const text = renderText(tpl, {
    name: name.split(' ')[0] ?? '',
    hour: localHour,
    gap: Math.round(gapHours),
    protein_pct: proteinPct,
    protein_remaining: proteinRemaining,
  })
  return {
    status: 'ready',
    text,
    slot,
    gapHours: Math.round(gapHours),
    proteinPct,
    localHour,
    localDate,
    dedupeKey,
  }
}
