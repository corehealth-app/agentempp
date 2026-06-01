import { detectPendingResponse, splitRegistrationParts } from '@mpp/agent'
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
import { loadHumanizerConfig, loadVisionConfig } from '../lib/runtime-config.js'

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

    // === FASE B/D — DEC-3: paciente digita "sim"/"editar" em vez de tocar ===
    // Antes de qualquer outro processamento, se for texto curto que casa com
    // padrão de confirm/edit E houver pending em aberto pra esse paciente,
    // tratamos como TAP — dispara o mesmo evento Inngest do botão (handler
    // determinístico). Conservador: só fica ativo pra paciente com
    // buttons_enabled, e só intercepta texto curto. Roberto 2026-05-28.
    if (contentType === 'text' && text) {
      const responseKind = detectPendingResponse(text)
      if (responseKind) {
        const handled = await step.run('text-pending-fallback', async () => {
          const { supabase } = createWorkerDeps()
          const { data: pending } = await supabase
            .from('pending_registrations')
            .select('id')
            .eq('user_id', userId)
            .eq('status', 'pending')
            .gt('expires_at', new Date().toISOString())
            .order('created_at', { ascending: false })
            .limit(1)
            .maybeSingle()
          const pendingId = (pending as { id: string } | null)?.id
          if (!pendingId) return { dispatched: false, reason: 'no_active_pending' }
          await inngest.send({
            name: 'interactive.button.tapped',
            data: {
              userId,
              wpp,
              buttonId: `${responseKind}_${pendingId}`,
              buttonTitle: responseKind === 'confirm' ? 'Sim, registrar' : 'Editar',
              providerMessageId,
              tappedAt: new Date().toISOString(),
            },
          })
          await supabase.from('product_events').insert({
            user_id: userId,
            event: 'pending.text_fallback',
            properties: { pendingId, response: responseKind, text_preview: text.slice(0, 50) },
          })
          return { dispatched: true, pendingId, responseKind }
        })
        if ((handled as { dispatched?: boolean })?.dispatched) {
          return {
            ok: true,
            sent: 0,
            reason: 'text_fallback_to_button_handler',
            kind: responseKind,
          }
        }
        // Sem pending ativo → cai no fluxo normal (LLM responde)
      }
    }

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
      // Observabilidade: loga STT (sucesso ou falha). Sem isso, audio quebrado
      // só vira visível quando paciente reclama (caso Paulo 05-13).
      try {
        const { supabase } = createWorkerDeps()
        await supabase.from('product_events').insert({
          user_id: userId,
          event: sttRes.ok ? 'stt.transcribed' : 'stt.failed',
          properties: {
            provider_message_id: providerMessageId,
            success: sttRes.ok,
            latency_ms: sttRes.latency_ms,
            text_length: sttRes.ok ? (sttRes.text?.length ?? 0) : 0,
            text_preview: sttRes.ok ? (sttRes.text ?? '').slice(0, 120) : null,
            reason: !sttRes.ok ? sttRes.reason : null,
            provider: 'groq-whisper',
            language: 'pt',
          },
        })
        // Persiste transcrição em messages.content pra rastreabilidade.
        // Antes ficava só no contexto LLM e sumia — banco mostrava content vazio.
        if (sttRes.ok && sttRes.text && providerMessageId) {
          await supabase
            .from('messages')
            .update({ content: sttRes.text })
            .eq('provider_message_id', providerMessageId)
            .eq('direction', 'in')
        }
      } catch (logErr) {
        logger.warn('STT event log failed', {
          error: logErr instanceof Error ? logErr.message : String(logErr),
        })
      }
    }

    if (contentType === 'image' && allMediaUrls.length > 0) {
      const visionCfg = await step.run('vision-config', async () => {
        const { supabase } = createWorkerDeps()
        return loadVisionConfig(supabase)
      })
      const vRes = await step.run('vision-analyze', async () => {
        if (!process.env.OPENROUTER_API_KEY) {
          return { ok: false as const, reason: 'OPENROUTER_API_KEY ausente', images: [] }
        }
        try {
          const vision = new GeminiVision({
            apiKey: process.env.OPENROUTER_API_KEY,
            heliconeApiKey: process.env.HELICONE_API_KEY,
            model: visionCfg.model,
            nutritionLabelModel: visionCfg.nutrition_label_model,
            prompts: visionCfg.prompts,
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
        let bodyBf: { estimate: number; confidence: number } | null = null
        for (let i = 0; i < vRes.images.length; i++) {
          const img = vRes.images[i]!
          const idx = vRes.images.length > 1 ? `Foto ${i + 1}/${vRes.images.length}` : 'Foto'
          if (img.type === 'meal') {
            const threshold = visionCfg.meal_confidence_threshold
            const lowConfItems = img.items.filter((it) => it.confidence < threshold)
            const itemsTxt =
              img.items
                .map((it) => {
                  const confPct = (it.confidence * 100).toFixed(0)
                  const flag = it.confidence < threshold ? ' ⚠️ INCERTO' : ''
                  return `  - ${it.name}: ${it.quantity_g_estimate}g (conf ${confPct}%${flag})`
                })
                .join('\n') || '  (nenhum alimento identificado)'
            const guidance =
              img.items.length === 0
                ? '\n  ⚠️ AÇÃO: a vision não identificou nada. Pergunte ao paciente o que ele comeu (descreva o prato), NÃO chute.'
                : lowConfItems.length > 0
                  ? `\n  ⚠️ AÇÃO: ${lowConfItems.length} item(ns) com confiança baixa marcados ⚠️. Antes de chamar registra_refeicao, CONFIRME esses itens com o paciente em 1 pergunta curta (ex: "Recebi a foto. Vi X com certeza, mas tô em dúvida se isso é Y ou Z — confirma?"). Itens com conf ≥ 60% pode registrar direto.`
                  : ''
            blocks.push(
              `${idx} [refeição]:\n${img.meal_context ? `  contexto: ${img.meal_context}\n` : ''}${itemsTxt}${guidance}`,
            )
          } else if (img.type === 'body') {
            blocks.push(
              `${idx} [corporal · ${img.view}]:\n  BF% estimado: ${img.bf_percent_estimate ?? 'n/d'} (conf ${(img.bf_confidence * 100).toFixed(0)}%)\n  ${img.composition_notes}${img.posture_notes ? `\n  postura: ${img.posture_notes}` : ''}`,
            )
            if (img.bf_percent_estimate != null) {
              bodyBf = { estimate: img.bf_percent_estimate, confidence: img.bf_confidence }
            }
          } else if (img.type === 'scale') {
            blocks.push(
              `${idx} [balança]:\n  peso lido: ${img.weight_kg ?? 'n/d'} kg (conf ${(img.confidence * 100).toFixed(0)}%, unidade ${img.unit_detected})`,
            )
          } else if (img.type === 'nutrition_label') {
            const ps = img.per_serving
            const p100 = img.per_100g
            const fmt = (n: number | null) => (n == null ? 'n/d' : String(n))
            const servingLine =
              img.serving_size_g != null
                ? `  porção declarada: **${img.serving_size_g}g**`
                : '  porção não declarada na imagem'
            const perServingLine = `  POR PORÇÃO (${img.serving_size_g ?? '?'}g): ${fmt(ps.kcal)} kcal | ${fmt(ps.protein_g)}g P | ${fmt(ps.carbs_g)}g C | ${fmt(ps.fat_g)}g G`
            const per100Line = `  POR 100g: ${fmt(p100.kcal)} kcal | ${fmt(p100.protein_g)}g P | ${fmt(p100.carbs_g)}g C | ${fmt(p100.fat_g)}g G`
            const confPct = (img.confidence * 100).toFixed(0)
            // Guidance pro LLM usar `corrections[]` em registra_refeicao com os
            // macros customizados (campos kcal_per_100g, protein_g, carbs_g, fat_g).
            // Caso Amanda 2026-05-16: ficou stuck pedindo "manda foto melhor" 3x;
            // com isto extraído, basta passar pra tool e fim.
            const guidance =
              img.per_100g.kcal != null
                ? `\n  ✅ AÇÃO: chame registra_refeicao com itens normais E preencha \`corrections[]\` com {de:"${img.product_name ?? 'iogurte/produto'}", para:"${img.product_name ?? 'iogurte/produto'}", kcal_per_100g:${p100.kcal}, protein_g:${p100.protein_g ?? 0}, carbs_g:${p100.carbs_g ?? 0}, fat_g:${p100.fat_g ?? 0}}. Isso registra com macros REAIS da embalagem em vez de estimativa genérica.`
                : img.per_serving.kcal != null && img.serving_size_g
                  ? `\n  ✅ AÇÃO: tabela só tem POR PORÇÃO. Calcule POR 100g dividindo: kcal_per_100g=${Math.round((ps.kcal! / img.serving_size_g) * 100)}, protein_g=${ps.protein_g != null ? ((ps.protein_g / img.serving_size_g) * 100).toFixed(1) : 0}, etc. Use em \`corrections[]\` de registra_refeicao.`
                  : `\n  ⚠️ AÇÃO: tabela ilegível ou incompleta. Pergunte ao paciente pra digitar os valores (kcal, proteína, carboidrato, gordura por porção).`
            blocks.push(
              `${idx} [tabela nutricional]:\n  produto: ${img.product_name ?? '?'} (conf ${confPct}%)\n${servingLine}\n${perServingLine}\n${per100Line}${img.notes ? `\n  notas vision: ${img.notes}` : ''}${guidance}`,
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
        // Persiste a ESTIMATIVA de BF% da foto num campo separado (sub-projeto B).
        // NUNCA sobrescreve body_fat_percent (confirmado pelo paciente/Roberto).
        if (bodyBf != null) {
          const bf = bodyBf
          await step.run('persist-bf-estimate', async () => {
            const { supabase } = createWorkerDeps()
            await supabase
              .from('user_profiles')
              .update({
                bf_percent_estimated: bf.estimate,
                bf_source: 'vision',
                bf_estimated_at: new Date().toISOString(),
              })
              .eq('user_id', userId)
          })
        }
      } else {
        logger.warn('Vision skipped', { reason: vRes.ok ? 'sem imagens' : vRes.reason })
        // Observabilidade (Roberto 2026-05-27 08:47): a falha de visão NUNCA
        // virava evento — só logger.warn do Inngest, inacessível sem `vercel
        // logs` ao vivo. Confirmado: 0 logs de falha de download em 10 dias.
        // Agora grava product_events com o motivo exato (token/timeout/CDN/5xx)
        // pra auditoria saber a causa e medir frequência.
        if (!vRes.ok) {
          await step.run('log-vision-download-failed', async () => {
            const { supabase } = createWorkerDeps()
            await supabase.from('product_events').insert({
              user_id: userId,
              event: 'vision.download_failed',
              properties: {
                provider_message_id: providerMessageId,
                reason: String(vRes.reason ?? '').slice(0, 500),
                photo_count: allMediaUrls.length,
                had_caption: !!text,
              },
            })
          })
        }
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
      // Loga erro pra rastreabilidade (antes só ficava em logger.info do Inngest,
      // que era inacessível sem `vercel logs` ao vivo). Caso real 2026-05-13:
      // Roberto mandou foto, pipeline falhou silenciosamente, demoramos 30min
      // pra confirmar a causa porque não havia evento no banco.
      try {
        const errMsg = err instanceof Error ? err.message : String(err)
        const errStack = err instanceof Error ? err.stack?.slice(0, 1500) : undefined
        const { supabase } = createWorkerDeps()
        await supabase.from('product_events').insert({
          user_id: userId,
          event: 'pipeline.error',
          properties: {
            provider_message_id: providerMessageId,
            content_type: contentType,
            has_media: !!mediaUrl,
            error_message: errMsg.slice(0, 500),
            error_stack: errStack,
            text_preview: (enrichedText ?? text ?? '').slice(0, 200),
          },
        })
      } catch (logErr) {
        logger.error('Failed to log pipeline.error event', {
          error: logErr instanceof Error ? logErr.message : String(logErr),
        })
      }
      await messaging.react(wpp, providerMessageId, '❌').catch(() => {})

      // Roberto+Paulo 2026-05-31 22h BRT: pipeline.error 402 (OpenRouter sem
      // saldo). O fallback existia mas tinha `.catch(() => {})` silencioso —
      // se o sendText falhasse (replyTo p/ msg antiga rejeitado, Meta API
      // intermitente etc), paciente ficava sem resposta NENHUMA e a gente nem
      // sabia. Agora: detecta tipo de erro p/ msg mais útil + retry sem
      // replyTo se falhar + LOGA o resultado.
      const errMsgLower = (err instanceof Error ? err.message : String(err)).toLowerCase()
      const is402 = errMsgLower.includes('402') || errMsgLower.includes('credits')
      const fallbackText = is402
        ? 'Tive uma falha técnica de instante e não consegui processar agora. Já fui notificado aqui. Pode reenviar em uns minutos? 🙏'
        : 'Tive um problema agora. Tenta de novo em alguns segundos? 🙏'

      let fallbackSent = false
      let fallbackError: string | null = null
      try {
        await messaging.sendText(wpp, fallbackText, { replyTo: providerMessageId })
        fallbackSent = true
      } catch (e1) {
        // 1ª tentativa falhou — replyTo pode ter rejeitado. Retry sem replyTo.
        try {
          await messaging.sendText(wpp, fallbackText)
          fallbackSent = true
        } catch (e2) {
          fallbackError = e2 instanceof Error ? e2.message : String(e2)
        }
      }
      try {
        const { supabase: supA } = createWorkerDeps()
        await supA.from('product_events').insert({
          user_id: userId,
          event: fallbackSent
            ? 'pipeline.error.fallback_sent'
            : 'pipeline.error.fallback_failed',
          properties: {
            provider_message_id: providerMessageId,
            is_402: is402,
            fallback_error: fallbackError,
          },
        })
      } catch {
        /* logging opcional, não bloqueia */
      }
      throw err
    }

    logger.info('Pipeline done', {
      userId,
      stage: result.stage,
      cost: result.costUsd,
      tools: result.toolCalls.map((t) => t.name),
    })

    // === Step 4: envio ===
    // FASE B BOTÕES (Roberto 2026-05-28): se o pipeline retornou uma proposta
    // pendente (paciente está no opt-in + a refeição não era express), manda via
    // sendInteractive em vez do sendHumanized normal. O pending já foi criado
    // no DB; aqui só anexa o providerMessageId da msg out pra responder no tap.
    if (result.interactive) {
      const ix = result.interactive
      const sendRes = await step.run('send-interactive', async () => {
        // Roberto 2026-06-01 Fase 2 botões onboarding: se `list` presente,
        // envia como List Message (4-10 opções, dropdown). Senão, botão simples.
        if (ix.list) {
          if (!messaging.sendInteractiveList) {
            throw new Error('messaging provider sem sendInteractiveList')
          }
          const items = ix.buttons.map((b) => ({ id: b.id, title: b.title }))
          return messaging.sendInteractiveList(wpp, ix.body, ix.list.buttonText, items, {
            replyTo: providerMessageId,
          })
        }
        if (!messaging.sendInteractive) {
          throw new Error('messaging provider sem sendInteractive')
        }
        return messaging.sendInteractive(wpp, ix.body, ix.buttons, { replyTo: providerMessageId })
      })
      const { supabase } = createWorkerDeps()
      if (sendRes.providerMessageId) {
        // anexa o id da msg out pra que o tap possa responder/quotar
        await supabase
          .from('pending_registrations')
          .update({ proposal_msg_id: sendRes.providerMessageId })
          .eq('id', ix.pendingId)
      }
      await supabase.from('messages').insert({
        user_id: userId,
        direction: 'out',
        role: 'assistant',
        content_type: 'interactive',
        content: ix.body,
        provider: 'whatsapp_cloud',
        provider_message_id: sendRes.providerMessageId ?? null,
        agent_stage: result.stage,
        model_used: result.modelUsed,
        prompt_tokens: result.promptTokens,
        completion_tokens: result.completionTokens,
        cost_usd: result.costUsd,
        latency_ms: result.latencyMs,
        delivery_status: sendRes.status,
        delivery_error: sendRes.error ? { error: sendRes.error } : null,
      })
      return {
        ok: true,
        sent: 1,
        mode: 'interactive',
        pendingId: ix.pendingId,
        stage: result.stage,
        media: mediaSummary,
      }
    }

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
    let deliveryError: string | undefined
    let ttsMediaId: string | undefined

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
          media_id: mediaId,
        }
      })
      if (audioRes.status === 'sent') sentCount = 1
      else failedCount = 1
      ttsMediaId = audioRes.media_id
      logger.info('Audio sent', audioRes)
      // Observabilidade TTS — antes era invisível, só visível no /audit por
      // contagem de OUT com content_type=audio sem detalhe de provider/latência.
      try {
        await supabase.from('product_events').insert({
          user_id: userId,
          event: audioRes.status === 'sent' ? 'tts.generated' : 'tts.failed',
          properties: {
            provider_message_id: providerMessageId,
            success: audioRes.status === 'sent',
            tts_provider: audioRes.tts_provider,
            tts_latency_ms: audioRes.tts_latency_ms,
            chars: audioRes.chars,
            media_id: audioRes.media_id,
            voice_id: elevenlabsVoice ? `${elevenlabsVoice.slice(0, 8)}...` : null,
          },
        })
      } catch (logErr) {
        logger.warn('TTS event log failed', {
          error: logErr instanceof Error ? logErr.message : String(logErr),
        })
      }
    } else {
      // Humanizer config editável via /settings/global → humanizer.*
      // Process-message usa response_max_delay_ms (maior que engagement
      // pra parecer "pensando" antes de responder).
      const humanizer = await loadHumanizerConfig(supabase)
      // Roberto 2026-06-01: msg de registro vai em ATÉ 3 bolhas: tabela |
      // comentário educativo (se Haiku gerou) | card de balanço. Cada parte
      // ganha respiro próprio (almoço com 8 itens + comentário ficava 1.4kb
      // numa msg só). Marker '🔥 Consumido:' separa card; marker invisível
      // EDU_COMMENT_MARKER separa comentário. Se nenhum marker presente,
      // cai no envio único.
      const splitForRegistration = result.singleMessage === true
      const parts = splitForRegistration ? splitRegistrationParts(result.text) : null
      const sendResults = await step.run('send-to-user', async () => {
        if (parts && (parts.card || parts.comment)) {
          const baseOpts = {
            showTyping: true,
            minDelay: humanizer.min_delay_ms,
            maxDelay: humanizer.response_max_delay_ms,
            charsPerSecond: humanizer.chars_per_second,
            singleMessage: true,
          }
          const r1 = await sendHumanized(messaging, wpp, parts.meal, {
            ...baseOpts,
            inReplyTo: providerMessageId,
            replyTo: result.toolCalls.length > 0 ? providerMessageId : undefined,
          })
          const all = [...r1]
          if (parts.comment) {
            await new Promise((res) => setTimeout(res, 1500))
            const r2 = await sendHumanized(messaging, wpp, parts.comment, baseOpts)
            all.push(...r2)
          }
          if (parts.card) {
            await new Promise((res) => setTimeout(res, 1500))
            const r3 = await sendHumanized(messaging, wpp, parts.card, baseOpts)
            all.push(...r3)
          }
          return all
        }
        return sendHumanized(messaging, wpp, result.text, {
          showTyping: true,
          minDelay: humanizer.min_delay_ms,
          maxDelay: humanizer.response_max_delay_ms,
          charsPerSecond: humanizer.chars_per_second,
          inReplyTo: providerMessageId,
          replyTo: result.toolCalls.length > 0 ? providerMessageId : undefined,
          singleMessage: result.singleMessage === true,
        })
      })
      sentCount = sendResults.filter((r) => r.status === 'sent').length
      failedCount = sendResults.filter((r) => r.status !== 'sent').length
      deliveryError = sendResults.find((r) => r.error)?.error
    }

    // Persiste a OUT no banco COM delivery_status real.
    // Antes a persistência acontecia em pipeline.ts SEM delivery_status
    // (sempre null), agora roda aqui depois do envio com status sent/failed.
    {
      const deliveryStatus: 'sent' | 'failed' = failedCount > 0 ? 'failed' : 'sent'
      await step.run('persist-out', async () => {
        const { error: insErr } = await supabase.from('messages').insert({
          user_id: userId,
          direction: 'out',
          role: 'assistant',
          content_type: sendMode === 'audio' ? 'audio' : 'text',
          content: result.text,
          // Persiste o media_id do áudio TTS pra rastreabilidade.
          // Antes ficava null em mensagens content_type=audio.
          media_url: ttsMediaId ?? null,
          provider: process.env.MESSAGING_PROVIDER ?? 'whatsapp_cloud',
          agent_stage: result.stage,
          model_used: result.modelUsed,
          prompt_tokens: result.promptTokens,
          completion_tokens: result.completionTokens,
          cost_usd: result.costUsd,
          latency_ms: result.latencyMs,
          delivery_status: deliveryStatus,
          delivery_error: deliveryError ? { msg: deliveryError } : null,
        })
        if (insErr) logger.error('persist OUT failed', { error: insErr })
        return { ok: true }
      })
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
