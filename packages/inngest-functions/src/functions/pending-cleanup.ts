/**
 * Worker: cleanup de pending_registrations expirados.
 *
 * Roda a cada 5 minutos via cron Inngest. Marca como 'expired' todo pending
 * que passou do TTL sem o paciente tocar/responder. Sem isso, a tabela
 * acumula 'pending' órfãos pra sempre (o handler do tap só marca expired
 * quando há tap — se o paciente nunca volta, fica eternamente 'pending').
 *
 * Não afeta correção do fluxo: o handler do tap já checa expires_at > now
 * antes de processar, e a query do DEC-3 fallback também filtra por expiry.
 * Esse cleanup é só hygiene de DB + KPI de "% pendings que expiraram sem
 * resposta" (sinal de UX ruim ou paciente não engajado).
 *
 * Roberto 2026-05-28 — Fase B/D botões #4 (opção #4).
 */
import { inngest } from '../client.js'
import { createWorkerDeps } from '../lib/env.js'

export const pendingCleanupFn = inngest.createFunction(
  { id: 'pending-registrations-cleanup', retries: 1, concurrency: { limit: 1 } },
  { cron: '*/5 * * * *' },
  async ({ step, logger }) => {
    return await step.run('cleanup-expired-pendings', async () => {
      const { supabase } = createWorkerDeps()
      const nowIso = new Date().toISOString()
      const { data, error } = await supabase
        .from('pending_registrations')
        .update({ status: 'expired', resolved_at: nowIso })
        .eq('status', 'pending')
        .lte('expires_at', nowIso)
        .select('id')
      if (error) {
        logger.error('cleanup error', { error: error.message })
        return { expired: 0, error: error.message }
      }
      const count = (data ?? []).length
      if (count > 0) {
        await supabase.from('product_events').insert({
          user_id: null,
          event: 'pending.cleanup_expired',
          properties: { count, ran_at: nowIso },
        })
        logger.info('expired pendings cleaned', { count })
      }
      return { expired: count }
    })
  },
)
