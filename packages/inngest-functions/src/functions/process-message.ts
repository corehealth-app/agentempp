import {
  aggregateBodyBfEstimate,
  type BodyPhotoSignal,
  bodyPhotoSignalFromEventProperties,
  detectPendingResponse,
  formatBodyPhotoDigest,
  splitRegistrationParts,
} from '@mpp/agent'
import {
  createMessagingProvider,
  GeminiVision,
  GroqSTT,
  rewriteForTTS,
  sendHumanized,
  TTSRouter,
} from '@mpp/providers'
import { inngest } from '../client.js'
import { createWorkerDeps, loadCredential, processMessage } from '../lib/env.js'
import { loadHumanizerConfig, loadVisionConfig } from '../lib/runtime-config.js'
import { persistOutboundMessage } from './outbound-message-persistence.js'
import {
  buildOutboundMessageRows,
  requireOutboundDelivery,
  type OutboundDelivery,
} from './outbound-message-rows.js'
import { classifyProposalMsgIdWrite } from './proposal-msg-id-policy.js'
import {
  combinePatientNarrative,
  normalizeInboundMediaItems,
} from './media-burst.js'

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
      providerMessageIds,
      providerTimestamps,
      contentType,
      text,
      mediaUrl,
      mediaUrls,
      mediaItems,
      provider,
      timestamp,
    } = event.data

    const normalizedMediaItems = normalizeInboundMediaItems({
      mediaItems,
      contentType,
      mediaUrl,
      mediaUrls,
      providerMessageId,
      timestamp,
    })
    const audioMediaItems = normalizedMediaItems.filter(
      (item) => item.contentType === 'audio',
    )
    const imageMediaItems = normalizedMediaItems.filter(
      (item) => item.contentType === 'image',
    )
    const allMediaUrls = normalizedMediaItems.map((item) => item.url)

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
    //
    // BUG T3 (2026-06-15) + review adversarial:
    //   - Janela 4h via created_at (era 24h livre antes): confirmação fora
    //     dessa janela quase sempre é coincidência ou pending órfão antigo.
    //     4h cobre cenário comum "paciente sai do WhatsApp e volta depois"
    //     sem abrir falso positivo de "ok" referindo a outra coisa.
    //   - 2 sub-casos de orphan: existe pending stale (>4h) → manda msg
    //     determinística pedindo o que registrar; nenhum pending → silêncio
    //     (cai no LLM normal pq pode ser msg ambígua).
    //   - Telemetria `pending.text_fallback_orphan` diferenciada.
    if (contentType === 'text' && text) {
      const responseKind = detectPendingResponse(text)
      if (responseKind) {
        const handled = await step.run('text-pending-fallback', async () => {
          const { supabase } = createWorkerDeps()
          const nowMs = Date.now()
          const fourHoursAgoIso = new Date(nowMs - 4 * 60 * 60 * 1000).toISOString()
          const nowIso = new Date(nowMs).toISOString()
          const { data: pending } = await supabase
            .from('pending_registrations')
            .select('id')
            .eq('user_id', userId)
            .eq('status', 'pending')
            .gt('expires_at', nowIso)
            .gte('created_at', fourHoursAgoIso)
            .order('created_at', { ascending: false })
            .limit(1)
            .maybeSingle()
          const pendingId = (pending as { id: string } | null)?.id
          if (!pendingId) {
            // Sub-caso: existe pending STALE (>4h e <expires_at, geralmente
            // <24h)? Diferencia "orphan_no_pending_at_all" de
            // "orphan_with_stale_pending" — só o 2º merece resposta
            // determinística (paciente confirmou tarde, perdeu a janela).
            const { data: stalePending } = await supabase
              .from('pending_registrations')
              .select('id, created_at, proposal')
              .eq('user_id', userId)
              .eq('status', 'pending')
              .gt('expires_at', nowIso)
              .lt('created_at', fourHoursAgoIso)
              .order('created_at', { ascending: false })
              .limit(1)
              .maybeSingle()
            const stale = stalePending as
              | { id: string; created_at: string; proposal?: { mealType?: string } | null }
              | null
            await supabase.from('product_events').insert({
              user_id: userId,
              event: 'pending.text_fallback_orphan',
              properties: {
                response: responseKind,
                text_preview: text.slice(0, 50),
                window: '4h',
                stale_pending: stale != null,
                stale_pending_id: stale?.id ?? null,
              },
            })
            if (stale) {
              const mealHint = stale.proposal?.mealType
                ? ` (era ${stale.proposal.mealType})`
                : ''
              const askText = `Recebi seu "${text.trim()}", mas a proposta${mealHint} ficou esperando muito tempo e eu não posso registrar com certeza. Pode me mandar de novo o que você comeu? Ou clicar no botão da proposta velha (se ainda estiver no chat).`
              return {
                dispatched: false,
                reason: 'stale_pending_too_old',
                stale_pending_id: stale.id,
                response_text: askText,
              }
            }
            return { dispatched: false, reason: 'no_recent_pending' }
          }
          await inngest.send({
            name: 'interactive.button.tapped',
            data: {
              userId,
              wpp,
              buttonId: `${responseKind}_${pendingId}`,
              buttonTitle: responseKind === 'confirm' ? 'Sim, registrar' : 'Editar',
              providerMessageId,
              tappedAt: new Date(timestamp).toISOString(),
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
        // Sub-caso T3: stale_pending_too_old já mandou msg determinística
        // pedindo o paciente reenviar — NÃO cai pro LLM (evita LLM
        // improvisar "Sim, e aí?" sem contexto).
        if ((handled as { reason?: string })?.reason === 'stale_pending_too_old') {
          const staleResult = handled as {
            stale_pending_id?: string
            response_text?: string
          }
          const responseText = staleResult.response_text
          if (!responseText) {
            throw new Error('stale pending response text missing')
          }
          const delivery = await step.run('send-stale-pending-response', async () =>
            requireOutboundDelivery(
              responseText,
              await messaging.sendText(wpp, responseText, {
                replyTo: providerMessageId,
              }),
            ),
          )
          await step.run('persist-stale-pending-response', async () => {
            const { supabase } = createWorkerDeps()
            const [row] = buildOutboundMessageRows({
              userId,
              provider: process.env.MESSAGING_PROVIDER ?? 'whatsapp_cloud',
              contentType: 'text',
              stage: 'recomposicao',
              modelUsed: null,
              promptTokens: null,
              completionTokens: null,
              costUsd: null,
              latencyMs: null,
              metadata: {
                response_part: 'stale_pending_response',
                pending_id: staleResult.stale_pending_id ?? 'unknown',
              },
              deliveries: [delivery],
            })
            if (!row) throw new Error('stale pending outbound row missing')
            await persistOutboundMessage(supabase, row)
            return { persisted: true }
          })
          return {
            ok: true,
            sent: 1,
            reason: 'stale_pending_handled_deterministically',
            kind: responseKind,
          }
        }
        // no_recent_pending genuíno → cai no fluxo normal (LLM responde)
      }
    }

    // === Step 1: ack ===
    await step.run('ack', async () => {
      await messaging.showTypingFor(providerMessageId).catch(() => {})
      if (normalizedMediaItems.length > 0) {
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
    let patientNarrative: string | undefined = text
    let mediaSummary: { kind: 'audio' | 'image' | 'mixed'; latency_ms: number } | null = null

    if (audioMediaItems.length > 0) {
      const sttRes = await step.run('stt-transcribe', async () => {
        if (!process.env.GROQ_API_KEY) {
          return {
            items: audioMediaItems.map((media) => ({
              ok: false as const,
              media,
              reason: 'GROQ_API_KEY ausente',
              text: null,
              latency_ms: 0,
            })),
            latency_ms: 0,
          }
        }
        const startedAt = Date.now()
        const stt = new GroqSTT({ apiKey: process.env.GROQ_API_KEY })
        const items = await Promise.all(
          audioMediaItems.map(async (media) => {
            try {
              const blob = await messaging.downloadMedia(media.url)
              const r = await stt.transcribe({ audio: blob, language: 'pt' })
              return {
                ok: true as const,
                media,
                text: r.text,
                reason: null,
                latency_ms: r.latencyMs,
              }
            } catch (error) {
              return {
                ok: false as const,
                media,
                text: null,
                reason: error instanceof Error ? error.message : String(error),
                latency_ms: 0,
              }
            }
          }),
        )
        return { items, latency_ms: Date.now() - startedAt }
      })

      const successfulTranscripts = sttRes.items.filter(
        (item): item is Extract<(typeof sttRes.items)[number], { ok: true }> => item.ok,
      )
      patientNarrative = combinePatientNarrative([
        text,
        ...successfulTranscripts.map((item) => item.text),
      ])
      enrichedText =
        patientNarrative ??
        `[${audioMediaItems.length} áudio(s) recebido(s), mas a transcrição falhou. Peça ao paciente para reenviar ou escrever o conteúdo. NÃO INVENTE.]`
      mediaSummary = {
        kind: imageMediaItems.length > 0 ? 'mixed' : 'audio',
        latency_ms: sttRes.latency_ms,
      }
      logger.info('STT batch done', {
        total: sttRes.items.length,
        successful: successfulTranscripts.length,
        latency: sttRes.latency_ms,
      })

      await step.run('persist-stt-results', async () => {
        const { supabase } = createWorkerDeps()
        for (const item of successfulTranscripts) {
          const { error: transcriptError } = await supabase
            .from('messages')
            .update({ content: item.text })
            .eq('user_id', userId)
            .eq('provider', 'whatsapp_cloud')
            .eq('provider_message_id', item.media.providerMessageId)
            .eq('direction', 'in')
          if (transcriptError) {
            throw new Error(transcriptError.message ?? 'STT transcript persistence failed')
          }
        }

        const eventRows = sttRes.items.map((item) => ({
          user_id: userId,
          event: item.ok ? 'stt.transcribed' : 'stt.failed',
          properties: {
            provider_message_id: item.media.providerMessageId,
            success: item.ok,
            latency_ms: item.latency_ms,
            text_length: item.ok ? item.text.length : 0,
            text_preview: item.ok ? item.text.slice(0, 120) : null,
            reason: item.ok ? null : item.reason,
            provider: 'groq-whisper',
            language: 'pt',
          },
        }))
        const { error: eventError } = await supabase.from('product_events').insert(eventRows)
        if (eventError) {
          logger.warn('STT event persistence failed', {
            code: eventError.code,
            message: eventError.message,
          })
        }
        return { persisted: sttRes.items.length }
      })
    }

    if (imageMediaItems.length > 0) {
      const visionCfg = await step.run('vision-config', async () => {
        const { supabase } = createWorkerDeps()
        return loadVisionConfig(supabase)
      })
      const vRes = await step.run('vision-analyze', async () => {
        if (!process.env.OPENROUTER_API_KEY) {
          return {
            ok: false as const,
            reason: 'OPENROUTER_API_KEY ausente',
            images: [],
            imageMedia: [],
            failures: imageMediaItems.map((media) => ({
              media,
              reason: 'OPENROUTER_API_KEY ausente',
            })),
            latency_ms: 0,
          }
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
          // Uma imagem ruim não invalida as demais do mesmo burst.
          const results = await Promise.all(
            imageMediaItems.map(async (media) => {
              try {
                const blob = await messaging.downloadMedia(media.url)
                const buf = Buffer.from(await blob.arrayBuffer())
                const dataUri = `data:${blob.type || 'image/jpeg'};base64,${buf.toString('base64')}`
                const image = await vision.analyzeImage(dataUri, {
                  userMessage: patientNarrative,
                })
                return { ok: true as const, media, image }
              } catch (error) {
                return {
                  ok: false as const,
                  media,
                  reason: error instanceof Error ? error.message : String(error),
                }
              }
            }),
          )
          const successful = results.filter(
            (result): result is Extract<(typeof results)[number], { ok: true }> => result.ok,
          )
          const failures = results
            .filter(
              (result): result is Extract<(typeof results)[number], { ok: false }> => !result.ok,
            )
            .map(({ media, reason }) => ({ media, reason }))
          return {
            ok: successful.length > 0,
            reason: failures[0]?.reason ?? null,
            images: successful.map((result) => result.image),
            imageMedia: successful.map((result) => result.media),
            failures,
            latency_ms: Date.now() - start,
          }
        } catch (e) {
          const reason = e instanceof Error ? e.message : String(e)
          return {
            ok: false as const,
            reason,
            images: [],
            imageMedia: [],
            failures: imageMediaItems.map((media) => ({ media, reason })),
            latency_ms: 0,
          }
        }
      })

      if (vRes.failures.length > 0) {
        await step.run('log-vision-download-failed', async () => {
          const { supabase } = createWorkerDeps()
          const rows = vRes.failures.map((failure) => ({
            user_id: userId,
            event: 'vision.download_failed',
            properties: {
              provider_message_id: failure.media.providerMessageId,
              reason: failure.reason.slice(0, 500),
              photo_count: imageMediaItems.length,
              had_caption: !!patientNarrative,
            },
          }))
          const { error } = await supabase.from('product_events').insert(rows)
          if (error) {
            logger.warn('vision.download_failed insert error', {
              code: error.code,
              message: error.message,
            })
          }
          return { logged: rows.length }
        })
      }

      if (vRes.ok && vRes.images.length > 0) {
        // Formata cada imagem segundo seu tipo
        const blocks: string[] = []
        const bodySignals: BodyPhotoSignal[] = []
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
            const bodyMedia = vRes.imageMedia[i]
            bodySignals.push({
              view: img.view,
              bfPercentEstimate: img.bf_percent_estimate,
              confidence: img.bf_confidence,
              occurredAt: new Date(bodyMedia?.timestamp ?? timestamp).toISOString(),
              providerMessageId: bodyMedia?.providerMessageId ?? providerMessageId,
              photoCount: vRes.images.length,
              compositionNotes: img.composition_notes ?? null,
              postureNotes: img.posture_notes ?? null,
            })
            blocks.push(
              `${idx} [corporal · ${img.view}]:\n  BF% estimado: ${img.bf_percent_estimate ?? 'n/d'} (conf ${(img.bf_confidence * 100).toFixed(0)}%)\n  ${img.composition_notes}${img.posture_notes ? `\n  postura: ${img.posture_notes}` : ''}`,
            )
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
          } else if (img.type === 'equipment') {
            const confPct = (img.confidence * 100).toFixed(0)
            const items = img.equipment.length > 0 ? img.equipment.join(', ') : '(nenhum item visível)'
            const locLine = img.location ? `  local inferido: ${img.location}` : '  local: indeterminado'
            // Guidance pro LLM: confirmar com paciente + perguntar dias/semana
            // e nível antes de chamar gera_treino. NUNCA chamar a tool direto
            // da foto (description da tool é clara sobre os 3 dados obrigatórios).
            const guidance =
              img.equipment.length > 0
                ? `\n  ✅ AÇÃO: liste os equipamentos detectados PRO PACIENTE, pergunte (a) faltou algum? (b) quantos dias/semana topa treinar? (c) nível atual (iniciante/intermediario/avancado)? SÓ chame gera_treino DEPOIS das 3 confirmações.`
                : `\n  ⚠️ AÇÃO: foto sem equipamentos visíveis ou pouco clara. Peça pro paciente listar os equipamentos por texto.`
            blocks.push(
              `${idx} [equipamentos de treino] (conf ${confPct}%):\n  detectados: ${items}\n${locLine}${img.notes ? `\n  notas vision: ${img.notes}` : ''}${guidance}`,
            )
          } else {
            blocks.push(`${idx} [outra]:\n  ${img.description}`)
          }
        }
        const partialFailureNotice =
          vRes.failures.length > 0
            ? `\n\n[${vRes.failures.length} de ${imageMediaItems.length} foto(s) não puderam ser analisadas. Considere apenas as análises acima e peça somente a mídia faltante se ela for necessária.]`
            : ''
        enrichedText =
          `[${vRes.images.length}/${imageMediaItems.length} foto(s) analisada(s) — análise visual automática abaixo]\n\n` +
          blocks.join('\n\n') +
          (patientNarrative ? `\n\nRelato do usuário: "${patientNarrative}"` : '') +
          partialFailureNotice
        mediaSummary = {
          kind: audioMediaItems.length > 0 ? 'mixed' : 'image',
          latency_ms: (mediaSummary?.latency_ms ?? 0) + vRes.latency_ms,
        }
        logger.info('Vision done', {
          count: vRes.images.length,
          types: vRes.images.map((i) => i.type),
          latency: vRes.latency_ms,
        })
        // Observabilidade vision (audit P2 2026-06-13): cada imagem analisada
        // gera UM product_event 'vision.analyzed'. Antes só `vision.download_failed`
        // virava evento — sucesso era cego, sem medir latência/confidence/
        // distribuição de type sem `vercel logs` ao vivo. Latência é do batch
        // (Promise.all paralelo), mesma pra todas as imagens do turno.
        await step.run('log-vision-analyzed', async () => {
          try {
            const { supabase } = createWorkerDeps()
            const rows = vRes.images.map((img, imageIndex) => {
              let confidence: number | null = null
              // FIX 4 (Roberto 2026-06-15): expor meal_items + meal_context
              // no properties pra pipeline.ts conseguir detectar "foto pendente
              // de registro" sem precisar re-rodar vision. Caso real: paciente
              // mandou foto, respondeu disambiguação, LLM chamou
              // marca_refeicao_pulada em vez de registra_refeicao — foto
              // perdida. Com meal_items aqui, o pipeline carrega visionPending
              // do estado e bloqueia o skip.
              let mealItems:
                | Array<{ name: string; quantity_g_estimate: number; confidence: number }>
                | null = null
              let mealContext: string | null = null
              let needsDisambiguation = false
              let bodyView: string | null = null
              let bodyBfPercentEstimate: number | null = null
              let bodyCompositionNotes: string | null = null
              let bodyPostureNotes: string | null = null
              if (img.type === 'meal') {
                confidence = img.items.length > 0
                  ? img.items.reduce((acc, it) => acc + (it.confidence ?? 0), 0) / img.items.length
                  : null
                mealItems = img.items.map((it) => ({
                  name: it.name,
                  quantity_g_estimate: it.quantity_g_estimate,
                  confidence: it.confidence,
                }))
                mealContext = img.meal_context ?? null
                needsDisambiguation = img.items.some(
                  (it) => it.confidence < visionCfg.meal_confidence_threshold,
                )
              } else if (img.type === 'body') {
                confidence = img.bf_confidence
                bodyView = img.view
                bodyBfPercentEstimate = img.bf_percent_estimate
                bodyCompositionNotes = img.composition_notes ?? null
                bodyPostureNotes = img.posture_notes ?? null
              } else if (
                img.type === 'scale' ||
                img.type === 'equipment' ||
                img.type === 'nutrition_label'
              ) {
                confidence = img.confidence
              }
              const model =
                img.type === 'nutrition_label'
                  ? visionCfg.nutrition_label_model
                  : visionCfg.model
              return {
                user_id: userId,
                event: 'vision.analyzed',
                properties: {
                  provider_message_id:
                    vRes.imageMedia[imageIndex]?.providerMessageId ?? providerMessageId,
                  type: img.type,
                  latency_ms: vRes.latency_ms,
                  confidence,
                  model,
                  photo_count: vRes.images.length,
                  had_caption: !!patientNarrative,
                  // FIX 4 — telemetria rica pro gate funcionar
                  meal_items: mealItems,
                  meal_context: mealContext,
                  needs_disambiguation: needsDisambiguation,
                  view: bodyView,
                  bf_percent_estimate: bodyBfPercentEstimate,
                  bf_confidence: img.type === 'body' ? img.bf_confidence : null,
                  composition_notes: bodyCompositionNotes,
                  posture_notes: bodyPostureNotes,
                },
              }
            })
            // supabase-js v2 NÃO lança em 4xx/5xx (RLS, FK, payload errado);
            // o erro vem em { error }. Sem capturar, telemetria zera silenciosa
            // — exatamente o padrão que escondeu o bug do edu_comment 36h.
            const { error: insertErr } = await supabase.from('product_events').insert(rows)
            if (insertErr) {
              logger.warn('vision.analyzed insert error', {
                code: insertErr.code,
                message: insertErr.message,
              })
            }

            // Audit 06-25 Bug B (Roberto 25/06): grava digest curto em
            // messages.content do inbound da foto. Hoje content é NULL pra
            // content_type=image SEM caption — quando paciente manda 2 fotos
            // + texto, e LLM faz pergunta no meio, o turno seguinte filtra
            // recentMessages por `.content` truthy (pipeline.ts:1810) e perde
            // a memória das fotos.
            //
            // Review HIGH 3 (audit 06-25): fotos COM caption já têm
            // content=caption (webhook-whatsapp:234). Filtro `.is(content,null)`
            // antigo bloqueava digest pra essas — bug! Maioria das fotos têm
            // caption ("aqui meu almoço"), então o fix antigo cobria minoria.
            // Agora: SE content já existe E não tem sentinela [vision], faz
            // append com prefixo `\n[vision] ...` pra preservar AMBOS caption
            // e digest. Sentinela permite idempotência em retries.
            try {
              const mealImgs = vRes.images.filter((i) => i.type === 'meal')
              if (providerMessageId && mealImgs.length > 0) {
                const digests = mealImgs.map((img, idx) => {
                  const names = img.items.slice(0, 8).map((it) => it.name).join(', ')
                  const more = img.items.length > 8 ? ` +${img.items.length - 8}` : ''
                  const ctx = img.meal_context ? ` — ${img.meal_context.slice(0, 60)}` : ''
                  const prefix = mealImgs.length > 1 ? `Foto ${idx + 1}/${mealImgs.length}` : 'Foto'
                  return `[vision] ${prefix}: ${img.items.length} itens: ${names}${more}${ctx}`
                })
                const digestText = digests.join('\n')
                // Busca content atual pra decidir entre SET (null) ou APPEND.
                const { data: existing } = await supabase
                  .from('messages')
                  .select('content')
                  .eq('provider_message_id', providerMessageId)
                  .eq('user_id', userId)
                  .maybeSingle()
                const cur = (existing as { content?: string | null } | null)?.content ?? null
                // Idempotência: se sentinela já está no content, não duplica.
                if (cur && cur.includes('[vision]')) {
                  // já gravado — no-op
                } else if (cur && cur.length > 0) {
                  // foto com caption — APPEND digest preservando caption
                  await supabase
                    .from('messages')
                    .update({ content: `${cur}\n${digestText}` })
                    .eq('provider_message_id', providerMessageId)
                    .eq('user_id', userId)
                } else {
                  // foto sem caption (content=null) — SET digest
                  await supabase
                    .from('messages')
                    .update({ content: digestText })
                    .eq('provider_message_id', providerMessageId)
                    .eq('user_id', userId)
                    .is('content', null)
                }
              }
              const bodyDigestText = formatBodyPhotoDigest(bodySignals)
              if (providerMessageId && bodyDigestText.length > 0) {
                const { data: existing } = await supabase
                  .from('messages')
                  .select('content')
                  .eq('provider_message_id', providerMessageId)
                  .eq('user_id', userId)
                  .maybeSingle()
                const cur = (existing as { content?: string | null } | null)?.content ?? null
                if (cur && cur.includes('[vision-body]')) {
                  // já gravado — no-op
                } else if (cur && cur.length > 0) {
                  await supabase
                    .from('messages')
                    .update({ content: `${cur}\n${bodyDigestText}` })
                    .eq('provider_message_id', providerMessageId)
                    .eq('user_id', userId)
                } else {
                  await supabase
                    .from('messages')
                    .update({ content: bodyDigestText })
                    .eq('provider_message_id', providerMessageId)
                    .eq('user_id', userId)
                    .is('content', null)
                }
              }
            } catch (digestErr) {
              logger.warn('vision digest update failed (non-fatal)', {
                error: digestErr instanceof Error ? digestErr.message : String(digestErr),
              })
            }
          } catch (logErr) {
            logger.warn('vision.analyzed event log failed', {
              error: logErr instanceof Error ? logErr.message : String(logErr),
            })
          }
        })
        // Persiste a ESTIMATIVA de BF% agregando as fotos corporais recentes.
        // NUNCA sobrescreve body_fat_percent (confirmado pelo paciente/Roberto).
        if (bodySignals.some((signal) => signal.bfPercentEstimate != null)) {
          await step.run('persist-bf-estimate', async () => {
            const { supabase } = createWorkerDeps()
            const since = new Date(Date.now() - 48 * 3600 * 1000).toISOString()
            const { data: rows } = await supabase
              .from('product_events')
              .select('properties, occurred_at')
              .eq('user_id', userId)
              .eq('event', 'vision.analyzed')
              .gte('occurred_at', since)
              .order('occurred_at', { ascending: false })
              .limit(30)
            const recentSignals = ((rows ?? []) as Array<{
              properties: unknown
              occurred_at: string | null
            }>)
              .map((row) => bodyPhotoSignalFromEventProperties(row.properties, row.occurred_at))
              .filter((signal): signal is BodyPhotoSignal => signal != null)
            const bf = aggregateBodyBfEstimate(
              recentSignals.length > 0 ? recentSignals : bodySignals,
            )
            if (!bf) return
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
        mediaSummary = {
          kind: audioMediaItems.length > 0 ? 'mixed' : 'image',
          latency_ms: (mediaSummary?.latency_ms ?? 0) + vRes.latency_ms,
        }
        const failureNotice = `[${imageMediaItems.length} foto(s) recebida(s), mas nenhuma pôde ser analisada. Peça ao usuário para reenviar apenas as fotos ou descrever o conteúdo. NÃO INVENTE.]`
        if (patientNarrative) {
          enrichedText = `${patientNarrative}\n\n${failureNotice}`
        } else {
          enrichedText = failureNotice
        }
      }
    }

    // === Step 3: pipeline ===
    let result: Awaited<ReturnType<typeof processMessage>>
    try {
      result = await step.run('agent-pipeline', async () => {
        const deps = createWorkerDeps()
        return processMessage(deps, {
          from: wpp,
          providerMessageId,
          providerMessageIds,
          contentType,
          text: enrichedText,
          patientText: patientNarrative,
          mediaUrl,
          provider,
          timestamp: new Date(timestamp),
          timestamps: providerTimestamps
            ?.map((value) => new Date(value))
            .filter((value) => Number.isFinite(value.getTime())),
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
            has_media: normalizedMediaItems.length > 0,
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
          const delivery = await messaging.sendInteractiveList(wpp, ix.body, ix.list.buttonText, items, {
            replyTo: providerMessageId,
          })
          if (delivery.status === 'failed') {
            throw new Error(delivery.error ?? 'interactive list delivery failed')
          }
          return delivery
        }
        if (!messaging.sendInteractive) {
          throw new Error('messaging provider sem sendInteractive')
        }
        const delivery = await messaging.sendInteractive(wpp, ix.body, ix.buttons, {
          replyTo: providerMessageId,
        })
        if (delivery.status === 'failed') {
          throw new Error(delivery.error ?? 'interactive delivery failed')
        }
        return delivery
      })
      const { supabase } = createWorkerDeps()
      const messageId = await step.run('persist-interactive-out', async () => {
        const [row] = buildOutboundMessageRows({
          userId,
          provider: 'whatsapp_cloud',
          contentType: 'interactive',
          stage: result.stage,
          modelUsed: result.modelUsed,
          promptTokens: result.promptTokens,
          completionTokens: result.completionTokens,
          costUsd: result.costUsd,
          latencyMs: result.latencyMs,
          deliveries: [{
            content: ix.body,
            providerMessageId: sendRes.providerMessageId,
            status: sendRes.status,
            error: sendRes.error,
          }],
        })
        if (!row) throw new Error('interactive delivery row missing')
        return persistOutboundMessage(supabase, row)
      })
      const upd = await supabase
        .from('pending_registrations')
        .update({ proposal_msg_id: messageId })
        .eq('id', ix.pendingId)
        .is('proposal_msg_id', null)
        .select('id')
      if (upd.error) throw new Error(upd.error.message)
      const policy = classifyProposalMsgIdWrite({
        rowWasSet: Array.isArray(upd.data) && upd.data.length > 0,
        messageId,
        newProviderMessageId: sendRes.providerMessageId ?? '',
      })
      await supabase.from('product_events').insert({
        user_id: userId,
        event: policy.event,
        properties: { ...policy.properties, pendingId: ix.pendingId },
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
    let ttsMediaId: string | undefined
    let outboundDeliveries: OutboundDelivery[] = []

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
        if (sendResult.status === 'failed') {
          throw new Error(sendResult.error ?? 'audio delivery failed')
        }
        return {
          status: sendResult.status,
          provider_message_id: sendResult.providerMessageId,
          error: sendResult.error,
          chars: speechText.length,
          tts_provider: ttsProvider,
          tts_latency_ms: ttsResult.durationMs,
          media_id: mediaId,
        }
      })
      sentCount = 1
      ttsMediaId = audioRes.media_id
      outboundDeliveries = [
        {
          content: result.text,
          providerMessageId: audioRes.provider_message_id,
          status: audioRes.status,
          error: audioRes.error,
        },
      ]
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
      const assertSuccessful = <T extends { status: string; error?: string }>(deliveries: T[]) => {
        const failed = deliveries.find((delivery) => delivery.status === 'failed')
        if (failed) throw new Error(failed.error ?? 'message delivery failed')
        return deliveries
      }
      let sendResults: Awaited<ReturnType<typeof sendHumanized>> = []
      if (parts && (parts.card || parts.comment)) {
        const baseOpts = {
          showTyping: true,
          minDelay: humanizer.min_delay_ms,
          maxDelay: humanizer.response_max_delay_ms,
          charsPerSecond: humanizer.chars_per_second,
          singleMessage: true,
        }
        const mealResults = await step.run('send-registration-meal', async () =>
          assertSuccessful(
            await sendHumanized(messaging, wpp, parts.meal, {
              ...baseOpts,
              inReplyTo: providerMessageId,
              replyTo: result.toolCalls.length > 0 ? providerMessageId : undefined,
            }),
          ),
        )
        sendResults.push(...mealResults)
        if (parts.comment) {
          const comment = parts.comment
          await new Promise((resolve) => setTimeout(resolve, 1500))
          const commentResults = await step.run('send-registration-comment', async () =>
            assertSuccessful(await sendHumanized(messaging, wpp, comment, baseOpts)),
          )
          sendResults.push(...commentResults)
        }
        if (parts.card) {
          const card = parts.card
          await new Promise((resolve) => setTimeout(resolve, 1500))
          const cardResults = await step.run('send-registration-card', async () =>
            assertSuccessful(await sendHumanized(messaging, wpp, card, baseOpts)),
          )
          sendResults.push(...cardResults)
        }
      } else {
        sendResults = await step.run('send-to-user', async () =>
          assertSuccessful(
            await sendHumanized(messaging, wpp, result.text, {
              showTyping: true,
              minDelay: humanizer.min_delay_ms,
              maxDelay: humanizer.response_max_delay_ms,
              charsPerSecond: humanizer.chars_per_second,
              inReplyTo: providerMessageId,
              replyTo: result.toolCalls.length > 0 ? providerMessageId : undefined,
              singleMessage: result.singleMessage === true,
            }),
          ),
        )
      }
      sentCount = sendResults.filter((delivery) => delivery.status !== 'failed').length
      failedCount = sendResults.filter((delivery) => delivery.status === 'failed').length
      outboundDeliveries = sendResults.map((delivery) => ({
        content: delivery.content,
        providerMessageId: delivery.providerMessageId,
        status: delivery.status,
        error: delivery.error,
      }))
    }

    if (outboundDeliveries.length === 0) {
      throw new Error('delivery completed without outbound results')
    }
    await step.run('persist-out', async () => {
      const providerName = process.env.MESSAGING_PROVIDER ?? 'whatsapp_cloud'
      const rows = buildOutboundMessageRows({
        userId,
        provider: providerName,
        contentType: sendMode === 'audio' ? 'audio' : 'text',
        stage: result.stage,
        modelUsed: result.modelUsed,
        promptTokens: result.promptTokens,
        completionTokens: result.completionTokens,
        costUsd: result.costUsd,
        latencyMs: result.latencyMs,
        deliveries: outboundDeliveries,
      })
      for (const row of rows) {
        await persistOutboundMessage(supabase, {
          ...row,
          media_url: sendMode === 'audio' ? (ttsMediaId ?? null) : null,
        })
      }
      return { persisted: rows.length }
    })

    // === Step 5: reação final ===
    await step.run('final-reaction', async () => {
      if (result.toolCalls.length > 0) {
        const allOk = result.toolCalls.every((t) => !t.error)
        await messaging.react(wpp, providerMessageId, allOk ? '✅' : '⚠️').catch(() => {})
      } else if (normalizedMediaItems.length > 0) {
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
