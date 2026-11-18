import { PrivateMediaCatalogError } from '@mpp/core/conversation-media'
import { NonRetriableError, RetryAfterError } from 'inngest'
import { z } from 'zod'
import { inngest } from '../client.js'
import { assertClinicalStagingWorkerTarget } from '../lib/clinical-staging-worker-target.js'
import { createWorkerSupabase } from '../lib/env.js'
import { createPrivateMediaProcessingDependencies } from '../lib/private-conversation-media-dependencies.js'
import { processPrivateConversationMedia } from './private-conversation-media-processing.js'

// Keep the existing worker API stable; direct transports use the inert leaf.
export {
  createPrivateMediaProcessingDependencies,
  privateConversationMediaWorkerEnabled,
} from '../lib/private-conversation-media-dependencies.js'

const uuid = z
  .string()
  .uuid()
  .refine((value) => value === value.toLowerCase())
const eventSchema = z
  .object({
    schema: z.literal('conversation.media-process.v2'),
    catalogVersion: z.literal(2),
    userId: uuid,
    assetId: uuid,
    requestId: z.string().regex(/^[0-9a-f]{64}$/),
  })
  .strict()
export const privateConversationMediaProcessingFn = inngest.createFunction(
  {
    id: 'conversation-private-media-processing',
    retries: 3,
    concurrency: { key: 'event.data.assetId', limit: 1 },
  },
  { event: 'conversation.media.private.process.requested' },
  async ({ event }) => {
    const parsed = eventSchema.safeParse(event.data)
    if (!parsed.success) throw new NonRetriableError('Invalid private media request')
    try {
      if (process.env.MOBILE_CONVERSATION_PRIVATE_CATALOG_ENABLED !== 'true')
        throw new RetryAfterError('Private media capability temporarily unavailable', 60_000)
      assertClinicalStagingWorkerTarget(process.env, 'media-conversation-staging')
      const deps = createPrivateMediaProcessingDependencies(createWorkerSupabase())
      // Do not memoize a busy claim as a completed durable step. SQL leases and
      // persisted processing results make re-entry safe after uncertain IO.
      const outcome = await processPrivateConversationMedia(deps, {
        userId: parsed.data.userId,
        assetId: parsed.data.assetId,
        requestId: parsed.data.requestId,
      })
      if (outcome.status === 'busy') {
        const retry = Date.parse(outcome.retry_at)
        if (!Number.isFinite(retry)) throw new PrivateMediaCatalogError()
        throw new RetryAfterError(
          'Private media source is busy',
          new Date(Math.max(Date.now() + 1000, retry + 1000)),
        )
      }
      return outcome
    } catch (error) {
      if (error instanceof RetryAfterError) throw error
      throw new Error('Private media processing unavailable')
    }
  },
)
