import { inngest } from '../client.js'
import { createWorkerDeps } from '../lib/env.js'

/**
 * Worker: consome buffer de mensagens vencido.
 *
 * Disparado pelo webhook com delay (8s) ou pelo cron buffer-flush.
 * IDEMPOTENTE: só processa se ainda existir buffer com flush_after expirado.
 *
 * Fluxo:
 *   1. Lê message_buffer do user
 *   2. Se vazio ou flush_after futuro → no-op (outra invocação já processou)
 *   3. Agrega texts em uma única mensagem
 *   4. Dispara process-message com texto agregado e providerMessageId da MAIS RECENTE
 *   5. Limpa buffer
 *
 * Concurrency=1 por userId — garante que só um flush roda por user.
 */
export const bufferListenerFn = inngest.createFunction(
  {
    id: 'buffer-listener',
    retries: 1,
    concurrency: { key: 'event.data.userId', limit: 1 },
  },
  { event: 'buffer.flush' },
  async ({ event, step, logger }) => {
    const userId = (event.data as { userId?: string }).userId
    if (!userId) return { dispatched: false, reason: 'sem userId no payload' }

    const result = await step.run('flush-buffer', async () => {
      const { supabase } = createWorkerDeps()

      const { data: buf } = await supabase
        .from('message_buffer')
        .select('user_id, messages, flush_after')
        .eq('user_id', userId)
        .maybeSingle()

      if (!buf) return { dispatched: false, reason: 'sem buffer' }

      const now = Date.now()
      const flushAt = new Date(buf.flush_after).getTime()

      // Ainda no debounce? Outra invocação vai pegar.
      if (flushAt > now) {
        return { dispatched: false, reason: 'ainda em debounce', remaining_ms: flushAt - now }
      }

      const msgs =
        (buf.messages as Array<{
          provider_message_id: string
          content_type: string
          text?: string | null
          mediaUrl?: string | null
          received_at: string
        }>) ?? []

      if (msgs.length === 0) {
        await supabase.from('message_buffer').delete().eq('user_id', userId)
        return { dispatched: false, reason: 'buffer vazio' }
      }

      const { data: user } = await supabase
        .from('users')
        .select('wpp')
        .eq('id', userId)
        .maybeSingle()
      if (!user) return { dispatched: false, reason: 'user not found' }

      // Agrega texts (\n entre msgs)
      const aggregated = msgs
        .map((m) => m.text)
        .filter(Boolean)
        .join('\n')
        .trim()

      // Msg mais recente é referência para typing/reactions
      const latest = msgs[msgs.length - 1]!

      // Determina contentType: mídia tem prioridade
      const hasAudio = msgs.some((m) => m.content_type === 'audio')
      const hasImage = msgs.some((m) => m.content_type === 'image')
      const contentType = hasAudio ? 'audio' : hasImage ? 'image' : 'text'
      const mediaUrl = msgs.find((m) => m.mediaUrl)?.mediaUrl ?? undefined

      await inngest.send({
        name: 'message.received',
        data: {
          userId,
          wpp: (user as { wpp: string }).wpp,
          providerMessageId: latest.provider_message_id,
          contentType,
          text: aggregated || undefined,
          mediaUrl: mediaUrl ?? undefined,
          provider: 'whatsapp_cloud',
          timestamp: latest.received_at,
        },
      })

      await supabase.from('message_buffer').delete().eq('user_id', userId)

      return {
        dispatched: true,
        aggregated_count: msgs.length,
        text_length: aggregated.length,
      }
    })

    logger.info('Buffer flush result', { userId, ...result })
    return result
  },
)
