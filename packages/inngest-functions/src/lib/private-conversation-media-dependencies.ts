import { createPrivateMediaCatalogV2, PrivateMediaCatalogError } from '@mpp/core/conversation-media'
import { conversationPhotoWorkerEnabled } from '@mpp/core/conversation-photo-purpose'
import type { ServiceClient } from '@mpp/db'
import { GeminiVision, GroqSTT } from '@mpp/providers'
import type { PrivateConversationMediaProcessingPorts } from '../functions/private-conversation-media-processing.js'
import { loadVisionConfig } from './runtime-config.js'

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
