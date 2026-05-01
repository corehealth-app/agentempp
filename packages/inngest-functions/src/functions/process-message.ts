import { createMessagingProvider, sendHumanized } from '@mpp/providers'
import { inngest } from '../client.js'
import { createWorkerDeps, processMessage } from '../lib/env.js'

/**
 * Worker principal: processa cada mensagem recebida.
 *
 * UX rica do WhatsApp:
 *   1. ✓✓ azul (markRead implícito no showTypingFor)
 *   2. 👀 reaction (visto / processando) — para mídia (foto/áudio)
 *   3. "digitando..." real (showTypingFor)
 *   4. Pipeline @mpp/agent (LLM + tools)
 *   5. Reaction final ✅ se tool call ok, ⚠️ se erro, ❌ se exception
 *   6. sendHumanized: split por \n\n + delay 800-3500ms + quoted reply no 1º chunk
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

    logger.info('Processing', { userId, contentType })

    const messaging = createMessagingProvider({
      MESSAGING_PROVIDER: process.env.MESSAGING_PROVIDER ?? 'whatsapp_cloud',
      META_PHONE_NUMBER_ID: process.env.META_PHONE_NUMBER_ID,
      META_ACCESS_TOKEN: process.env.META_ACCESS_TOKEN,
      META_APP_SECRET: process.env.META_APP_SECRET,
      META_VERIFY_TOKEN: process.env.META_VERIFY_TOKEN,
    })

    // === Step 1: Ack rápido — typing + reação 👀 ===
    await step.run('ack', async () => {
      // Marca como lida (✓✓ azul) + ativa "digitando..." real
      await messaging.showTypingFor(providerMessageId).catch(() => {})
      // Reação 👀 só pra mídia (sinaliza "estou processando isso")
      if (contentType === 'audio' || contentType === 'image') {
        await messaging.react(wpp, providerMessageId, '👀').catch(() => {})
      }
      return { acked: true }
    })

    // === Step 2: pipeline do agente ===
    let result
    try {
      result = await step.run('agent-pipeline', async () => {
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
    } catch (err) {
      await messaging.react(wpp, providerMessageId, '❌').catch(() => {})
      await messaging
        .sendText(wpp, 'Tive um problema agora. Tenta de novo em alguns segundos? 🙏', {
          replyTo: providerMessageId,
        })
        .catch(() => {})
      throw err
    }

    logger.info('Pipeline done', {
      userId,
      stage: result.stage,
      cost: result.costUsd,
      tools: result.toolCalls.map((t) => t.name),
    })

    // === Step 3: envio humanizado ===
    if (!result.text || !result.text.trim()) {
      await messaging.react(wpp, providerMessageId, '🤔').catch(() => {})
      return { ok: true, sent: 0, reason: 'empty', stage: result.stage }
    }

    const sendResults = await step.run('send-to-user', async () =>
      sendHumanized(messaging, wpp, result.text, {
        showTyping: true,
        minDelay: 800,
        maxDelay: 3500,
        charsPerSecond: 55,
        inReplyTo: providerMessageId,
        // Quoted reply no 1º chunk se houve tool call
        replyTo: result.toolCalls.length > 0 ? providerMessageId : undefined,
      }),
    )

    const sentCount = sendResults.filter((r) => r.status === 'sent').length
    const failedCount = sendResults.filter((r) => r.status !== 'sent').length

    // === Step 4: reação final ===
    await step.run('final-reaction', async () => {
      if (result.toolCalls.length > 0) {
        const allOk = result.toolCalls.every((t) => !t.error)
        await messaging.react(wpp, providerMessageId, allOk ? '✅' : '⚠️').catch(() => {})
      } else if (contentType === 'audio' || contentType === 'image') {
        // Remove o 👀 do step 1 já que o conteúdo foi processado
        await messaging.react(wpp, providerMessageId, '').catch(() => {})
      }
      return { ok: true }
    })

    return {
      ok: true,
      sent: sentCount,
      failed: failedCount,
      stage: result.stage,
      tools: result.toolCalls.length,
      latency_ms: result.latencyMs,
    }
  },
)
