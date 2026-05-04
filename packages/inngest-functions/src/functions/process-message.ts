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
import { loadHumanizerConfig } from '../lib/runtime-config.js'

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
    const {
      userId,
      wpp,
      providerMessageId,
      contentType,
      text,
      mediaUrl,
      mediaUrls,
      provider,
      timestamp,
    } = event.data

    // Suporta múltiplas mídias: prioriza mediaUrls[]; cai pro mediaUrl singular
    const allMediaUrls = mediaUrls && mediaUrls.length > 0 ? mediaUrls : mediaUrl ? [mediaUrl] : []

    logger.info('Processing', {
      userId,
      contentType,
      mediaCount: allMediaUrls.length,
    })

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

    // === Step 1.5: pausa? ===
    // Se o user está com paused_until > now, NÃO processa — só reage com 💤
    const pauseCheck = await step.run('check-pause', async (): Promise<{ paused: boolean; until: string | null }> => {
      const { supabase } = createWorkerDeps()
      const { data: u } = await supabase
        .from('users')
        .select('status, metadata')
        .eq('id', userId)
        .maybeSingle()
      if (!u) return { paused: false, until: null }
      const meta = (u as { metadata: Record<string, unknown> | null }).metadata
      const pausedUntil = meta?.paused_until as string | undefined
      if (pausedUntil && new Date(pausedUntil) > new Date()) {
        return { paused: true, until: pausedUntil }
      }
      return { paused: false, until: null }
    })

    if (pauseCheck.paused) {
      logger.info('User pausado, ignorando msg', { userId, until: pauseCheck.until })
      await messaging.react(wpp, providerMessageId, '💤').catch(() => {})
      return { ok: true, paused: true, until: pauseCheck.until }
    }

    // === Step 2: media prep — STT ou Vision ===
    let enrichedText: string | undefined = text
    let mediaSummary: { kind: 'audio' | 'image'; latency_ms: number } | null = null

    if (contentType === 'audio' && allMediaUrls.length > 0) {
      const sttRes = await step.run('stt-transcribe', async () => {
        if (!process.env.GROQ_API_KEY) {
          return { ok: false as const, reason: 'GROQ_API_KEY ausente', text: null, latency_ms: 0 }
        }
        try {
          const stt = new GroqSTT({ apiKey: process.env.GROQ_API_KEY })
          // Áudio: transcreve só o primeiro (cada áudio = um turno semântico)
          const blob = await messaging.downloadMedia(allMediaUrls[0]!)
          const r = await stt.transcribe({ audio: blob, language: 'pt' })
          return { ok: true as const, text: r.text, latency_ms: r.latencyMs }
        } catch (e) {
          return {
            ok: false as const,
            reason: e instanceof Error ? e.message : String(e),
            text: null,
            latency_ms: 0,
          }
        }
      })
      if (sttRes.ok) {
        enrichedText = sttRes.text || text
        mediaSummary = { kind: 'audio', latency_ms: sttRes.latency_ms }
        logger.info('STT done', { length: sttRes.text?.length, latency: sttRes.latency_ms })
      } else {
        logger.warn('STT skipped', { reason: sttRes.reason })
      }
    }

    if (contentType === 'image' && allMediaUrls.length > 0) {
      const vRes = await step.run('vision-analyze', async () => {
        if (!process.env.OPENROUTER_API_KEY) {
          return { ok: false as const, reason: 'OPENROUTER_API_KEY ausente', images: [] }
        }
        try {
          const vision = new GeminiVision({
            apiKey: process.env.OPENROUTER_API_KEY,
            heliconeApiKey: process.env.HELICONE_API_KEY,
          })
          const start = Date.now()
          // Processa TODAS as imagens em paralelo
          const analyses = await Promise.all(
            allMediaUrls.map(async (url) => {
              const blob = await messaging.downloadMedia(url)
              const buf = Buffer.from(await blob.arrayBuffer())
              const dataUri = `data:${blob.type || 'image/jpeg'};base64,${buf.toString('base64')}`
              return vision.analyzeImage(dataUri, { userMessage: text ?? undefined })
            }),
          )
          return { ok: true as const, images: analyses, latency_ms: Date.now() - start }
        } catch (e) {
          return {
            ok: false as const,
            reason: e instanceof Error ? e.message : String(e),
            images: [],
          }
        }
      })
      if (vRes.ok && vRes.images.length > 0) {
        // Formata cada imagem segundo seu tipo
        const blocks: string[] = []
        for (let i = 0; i < vRes.images.length; i++) {
          const img = vRes.images[i]!
          const idx = vRes.images.length > 1 ? `Foto ${i + 1}/${vRes.images.length}` : 'Foto'
          if (img.type === 'meal') {
            const itemsTxt =
              img.items
                .map(
                  (it) =>
                    `  - ${it.name}: ${it.quantity_g_estimate}g (conf ${(it.confidence * 100).toFixed(0)}%)`,
                )
                .join('\n') || '  (nenhum alimento identificado)'
            blocks.push(
              `${idx} [refeição]:\n${img.meal_context ? `  contexto: ${img.meal_context}\n` : ''}${itemsTxt}`,
            )
          } else if (img.type === 'body') {
            blocks.push(
              `${idx} [corporal · ${img.view}]:\n  BF% estimado: ${img.bf_percent_estimate ?? 'n/d'} (conf ${(img.bf_confidence * 100).toFixed(0)}%)\n  ${img.composition_notes}${img.posture_notes ? `\n  postura: ${img.posture_notes}` : ''}`,
            )
          } else if (img.type === 'scale') {
            blocks.push(
              `${idx} [balança]:\n  peso lido: ${img.weight_kg ?? 'n/d'} kg (conf ${(img.confidence * 100).toFixed(0)}%, unidade ${img.unit_detected})`,
            )
          } else {
            blocks.push(`${idx} [outra]:\n  ${img.description}`)
          }
        }
        enrichedText =
          `[${vRes.images.length} foto(s) recebida(s) — análise visual automática abaixo]\n\n` +
          blocks.join('\n\n') +
          (text ? `\n\nLegenda do usuário: "${text}"` : '')
        mediaSummary = { kind: 'image', latency_ms: vRes.latency_ms }
        logger.info('Vision done', {
          count: vRes.images.length,
          types: vRes.images.map((i) => i.type),
          latency: vRes.latency_ms,
        })
      } else {
        logger.warn('Vision skipped', { reason: vRes.ok ? 'sem imagens' : vRes.reason })
        if (text) {
          // Se não conseguiu ler mas tem caption, usa só a caption
          enrichedText = text
        } else {
          // Sem texto e sem vision: avisa o LLM explicitamente que recebeu foto mas não conseguiu ler
          enrichedText = `[${allMediaUrls.length} foto(s) recebida(s) — falhou ao baixar/analisar. Peça ao usuário pra reenviar ou descrever por texto. NÃO INVENTE o conteúdo.]`
        }
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
      // Humanizer config editável via /settings/global → humanizer.*
      // Process-message usa response_max_delay_ms (maior que engagement
      // pra parecer "pensando" antes de responder).
      const humanizer = await loadHumanizerConfig(supabase)
      const sendResults = await step.run('send-to-user', async () =>
        sendHumanized(messaging, wpp, result.text, {
          showTyping: true,
          minDelay: humanizer.min_delay_ms,
          maxDelay: humanizer.response_max_delay_ms,
          charsPerSecond: humanizer.chars_per_second,
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
