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
import { inngest } from '../client.js'
import { createWorkerDeps } from '../lib/env.js'
import { getTodayTraining } from '@mpp/agent'

const DAY_LABELS = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sab'] as const

function dayLabel(date: Date, timezone: string): string {
  const fmt = new Intl.DateTimeFormat('en-US', {
    timeZone: timezone,
    weekday: 'short',
  })
  const en = fmt.format(date).toLowerCase()
  const map: Record<string, (typeof DAY_LABELS)[number]> = {
    sun: 'dom',
    mon: 'seg',
    tue: 'ter',
    wed: 'qua',
    thu: 'qui',
    fri: 'sex',
    sat: 'sab',
  }
  return map[en] ?? 'seg'
}

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

function getLocalHour(now: Date, timezone: string): number | null {
  try {
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone: timezone,
      hour: '2-digit',
      hour12: false,
    }).formatToParts(now)
    const h = parts.find((p) => p.type === 'hour')?.value
    if (!h) return null
    const n = parseInt(h, 10)
    return Number.isFinite(n) ? n : null
  } catch {
    return null
  }
}

export const trainingDailyDeliveryFn = inngest.createFunction(
  { id: 'training-daily-delivery', retries: 1 },
  // Roda a cada hora cheia em UTC. Pra cada paciente, calcula a hora local
  // do TZ dele e só envia se bate com training_delivery_hour (default 7).
  // Vale pra qualquer fuso — paciente em Lisboa recebe 7h Lisboa, em
  // Tóquio recebe 7h Tóquio.
  { cron: '0 * * * *' },
  async ({ step, logger }) => {
    const deps = createWorkerDeps()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const sp = deps.supabase as any

    // Lista de testers UUIDs vem do global_config (não hardcoded). Permite
    // expandir/contrair rollout sem deploy.
    const testerUserIds = await step.run('load-testers', async () => {
      const { data } = await sp
        .from('global_config')
        .select('value')
        .eq('key', 'training_reminders.tester_user_ids')
        .maybeSingle()
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
        logger.error({ error }, 'training-daily: list candidates failed')
        return []
      }
      return (data ?? []) as Array<{
        id: string
        wpp: string
        name: string
        timezone: string | null
        metadata: Record<string, unknown> | null
      }>
    })

    const token = process.env.WHATSAPP_CLOUD_TOKEN
    const phoneId = process.env.WHATSAPP_CLOUD_PHONE_ID
    if (!token || !phoneId) {
      logger.warn({}, 'training-daily: WPP creds missing')
      return { sent: 0, candidates: candidates.length, reason: 'wpp_creds_missing' }
    }

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
      const localHour = getLocalHour(new Date(), tz)
      const targetHour =
        typeof meta?.training_delivery_hour === 'number' &&
        meta.training_delivery_hour >= 0 &&
        meta.training_delivery_hour <= 23
          ? meta.training_delivery_hour
          : DEFAULT_DELIVERY_HOUR
      if (localHour !== targetHour) continue

      await step.run(`deliver-${cand.id}`, async () => {
        // Dedup intra-dia: janela de 22h (defensivo — o dedup primário é o
        // filtro localHour===targetHour que só matches 1×/dia por paciente).
        // Coluna correta é `occurred_at` (não created_at).
        const sinceIso = new Date(Date.now() - 22 * 3600 * 1000).toISOString()
        const { data: already } = await sp
          .from('product_events')
          .select('id')
          .eq('user_id', cand.id)
          .in('event', ['training.daily_dispatching', 'training.daily_delivered'])
          .gte('occurred_at', sinceIso)
          .limit(1)
        if ((already ?? []).length > 0) return

        let todayLabelStr: string
        try {
          todayLabelStr = dayLabel(new Date(), tz)
        } catch {
          // Timezone inválido em users.timezone — loga e segue com SP
          await sp.from('product_events').insert({
            user_id: cand.id,
            event: 'training.daily.timezone_invalid',
            properties: { timezone: tz },
          })
          todayLabelStr = dayLabel(new Date(), 'America/Sao_Paulo')
        }
        const todayPlan = await getTodayTraining(deps.supabase, cand.id, todayLabelStr)
        if (!todayPlan) return

        // Idempotência: registra "em dispatch" ANTES do fetch. Se step
        // crashar entre fetch e o delivered event, o retry vê esse marker
        // e pula — evita re-envio. Custo: 1 event extra por entrega.
        await sp.from('product_events').insert({
          user_id: cand.id,
          event: 'training.daily_dispatching',
          properties: {
            plan_id: todayPlan.plan_id,
            day_label: todayLabelStr,
          },
        })

        const text = formatTraining(todayPlan.day as TrainingDay)
        let providerMessageId: string | null = null

        try {
          const res = await fetch(`https://graph.facebook.com/v18.0/${phoneId}/messages`, {
            method: 'POST',
            headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({
              messaging_product: 'whatsapp',
              to: cand.wpp,
              type: 'text',
              text: { body: text },
            }),
          })
          const ok = res.ok
          if (ok) {
            const j = (await res.json().catch(() => null)) as {
              messages?: Array<{ id?: string }>
            } | null
            providerMessageId = j?.messages?.[0]?.id ?? null
          }

          await sp.from('product_events').insert({
            user_id: cand.id,
            event: 'training.daily_delivered',
            properties: {
              plan_id: todayPlan.plan_id,
              day_label: todayLabelStr,
              focus: todayPlan.day.focus,
              exercises_count: todayPlan.day.exercises.length,
              ok,
            },
          })
          if (ok) {
            // role é NOT NULL em messages — sempre 'assistant' pra outbound do agente.
            await sp.from('messages').insert({
              user_id: cand.id,
              direction: 'out',
              role: 'assistant',
              content_type: 'text',
              content: text,
              provider: 'whatsapp_cloud',
              provider_message_id: providerMessageId,
              agent_stage: 'training-daily',
              delivery_status: 'delivered',
            })
            sent++
          }
        } catch (err) {
          logger.error({ user_id: cand.id, err }, 'training-daily: send failed')
        }
      })
    }

    return { sent, candidates: candidates.length }
  },
)
