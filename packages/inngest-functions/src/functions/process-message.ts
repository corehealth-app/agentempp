import { createMessagingProvider, sendHumanized } from '@mpp/providers'
import { inngest } from '../client.js'
import { createWorkerDeps, processMessage } from '../lib/env.js'

/**
 * Worker principal: processa cada mensagem recebida.
 *
 * Steps:
 *   1. Pipeline @mpp/agent (LLM, tools, persistência da resposta no DB)
 *   2. Envia resposta via MessagingProvider (humanizado: split + delay)
 *
 * Concurrency limit=1 por user_id (evita race em msgs simultâneas).
 */
export const processMessageFn = inngest.createFunction(
  {
    id: 'process-message',
    retries: 3,
    concurrency: { key: 'event.data.userId', limit: 1 },
  },
  { event: 'message.received' },
  async ({ event, step, logger }) => {
    const { userId, wpp, providerMessageId, contentType, text, mediaUrl, provider, timestamp } =
      event.data

    logger.info('Processing message', { userId, contentType })

    // ============================================================
    //  Step 1: pipeline do agente (LLM + tools)
    // ============================================================
    const result = await step.run('agent-pipeline', async () => {
      const deps = createWorkerDeps()
      return processMessage(deps, {
        from: wpp,
        providerMessageId,
        contentType,
        text,
        mediaUrl,
        provider,
        timestamp: new Date(timestamp),
      })
    })

    logger.info('Pipeline done', {
      userId,
      stage: result.stage,
      cost: result.costUsd,
      tokens: result.promptTokens + result.completionTokens,
      tools: result.toolCalls.map((t) => t.name),
    })

    // ============================================================
    //  Step 2: envio humanizado da resposta
    // ============================================================
    if (!result.text || !result.text.trim()) {
      logger.warn('Pipeline returned empty response', { userId })
      return { ok: true, sent: 0, reason: 'empty response', stage: result.stage }
    }

    const sendResults = await step.run('send-to-user', async () => {
      const messaging = createMessagingProvider({
        MESSAGING_PROVIDER: process.env.MESSAGING_PROVIDER ?? 'whatsapp_cloud',
        META_PHONE_NUMBER_ID: process.env.META_PHONE_NUMBER_ID,
        META_ACCESS_TOKEN: process.env.META_ACCESS_TOKEN,
        META_APP_SECRET: process.env.META_APP_SECRET,
        META_VERIFY_TOKEN: process.env.META_VERIFY_TOKEN,
      })

      // Marca a mensagem do usuário como lida (✓✓ azul)
      try {
        await messaging.markRead(providerMessageId)
      } catch (e) {
        logger.warn('markRead failed', { error: String(e) })
      }

      // Envio humanizado: split por \n\n + delay proporcional ao tamanho
      return sendHumanized(messaging, wpp, result.text, {
        showTyping: true,
        minDelay: 800,
        maxDelay: 3500,
        charsPerSecond: 55,
      })
    })

    const sentCount = sendResults.filter((r) => r.status === 'sent').length
    const failedCount = sendResults.filter((r) => r.status !== 'sent').length

    logger.info('Sent', { userId, sent: sentCount, failed: failedCount, stage: result.stage })

    return {
      ok: true,
      sent: sentCount,
      failed: failedCount,
      stage: result.stage,
      response: result.text,
      latency_ms: result.latencyMs,
    }
  },
)
