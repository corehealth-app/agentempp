import { getLocalDateString, getLocalHour, getTodayGap, type MealType } from '@mpp/agent'
import { createMessagingProvider, sendHumanized } from '@mpp/providers'
import { inngest } from '../client.js'
import { createWorkerDeps } from '../lib/env.js'

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
  async ({ step, logger }) => {
    const users = await step.run('list-users-gap', async () => {
      const { supabase } = createWorkerDeps()
      const { data } = await supabase
        .from('users')
        .select('id, timezone, wpp, name')
        .eq('status', 'active')
      return data ?? []
    })

    let checked = 0
    let reminded = 0
    let skipped = 0

    for (const user of users as Array<{ id: string; timezone: string | null; wpp: string; name: string | null }>) {
      try {
        const result = await step.run(`gap-${user.id}`, async () =>
          checkUserGap(user.id, user.timezone ?? 'America/Sao_Paulo', user.wpp, user.name ?? 'você'),
        )
        if (result.reminded) reminded++
        else if (result.skipped) skipped++
        checked++
      } catch (e) {
        logger.error('gap-check failed', { userId: user.id, error: String(e) })
      }
    }

    return { checked, reminded, skipped, total: users.length }
  },
)

async function checkUserGap(
  userId: string,
  userTimezone: string,
  wpp: string,
  name: string,
): Promise<{ reminded?: boolean; skipped?: boolean; reason?: string }> {
  const { supabase } = createWorkerDeps()
  const localHour = getLocalHour(userTimezone)

  // Janela de envio do lembrete: 21h-23h local (1-3h antes do bedtime típico).
  // Antes disso, é cedo demais (paciente pode ainda jantar). Depois, daily-closer pega.
  if (localHour < 21 || localHour > 23) {
    return { skipped: true, reason: `local hour ${localHour} fora janela 21-23` }
  }

  const today = getLocalDateString(userTimezone)

  // Snapshot de hoje (cria se não existir, leve)
  const { data: snapBefore } = await supabase
    .from('daily_snapshots')
    .select('id, day_status, gap_reminder_sent_at, day_closed')
    .eq('user_id', userId)
    .eq('date', today)
    .maybeSingle()

  const snap = snapBefore as {
    id: string
    day_status: string | null
    gap_reminder_sent_at: string | null
    day_closed: boolean | null
  } | null

  // Já fechou ou já mandou lembrete → skip
  if (snap?.day_closed) return { skipped: true, reason: 'já fechado' }
  if (snap?.gap_reminder_sent_at) {
    return { skipped: true, reason: 'lembrete já enviado hoje' }
  }

  // Computa gap baseado em padrão 14d
  const gapInfo = await getTodayGap(supabase, userId, userTimezone)
  if (gapInfo.gap.size === 0) {
    return { skipped: true, reason: 'sem gap' }
  }

  // Fallback (paciente novo, <5 dias ativos): NÃO manda lembrete — sem padrão
  // confiável pra cobrar. Só começa a checar depois que tem histórico.
  if (gapInfo.pattern.fallbackUsed) {
    return { skipped: true, reason: 'paciente novo (sem padrão 14d ainda)' }
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
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data } = await (supabase as any)
      .from('meal_logs')
      .select('meal_type, kcal, consumed_at')
      .eq('snapshot_id', snap.id)
      .order('consumed_at', { ascending: true })
    todayLogs = (data ?? []) as LogRow[]
  }

  const text = buildReminderText(name, gapList, todayLogs, userTimezone)

  const messaging = createMessagingProvider({
    MESSAGING_PROVIDER: process.env.MESSAGING_PROVIDER ?? 'whatsapp_cloud',
    META_PHONE_NUMBER_ID: process.env.META_PHONE_NUMBER_ID,
    META_ACCESS_TOKEN: process.env.META_ACCESS_TOKEN,
    META_APP_SECRET: process.env.META_APP_SECRET,
    META_VERIFY_TOKEN: process.env.META_VERIFY_TOKEN,
  })

  let deliveryStatus: 'sent' | 'failed' = 'sent'
  let deliveryError: string | undefined
  try {
    const results = await sendHumanized(messaging, wpp, text, {
      showTyping: false,
      minDelay: 500,
      maxDelay: 1500,
      charsPerSecond: 60,
      // Review F9: texto novo (~500 chars) seria estilhaçado em 3 bolhas pelo
      // humanizer e paciente pode responder antes de ler a hint inteira.
      // singleMessage garante chegada atômica (cabe em 1 msg WhatsApp, 4096 max).
      singleMessage: true,
    })
    if (results.some((r) => r.status !== 'sent')) {
      deliveryStatus = 'failed'
      deliveryError = results.find((r) => r.error)?.error
    }
  } catch (e) {
    deliveryStatus = 'failed'
    deliveryError = e instanceof Error ? e.message : String(e)
  }

  // Marca snapshot (cria se não existir) com pending_close + reminder_sent_at.
  // Cast: DB types ainda sem day_status/gap_reminder_sent_at (regerar após
  // migration 20260516133000). Cast é safe — campos adicionados ao schema.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  await (supabase as any).from('daily_snapshots').upsert(
    {
      user_id: userId,
      date: today,
      day_status: 'pending_close',
      gap_reminder_sent_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    },
    { onConflict: 'user_id,date' },
  )

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  await (supabase as any).from('messages').insert({
    user_id: userId,
    direction: 'out',
    role: 'assistant',
    content_type: 'text',
    content: text,
    provider: process.env.MESSAGING_PROVIDER ?? 'whatsapp_cloud',
    agent_stage: 'engajamento',
    delivery_status: deliveryStatus,
    delivery_error: deliveryError ? { msg: deliveryError } : null,
    raw_payload: { source: 'daily_gap_checker', gap: gapList },
  })

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  await (supabase as any).from('product_events').insert({
    user_id: userId,
    event: 'daily.gap_reminder_sent',
    properties: {
      gap: gapList,
      pattern_active_days: gapInfo.pattern.activeDays,
      local_hour: localHour,
      delivery_status: deliveryStatus,
    },
  })

  return { reminded: true, skipped: false }
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
