import { inngest } from '../client.js'
import { createWorkerDeps } from '../lib/env.js'

/**
 * Worker: auditoria automática diária do agente.
 *
 * Roberto pediu (sessão 2026-05-19): "audita amanhã 9h BRT pra ver se os
 * fixes seguraram". Em vez de ser manual recorrente, automatizei como cron
 * diário 12h UTC = 9h BRT. Envia resumo via Telegram pro admin (Eduardo
 * @MargotPiper_Bot — mesmo bot do Modo A e dos alertas de saldo).
 *
 * Métricas auditadas (janela 24h):
 *   - Pipeline errors (esperado 0)
 *   - Numeric mismatches (esperado 0-2, separado de falsos positivos)
 *   - Sentiment mismatches (esperado 0)
 *   - Card replaced count (esperado 5-15 se ativo)
 *   - Loose bloco replaced count (esperado 0-3)
 *   - Engagement enviado vs skipped (esperado ratio 1:3-5 com fix Bug A)
 *   - Custo total e custo médio por turno
 *   - Cache hit rate médio
 *   - Saldo OpenRouter restante
 *   - Integridade snapshot vs meal_logs (esperado 0 divergências)
 *   - Composite rejected (esperado 0-1)
 *   - Pacientes que sumiram (gap > 2 dias com streak_reset)
 *
 * Formato relatório: short markdown ~600 chars no Telegram.
 */
export const dailyAuditFn = inngest.createFunction(
  { id: 'daily-audit', retries: 1, concurrency: { limit: 1 } },
  { event: 'audit.daily.tick' },
  async ({ step, logger }) => {
    const { supabase } = createWorkerDeps()

    const metrics = await step.run('collect-metrics', async () => {
      // 1. Pipeline errors 24h
      const { count: pipelineErrors } = await supabase
        .from('product_events')
        .select('id', { count: 'exact', head: true })
        .eq('event', 'pipeline.error')
        .gte('occurred_at', new Date(Date.now() - 24 * 3600 * 1000).toISOString())

      // 2. Numeric mismatches + sentiment
      const { count: numericMismatch } = await supabase
        .from('product_events')
        .select('id', { count: 'exact', head: true })
        .eq('event', 'llm.numeric_mismatch')
        .gte('occurred_at', new Date(Date.now() - 24 * 3600 * 1000).toISOString())
      const { count: sentimentMismatch } = await supabase
        .from('product_events')
        .select('id', { count: 'exact', head: true })
        .eq('event', 'llm.sentiment_mismatch')
        .gte('occurred_at', new Date(Date.now() - 24 * 3600 * 1000).toISOString())

      // 3. Card replacements (fix C ativo)
      const { count: cardReplaced } = await supabase
        .from('product_events')
        .select('id', { count: 'exact', head: true })
        .eq('event', 'llm.card_replaced')
        .gte('occurred_at', new Date(Date.now() - 24 * 3600 * 1000).toISOString())
      const { count: looseBlocoReplaced } = await supabase
        .from('product_events')
        .select('id', { count: 'exact', head: true })
        .eq('event', 'llm.loose_bloco_replaced')
        .gte('occurred_at', new Date(Date.now() - 24 * 3600 * 1000).toISOString())

      // 4. Engagement Bug A fix check
      const { count: engagementSent } = await supabase
        .from('product_events')
        .select('id', { count: 'exact', head: true })
        .eq('event', 'engagement.sent')
        .gte('occurred_at', new Date(Date.now() - 24 * 3600 * 1000).toISOString())
      const { count: engagementSkipped } = await supabase
        .from('product_events')
        .select('id', { count: 'exact', head: true })
        .eq('event', 'engagement.skipped')
        .gte('occurred_at', new Date(Date.now() - 24 * 3600 * 1000).toISOString())

      // 5. Streak resets
      const { count: streakResets } = await supabase
        .from('product_events')
        .select('id', { count: 'exact', head: true })
        .eq('event', 'streak.reset_inactive')
        .gte('occurred_at', new Date(Date.now() - 24 * 3600 * 1000).toISOString())

      // 6. Composite rejected
      const { count: compositeRejected } = await supabase
        .from('meal_logs')
        .select('id', { count: 'exact', head: true })
        .eq('source', 'composite_rejected')
        .gte('created_at', new Date(Date.now() - 24 * 3600 * 1000).toISOString())

      // 7. Custo total + médio
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data: costData } = await (supabase as any)
        .from('messages')
        .select('cost_usd, prompt_tokens')
        .eq('direction', 'out')
        .not('cost_usd', 'is', null)
        .gte('created_at', new Date(Date.now() - 24 * 3600 * 1000).toISOString())
      const costs = (costData ?? []) as Array<{ cost_usd: number; prompt_tokens: number }>
      const totalCost = costs.reduce((s, c) => s + (Number(c.cost_usd) || 0), 0)
      const avgCostPerTurn = costs.length > 0 ? totalCost / costs.length : 0
      const totalTokens = costs.reduce((s, c) => s + (Number(c.prompt_tokens) || 0), 0)

      // 8. Cache hit rate médio
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data: cacheData } = await (supabase as any)
        .from('product_events')
        .select('properties')
        .eq('event', 'llm.cache_usage')
        .gte('occurred_at', new Date(Date.now() - 24 * 3600 * 1000).toISOString())
      const cacheEvents = (cacheData ?? []) as Array<{ properties: { hit_rate?: number } }>
      const hitRates = cacheEvents.map((e) => Number(e.properties?.hit_rate) || 0)
      const avgHitRate =
        hitRates.length > 0 ? hitRates.reduce((s, h) => s + h, 0) / hitRates.length : 0

      // 9. Saldo OpenRouter (último check)
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data: balanceData } = await (supabase as any)
        .from('product_events')
        .select('properties')
        .eq('event', 'openrouter.balance_checked')
        .order('occurred_at', { ascending: false })
        .limit(1)
      const balance = (balanceData?.[0]?.properties?.limit_remaining_usd as number) ?? null

      // 10. Integridade snapshots últimos 3d
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data: snapData } = await (supabase as any)
        .from('daily_snapshots')
        .select('id, calories_consumed')
        .gte('date', new Date(Date.now() - 3 * 24 * 3600 * 1000).toISOString().slice(0, 10))
      const snaps = (snapData ?? []) as Array<{ id: string; calories_consumed: number }>
      let divergencias = 0
      for (const s of snaps) {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const { data: ml } = await (supabase as any)
          .from('meal_logs')
          .select('kcal')
          .eq('snapshot_id', s.id)
        const sum = (ml ?? []).reduce(
          (acc: number, r: { kcal: number }) => acc + (Number(r.kcal) || 0),
          0,
        )
        if (Math.abs(s.calories_consumed - sum) > 50) divergencias++
      }

      return {
        pipelineErrors: pipelineErrors ?? 0,
        numericMismatch: numericMismatch ?? 0,
        sentimentMismatch: sentimentMismatch ?? 0,
        cardReplaced: cardReplaced ?? 0,
        looseBlocoReplaced: looseBlocoReplaced ?? 0,
        engagementSent: engagementSent ?? 0,
        engagementSkipped: engagementSkipped ?? 0,
        streakResets: streakResets ?? 0,
        compositeRejected: compositeRejected ?? 0,
        totalCost: +totalCost.toFixed(2),
        avgCostPerTurn: +avgCostPerTurn.toFixed(3),
        totalTokens,
        avgHitRate: +(avgHitRate * 100).toFixed(1),
        balance,
        snapshotIntegrityOk: divergencias === 0,
        snapshotDivergencias: divergencias,
        turnos: costs.length,
      }
    })

    // Decide se há alerta crítico (vai pro topo da mensagem)
    const alerts: string[] = []
    if (metrics.pipelineErrors > 0) alerts.push(`🔴 ${metrics.pipelineErrors} pipeline.error`)
    if (metrics.numericMismatch > 3) alerts.push(`⚠️ ${metrics.numericMismatch} numeric_mismatch`)
    if (metrics.sentimentMismatch > 0) alerts.push(`⚠️ ${metrics.sentimentMismatch} sentiment_mismatch`)
    if (metrics.compositeRejected > 2) alerts.push(`⚠️ ${metrics.compositeRejected} composite rejected`)
    if (!metrics.snapshotIntegrityOk) alerts.push(`🔴 ${metrics.snapshotDivergencias} divergência snapshot`)
    if (metrics.balance != null && metrics.balance < 20)
      alerts.push(`🔴 saldo OpenRouter $${metrics.balance.toFixed(2)} < $20`)

    const overallStatus = alerts.length === 0 ? '✅ Tudo OK' : '⚠️ Atenção'

    const msg =
      `*Auditoria diária agente MPP — 24h*\n\n` +
      `${overallStatus}\n` +
      (alerts.length > 0 ? `\n${alerts.join('\n')}\n` : '') +
      `\n*Saúde do pipeline*\n` +
      `• Pipeline errors: ${metrics.pipelineErrors}\n` +
      `• Numeric mismatch: ${metrics.numericMismatch} | Sentiment: ${metrics.sentimentMismatch}\n` +
      `• Composite rejected: ${metrics.compositeRejected}\n` +
      `• Snapshot integrity: ${metrics.snapshotIntegrityOk ? 'OK' : `❌ ${metrics.snapshotDivergencias} diff`}\n` +
      `\n*Defesas ativas*\n` +
      `• Card canônico substituiu: ${metrics.cardReplaced}\n` +
      `• Bloco solto substituído: ${metrics.looseBlocoReplaced}\n` +
      `• Streak resets: ${metrics.streakResets}\n` +
      `\n*Engagement*\n` +
      `• Enviadas: ${metrics.engagementSent} | Skipped: ${metrics.engagementSkipped}\n` +
      `\n*Custo & cache*\n` +
      `• Turnos LLM: ${metrics.turnos}\n` +
      `• Custo 24h: *$${metrics.totalCost}* (avg $${metrics.avgCostPerTurn}/turno)\n` +
      `• Tokens input: ${(metrics.totalTokens / 1000).toFixed(0)}k\n` +
      `• Cache hit rate: ${metrics.avgHitRate}%\n` +
      `• Saldo OpenRouter: ${metrics.balance != null ? `*$${metrics.balance.toFixed(2)}*` : 'n/d'}\n`

    // Loga sempre (histórico)
    await supabase.from('product_events').insert({
      event: 'audit.daily_report',
      properties: { ...metrics, alerts_count: alerts.length },
    })

    // Envia Telegram só se há alertas OU sempre (config). Default: sempre,
    // pra Eduardo ter visibilidade diária do estado.
    const botToken = process.env.TELEGRAM_BOT_TOKEN
    const adminChatId = process.env.TELEGRAM_ADMIN_CHAT_ID
    if (!botToken || !adminChatId) {
      logger.warn('Telegram creds ausentes — relatório só no banco')
      return { ok: true, alerts: alerts.length, sent: false }
    }

    await step.run('send-telegram', async () => {
      const res = await fetch(`https://api.telegram.org/bot${botToken}/sendMessage`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          chat_id: adminChatId,
          text: msg,
          parse_mode: 'Markdown',
          disable_web_page_preview: true,
        }),
      })
      if (!res.ok) {
        throw new Error(`Telegram send failed ${res.status}`)
      }
    })

    return { ok: true, alerts: alerts.length, sent: true, ...metrics }
  },
)
