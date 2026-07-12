import { createHash } from 'node:crypto'
import { inngest } from '../client.js'
import { createWorkerDeps } from '../lib/env.js'
import { throwIfQueryFailed } from '../lib/query-error.js'
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

export function buildBufferDispatchEventId(
  userId: string,
  latestProviderMessageId: string,
): string {
  const digest = createHash('sha256')
    .update(`${userId}\u0000${latestProviderMessageId}`)
    .digest('hex')
  return `buffer-dispatch-${digest}`
}

type MessageDispatchClaim = {
  dispatch_id: string
  messages: BufferedInboundMessage[]
  source_flush_after: string
}

export function buildBufferedDispatchPayload(msgs: BufferedInboundMessage[]) {
  if (msgs.length === 0) throw new Error('claimed message dispatch is empty')

  const aggregated = msgs
    .map((m) => m.text)
    .filter(Boolean)
    .join('\n')
    .trim()
  const latest = msgs.at(-1)
  if (!latest) throw new Error('claimed message dispatch has no latest message')
  const providerMessageIds = collectProviderMessageIds(msgs)
  const providerTimestamps = collectProviderTimestamps(msgs)
  const hasAudio = msgs.some((m) => m.content_type === 'audio')
  const hasImage = msgs.some((m) => m.content_type === 'image')
  const contentType: 'audio' | 'image' | 'text' = hasAudio
    ? 'audio'
    : hasImage
      ? 'image'
      : 'text'
  const mediaUrls = msgs
    .filter((m) => m.mediaUrl && m.content_type === contentType)
    .map((m) => m.mediaUrl as string)

  return {
    aggregated,
    latest,
    providerMessageIds,
    providerTimestamps,
    contentType,
    mediaUrls,
  }
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

      const scheduleBufferFlush = async (
        flushAfter: string,
        count: number,
      ): Promise<void> => {
        const flushAtMs = new Date(flushAfter).getTime()
        if (!Number.isFinite(flushAtMs)) throw new Error('invalid buffer flush timestamp')
        const scheduledAt = Math.max(flushAtMs, Date.now()) + 250
        await inngest.send({
          id: buildBufferDispatchEventId(userId, `flush-at:${flushAfter}`),
          name: 'buffer.flush',
          data: {
            userId,
            count,
            fired_at: new Date(scheduledAt).toISOString(),
          },
          ts: scheduledAt,
        })
      }

      const dispatchClaim = async (claim: MessageDispatchClaim) => {
        const payload = buildBufferedDispatchPayload(claim.messages)
        const { data: user, error: userError } = await supabase
          .from('users')
          .select('wpp')
          .eq('id', userId)
          .maybeSingle()
        throwIfQueryFailed(userError, 'buffer user lookup failed')
        if (!user) throw new Error('buffer user not found')

        await inngest.send({
          id: buildBufferDispatchEventId(userId, `dispatch:${claim.dispatch_id}`),
          name: 'message.received',
          data: {
            userId,
            wpp: (user as { wpp: string }).wpp,
            providerMessageId: payload.latest.provider_message_id,
            providerMessageIds: payload.providerMessageIds,
            providerTimestamps: payload.providerTimestamps,
            contentType: payload.contentType,
            text: payload.aggregated || undefined,
            mediaUrl: payload.mediaUrls[0] ?? undefined,
            mediaUrls: payload.mediaUrls.length > 0 ? payload.mediaUrls : undefined,
            provider: 'whatsapp_cloud',
            timestamp: payload.latest.received_at,
          },
        })

        const { data: completion, error: completionError } = await (
          supabase as unknown as {
            rpc: (
              name: string,
              params: Record<string, unknown>,
            ) => Promise<{
              data: {
                status?: string
                next_buffer_count?: number
                next_flush_after?: string | null
              } | null
              error: unknown
            }>
          }
        ).rpc('complete_message_dispatch', {
          p_dispatch_id: claim.dispatch_id,
        })
        throwIfQueryFailed(completionError, 'message dispatch completion failed')

        const nextCount = Number(completion?.next_buffer_count ?? 0)
        const nextFlushAfter = completion?.next_flush_after ?? null
        if (nextCount > 0 && nextFlushAfter) {
          await scheduleBufferFlush(nextFlushAfter, nextCount)
        }

        return {
          dispatched: true,
          aggregated_count: claim.messages.length,
          text_length: payload.aggregated.length,
          dispatch_id: claim.dispatch_id,
        }
      }

      const { data: pendingDispatch, error: pendingDispatchError } = await supabase
        .from('message_dispatch_outbox')
        .select('id, messages, source_flush_after')
        .eq('user_id', userId)
        .maybeSingle()
      throwIfQueryFailed(pendingDispatchError, 'pending message dispatch lookup failed')
      if (pendingDispatch) {
        return dispatchClaim({
          dispatch_id: pendingDispatch.id,
          messages: pendingDispatch.messages as unknown as BufferedInboundMessage[],
          source_flush_after: pendingDispatch.source_flush_after,
        })
      }

      const { data: buf, error: bufferError } = await supabase
        .from('message_buffer')
        .select('user_id, messages, flush_after, media_extension_count')
        .eq('user_id', userId)
        .maybeSingle()
      throwIfQueryFailed(bufferError, 'message buffer lookup failed')

      if (!buf) return { dispatched: false, reason: 'sem buffer' }

      const now = Date.now()
      const flushAt = new Date(buf.flush_after).getTime()

      // Ainda no debounce? Garante uma invocacao na data persistida. Isso
      // recupera o caso em que o banco foi atualizado, mas o envio anterior
      // ao Inngest falhou logo depois.
      if (flushAt > now) {
        await scheduleBufferFlush(
          buf.flush_after,
          Array.isArray(buf.messages) ? buf.messages.length : 0,
        )
        return { dispatched: false, reason: 'ainda em debounce', remaining_ms: flushAt - now }
      }

      if (!Array.isArray(buf.messages)) throw new Error('message buffer payload is not an array')
      const msgs = buf.messages as unknown as BufferedInboundMessage[]

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
      // persistido atomicamente no próprio buffer).
      const VISION_INFLIGHT_WINDOW_MS = 30_000
      const EXTENSION_MS = 20_000
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
      if (msgs.length > 0 && !hasMediaInBuffer) {
        // O contador vive no proprio buffer e e atualizado atomicamente. Ele
        // nao depende de telemetria nem de timing entre queries.
        const alreadyExtended = Number(buf.media_extension_count ?? 0) >= 1
        if (!alreadyExtended) {
          // Audit 06-26 MED 1: busca AS 2 mídias mais recentes (não só
          // limit 1). Cenário multimodal: paciente manda foto + áudio juntos
          // → antes pegava só a mais recente e processava só 1 dos 2 done
          // events, deixando o outro escapar.
          const { data: recentMedia, error: recentMediaError } = await supabase
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
          throwIfQueryFailed(recentMediaError, 'recent media lookup failed')
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
            const { data: visionEvents, error: visionEventsError } = await supabase
              .from('product_events')
              .select('id, event')
              .eq('user_id', userId)
              .in('event', allDoneEvents)
              .gte(
                'occurred_at',
                new Date(now - VISION_INFLIGHT_WINDOW_MS).toISOString(),
              )
            throwIfQueryFailed(visionEventsError, 'media completion lookup failed')
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
              const { data: extended, error: extensionError } = await (
                supabase as unknown as {
                  rpc: (
                    name: string,
                    params: Record<string, unknown>,
                  ) => Promise<{ data: boolean | null; error: unknown }>
                }
              ).rpc('extend_message_buffer_once', {
                p_user_id: userId,
                p_new_flush_after: newFlushAt,
              })
              throwIfQueryFailed(extensionError, 'message buffer extension failed')
              if (extended) {
                await scheduleBufferFlush(newFlushAt, msgs.length)
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
      }

      const { data: claimResult, error: claimError } = await (
        supabase as unknown as {
          rpc: (
            name: string,
            params: Record<string, unknown>,
          ) => Promise<{ data: Record<string, unknown> | null; error: unknown }>
        }
      ).rpc('claim_due_message_dispatch', {
        p_user_id: userId,
        p_now: new Date().toISOString(),
      })
      throwIfQueryFailed(claimError, 'message dispatch claim failed')

      const claimStatus = typeof claimResult?.status === 'string' ? claimResult.status : null
      if (claimStatus === 'not_due') {
        const nextFlushAfter =
          typeof claimResult?.flush_after === 'string' ? claimResult.flush_after : null
        const nextCount = Number(claimResult?.buffer_count ?? 0)
        if (nextFlushAfter) await scheduleBufferFlush(nextFlushAfter, nextCount)
        return { dispatched: false, reason: 'buffer mudou durante o flush' }
      }
      if (claimStatus !== 'claimed') {
        return { dispatched: false, reason: 'buffer vazio' }
      }

      const dispatchId =
        typeof claimResult?.dispatch_id === 'string' ? claimResult.dispatch_id : null
      const claimedMessages = Array.isArray(claimResult?.messages)
        ? (claimResult.messages as BufferedInboundMessage[])
        : []
      if (!dispatchId || claimedMessages.length === 0) {
        throw new Error('message dispatch claim returned an invalid payload')
      }

      return dispatchClaim({
        dispatch_id: dispatchId,
        messages: claimedMessages,
        source_flush_after:
          typeof claimResult?.source_flush_after === 'string'
            ? claimResult.source_flush_after
            : buf.flush_after,
      })
    })

    logger.info('Buffer flush result', { userId, ...result })
    return result
  },
)
