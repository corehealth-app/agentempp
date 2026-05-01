import { inngest } from '../client.js'
import { createWorkerDeps } from '../lib/env.js'

/**
 * Worker: processa buffers vencidos.
 *
 * Disparado a cada minuto pelo cron buffer-flush (NOTIFY).
 * Lê message_buffer cujo flush_after já passou, agrupa as mensagens
 * em um único turno e dispara message.received para o process-message.
 */
export const bufferListenerFn = inngest.createFunction(
  { id: 'buffer-listener', retries: 1, concurrency: { limit: 5 } },
  { event: 'buffer.flush' },
  async ({ step, logger }) => {
    const flushed = await step.run('flush-buffers', async () => {
      const { supabase } = createWorkerDeps()
      const { data: buffers } = await supabase
        .from('message_buffer')
        .select('user_id, messages, flush_after')
        .lt('flush_after', new Date().toISOString())

      if (!buffers || buffers.length === 0) return 0

      let count = 0
      for (const buf of buffers) {
        // Busca user p/ pegar wpp
        const { data: user } = await supabase
          .from('users')
          .select('wpp')
          .eq('id', buf.user_id)
          .maybeSingle()

        if (!user) continue

        // Agrega texto
        const msgs = (buf.messages as Array<{ text?: string; type?: string; mediaUrl?: string }>) ?? []
        const aggregatedText = msgs
          .map((m) => m.text ?? '')
          .filter(Boolean)
          .join('\n')

        // Dispara processamento
        await inngest.send({
          name: 'message.received',
          data: {
            userId: buf.user_id,
            wpp: user.wpp,
            providerMessageId: `buffer_${Date.now()}_${buf.user_id}`,
            contentType: 'text',
            text: aggregatedText,
            provider: 'whatsapp_cloud',
            timestamp: new Date().toISOString(),
          },
        })

        // Limpa buffer
        await supabase.from('message_buffer').delete().eq('user_id', buf.user_id)
        count++
      }

      return count
    })

    logger.info('Buffer flushed', { count: flushed })
    return { flushed }
  },
)
