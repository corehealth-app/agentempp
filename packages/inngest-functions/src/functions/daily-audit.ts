import {
  findTimezoneCountryMismatches,
  getTzOffset,
  looksLikeRegistrationRequest,
} from '@mpp/agent'
import { inngest } from '../client.js'
import { applyUserBlocoCorrection, recomputeUserBloco } from '../lib/bloco-recompute.js'
import { throwIfQueryFailed } from '../lib/query-error.js'
import { createWorkerDeps } from '../lib/env.js'
import { loadBooleanConfig } from '../lib/runtime-config.js'

/**
 * Gap de integridade de UM snapshot: |consumido_no_snapshot − soma_dos_logs|.
 *
 * Função pura (testável) — a soma dos logs DEVE vir filtrada por `consumed_at`
 * caindo na data local do snapshot (mesma invariante do daily-closer), NÃO por
 * `snapshot_id`. Ver comentário na coleta de métricas pro porquê.
 */
export function snapshotIntegrityGap(
  snapshotConsumed: number,
  logsSummedByConsumedAt: number,
): number {
  return Math.abs((Number(snapshotConsumed) || 0) - (Number(logsSummedByConsumedAt) || 0))
}

/** Tolerância de divergência snapshot vs meal_logs (kcal). */
export const SNAPSHOT_INTEGRITY_TOL_KCAL = 50

export interface BlocoAutofixDecision {
  canApply: boolean
  circuitBroke: boolean
  disabled: boolean
}

export function decideBlocoAutofix(
  divergeCount: number,
  maxFix: number,
  enabled: boolean,
): BlocoAutofixDecision {
  if (!enabled) return { canApply: false, circuitBroke: false, disabled: true }
  if (divergeCount > maxFix) return { canApply: false, circuitBroke: true, disabled: false }
  return { canApply: true, circuitBroke: false, disabled: false }
}

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
  // 5x/dia: 8h, 12h, 15h, 18h, 21h BRT (Eduardo 2026-05-21; antes 3x). Cron NATIVO
  // do Inngest. Acompanha o piloto do D (encolhimento do prompt) + auto-corrige
  // blocos (com circuit-breaker) e reporta no Telegram. pg_cron antigo
  // 'daily-audit-9h-brt' já removido.
  { cron: 'TZ=America/Sao_Paulo 0 8,12,15,18,21 * * *' },
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

      // 10. Integridade snapshots últimos 3d.
      //
      // ⚠️ ANTES comparávamos calories_consumed com a soma dos meal_logs POR
      // `snapshot_id` — isso dava FALSO-POSITIVO de divergência: quando um
      // meal_log tem o `snapshot_id` linkado ao dia errado (acontece com
      // backfills/correções), a soma por snapshot_id não bate com o
      // calories_consumed, MESMO quando o valor real por `consumed_at` está
      // certo. A linkagem por snapshot_id não é a invariante do sistema.
      //
      // O daily-closer calcula calories_consumed somando meal_logs por
      // `consumed_at` no intervalo [00:00..23:59] da DATA LOCAL do snapshot
      // (fuso do paciente — ver closeUserDay: startOfDay/endOfDay com
      // getTzOffset). Essa é a invariante correta. Replicamos aqui pra
      // auditar o mesmo que o closer produz e eliminar o alarme fantasma.
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data: snapData } = await (supabase as any)
        .from('daily_snapshots')
        .select('id, user_id, date, calories_consumed')
        .gte('date', new Date(Date.now() - 3 * 24 * 3600 * 1000).toISOString().slice(0, 10))
      const snaps = (snapData ?? []) as Array<{
        id: string
        user_id: string
        date: string
        calories_consumed: number
      }>
      // Timezone por usuário (igual o closer usa pra montar a janela do dia).
      // Default America/Sao_Paulo, idêntico ao fallback do daily-closer.
      const userIds = [...new Set(snaps.map((s) => s.user_id))]
      const tzByUser = new Map<string, string>()
      if (userIds.length > 0) {
        const { data: us } = await supabase.from('users').select('id, timezone').in('id', userIds)
        for (const u of (us ?? []) as Array<{ id: string; timezone: string | null }>) {
          tzByUser.set(u.id, u.timezone ?? 'America/Sao_Paulo')
        }
      }
      let divergencias = 0
      for (const s of snaps) {
        const tz = tzByUser.get(s.user_id) ?? 'America/Sao_Paulo'
        // Janela do dia local do snapshot — exatamente como o closer monta.
        const startOfDay = `${s.date}T00:00:00${getTzOffset(tz)}`
        const endOfDay = `${s.date}T23:59:59${getTzOffset(tz)}`
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const { data: ml } = await (supabase as any)
          .from('meal_logs')
          .select('kcal')
          .eq('user_id', s.user_id)
          .gte('consumed_at', startOfDay)
          .lte('consumed_at', endOfDay)
        const sum = (ml ?? []).reduce(
          (acc: number, r: { kcal: number }) => acc + (Number(r.kcal) || 0),
          0,
        )
        if (snapshotIntegrityGap(s.calories_consumed, sum) > SNAPSHOT_INTEGRITY_TOL_KCAL)
          divergencias++
      }

      // 11. Reavaliações disparadas há >24h e NÃO processadas (Roberto 2026-05-22).
      // "due" sem nenhum cadastra_dados_iniciais/define_protocolo depois = recálculo
      // não rodou. Janela 24-48h: dá 24h pro paciente responder antes de alertar.
      const { data: dueData } = await supabase
        .from('product_events')
        .select('user_id, occurred_at')
        .eq('event', 'reevaluation.due')
        .gte('occurred_at', new Date(Date.now() - 48 * 3600 * 1000).toISOString())
        .lt('occurred_at', new Date(Date.now() - 24 * 3600 * 1000).toISOString())
      const dues = (dueData ?? []) as Array<{ user_id: string; occurred_at: string }>
      let reevaluationPending = 0
      for (const d of dues) {
        const { count: recomputed } = await supabase
          .from('tools_audit')
          .select('id', { count: 'exact', head: true })
          .eq('user_id', d.user_id)
          .in('tool_name', ['cadastra_dados_iniciais', 'define_protocolo'])
          .eq('success', true)
          .gte('created_at', d.occurred_at)
        if (!recomputed || recomputed === 0) reevaluationPending++
      }

      // 12. Pedido de registro de refeição SEM resposta NEM meal_log (caso Erika
      // 2026-05-17: pediu 3× "Registre meu almoço" e o agente ficou MUDO →
      // refeição perdida por silêncio). O guard fake-write NÃO pega isso (não há
      // texto do agente afirmando registro). Janela: inbounds entre 24h e SILENCE_H
      // atrás (folga pro agente responder antes de alertar). Flag se, na janela de
      // SILENCE_H após o pedido, NÃO houve nem outbound nem meal_log. Conta por
      // USUÁRIO (1 basta), pra não inflar com pedidos repetidos.
      const SILENCE_H = 3
      const { data: inboundRows } = await supabase
        .from('messages')
        .select('user_id, content, content_type, created_at')
        .eq('direction', 'in')
        .gte('created_at', new Date(Date.now() - 24 * 3600 * 1000).toISOString())
        .lt('created_at', new Date(Date.now() - SILENCE_H * 3600 * 1000).toISOString())
        .order('created_at', { ascending: true })
      const inboundMsgs = (inboundRows ?? []) as Array<{
        user_id: string
        content: string | null
        content_type: string
        created_at: string
      }>
      const unansweredUserIds = new Set<string>()
      for (const m of inboundMsgs) {
        if (unansweredUserIds.has(m.user_id)) continue
        if (!looksLikeRegistrationRequest({ content: m.content, contentType: m.content_type }))
          continue
        const until = new Date(
          new Date(m.created_at).getTime() + SILENCE_H * 3600 * 1000,
        ).toISOString()
        const { count: replied } = await supabase
          .from('messages')
          .select('user_id', { count: 'exact', head: true })
          .eq('user_id', m.user_id)
          .eq('direction', 'out')
          .gt('created_at', m.created_at)
          .lte('created_at', until)
        if (replied && replied > 0) continue
        const { count: logged } = await supabase
          .from('meal_logs')
          .select('user_id', { count: 'exact', head: true })
          .eq('user_id', m.user_id)
          .gt('created_at', m.created_at)
          .lte('created_at', until)
        if (logged && logged > 0) continue
        unansweredUserIds.add(m.user_id)
      }
      let unansweredNames = ''
      if (unansweredUserIds.size > 0) {
        const { data: us } = await supabase
          .from('users')
          .select('name')
          .in('id', [...unansweredUserIds])
        unansweredNames = ((us ?? []) as Array<{ name: string | null }>)
          .map((u) => u.name ?? '?')
          .join(', ')
      }

      // 13. Pais confirmado com timezone deterministicamente incompatível.
      // Read-only: o auditor sinaliza; nunca altera localização sozinho.
      const { data: locationUsers } = await supabase
        .from('users')
        .select('id, country, timezone, country_confirmed')
        .eq('country_confirmed', true)
      const timezoneMismatches = findTimezoneCountryMismatches(
        (locationUsers ?? []) as Array<{
          id: string
          country: string | null
          timezone: string | null
          country_confirmed: boolean | null
        }>,
      )

      return {
        unansweredRegistrations: unansweredUserIds.size,
        unansweredNames,
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
        reevaluationPending,
        turnos: costs.length,
        timezoneCountryMismatches: timezoneMismatches.length,
        timezoneMismatchUserIds: timezoneMismatches.map((row) => row.id),
      }
    })

    // Auditoria de blocos 7700. Por padrão é read-only: detecta divergências
    // sem alterar progresso. Auto-fix precisa ser ligado explicitamente via
    // global_config `audit.bloco_autofix_enabled=true`.
    const autofix = await step.run('auto-reconcile-blocos', async () => {
      const BLOCO_DIFF_TOL = 50
      const MAX_BLOCO_FIX = 8
      const autofixEnabled = await loadBooleanConfig(supabase, 'audit.bloco_autofix_enabled', false)
      const { data: progs, error: progressRowsError } = await supabase
        .from('user_progress')
        .select('user_id, deficit_block, blocks_completed')
      throwIfQueryFailed(progressRowsError, 'audit bloco progress lookup failed')
      const diverge: Array<{
        uid: string
        old: number
        neu: number
        oldB: number
        newB: number
        days: number
      }> = []
      for (const p of (progs ?? []) as Array<{
        user_id: string
        deficit_block: number | null
        blocks_completed: number | null
      }>) {
        const r = await recomputeUserBloco(supabase, p.user_id)
        if (
          Math.abs((p.deficit_block ?? 0) - r.correctDeficitBlock) > BLOCO_DIFF_TOL ||
          (p.blocks_completed ?? 0) !== r.correctBlocksCompleted
        ) {
          diverge.push({
            uid: p.user_id,
            old: p.deficit_block ?? 0,
            neu: r.correctDeficitBlock,
            oldB: p.blocks_completed ?? 0,
            newB: r.correctBlocksCompleted,
            days: r.daysClosed,
          })
        }
      }
      let applied = 0
      const decision = decideBlocoAutofix(diverge.length, MAX_BLOCO_FIX, autofixEnabled)
      if (decision.canApply) {
        for (const b of diverge) {
          await applyUserBlocoCorrection(supabase, b.uid, b.neu, b.newB)
          await supabase.from('product_events').insert({
            user_id: b.uid,
            event: 'audit.bloco_autofixed',
            properties: {
              old_deficit_block: b.old,
              new_deficit_block: b.neu,
              old_blocks: b.oldB,
              new_blocks: b.newB,
              days_closed: b.days,
            },
          })
          applied++
        }
      }
      return {
        divergeCount: diverge.length,
        applied,
        circuitBroke: decision.circuitBroke,
        disabled: decision.disabled,
        details: diverge.slice(0, 8).map((b) => `${b.old}→${b.neu}`),
      }
    })

    // Decide se há alerta crítico (vai pro topo da mensagem)
    const alerts: string[] = []
    if (autofix.circuitBroke)
      alerts.push(
        `🔴 ${autofix.divergeCount} blocos divergentes — auto-fix BLOQUEADO (circuit-breaker, revisar fórmula/dado)`,
      )
    else if (autofix.disabled && autofix.divergeCount > 0)
      alerts.push(
        `⚠️ ${autofix.divergeCount} bloco(s) divergente(s) — auto-fix desligado (read-only)`,
      )
    else if (autofix.applied > 0)
      alerts.push(`🔧 ${autofix.applied} bloco(s) auto-corrigido(s): ${autofix.details.join(', ')}`)
    if (metrics.pipelineErrors > 0) alerts.push(`🔴 ${metrics.pipelineErrors} pipeline.error`)
    if (metrics.numericMismatch > 3) alerts.push(`⚠️ ${metrics.numericMismatch} numeric mismatch`)
    if (metrics.sentimentMismatch > 0)
      alerts.push(`⚠️ ${metrics.sentimentMismatch} sentiment mismatch`)
    if (metrics.compositeRejected > 2)
      alerts.push(`⚠️ ${metrics.compositeRejected} composite rejected`)
    if (!metrics.snapshotIntegrityOk)
      alerts.push(`🔴 ${metrics.snapshotDivergencias} divergência snapshot`)
    if (metrics.balance != null && metrics.balance < 20)
      alerts.push(`🔴 saldo OpenRouter $${metrics.balance.toFixed(2)} < $20`)
    if (metrics.reevaluationPending > 0)
      alerts.push(
        `🔴 ${metrics.reevaluationPending} reavaliação(ões) sem recálculo há +24h — processar (peso/fome → meta)`,
      )
    if (metrics.unansweredRegistrations > 0)
      alerts.push(
        `🔴 ${metrics.unansweredRegistrations} pedido(s) de registro SEM resposta nem meal_log (agente mudo → refeição perdida): ${metrics.unansweredNames}`,
      )
    if (metrics.timezoneCountryMismatches > 0)
      alerts.push(
        `🔴 ${metrics.timezoneCountryMismatches} paciente(s) com país confirmado e timezone incompatível`,
      )

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
      `• Reavaliação pendente (+24h): ${metrics.reevaluationPending}\n` +
      `• Registro sem resposta: ${metrics.unansweredRegistrations}${metrics.unansweredRegistrations > 0 ? ` (${metrics.unansweredNames})` : ''}\n` +
      `• País/timezone incompatível: ${metrics.timezoneCountryMismatches}\n` +
      `\n*Auto-correção (blocos 7700)*\n` +
      (autofix.circuitBroke
        ? `• 🔴 ${autofix.divergeCount} divergentes — BLOQUEADO (circuit-breaker)\n`
        : autofix.disabled
          ? autofix.divergeCount > 0
            ? `• ⚠️ desligada — ${autofix.divergeCount} divergente(s) detectado(s), 0 correções\n`
            : `• ✅ desligada — todos em sincronia (0 correções)\n`
          : autofix.applied > 0
            ? `• 🔧 ${autofix.applied} corrigido(s): ${autofix.details.join(', ')}\n`
            : `• ✅ todos em sincronia (0 correções)\n`) +
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

    // Loga sempre (histórico). Envolto em step.run pra Inngest cachear —
    // sem isso, qualquer retry/restart do handler re-executa o insert e
    // duplica o evento. Observado em prod 2026-05-30: 2 inserts por horário
    // de cron, distância 2-35s, números idênticos.
    await step.run('persist-audit-event', async () => {
      await supabase.from('product_events').insert({
        event: 'audit.daily_report',
        properties: {
          ...metrics,
          alerts_count: alerts.length,
          bloco_autofixed: autofix.applied,
          bloco_diverge: autofix.divergeCount,
          bloco_circuit_broke: autofix.circuitBroke,
          bloco_autofix_disabled: autofix.disabled,
        },
      })
    })

    // Envia Telegram só se há alertas OU sempre (config). Default: sempre,
    // pra Eduardo ter visibilidade diária do estado.
    const botToken = process.env.TELEGRAM_BOT_TOKEN
    const adminChatId = process.env.TELEGRAM_ADMIN_CHAT_ID
    // Destinatários: o admin do env (Eduardo) + extras configurados no banco
    // (global_config 'audit.telegram_chat_ids', array de chat_ids). Assim dá pra
    // adicionar/remover gente SEM deploy — só editando a config. ⚠️ Cada pessoa
    // precisa ter dado /start no @MargotPiper_Bot antes (Telegram NÃO deixa bot
    // iniciar conversa) — senão o envio pra ela falha com 403 (logado, não trava).
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
      logger.warn('Telegram creds/destinatários ausentes — relatório só no banco')
      return { ok: true, alerts: alerts.length, sent: 0 }
    }

    // Envio RESILIENTE (bug 2026-05-21): antes era parse_mode:Markdown e lançava
    // erro em !res.ok. Um underscore no conteúdo ("sentiment_mismatch") quebrava
    // o Markdown legado (400) → o passo lançava → Inngest re-rodava a função
    // inteira → relatório duplicado no banco e ZERO entrega no Telegram.
    // Agora: tenta Markdown, cai pra texto puro se falhar, e NUNCA lança (um
    // erro de envio não deve re-rodar a auditoria). Loga falha por destinatário.
    const sent = await step.run('send-telegram', async () => {
      const postTo = (chatId: string, useMarkdown: boolean) =>
        fetch(`https://api.telegram.org/bot${botToken}/sendMessage`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            chat_id: chatId,
            text: msg,
            ...(useMarkdown ? { parse_mode: 'Markdown' } : {}),
            disable_web_page_preview: true,
          }),
        })
      let okCount = 0
      for (const chatId of recipients) {
        let res = await postTo(chatId, true)
        if (!res.ok) res = await postTo(chatId, false) // Markdown quebrou → texto puro
        if (!res.ok) {
          const body = await res.text().catch(() => '')
          await supabase.from('product_events').insert({
            event: 'audit.telegram_failed',
            properties: { chat_id: chatId, status: res.status, body: body.slice(0, 200) },
          })
        } else {
          okCount++
        }
      }
      return okCount
    })

    return { ok: true, alerts: alerts.length, sent, recipients: recipients.length, ...metrics }
  },
)
