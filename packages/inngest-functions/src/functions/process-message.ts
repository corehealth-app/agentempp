import {
  GeminiVision,
  GroqSTT,
  TTSRouter,
  createMessagingProvider,
  rewriteForTTS,
  sendHumanized,
} from '@mpp/providers'
import { inngest } from '../client.js'
import { createWorkerDeps, loadCredential, processMessage } from '../lib/env.js'

/**
 * Worker principal: processa cada mensagem recebida.
 *
 * Fluxo:
 *   1. ack: showTypingFor + 👀 reaction (mídia)
 *   2. media-prep: STT (áudio→texto) ou Vision (foto→análise estruturada)
 *   3. agent-pipeline: LLM + tools (texto enriquecido)
 *   4. send-to-user: TTS (se preferAudio) OU sendHumanized
 *   5. final-reaction: ✅ tool ok, ⚠️ tool err, 🤔 vazio, '' remove 👀
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

    logger.info('Processing', { userId, contentType, hasMedia: !!mediaUrl })

    const messaging = createMessagingProvider({
      MESSAGING_PROVIDER: process.env.MESSAGING_PROVIDER ?? 'whatsapp_cloud',
      META_PHONE_NUMBER_ID: process.env.META_PHONE_NUMBER_ID,
      META_ACCESS_TOKEN: process.env.META_ACCESS_TOKEN,
      META_APP_SECRET: process.env.META_APP_SECRET,
      META_VERIFY_TOKEN: process.env.META_VERIFY_TOKEN,
    })

    // === Step 1: ack ===
    await step.run('ack', async () => {
      await messaging.showTypingFor(providerMessageId).catch(() => {})
      if (contentType === 'audio' || contentType === 'image') {
        await messaging.react(wpp, providerMessageId, '👀').catch(() => {})
      }
      return { acked: true }
    })

    // === Step 2: media prep — STT ou Vision ===
    let enrichedText: string | undefined = text
    let mediaSummary: { kind: 'audio' | 'image'; latency_ms: number } | null = null

    if (contentType === 'audio' && mediaUrl) {
      const sttRes = await step.run('stt-transcribe', async () => {
        if (!process.env.GROQ_API_KEY) {
          return { ok: false as const, reason: 'GROQ_API_KEY ausente', text: null, latency_ms: 0 }
        }
        const stt = new GroqSTT({ apiKey: process.env.GROQ_API_KEY })
        const blob = await messaging.downloadMedia(mediaUrl)
        const r = await stt.transcribe({ audio: blob, language: 'pt' })
        return { ok: true as const, text: r.text, latency_ms: r.latencyMs }
      })
      if (sttRes.ok) {
        enrichedText = sttRes.text || text
        mediaSummary = { kind: 'audio', latency_ms: sttRes.latency_ms }
        logger.info('STT done', { length: sttRes.text?.length, latency: sttRes.latency_ms })
      } else {
        logger.warn('STT skipped', { reason: sttRes.reason })
      }
    }

    if (contentType === 'image' && mediaUrl) {
      const vRes = await step.run('vision-analyze', async () => {
        if (!process.env.OPENROUTER_API_KEY) {
          return { ok: false as const, reason: 'OPENROUTER_API_KEY ausente' }
        }
        const vision = new GeminiVision({
          apiKey: process.env.OPENROUTER_API_KEY,
          heliconeApiKey: process.env.HELICONE_API_KEY,
        })
        const blob = await messaging.downloadMedia(mediaUrl)
        const buf = Buffer.from(await blob.arrayBuffer())
        const dataUri = `data:${blob.type || 'image/jpeg'};base64,${buf.toString('base64')}`
        const r = await vision.analyzeMeal(dataUri, text ?? undefined)
        return {
          ok: true as const,
          items: r.items,
          meal_context: r.meal_context,
          raw_response: r.raw_response,
          latency_ms: r.latencyMs,
        }
      })
      if (vRes.ok) {
        const itemsTxt = vRes.items
          .map(
            (it) =>
              `- ${it.name}: ${it.quantity_g_estimate}g (confiança ${(it.confidence * 100).toFixed(0)}%)${it.notes ? ` — ${it.notes}` : ''}`,
          )
          .join('\n')
        enrichedText =
          `[Foto de refeição enviada pelo usuário]\n` +
          (vRes.meal_context ? `Contexto: ${vRes.meal_context}\n` : '') +
          `Itens identificados (análise visual automática):\n${itemsTxt}\n` +
          (text ? `\nLegenda do usuário: "${text}"` : '')
        mediaSummary = { kind: 'image', latency_ms: vRes.latency_ms }
        logger.info('Vision done', { items: vRes.items.length, latency: vRes.latency_ms })
      } else {
        logger.warn('Vision skipped', { reason: vRes.reason })
      }
    }

    // === Step 3: pipeline ===
    let result
    try {
      result = await step.run('agent-pipeline', async () => {
        const deps = createWorkerDeps()
        return processMessage(deps, {
          from: wpp,
          providerMessageId,
          contentType,
          text: enrichedText,
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

    // === Step 4: envio ===
    if (!result.text || !result.text.trim()) {
      await messaging.react(wpp, providerMessageId, '🤔').catch(() => {})
      return { ok: true, sent: 0, reason: 'empty', stage: result.stage, media: mediaSummary }
    }

    // TTS credentials: tenta env → service_credentials
    const { supabase, llm } = createWorkerDeps()
    const elevenlabsKey = await loadCredential(
      supabase,
      'ELEVENLABS_API_KEY',
      'elevenlabs',
      'api_key',
    )
    const elevenlabsVoice = await loadCredential(
      supabase,
      'ELEVENLABS_VOICE_ID',
      'elevenlabs',
      'voice_id',
    )

    const wantsAudio = result.preferAudio && !!elevenlabsKey && !!elevenlabsVoice

    let sentCount = 0
    let failedCount = 0
    let sendMode: 'text' | 'audio' = 'text'

    if (wantsAudio) {
      sendMode = 'audio'
      const audioRes = await step.run('send-audio', async () => {
        const speechText = await rewriteForTTS(llm, result.text).catch(() => result.text)
        const cartesiaKey = await loadCredential(
          supabase,
          'CARTESIA_API_KEY',
          'cartesia',
          'api_key',
        )
        const cartesiaVoice = await loadCredential(
          supabase,
          'CARTESIA_VOICE_ID',
          'cartesia',
          'voice_id',
        )
        const tts = new TTSRouter({
          elevenlabs: { apiKey: elevenlabsKey!, voiceId: elevenlabsVoice! },
          cartesia:
            cartesiaKey && cartesiaVoice
              ? { apiKey: cartesiaKey, voiceId: cartesiaVoice }
              : undefined,
        })
        const { result: ttsResult, provider: ttsProvider } = await tts.synthesize(
          speechText,
          'standard',
        )
        const blob = new Blob([new Uint8Array(ttsResult.audio)], { type: ttsResult.mimeType })
        const mediaId = await messaging.uploadMedia(blob, ttsResult.mimeType)
        const sendResult = await messaging.sendAudio(wpp, mediaId)
        return {
          status: sendResult.status,
          chars: speechText.length,
          tts_provider: ttsProvider,
          tts_latency_ms: ttsResult.durationMs,
        }
      })
      if (audioRes.status === 'sent') sentCount = 1
      else failedCount = 1
      logger.info('Audio sent', audioRes)
    } else {
      const sendResults = await step.run('send-to-user', async () =>
        sendHumanized(messaging, wpp, result.text, {
          showTyping: true,
          minDelay: 800,
          maxDelay: 3500,
          charsPerSecond: 55,
          inReplyTo: providerMessageId,
          replyTo: result.toolCalls.length > 0 ? providerMessageId : undefined,
        }),
      )
      sentCount = sendResults.filter((r) => r.status === 'sent').length
      failedCount = sendResults.filter((r) => r.status !== 'sent').length
    }

    // === Step 5: reação final ===
    await step.run('final-reaction', async () => {
      if (result.toolCalls.length > 0) {
        const allOk = result.toolCalls.every((t) => !t.error)
        await messaging.react(wpp, providerMessageId, allOk ? '✅' : '⚠️').catch(() => {})
      } else if (contentType === 'audio' || contentType === 'image') {
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
      send_mode: sendMode,
      media: mediaSummary,
      latency_ms: result.latencyMs,
    }
  },
)
