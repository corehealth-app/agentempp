import { inngest } from '../client.js'
import { createWorkerDeps, processMessage } from '../lib/env.js'

/**
 * Worker principal: processa cada mensagem recebida do WhatsApp.
 *
 * Concurrency limitado a 1 por usuário (evita race entre msgs do mesmo user).
 * Retry automático em falhas transientes.
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

    const result = await step.run('process', async () => {
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

    logger.info('Message processed', {
      userId,
      stage: result.stage,
      cost: result.costUsd,
      tokens: result.promptTokens + result.completionTokens,
      tools: result.toolCalls.map((t) => t.name),
    })

    return {
      ok: true,
      stage: result.stage,
      response: result.text,
      latency_ms: result.latencyMs,
    }
  },
)
