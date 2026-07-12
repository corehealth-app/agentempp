/**
 * Entrega diária do treino (Sprint 4.2b — Roberto pediu 2026-06-11 via áudio).
 *
 * Cron `0 * * * *` (hora cheia UTC). Pra cada paciente com plano ativo em
 * `training_plans`:
 *   - Calcula hora local do timezone do user; só envia quando hora == target
 *     (DEFAULT_DELIVERY_HOUR=7 ou metadata.training_delivery_hour custom).
 *   - Calcula dia da semana local e busca `getTodayTraining(supabase, user_id, dia_label)`.
 *   - Se hoje é dia de treino → envia mensagem determinística com o resumo.
 *   - Se NÃO é dia de treino → silêncio (não polui).
 *
 * SEM LLM. Custo zero. Plano é gerado UMA vez via tool `gera_treino`, cron só
 * entrega o que está em `training_plans.weekly_schedule`.
 *
 * Anti-spam:
 *   - Só envia se paciente tiver `users.metadata.training_reminders = true`
 *     (opt-in específico — NÃO usa proactive_reminders, que é só pra refeição).
 *     A flag é ativada automaticamente quando saveTrainingPlan persiste um
 *     plano. Lista de testers vem de `global_config` (chave
 *     `training_reminders.tester_user_ids`) — controla rollout sem deploy.
 *   - Skip se já recebeu treino nas últimas 22h (event `training.daily_delivered`).
 */
import { getTodayTraining } from '@mpp/agent'
import { createMessagingProvider } from '@mpp/providers'
import { inngest } from '../client.js'
import { createWorkerDeps } from '../lib/env.js'
import { classifyGapReminderDelivery } from './daily-gap-delivery.js'
import { buildOutboundMessageRows } from './outbound-message-rows.js'
import { persistOutboundMessage } from './outbound-message-persistence.js'
import { resolveTrainingDeliveryClock } from './training-delivery-time.js'

interface TrainingDay {
  day: string
  focus: string
  duration_min: number
  exercises: Array<{
    name: string
    muscle_group: string
    sets: number
    reps_range: string
    rest_seconds: number
    rpe_target?: string
    notes?: string
    execution_steps?: string[]
  }>
}

function formatTraining(day: TrainingDay): string {
  const lines: string[] = []
  lines.push(`*Treino de hoje — ${day.focus}* (~${day.duration_min}min)`)
  lines.push('')
  for (const ex of day.exercises) {
    lines.push(`• *${ex.name}* (${ex.muscle_group})`)
    lines.push(
      `  ${ex.sets} séries × ${ex.reps_range} reps — descanso ${ex.rest_seconds}s${
        ex.rpe_target ? ` — ${ex.rpe_target}` : ''
      }`,
    )
    if (ex.notes) lines.push(`  ${ex.notes}`)
  }
  lines.push('')
  lines.push('Quando terminar, me manda "treino feito" ou registra com detalhes.')
  return lines.join('\n')
}

/**
 * Hora local em que o cron entrega. Por padrão 7h da manhã no TZ do
 * paciente. Pra customizar por paciente: users.metadata.training_delivery_hour
 * (0-23). Hora cheia única — só dispara quando localHour === target.
 */
const DEFAULT_DELIVERY_HOUR = 7

export const trainingDailyDeliveryFn = inngest.createFunction(
  { id: 'training-daily-delivery', retries: 1, concurrency: { limit: 1 } },
  // Roda a cada hora cheia em UTC. Pra cada paciente, calcula a hora local
  // do TZ dele e só envia se bate com training_delivery_hour (default 7).
  // Vale pra qualquer fuso — paciente em Lisboa recebe 7h Lisboa, em
  // Tóquio recebe 7h Tóquio.
  { cron: '0 * * * *' },
  async ({ event, step, logger }) => {
    const deps = createWorkerDeps()
    const sp = deps.supabase
    const eventTimestamp = new Date(event.ts ?? Date.now())
    const referenceTimestamp = Number.isFinite(eventTimestamp.getTime())
      ? eventTimestamp
      : new Date()

    // Lista de testers UUIDs vem do global_config (não hardcoded). Permite
    // expandir/contrair rollout sem deploy.
    const testerUserIds = await step.run('load-testers', async () => {
      const { data, error } = await sp
        .from('global_config')
        .select('value')
        .eq('key', 'training_reminders.tester_user_ids')
        .maybeSingle()
      if (error) throw new Error(error.message ?? 'training testers lookup failed')
      const v = (data as { value?: string[] } | null)?.value
      return Array.isArray(v) ? v : []
    })

    const candidates = await step.run('list-candidates', async () => {
      const { data, error } = await sp
        .from('users')
        .select(
          'id, wpp, name, timezone, metadata, training_plans!inner(id, active)',
        )
        .eq('status', 'active')
        .eq('training_plans.active', true)
      if (error) {
        throw new Error(error.message ?? 'training candidates lookup failed')
      }
      const rows = (data ?? []) as Array<{
        id: string
        wpp: string
        name: string
        timezone: string | null
        metadata: Record<string, unknown> | null
      }>
      return Array.from(new Map(rows.map((row) => [row.id, row])).values())
    })

    let sent = 0
    for (const cand of candidates) {
      // Opt-in específico pra treino: NÃO usa proactive_reminders (que é só
      // pra refeição). saveTrainingPlan seta metadata.training_reminders=true
      // automaticamente quando paciente acabou de gerar plano. Lista de
      // testers vem de global_config (chave training_reminders.tester_user_ids)
      // pra rollout controlado sem deploy. Sem opt-in nem tester → não envia.
      const meta = (cand.metadata as
        | { training_reminders?: boolean; training_delivery_hour?: number }
        | null) ?? null
      const explicitOptIn = meta?.training_reminders === true
      const isTester = testerUserIds.includes(cand.id)
      const optIn = explicitOptIn || isTester
      if (!optIn) continue

      // Só dispara quando a hora local do paciente == hora alvo. Cron roda
      // a cada hora, então pra qualquer fuso a janela é 1h. Default 7h.
      const tz = cand.timezone ?? 'America/Sao_Paulo'
      const clock = resolveTrainingDeliveryClock(referenceTimestamp, tz)
      if (!clock) {
        logger.warn({ user_id: cand.id, timezone: tz }, 'training-daily: invalid timezone')
        continue
      }
      const targetHour =
        typeof meta?.training_delivery_hour === 'number' &&
        meta.training_delivery_hour >= 0 &&
        meta.training_delivery_hour <= 23
          ? meta.training_delivery_hour
          : DEFAULT_DELIVERY_HOUR
      if (clock.localHour !== targetHour) continue

      const prepared = await step.run(`training-prepare-${cand.id}`, async () => {
        const { data: already, error: alreadyError } = await sp
          .from('product_events')
          .select('id')
          .eq('user_id', cand.id)
          .eq('event', 'training.daily_delivered')
          .filter('properties->>local_date', 'eq', clock.localDate)
          .filter('properties->>ok', 'eq', 'true')
          .limit(1)
        if (alreadyError) {
          throw new Error(alreadyError.message ?? 'training delivery dedupe lookup failed')
        }
        if ((already ?? []).length > 0) return null

        const todayPlan = await getTodayTraining(
          deps.supabase,
          cand.id,
          clock.dayLabel,
        )
        if (!todayPlan) return null
        return {
          planId: todayPlan.plan_id,
          day: todayPlan.day as TrainingDay,
          text: formatTraining(todayPlan.day as TrainingDay),
          dedupeKey: `training:${cand.id}:${clock.localDate}:${todayPlan.plan_id}`,
        }
      })
      if (!prepared) continue

      const delivery = await step.run(`training-send-${cand.id}`, async () => {
        const messaging = createMessagingProvider({
          MESSAGING_PROVIDER: process.env.MESSAGING_PROVIDER ?? 'whatsapp_cloud',
          META_PHONE_NUMBER_ID: process.env.META_PHONE_NUMBER_ID,
          META_ACCESS_TOKEN: process.env.META_ACCESS_TOKEN,
          META_APP_SECRET: process.env.META_APP_SECRET,
          META_VERIFY_TOKEN: process.env.META_VERIFY_TOKEN,
        })
        try {
          const result = await messaging.sendText(cand.wpp, prepared.text)
          return classifyGapReminderDelivery([result], new Date().toISOString())
        } catch (error) {
          return {
            sent: false as const,
            error: error instanceof Error ? error.message : String(error),
          }
        }
      })
      if (!delivery.sent) {
        logger.warn(
          { user_id: cand.id, error: delivery.error },
          'training-daily: send failed',
        )
        continue
      }

      await step.run(`training-persist-${cand.id}`, async () => {
        const provider = process.env.MESSAGING_PROVIDER ?? 'whatsapp_cloud'
        const [row] = buildOutboundMessageRows({
          userId: cand.id,
          provider,
          contentType: 'text',
          stage: 'training-daily',
          modelUsed: null,
          promptTokens: null,
          completionTokens: null,
          costUsd: null,
          latencyMs: null,
          metadata: {
            source: 'training_daily_delivery',
            dedupe_key: prepared.dedupeKey,
            local_date: clock.localDate,
            plan_id: prepared.planId,
          },
          deliveries: [
            {
              content: prepared.text,
              providerMessageId: delivery.providerMessageId,
              status: 'sent',
            },
          ],
        })
        if (!row) throw new Error('training outbound row missing')
        await persistOutboundMessage(deps.supabase, row)

        const { data: existingEvent, error: existingEventError } = await sp
          .from('product_events')
          .select('id')
          .eq('event', 'training.daily_delivered')
          .filter('properties->>dedupe_key', 'eq', prepared.dedupeKey)
          .limit(1)
        if (existingEventError) {
          throw new Error(existingEventError.message ?? 'training event lookup failed')
        }
        if ((existingEvent ?? []).length === 0) {
          const { error: eventError } = await sp.from('product_events').insert({
            user_id: cand.id,
            event: 'training.daily_delivered',
            occurred_at: delivery.sentAt,
            properties: {
              dedupe_key: prepared.dedupeKey,
              plan_id: prepared.planId,
              day_label: clock.dayLabel,
              local_date: clock.localDate,
              focus: prepared.day.focus,
              exercises_count: prepared.day.exercises.length,
              ok: true,
            },
          })
          if (eventError) {
            throw new Error(eventError.message ?? 'training event persistence failed')
          }
        }
        return { persisted: true }
      })
      sent++
    }

    return { sent, candidates: candidates.length }
  },
)
