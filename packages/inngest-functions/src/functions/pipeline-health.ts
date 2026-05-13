import { inngest } from '../client.js'
import { createWorkerDeps } from '../lib/env.js'

/**
 * Worker: detecta "pipeline parado".
 *
 * Contexto (2026-05-13): após deploy manual via `vercel --prod`, o Inngest
 * fica fora de sync e perde o registro das functions. Webhook recebe msgs
 * (escreve em `messages`) mas o evento Inngest não dispara o processamento.
 * Sistema fica mudo por horas sem alerta.
 *
 * Detecção: incoming msg sem resposta out em >10min é sinal de pipeline parado.
 *
 * Ação:
 *   1. Loga `pipeline.stuck` event com lista de user_ids afetados
 *   2. Faz auto-sync do Inngest (PUT /api/inngest) — recupera o caso típico
 *      de "registration drift" pós-deploy manual.
 *   3. (Futuro: alerta WhatsApp pro admin se persistir.)
 *
 * Roda via pg_cron a cada 5min disparando `pipeline.health.tick`.
 */
export const pipelineHealthFn = inngest.createFunction(
  { id: 'pipeline-health-check', retries: 1 },
  { event: 'pipeline.health.tick' },
  async ({ step, logger }) => {
    return step.run('check', async () => {
      const { supabase } = createWorkerDeps()
      const tenMinAgo = new Date(Date.now() - 10 * 60 * 1000).toISOString()
      const twoHoursAgo = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString()

      // Busca incoming msgs entre 10min e 2h atrás (janela razoável).
      // 2h limit evita re-detectar incidente antigo já resolvido manualmente.
      const { data: recentIn } = await supabase
        .from('messages')
        .select('id, user_id, created_at')
        .eq('direction', 'in')
        .gte('created_at', twoHoursAgo)
        .lte('created_at', tenMinAgo)
        .order('created_at', { ascending: false })
        .limit(50)
      const incoming = (recentIn ?? []) as Array<{
        id: string
        user_id: string
        created_at: string
      }>
      if (incoming.length === 0) {
        return { ok: true, stuck_users: 0 }
      }

      // Pra cada user com IN recente, checa se houve OUT depois.
      // user_ids únicos primeiro pra reduzir queries.
      const byUser = new Map<string, string>()
      for (const m of incoming) {
        const prev = byUser.get(m.user_id)
        if (!prev || prev < m.created_at) byUser.set(m.user_id, m.created_at)
      }
      const stuck: Array<{ user_id: string; last_in: string }> = []
      for (const [userId, lastIn] of byUser.entries()) {
        const { data: lastOut } = await supabase
          .from('messages')
          .select('id, created_at')
          .eq('user_id', userId)
          .eq('direction', 'out')
          .gt('created_at', lastIn)
          .order('created_at', { ascending: false })
          .limit(1)
        if (!lastOut || (lastOut as unknown[]).length === 0) {
          stuck.push({ user_id: userId, last_in: lastIn })
        }
      }

      if (stuck.length === 0) {
        return { ok: true, stuck_users: 0 }
      }

      // Pipeline parado detectado. Loga + tenta auto-recovery.
      await supabase.from('product_events').insert({
        event: 'pipeline.stuck',
        properties: {
          stuck_count: stuck.length,
          users: stuck.map((s) => ({ user_id: s.user_id, last_in: s.last_in })),
        },
      })

      // Auto-sync Inngest. Caso típico: deploy manual perdeu registro.
      // Usa a URL pública do app (configurada em INNGEST_SYNC_URL ou default).
      const syncUrl =
        process.env.INNGEST_SYNC_URL ?? 'https://agentempp.vercel.app/api/inngest'
      let syncResult = 'skipped'
      try {
        const resp = await fetch(syncUrl, { method: 'PUT' })
        const body = await resp.text()
        syncResult = `${resp.status}:${body.slice(0, 120)}`
        await supabase.from('product_events').insert({
          event: 'pipeline.auto_sync',
          properties: {
            status: resp.status,
            response: body.slice(0, 200),
            triggered_by_stuck: stuck.length,
          },
        })
      } catch (e) {
        syncResult = e instanceof Error ? `error:${e.message}` : 'error:unknown'
        logger.error('Inngest auto-sync failed', { error: syncResult })
      }

      return { ok: false, stuck_users: stuck.length, sync_result: syncResult }
    })
  },
)
