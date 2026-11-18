import { inngest } from '@mpp/inngest-functions/client'
import { z } from 'zod'
import type { MobileRouteContext } from './route'
import { versionedOwnedMediaResponse } from './versioned-media-owned-response'

const jobSchema = z
  .object({
    schema: z.literal('conversation.media-processing-job.v2'),
    job_id: z.string().uuid(),
    user_id: z.string().uuid(),
    asset_id: z.string().uuid(),
    state: z.enum(['waiting', 'queued', 'running', 'completed']),
  })
  .strict()

/** A queue capability is composed only by the processing POST. Neither caller
 * JSON nor headers choose catalog version, event name, owner or worker route. */
export function versionedMediaProcessingResponse(
  context: MobileRouteContext,
  assetId: string,
  legacy: () => Promise<Response>,
  env: Readonly<Record<string, string | undefined>> = process.env,
): Promise<Response> {
  return versionedOwnedMediaResponse(context, assetId, 'process', legacy, env, {
    requestKey: context.request.headers.get('idempotency-key') ?? '',
    async enqueue(input) {
      if (env.MOBILE_CONVERSATION_PROCESSING_BRIDGE_ENABLED === 'true') {
        const api = context.supabase as unknown as {
          rpc(
            name: string,
            args: Record<string, unknown>,
          ): {
            abortSignal(signal: AbortSignal): PromiseLike<{ data: unknown; error: unknown }>
          }
        }
        const reply = await api
          .rpc('enqueue_conversation_media_processing_job_v2', {
            p_user_id: input.userId,
            p_asset_id: input.assetId,
            p_request_id: input.requestId,
          })
          .abortSignal(AbortSignal.timeout(15_000))
        if (!reply || reply.error !== null) throw Error('Private queue unavailable')
        const job = jobSchema.parse(reply.data)
        if (job.user_id !== input.userId || job.asset_id !== input.assetId)
          throw Error('Private queue unavailable')
        // Acceptance above committed independently. A failed/lost immediate
        // wakeup is recovered by the owned due-only cron, never by another
        // transport/event or a second processing request.
        if (job.state === 'waiting') {
          try {
            await api
              .rpc('dispatch_due_conversation_media_processing_v2', {})
              .abortSignal(AbortSignal.timeout(15_000))
          } catch {
            /* the accepted durable job remains pending */
          }
        }
        return
      }
      await inngest.send({
        id: `conversation-media-v2:${input.assetId}:${input.requestId}`,
        name: 'conversation.media.private.process.requested',
        data: { schema: 'conversation.media-process.v2', catalogVersion: 2, ...input },
      })
    },
  })
}
