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
import { inngest } from '../client.js'
import { createWorkerDeps } from '../lib/env.js'

const ACTIVE_HOURS = { start: 10, end: 19 } // hora local
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

function pickReminder(slot: 'morning' | 'afternoon' | 'evening'): string {
  const pool = REMINDERS[slot] ?? REMINDERS.morning ?? ['Lembrete']
  const idx = Math.floor(Date.now() / 60000) % pool.length
  return pool[idx] ?? 'Lembrete'
}

function renderText(template: string, vars: Record<string, string | number>): string {
  return template.replace(/\{(\w+)\}/g, (_, k) => String(vars[k] ?? ''))
}

export const mealGapReminderFn = inngest.createFunction(
  { id: 'meal-gap-reminder', retries: 1 },
  // Cron: a cada hora cheia em horário ativo BRT (10-19h)
  { cron: 'TZ=America/Sao_Paulo 0 10-19 * * *' },
  async ({ step, logger }) => {
    const { supabase } = createWorkerDeps()

    // 1. Lista pacientes opt-in
    const optInPatients = await step.run('list-opt-in', async () => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data } = await (supabase as any)
        .from('users')
        .select('id, wpp, name, timezone, metadata')
        .eq('status', 'active')
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
      try {
        const result = await step.run(`check-${u.id}`, async () =>
          processPatient(supabase, u.id, u.wpp, u.name ?? '', u.timezone ?? 'America/Sao_Paulo'),
        )
        if (result.sent) sent++
      } catch (e) {
        logger.error('meal-gap-reminder failed pra paciente', { userId: u.id, error: String(e) })
      }
    }

    return { sent, total: optInPatients.length }
  },
)

async function processPatient(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: any,
  userId: string,
  wpp: string,
  name: string,
  timezone: string,
): Promise<{ sent: boolean; reason?: string }> {
  const nowMs = Date.now()
  const localHour = Number(
    new Date().toLocaleString('en-US', { timeZone: timezone, hour: '2-digit', hour12: false }),
  )
  if (localHour < ACTIVE_HOURS.start || localHour >= ACTIVE_HOURS.end) {
    return { sent: false, reason: 'fora_janela_ativa' }
  }

  // Skip se paciente mandou msg nos últimos N min (já engajado)
  const sinceUserMsg = new Date(nowMs - SKIP_IF_USER_MSG_LAST_MIN * 60 * 1000).toISOString()
  const { data: recentUserMsg } = await supabase
    .from('messages')
    .select('id')
    .eq('user_id', userId)
    .eq('direction', 'in')
    .gte('created_at', sinceUserMsg)
    .limit(1)
  if (Array.isArray(recentUserMsg) && recentUserMsg.length > 0) {
    return { sent: false, reason: 'usuario_engajado_recentemente' }
  }

  // Cooldown — não enviar se já enviei lembrete nas últimas N horas
  const sinceCooldown = new Date(nowMs - COOLDOWN_HOURS * 60 * 60 * 1000).toISOString()
  const { data: recentRem } = await supabase
    .from('product_events')
    .select('id, occurred_at')
    .eq('user_id', userId)
    .eq('event', 'proactive.reminder_sent')
    .gte('occurred_at', sinceCooldown)
  if (Array.isArray(recentRem) && recentRem.length > 0) {
    return { sent: false, reason: 'cooldown' }
  }

  // Quota diária — máximo MAX_PER_DAY
  const sinceDay = new Date(nowMs - 24 * 60 * 60 * 1000).toISOString()
  const { data: dayRem } = await supabase
    .from('product_events')
    .select('id')
    .eq('user_id', userId)
    .eq('event', 'proactive.reminder_sent')
    .gte('occurred_at', sinceDay)
  if (Array.isArray(dayRem) && dayRem.length >= MAX_PER_DAY) {
    return { sent: false, reason: 'quota_diaria_atingida' }
  }

  // Gap de refeição
  const { data: lastMeal } = await supabase
    .from('meal_logs')
    .select('created_at')
    .eq('user_id', userId)
    .order('created_at', { ascending: false })
    .limit(1)
  const lastMealAt = (lastMeal?.[0]?.created_at as string | undefined) ?? null
  const gapHours = lastMealAt
    ? (nowMs - new Date(lastMealAt).getTime()) / 3600000
    : 99
  if (gapHours < GAP_MIN_HOURS) {
    return { sent: false, reason: 'gap_insuficiente' }
  }

  // Snapshot proteína hoje
  const today = new Date(
    new Date().toLocaleString('en-CA', { timeZone: timezone, year: 'numeric', month: '2-digit', day: '2-digit' }),
  )
    .toISOString()
    .slice(0, 10)
  const { data: snap } = await supabase
    .from('daily_snapshots')
    .select('protein_g, protein_target')
    .eq('user_id', userId)
    .eq('date', today)
    .maybeSingle()
  const proteinPct =
    snap && snap.protein_target > 0
      ? Math.round((Number(snap.protein_g) / Number(snap.protein_target)) * 100)
      : 0
  const proteinRemaining =
    snap && snap.protein_target > 0
      ? Math.max(0, Math.round(Number(snap.protein_target) - Number(snap.protein_g)))
      : 0

  // Só envia se proteína abaixo de 60% — sinal real de baixa ingestão
  if (proteinPct >= 60) {
    return { sent: false, reason: 'proteina_ok' }
  }

  // Escolhe slot por hora local
  const slot: 'morning' | 'afternoon' | 'evening' =
    localHour < 12 ? 'morning' : localHour < 17 ? 'afternoon' : 'evening'
  const tpl = pickReminder(slot)
  const text = renderText(tpl, {
    name: name.split(' ')[0] ?? '',
    hour: localHour,
    gap: Math.round(gapHours),
    protein_pct: proteinPct,
    protein_remaining: proteinRemaining,
  })

  // Envia via WhatsApp Cloud (usa env, mesmo padrão do engagement-sender)
  const token = process.env.WHATSAPP_CLOUD_TOKEN
  const phoneId = process.env.WHATSAPP_CLOUD_PHONE_ID
  if (!token || !phoneId) {
    return { sent: false, reason: 'wpp_creds_missing' }
  }
  const res = await fetch(`https://graph.facebook.com/v18.0/${phoneId}/messages`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      messaging_product: 'whatsapp',
      to: wpp,
      type: 'text',
      text: { body: text },
    }),
  })
  const ok = res.ok

  await supabase.from('product_events').insert({
    user_id: userId,
    event: 'proactive.reminder_sent',
    properties: {
      slot,
      gap_hours: Math.round(gapHours),
      protein_pct: proteinPct,
      local_hour: localHour,
      ok,
      text_preview: text.slice(0, 100),
    },
  })

  // Loga como msg outbound pra histórico
  if (ok) {
    await supabase.from('messages').insert({
      user_id: userId,
      direction: 'out',
      content_type: 'text',
      content: text,
    })
  }

  return { sent: ok, reason: ok ? 'sent' : 'send_failed' }
}
