import { getGapForDate, getLocalDateString, getLocalHour, type MealType } from '@mpp/agent'
import { createMessagingProvider, sendHumanized } from '@mpp/providers'
import { inngest } from '../client.js'
import { createWorkerDeps } from '../lib/env.js'
import { classifyGapReminderDelivery } from './daily-gap-delivery.js'

/**
 * Worker: detector de "esqueceu de registrar refeição" pré-fechamento.
 *
 * Roberto levantou (2026-05-16): paciente registra café+almoço mas esquece
 * de registrar jantar. Bloco 7700 atual creditava falsamente como déficit,
 * quando na verdade ele só esqueceu de logar. Vira gamificação enganosa.
 *
 * Fluxo:
 *   1. Ouve `day.close.tick` (mesmo evento do daily-closer, cron horário 24x).
 *   2. Pra cada user, se localHour ∈ [21, 22, 23] → janela do gap-check.
 *   3. Compara o que ele registrou hoje vs padrão dos últimos 14d.
 *   4. Se há refeição esperada faltando E ainda não mandou lembrete hoje:
 *      - Envia 1 msg ("comeu jantar? se sim, manda. se não, responde 'pulei'")
 *      - Seta day_status='pending_close' + gap_reminder_sent_at=now()
 *   5. Daily-closer (0h-4h local) respeita day_status: se ainda pending_close
 *      e gap continua, marca incomplete_no_response → NÃO credita bloco 7700.
 *
 * Idempotência: gap_reminder_sent_at IS NOT NULL = não manda de novo.
 * Concurrency=5 (igual daily-closer).
 */
export const dailyGapCheckerFn = inngest.createFunction(
  { id: 'daily-gap-checker', retries: 1, concurrency: { limit: 5 } },
  { event: 'day.close.tick' },
  async ({ event, step, logger }) => {
    const firedAtRaw = (event.data as { fired_at?: string }).fired_at
    const firedAt = firedAtRaw ? new Date(firedAtRaw) : new Date()
    const referenceTimestamp = Number.isFinite(firedAt.getTime()) ? firedAt : new Date()
    const claimKey = event.id ?? `day-close:${referenceTimestamp.toISOString()}`
    const users = await step.run('list-users-gap', async () => {
      const { supabase } = createWorkerDeps()
      const { data, error } = await supabase
        .from('users')
        .select('id, timezone, wpp, name')
        .eq('status', 'active')
      if (error) throw new Error(error.message ?? 'gap users lookup failed')
      return data ?? []
    })

    let checked = 0
    let reminded = 0
    let skipped = 0

    for (const user of users as Array<{ id: string; timezone: string | null; wpp: string; name: string | null }>) {
      const prepared = await step.run(`gap-prepare-${user.id}`, async () =>
        prepareUserGap(
          user.id,
          user.timezone ?? 'America/Sao_Paulo',
          user.name ?? 'você',
          claimKey,
          referenceTimestamp,
        ),
      )
      checked++
      if (prepared.status !== 'claimed') {
        skipped++
        continue
      }

      const delivery = await step.run(
        `gap-send-${user.id}-${prepared.attemptId}`,
        async () => {
          const messaging = createMessagingProvider({
            MESSAGING_PROVIDER: process.env.MESSAGING_PROVIDER ?? 'whatsapp_cloud',
            META_PHONE_NUMBER_ID: process.env.META_PHONE_NUMBER_ID,
            META_ACCESS_TOKEN: process.env.META_ACCESS_TOKEN,
            META_APP_SECRET: process.env.META_APP_SECRET,
            META_VERIFY_TOKEN: process.env.META_VERIFY_TOKEN,
          })
          try {
            const results = await sendHumanized(messaging, user.wpp, prepared.text, {
              showTyping: false,
              minDelay: 500,
              maxDelay: 1500,
              charsPerSecond: 60,
              singleMessage: true,
            })
            return classifyGapReminderDelivery(results, new Date().toISOString())
          } catch (error) {
            return {
              sent: false as const,
              error: error instanceof Error ? error.message : String(error),
            }
          }
        },
      )

      if (!delivery.sent) {
        await step.run(`gap-fail-${user.id}-${prepared.attemptId}`, async () => {
          const { supabase } = createWorkerDeps()
          const { data, error } = await (
            supabase as unknown as {
              rpc: (
                name: string,
                params: Record<string, unknown>,
              ) => Promise<{ data: boolean | null; error: { message?: string } | null }>
            }
          ).rpc('fail_daily_gap_reminder', {
            p_attempt_id: prepared.attemptId,
            p_claim_key: claimKey,
            p_error: delivery.error,
            p_now: new Date().toISOString(),
          })
          if (error) throw new Error(error.message ?? 'gap reminder failure write failed')
          return { markedFailed: data === true }
        })
        logger.warn('gap reminder delivery failed', {
          userId: user.id,
          error: delivery.error,
        })
        skipped++
        continue
      }

      await step.run(`gap-finalize-${user.id}-${prepared.attemptId}`, async () => {
        const { supabase } = createWorkerDeps()
        const { data, error } = await (
          supabase as unknown as {
            rpc: (
              name: string,
              params: Record<string, unknown>,
            ) => Promise<{
              data: { applied?: boolean; status?: string } | null
              error: { message?: string } | null
            }>
          }
        ).rpc('finalize_daily_gap_reminder', {
          p_attempt_id: prepared.attemptId,
          p_claim_key: claimKey,
          p_provider: process.env.MESSAGING_PROVIDER ?? 'whatsapp_cloud',
          p_provider_message_id: delivery.providerMessageId,
          p_content: prepared.text,
          p_sent_at: delivery.sentAt,
          p_pattern_days: prepared.patternActiveDays,
          p_local_hour: prepared.localHour,
        })
        if (error) throw new Error(error.message ?? 'gap reminder finalization failed')
        return data ?? { applied: false, status: 'missing_result' }
      })
      reminded++
    }

    return { checked, reminded, skipped, total: users.length }
  },
)

type PreparedGap =
  | {
      status: 'claimed'
      attemptId: string
      text: string
      patternActiveDays: number
      localHour: number
    }
  | { status: 'skipped'; reason: string }

async function prepareUserGap(
  userId: string,
  userTimezone: string,
  name: string,
  claimKey: string,
  referenceTimestamp: Date,
): Promise<PreparedGap> {
  const { supabase } = createWorkerDeps()
  const localHour = getLocalHour(userTimezone, referenceTimestamp)

  // Janela de envio do lembrete: 21h-23h local (1-3h antes do bedtime típico).
  // Antes disso, é cedo demais (paciente pode ainda jantar). Depois, daily-closer pega.
  if (localHour < 21 || localHour > 23) {
    return { status: 'skipped', reason: `local hour ${localHour} fora janela 21-23` }
  }

  const today = getLocalDateString(userTimezone, referenceTimestamp)

  // Snapshot de hoje (cria se não existir, leve)
  const { data: snapBefore, error: snapshotError } = await supabase
    .from('daily_snapshots')
    .select('id, day_status, gap_reminder_sent_at, day_closed')
    .eq('user_id', userId)
    .eq('date', today)
    .maybeSingle()
  if (snapshotError) throw new Error(snapshotError.message ?? 'gap snapshot lookup failed')

  const snap = snapBefore as {
    id: string
    day_status: string | null
    gap_reminder_sent_at: string | null
    day_closed: boolean | null
  } | null

  // Já fechou ou já mandou lembrete → skip
  if (snap?.day_closed) return { status: 'skipped', reason: 'já fechado' }
  if (snap?.gap_reminder_sent_at) {
    return { status: 'skipped', reason: 'lembrete já enviado hoje' }
  }

  // Computa gap baseado em padrão 14d
  const gapInfo = await getGapForDate(supabase, userId, userTimezone, today)
  if (gapInfo.gap.size === 0) {
    return { status: 'skipped', reason: 'sem gap' }
  }

  // Fallback (paciente novo, <5 dias ativos): NÃO manda lembrete — sem padrão
  // confiável pra cobrar. Só começa a checar depois que tem histórico.
  if (gapInfo.pattern.fallbackUsed) {
    return { status: 'skipped', reason: 'paciente novo (sem padrão 14d ainda)' }
  }

  // Tem gap real. Monta mensagem e envia.
  const gapList = Array.from(gapInfo.gap)

  // Audit 06-20 (Roberto): busca refeições JÁ registradas hoje pra montar
  // lembrete acionável ("hoje você registrou: 17:48 lanche, 19:56 jantar.
  // Algum desses ERA seu almoço?"). Snapshot id é o filtro mais robusto;
  // sem snapshot (caso novo do dia), todayLogs fica vazia e o texto cai no
  // fallback simples (mesmo comportamento de antes).
  type LogRow = { meal_type: string | null; kcal: number | string | null; consumed_at: string }
  let todayLogs: LogRow[] = []
  if (snap?.id) {
    const { data, error: logsError } = await supabase
      .from('meal_logs')
      .select('meal_type, kcal, consumed_at')
      .eq('snapshot_id', snap.id)
      .order('consumed_at', { ascending: true })
    if (logsError) throw new Error(logsError.message ?? 'gap meal logs lookup failed')
    todayLogs = (data ?? []) as LogRow[]
  }

  const text = buildReminderText(name, gapList, todayLogs, userTimezone)
  const { data: claim, error: claimError } = await (
    supabase as unknown as {
      rpc: (
        name: string,
        params: Record<string, unknown>,
      ) => Promise<{
        data: { status?: string; attempt_id?: string } | null
        error: { message?: string } | null
      }>
    }
  ).rpc('claim_daily_gap_reminder', {
    p_user_id: userId,
    p_date: today,
    p_claim_key: claimKey,
    p_gap: gapList,
    p_now: referenceTimestamp.toISOString(),
  })
  if (claimError) throw new Error(claimError.message ?? 'gap reminder claim failed')
  if (claim?.status !== 'claimed' || !claim.attempt_id) {
    return { status: 'skipped', reason: claim?.status ?? 'claim unavailable' }
  }

  return {
    status: 'claimed',
    attemptId: claim.attempt_id,
    text,
    patternActiveDays: gapInfo.pattern.activeDays,
    localHour,
  }
}

function buildReminderText(
  name: string,
  gap: MealType[],
  todayLogs: Array<{ meal_type: string | null; kcal: number | string | null; consumed_at: string }>,
  tz: string,
): string {
  // Audit 06-20 (review F7): inclui 'outro' no map de labels pra não vazar a
  // string técnica 'outro' na mensagem ao paciente. Padrão consistente com
  // post-registration-message.ts (MEAL_LABEL).
  const labels: Record<string, string> = {
    cafe: 'café da manhã',
    almoco: 'almoço',
    lanche: 'lanche',
    jantar: 'jantar',
    ceia: 'ceia',
    outro: 'refeição',
  }
  const list = gap.map((mt) => labels[mt] ?? mt).join(' e ')

  // Audit 06-20 (Roberto): lista refeições já registradas hoje com horário
  // local. Caso real: Roberto comeu camarão+kani às 17:48 ET, virou "lanche",
  // lembrete às 21:31 perguntou pelo almoço, ele respondeu chicken wings e o
  // sistema criou 4º jantar em vez de reconhecer que o lanche das 17:48 ERA
  // o almoço.
  //
  // Audit 06-22/23 (Luciana + Roberto): F5 (lista individual) virou regressão
  // pior. Refeições com 5-7 itens viraram "14:18 almoço (192), 14:18 almoço
  // (236), 14:18 almoço (88)..." gigante. Cada item = 1 linha. Solução:
  // agrupar por (meal_type, consumed_at) — itens registrados juntos (mesma
  // timestamp) viram 1 linha; refeições em horários distintos viram linhas
  // separadas (cobre caso original do Roberto E o caso multi-item agora).
  type LogShow = { hour: string; mealType: string; kcal: number; itemCount: number }
  const groupKey = (mt: string, isoTs: string) => `${mt}|${isoTs}`
  const grouped: Map<string, LogShow> = new Map()
  for (const log of todayLogs) {
    if (!log.meal_type) continue
    const key = groupKey(log.meal_type, log.consumed_at)
    const existing = grouped.get(key)
    if (existing) {
      existing.kcal += Number(log.kcal) || 0
      existing.itemCount += 1
    } else {
      grouped.set(key, {
        hour: formatLocalHourMinute(log.consumed_at, tz),
        mealType: log.meal_type,
        kcal: Number(log.kcal) || 0,
        itemCount: 1,
      })
    }
  }
  const logs: LogShow[] = Array.from(grouped.values())

  const firstGap = gap[0]
  if (logs.length === 0 || !firstGap) {
    // Fallback simples (sem registros hoje OU sem gap conhecido): texto antigo.
    return (
      `Olá ${name}, antes de fechar o dia: você não registrou ${list} hoje. ` +
      `Se comeu, me descreve rapidão o que foi (ou manda foto) — ` +
      `dá tempo de registrar agora ou até amanhã cedo. ` +
      `Se realmente pulou, é só responder "pulei". ` +
      `Sem resposta até o fechamento, o dia fica como incompleto — e o bloco 7700 não credita.`
    )
  }

  const registradoLines = logs
    .map((l) => {
      const lbl = labels[l.mealType] ?? l.mealType
      const itemsSuffix = l.itemCount > 1 ? `, ${l.itemCount} itens` : ''
      return `${l.hour} ${lbl} (${Math.round(l.kcal)} kcal${itemsSuffix})`
    })
    .join(', ')

  // Review F6: não usar como exemplo um log que JÁ é do mesmo meal_type do
  // gap (gera "aquele almoço das 13:42 era o almoço" — nonsense). Filtra os
  // logs candidatos pra exemplo, excluindo qualquer um já no meal_type do gap.
  const exampleLogs = logs.filter((l) => l.mealType !== firstGap)
  const exampleLog = exampleLogs[0]

  // Review F8: plural reformulado pra evitar "Algum desses (X e Y) era X e Y?"
  // (sujeito singular + lista duplicada). Frase plural mais natural.
  const reclassifyHint =
    gap.length === 1
      ? exampleLog
        ? `Algum desses ERA seu ${labels[firstGap]}? Se sim, me diz qual horário e eu reclassifico sem dobrar ` +
          `(ex: "aquele ${labels[exampleLog.mealType] ?? exampleLog.mealType} das ${exampleLog.hour} era o ${labels[firstGap]}"). `
        : `Algum desses ERA seu ${labels[firstGap]}? Se sim, me diz qual horário e eu reclassifico sem dobrar. `
      : `Alguma dessas refeições do dia ERA na verdade ${list}? Me diz qual horário e eu reclassifico sem dobrar. `

  return (
    `Olá ${name}, antes de fechar o dia: você não registrou ${list} hoje. ` +
    `Hoje você já registrou: ${registradoLines}. ` +
    reclassifyHint +
    `Se ainda vai comer agora ou amanhã cedo, me descreve. ` +
    `Se realmente pulou, é só responder "pulei". ` +
    `Sem resposta até o fechamento, o dia fica como incompleto — e o bloco 7700 não credita.`
  )
}

function formatLocalHourMinute(iso: string, tz: string): string {
  try {
    const d = new Date(iso)
    return d.toLocaleTimeString('pt-BR', {
      timeZone: tz,
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    })
  } catch {
    return iso.slice(11, 16)
  }
}
