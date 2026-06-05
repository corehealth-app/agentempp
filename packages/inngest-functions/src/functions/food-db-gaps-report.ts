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

export const foodDbGapsReportFn = inngest.createFunction(
  { id: 'food-db-gaps-report', retries: 1 },
  { cron: 'TZ=America/Sao_Paulo 0 9 * * 1' },
  async ({ step, logger }) => {
    const { supabase } = createWorkerDeps()

    // 1. Top 15 nomes que apareceram em meal_logs sem match exato em food_db
    //    nos últimos 7d. Usa join LEFT pra detectar AUSÊNCIA de entry.
    type GapRow = {
      food_name: string
      logs: number
      patients: number
      avg_kcal_per_100g: number
    }
    const gaps = await step.run('compute-gaps', async () => {
      const sql = `
        SELECT m.food_name,
               COUNT(*) AS logs,
               COUNT(DISTINCT m.user_id) AS patients,
               ROUND(AVG(m.kcal / NULLIF(m.quantity_g, 0) * 100)::numeric, 1) AS avg_kcal_per_100g
        FROM meal_logs m
        LEFT JOIN food_db f
          ON LOWER(public.unaccent(f.name_pt)) = LOWER(public.unaccent(m.food_name))
        WHERE m.created_at >= now() - interval '7 days'
          AND f.id IS NULL
        GROUP BY m.food_name
        ORDER BY logs DESC, patients DESC
        LIMIT 15
      `
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data } = await (supabase as any).rpc('exec_sql', { sql }).catch(() => ({ data: null }))
      if (Array.isArray(data)) return data as GapRow[]
      // Fallback: PostgREST simples (sem RPC exec_sql). Faz query Supabase nativa.
      const since = new Date(Date.now() - 7 * 24 * 3600 * 1000).toISOString()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data: rows } = await (supabase as any)
        .from('meal_logs')
        .select('food_name, kcal, quantity_g, user_id')
        .gte('created_at', since)
        .neq('source', 'taco')
      const allRows = (rows ?? []) as Array<{
        food_name: string
        kcal: number
        quantity_g: number
        user_id: string
      }>
      const byName = new Map<
        string,
        { logs: number; patients: Set<string>; kcalSum: number; kcalCount: number }
      >()
      for (const r of allRows) {
        if (!r.food_name) continue
        const key = r.food_name.trim().toLowerCase()
        const entry =
          byName.get(key) ?? { logs: 0, patients: new Set<string>(), kcalSum: 0, kcalCount: 0 }
        entry.logs++
        entry.patients.add(r.user_id)
        if (r.quantity_g > 0 && r.kcal > 0) {
          entry.kcalSum += (r.kcal / r.quantity_g) * 100
          entry.kcalCount++
        }
        byName.set(key, entry)
      }
      const arr: GapRow[] = Array.from(byName.entries())
        .map(([food_name, v]) => ({
          food_name,
          logs: v.logs,
          patients: v.patients.size,
          avg_kcal_per_100g: v.kcalCount > 0 ? +(v.kcalSum / v.kcalCount).toFixed(1) : 0,
        }))
        .sort((a, b) => b.logs - a.logs || b.patients - a.patients)
        .slice(0, 15)
      return arr
    })

    // 2. Contadores agregados
    const summary = await step.run('compute-summary', async () => {
      const since = new Date(Date.now() - 7 * 24 * 3600 * 1000).toISOString()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data: all } = await (supabase as any)
        .from('meal_logs')
        .select('source')
        .gte('created_at', since)
      const rows = (all ?? []) as Array<{ source: string }>
      const total = rows.length
      const fallback = rows.filter((r) => r.source !== 'taco').length
      return {
        total_logs: total,
        fallback_logs: fallback,
        fallback_pct: total > 0 ? Math.round((fallback / total) * 100) : 0,
      }
    })

    // 3. Monta mensagem
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

    // 4. Envio Telegram (mesmo padrão do daily-audit)
    const botToken = process.env.TELEGRAM_BOT_TOKEN
    const adminChatId = process.env.TELEGRAM_ADMIN_CHAT_ID
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data: extraCfg } = await (supabase as any)
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
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any).from('product_events').insert({
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

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('product_events').insert({
      event: 'food_db.gaps_report',
      properties: { ...summary, gaps_count: gaps.length, sent: okCount, top_gaps: gaps },
    })

    return { sent: okCount, gaps_count: gaps.length, summary }
  },
)
