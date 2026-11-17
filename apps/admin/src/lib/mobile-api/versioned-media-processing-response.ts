import { inngest } from '@mpp/inngest-functions/client'
import type { MobileRouteContext } from './route'
import { versionedOwnedMediaResponse } from './versioned-media-owned-response'

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
      await inngest.send({
        id: `conversation-media-v2:${input.assetId}:${input.requestId}`,
        name: 'conversation.media.private.process.requested',
        data: { schema: 'conversation.media-process.v2', catalogVersion: 2, ...input },
      })
    },
  })
}
