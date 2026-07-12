/**
 * Relatório semanal de GAPS em food_db (Roberto/Eduardo 2026-06-05).
 *
 * Eduardo argumentou que NÃO vale expandir food_db cegamente — vale expandir
 * DIRIGIDO POR DADO. Esta função roda 1×/semana, lista os top 15 alimentos
 * dos últimos 7d que caíram em fallback (llm_estimate / sem match exato em
 * food_db), e manda pro Telegram do Eduardo + audit chat_ids.
 *
 * Não toma ação automática — só REPORTA. Eduardo decide o que adicionar.
 *
 * Cron: segunda 09:00 BRT.
 */
import { inngest } from '../client.js'
import { createWorkerDeps } from '../lib/env.js'
import { aggregateFoodDbGaps, collectPages, type FoodDbGapLog } from './food-db-gaps.js'

export const foodDbGapsReportFn = inngest.createFunction(
  { id: 'food-db-gaps-report', retries: 1 },
  { cron: 'TZ=America/Sao_Paulo 0 9 * * 1' },
  async ({ step, logger }) => {
    const { supabase } = createWorkerDeps()

    // 1. Carrega os logs e nomes canônicos de forma paginada. A RPC genérica
    // exec_sql nunca existiu no schema e o fallback antigo confundia source
    // nutricional com ausência real no food_db.
    const gapData = await step.run('compute-gap-data-v2', async () => {
      const since = new Date(Date.now() - 7 * 24 * 3600 * 1000).toISOString()
      const [logs, knownFoods] = await Promise.all([
        collectPages<FoodDbGapLog>(async (from, to) => {
          const { data, error } = await supabase
            .from('meal_logs')
            .select('food_name, kcal, quantity_g, user_id')
            .gte('created_at', since)
            .order('created_at', { ascending: true })
            .order('id', { ascending: true })
            .range(from, to)
          if (error) throw new Error(`meal_logs gap query failed: ${error.message}`)
          return (data ?? []) as FoodDbGapLog[]
        }),
        collectPages<{ name_norm: string | null }>(async (from, to) => {
          const { data, error } = await supabase
            .from('food_db')
            .select('name_norm')
            .order('id', { ascending: true })
            .range(from, to)
          if (error) throw new Error(`food_db gap query failed: ${error.message}`)
          return data ?? []
        }),
      ])
      return aggregateFoodDbGaps(
        logs,
        knownFoods.map((food) => food.name_norm),
      )
    })
    const { gaps, summary } = gapData

    // 2. Monta mensagem
    const lines: string[] = []
    lines.push(`📊 *food_db gaps semanal* (últimos 7d)`)
    lines.push('')
    lines.push(
      `Total logs: *${summary.total_logs}* | fallback: *${summary.fallback_logs}* (${summary.fallback_pct}%)`,
    )
    lines.push('')
    if (gaps.length === 0) {
      lines.push('✅ Nenhum gap detectado — todos os alimentos têm match exato.')
    } else {
      lines.push(`Top ${gaps.length} alimentos sem entry exata em food_db:`)
      lines.push('')
      for (const g of gaps) {
        const kcalStr = g.avg_kcal_per_100g > 0 ? `~${g.avg_kcal_per_100g} kcal/100g` : '?'
        lines.push(
          `• \`${g.food_name}\` — ${g.logs} log${g.logs === 1 ? '' : 's'} (${g.patients}p), ${kcalStr}`,
        )
      }
      lines.push('')
      lines.push(`_Decisão: revisar e adicionar ao food_db os que valem (TACO IV)._`)
    }
    const msg = lines.join('\n')

    // 3. Envio Telegram (mesmo padrão do daily-audit)
    const botToken = process.env.TELEGRAM_BOT_TOKEN
    const adminChatId = process.env.TELEGRAM_ADMIN_CHAT_ID
    const { data: extraCfg } = await supabase
      .from('global_config')
      .select('value')
      .eq('key', 'audit.telegram_chat_ids')
      .maybeSingle()
    const extraIds = Array.isArray((extraCfg as { value?: unknown } | null)?.value)
      ? (extraCfg as { value: unknown[] }).value.map((v) => String(v))
      : []
    const recipients = [...new Set([...(adminChatId ? [adminChatId] : []), ...extraIds])]

    if (!botToken || recipients.length === 0) {
      logger.warn('Telegram creds/destinatários ausentes — só log')
      await supabase.from('product_events').insert({
        event: 'food_db.gaps_report',
        properties: { ...summary, gaps_count: gaps.length, sent: 0 },
      })
      return { sent: 0, gaps_count: gaps.length, summary }
    }

    let okCount = 0
    for (const chatId of recipients) {
      const postIt = (md: boolean) =>
        fetch(`https://api.telegram.org/bot${botToken}/sendMessage`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            chat_id: chatId,
            text: msg,
            ...(md ? { parse_mode: 'Markdown' } : {}),
            disable_web_page_preview: true,
          }),
        })
      let res = await postIt(true)
      if (!res.ok) res = await postIt(false)
      if (res.ok) okCount++
    }

    await supabase.from('product_events').insert({
      event: 'food_db.gaps_report',
      properties: { ...summary, gaps_count: gaps.length, sent: okCount, top_gaps: gaps },
    })

    return { sent: okCount, gaps_count: gaps.length, summary }
  },
)
