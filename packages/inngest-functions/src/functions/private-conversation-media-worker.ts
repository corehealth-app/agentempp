import { createPrivateMediaCatalogV2, PrivateMediaCatalogError } from '@mpp/core/conversation-media'
import { conversationPhotoWorkerEnabled } from '@mpp/core/conversation-photo-purpose'
import type { ServiceClient } from '@mpp/db'
import { GeminiVision, GroqSTT } from '@mpp/providers'
import { NonRetriableError, RetryAfterError } from 'inngest'
import { z } from 'zod'
import { inngest } from '../client.js'
import { assertClinicalStagingWorkerTarget } from '../lib/clinical-staging-worker-target.js'
import { createWorkerSupabase } from '../lib/env.js'
import { loadVisionConfig } from '../lib/runtime-config.js'
import {
  type PrivateConversationMediaProcessingPorts,
  processPrivateConversationMedia,
} from './private-conversation-media-processing.js'

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
/** Explicit private policy in the existing qualified staging worker only.
 * This never widens any older/default production function set. */
export function privateConversationMediaWorkerEnabled(
  env: Readonly<Record<string, string | undefined>> = process.env,
): boolean {
  const target = env.SUPABASE_URL ?? env.NEXT_PUBLIC_SUPABASE_URL
  return (
    env.MOBILE_CONVERSATION_PRIVATE_CATALOG_ENABLED === 'true' &&
    env.INNGEST_FUNCTION_SET === 'media-conversation-staging' &&
    (target === 'https://xitugspwfxkcluxvrdeg.supabase.co' ||
      target === 'https://xitugspwfxkcluxvrdeg.supabase.co/')
  )
}

/** Uses the existing server client and approved providers/config. No legacy
 * catalog fallback, factual writer, new credentials or schedule is composed. */
export function createPrivateMediaProcessingDependencies(
  client: ServiceClient,
  env: Readonly<Record<string, string | undefined>> = process.env,
): PrivateConversationMediaProcessingPorts {
  function current() {
    if (!privateConversationMediaWorkerEnabled(env)) throw new PrivateMediaCatalogError()
  }
  function photoCurrent() {
    current()
    if (!conversationPhotoWorkerEnabled(env)) throw new PrivateMediaCatalogError()
  }
  current()
  const api = client as unknown as {
    rpc(
      name: string,
      args: Record<string, unknown>,
    ): {
      abortSignal(
        signal: AbortSignal,
      ): PromiseLike<{ data: unknown; error: { code?: string } | null }>
    }
  }
  const catalog = createPrivateMediaCatalogV2(async (name, args) => {
    current()
    const reply = await api.rpc(name, args).abortSignal(AbortSignal.timeout(15_000))
    current()
    return { data: reply.data, error: reply.error ? { code: reply.error.code } : null }
  })
  return {
    catalog: {
      ...catalog,
      async claimProcessing(scope, requestId) {
        const claim = await catalog.claimProcessing(scope, requestId)
        if (claim.action === 'claimed' && claim.asset.identity.kind === 'conversation_photo')
          photoCurrent()
        return claim
      },
    },
    now: () => {
      current()
      return new Date()
    },
    storage: {
      async download(bucketId, objectPath) {
        current()
        if (bucketId === 'meal-photos') photoCurrent()
        const { data, error } = await client.storage.from(bucketId).download(objectPath)
        current()
        if (bucketId === 'meal-photos') photoCurrent()
        if (error || !data) throw new PrivateMediaCatalogError()
        const bytes = new Uint8Array(await data.arrayBuffer())
        current()
        return bytes
      },
    },
    providers: {
      async analyzeImage(input) {
        photoCurrent()
        const apiKey = env.OPENROUTER_API_KEY
        if (!apiKey) throw new PrivateMediaCatalogError()
        const config = await loadVisionConfig(client)
        photoCurrent()
        const vision = new GeminiVision({
          apiKey,
          heliconeApiKey: env.HELICONE_API_KEY,
          model: config.model,
          nutritionLabelModel: config.nutrition_label_model,
          prompts: config.prompts,
        })
        const result = await vision.analyzeConversationImage(
          `data:${input.mimeType};base64,${Buffer.from(input.bytes).toString('base64')}`,
          {
            userMessage: input.contextText ?? undefined,
            purposeEnabled: () =>
              privateConversationMediaWorkerEnabled(env) && conversationPhotoWorkerEnabled(env),
          },
        )
        photoCurrent()
        return result
      },
      async transcribeAudio(input) {
        current()
        const apiKey = env.GROQ_API_KEY
        if (!apiKey) throw new PrivateMediaCatalogError()
        const extensions: Record<string, string> = {
          'audio/mpeg': 'mp3',
          'audio/mp4': 'm4a',
          'audio/x-m4a': 'm4a',
          'audio/aac': 'aac',
          'audio/wav': 'wav',
          'audio/x-wav': 'wav',
          'audio/ogg': 'ogg',
        }
        const stt = new GroqSTT({ apiKey })
        const result = await stt.transcribe({
          audio: input.bytes,
          mimeType: input.mimeType,
          filename: `bodyflow-audio.${extensions[input.mimeType] ?? 'bin'}`,
          language: 'pt',
        })
        current()
        return result
      },
    },
  }
}

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
