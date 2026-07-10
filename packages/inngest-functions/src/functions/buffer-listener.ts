import { inngest } from '../client.js'
import { createWorkerDeps } from '../lib/env.js'
import { allMediaDone, pickMediaDoneEvents } from './vision-inflight-policy.js'

export type BufferedInboundMessage = {
  provider_message_id: string
  content_type: string
  text?: string | null
  mediaUrl?: string | null
  received_at: string
  server_received_at?: string | null
}

export function collectProviderMessageIds(msgs: BufferedInboundMessage[]): string[] {
  return msgs.map((m) => m.provider_message_id).filter(Boolean)
}

export function collectProviderTimestamps(msgs: BufferedInboundMessage[]): string[] {
  return msgs.map((m) => m.received_at).filter(Boolean)
}

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
 *   4. Dispara process-message com texto agregado, providerMessageId da MAIS RECENTE
 *      e providerMessageIds de TODAS as mensagens do turno atual.
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

      const msgs = (buf.messages as BufferedInboundMessage[]) ?? []

      if (msgs.length === 0) {
        await supabase.from('message_buffer').delete().eq('user_id', userId)
        return { dispatched: false, reason: 'buffer vazio' }
      }

      // Layer 4 (Bug #2 Luciana 23/06, audit 06-24): vision-inflight gate.
      // Cenário real: foto chegou no buffer 1, flushada → vision Sonnet rodou
      // ~20s, criou pending com 8 itens. Caption "10g ketchup + 10g maionese"
      // chegou 27s depois (>debounce 8s) no buffer 2 → segundo turno do LLM
      // viu o card de 8 itens como "refeição já registrada" e chamou
      // registra_refeicao só com 2 itens (subset). Layer 4 evita o split:
      // antes de flushar buffer SEM imagem, checa se houve image-msg do mesmo
      // user nos últimos 30s e se vision AINDA não emitiu vision.analyzed.
      // Se vision em vôo → estende debounce em +20s pra caption entrar no
      // MESMO ciclo da foto. Limite: só estende 1× por buffer (alreadyExtended
      // detectado por gap entre latest msg e flush_after).
      const VISION_INFLIGHT_WINDOW_MS = 30_000
      const EXTENSION_MS = 20_000
      const ANTI_LOOP_WINDOW_MS = 60_000
      // Audit 06-26 sprint pendentes Item 3: estende vision-inflight gate
      // pra incluir audio. Caso simétrico ao da foto: paciente manda áudio
      // longo, STT em vôo (~10-30s), caption/refinamento curto chega antes
      // do `stt.transcribed` → buffer flusha sem o áudio processado e
      // dispara LLM com contexto truncado. Inclui audio + eventos STT
      // (stt.transcribed = sucesso; stt.failed = falha — bate com nomes
      // reais em process-message.ts:263).
      const hasMediaInBuffer = msgs.some(
        (m) => m.content_type === 'image' || m.content_type === 'audio',
      )
      if (!hasMediaInBuffer) {
        // Review H3+H4 (audit 06-24): anti-loop via contagem de extensões
        // recentes em product_events. Antes usava heurística debounceWindowMs
        // > 15s, mas a RPC buffer_append_msg sobrescreve flush_after a cada
        // nova msg, apagando a marca de extensão e permitindo múltiplas
        // estensões. Agora: se buffer.flush_delayed_vision_inflight foi
        // emitido nos últimos 60s pro mesmo user, NÃO estende de novo (limite
        // hard). Defesa em camadas vs loop infinito.
        const { data: prevExt } = await supabase
          .from('product_events')
          .select('id')
          .eq('user_id', userId)
          .eq('event', 'buffer.flush_delayed_vision_inflight')
          .gte('occurred_at', new Date(now - ANTI_LOOP_WINDOW_MS).toISOString())
          .limit(1)
        const alreadyExtended = (prevExt ?? []).length > 0
        if (!alreadyExtended) {
          // Audit 06-26 MED 1: busca AS 2 mídias mais recentes (não só
          // limit 1). Cenário multimodal: paciente manda foto + áudio juntos
          // → antes pegava só a mais recente e processava só 1 dos 2 done
          // events, deixando o outro escapar.
          const { data: recentMedia } = await supabase
            .from('messages')
            .select('id, created_at, content_type')
            .eq('user_id', userId)
            .eq('direction', 'in')
            .in('content_type', ['image', 'audio'])
            .gte(
              'created_at',
              new Date(now - VISION_INFLIGHT_WINDOW_MS).toISOString(),
            )
            .order('created_at', { ascending: false })
            .limit(2)
          const mediaRows = (recentMedia ?? []) as Array<{
            id: string
            created_at: string
            content_type: string
          }>
          const recentImage = mediaRows[0]
          if (recentImage) {
            // Review H5 (audit 06-24): nomes de eventos vision do código real
            // são 'vision.analyzed' (sucesso) e 'vision.download_failed'
            // (falha). 'vision.completed' e 'vision.failed' NÃO existem.
            //
            // Audit 06-26 review HIGH 3 + MED 1: extraído pra
            // vision-inflight-policy.ts (pickMediaDoneEvents + allMediaDone).
            // Multimodal: se buffer tem foto + áudio, exige AMBOS done events
            // pra flushar.
            const distinctTypes = Array.from(
              new Set(mediaRows.map((r) => r.content_type)),
            ).filter((t): t is 'image' | 'audio' => t === 'image' || t === 'audio')
            const allDoneEvents = Array.from(
              new Set(distinctTypes.flatMap((t) => pickMediaDoneEvents(t))),
            )
            const { data: visionEvents } = await supabase
              .from('product_events')
              .select('id, event')
              .eq('user_id', userId)
              .in('event', allDoneEvents)
              .gte(
                'occurred_at',
                new Date(now - VISION_INFLIGHT_WINDOW_MS).toISOString(),
              )
            const eventRows = (visionEvents ?? []) as Array<{ event: string }>
            const hasVisionDone = eventRows.some(
              (e) => e.event === 'vision.analyzed' || e.event === 'vision.download_failed',
            )
            const hasSttDone = eventRows.some(
              (e) => e.event === 'stt.transcribed' || e.event === 'stt.failed',
            )
            const visionDone = allMediaDone(distinctTypes, {
              hasVisionDone,
              hasSttDone,
            })
            if (!visionDone) {
              const newFlushAt = new Date(now + EXTENSION_MS).toISOString()
              await supabase
                .from('message_buffer')
                .update({ flush_after: newFlushAt })
                .eq('user_id', userId)
              // eslint-disable-next-line @typescript-eslint/no-explicit-any
              await inngest.send({
                name: 'buffer.flush',
                data: {
                  userId,
                  count: msgs.length,
                  fired_at: new Date(now + EXTENSION_MS).toISOString(),
                } as any,
                ts: now + EXTENSION_MS,
              })
              await supabase.from('product_events').insert({
                user_id: userId,
                event: 'buffer.flush_delayed_vision_inflight',
                properties: {
                  recent_image_id: recentImage.id,
                  extension_ms: EXTENSION_MS,
                  buffer_size: msgs.length,
                  image_age_ms: now - new Date(recentImage.created_at).getTime(),
                },
              })
              return {
                dispatched: false,
                reason: `vision-inflight: estendido +${EXTENSION_MS}ms`,
              }
            }
          }
        }
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
      const providerMessageIds = collectProviderMessageIds(msgs)
      const providerTimestamps = collectProviderTimestamps(msgs)

      // Determina contentType: mídia tem prioridade
      const hasAudio = msgs.some((m) => m.content_type === 'audio')
      const hasImage = msgs.some((m) => m.content_type === 'image')
      const contentType = hasAudio ? 'audio' : hasImage ? 'image' : 'text'

      // Múltiplas mídias: array com TODAS na ordem em que chegaram
      const mediaUrls = msgs
        .filter((m) => m.mediaUrl && m.content_type === contentType)
        .map((m) => m.mediaUrl as string)
      const mediaUrl = mediaUrls[0]

      await inngest.send({
        name: 'message.received',
        data: {
          userId,
          wpp: (user as { wpp: string }).wpp,
          providerMessageId: latest.provider_message_id,
          providerMessageIds,
          providerTimestamps,
          contentType,
          text: aggregated || undefined,
          mediaUrl: mediaUrl ?? undefined,
          mediaUrls: mediaUrls.length > 0 ? mediaUrls : undefined,
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
