import { createHash } from 'node:crypto'
import { conversationPhotoWorkerEnabled } from '@mpp/core/conversation-photo-purpose'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import {
  type PrivateConversationMediaProcessingPorts,
  processPrivateConversationMedia,
} from '../functions/private-conversation-media-processing.js'
import {
  createPrivateMediaProcessingDependencies,
  privateConversationMediaWorkerEnabled,
} from './private-conversation-media-dependencies.js'

const uuid = z
  .string()
  .uuid()
  .refine((s) => s === s.toLowerCase())
const bodySchema = z.union([
  z.object({ dispatch_id: uuid }).strict(),
  z.object({ setup: z.literal(true) }).strict(),
])
const leaseSchema = z
  .object({
    schema: z.literal('conversation.media-processing-dispatch.v2'),
    dispatch_id: uuid,
    job_id: uuid,
    lease_id: uuid,
    user_id: uuid,
    asset_id: uuid,
    request_id: z.string().regex(/^[0-9a-f]{64}$/),
    source_sha: z.string().regex(/^[0-9a-f]{40}$/),
    kind: z.enum(['conversation_photo', 'audio_note']),
    expires_at: z.string().datetime({ offset: true }),
  })
  .strict()
type Lease = z.infer<typeof leaseSchema>
interface Dependencies {
  env: Readonly<Record<string, string | undefined>>
  createClient(context: { signal: AbortSignal; assertActive(): void }): ServiceClient
  now?: () => number
}
function response(status: number, value: unknown) {
  return Response.json(value, { status, headers: { 'cache-control': 'no-store' } })
}
async function readCommand(request: Request) {
  const reader = request.body?.getReader()
  if (!reader) throw Error('Unavailable')
  let expired = false
  const timer = setTimeout(() => {
    expired = true
    void reader.cancel().catch(() => {})
  }, 5000)
  const parts: Uint8Array[] = []
  let length = 0
  try {
    for (;;) {
      const part = await reader.read()
      if (part.done) break
      length += part.value.length
      if (length > 256) throw Error('Unavailable')
      parts.push(part.value)
    }
    if (expired) throw Error('Unavailable')
    const bytes = new Uint8Array(length)
    let at = 0
    for (const part of parts) {
      bytes.set(part, at)
      at += part.length
    }
    return bodySchema.parse(JSON.parse(new TextDecoder().decode(bytes)))
  } finally {
    clearTimeout(timer)
    await reader.cancel()
  }
}

/** Backend-only, default-OFF worker transport. SQL authenticates a short-lived
 * one-use dispatch and supplies the complete source scope. No client body can
 * select an owner, Storage path, model, callback target or factual writer. */
export function createPrivateMediaTransportHandler(deps: Dependencies) {
  const now = deps.now ?? Date.now
  function target() {
    const env = deps.env
    if (
      env.MOBILE_CONVERSATION_PROCESSING_BRIDGE_ENABLED !== 'true' ||
      env.INNGEST_FUNCTION_SET !== 'media-conversation-staging' ||
      env.SUPABASE_URL !== 'https://xitugspwfxkcluxvrdeg.supabase.co' ||
      env.MOBILE_CONVERSATION_PROCESSING_WORKER_PROJECT_ID !== 'prj_0SRds3zTc57EB0sExjYPygKGEgBx' ||
      !/^[0-9a-f]{40}$/.test(env.MOBILE_CONVERSATION_PROCESSING_SOURCE_SHA ?? '') ||
      !/^agentempp-media-worker-staging-[a-z0-9]+-gestao-9664s-projects\.vercel\.app$/.test(
        env.VERCEL_URL ?? '',
      )
    )
      throw Error('Unavailable')
  }
  return async (request: Request): Promise<Response> => {
    if (request.method !== 'POST') return response(405, { status: 'method_not_allowed' })
    try {
      target()
    } catch {
      return response(503, { status: 'unavailable' })
    }
    const token = request.headers.get('x-performe-processing-token') ?? ''
    if (
      !/^[0-9a-f]{64}$/.test(token) ||
      request.headers.get('content-type')?.split(';')[0] !== 'application/json' ||
      Number(request.headers.get('content-length') ?? 0) > 256
    )
      return response(400, { status: 'invalid_request' })
    let command: z.infer<typeof bodySchema>
    try {
      command = await readCommand(request)
    } catch {
      return response(400, { status: 'invalid_request' })
    }
    const controller = new AbortController(),
      deadline = now() + 240_000
    const timer = setTimeout(() => controller.abort(), 240_000)
    const signal = AbortSignal.any([controller.signal, request.signal])
    let lease: Lease | undefined
    let completionAttempted = false
    function assertActive() {
      target()
      if (signal.aborted || now() >= deadline || (lease && now() >= Date.parse(lease.expires_at)))
        throw Error('Unavailable')
    }
    let api:
      | {
          rpc(
            name: string,
            args: Record<string, unknown>,
          ): { abortSignal(signal: AbortSignal): PromiseLike<{ data: unknown; error: unknown }> }
        }
      | undefined
    async function rpc(name: string, args: Record<string, unknown>) {
      assertActive()
      if (!api) throw Error('Unavailable')
      const result = await api
        .rpc(name, args)
        .abortSignal(AbortSignal.any([signal, AbortSignal.timeout(15_000)]))
      assertActive()
      if (!result || result.error !== null) throw Error('Unavailable')
      return result.data
    }
    async function guard(reserveMs = 0) {
      assertActive()
      if (
        now() + reserveMs >= deadline ||
        (lease && now() + reserveMs >= Date.parse(lease.expires_at))
      )
        throw Error('Unavailable')
      if (
        !lease ||
        (await rpc('validate_conversation_media_processing_job_v2', {
          p_dispatch_id: lease.dispatch_id,
          p_lease_id: lease.lease_id,
          p_source_sha: lease.source_sha,
        })) !== true
      )
        throw Error('Unavailable')
    }
    async function complete(
      outcome: 'completed' | 'retry' | 'defer',
      retryAt: string | null = null,
    ) {
      assertActive()
      if (!lease) throw Error('Unavailable')
      completionAttempted = true
      if (
        (await rpc('complete_conversation_media_processing_job_v2', {
          p_dispatch_id: lease.dispatch_id,
          p_lease_id: lease.lease_id,
          p_outcome: outcome,
          p_retry_at: retryAt,
        })) !== true
      )
        throw Error('Unavailable')
    }
    try {
      const client = deps.createClient({ signal, assertActive })
      api = client as unknown as NonNullable<typeof api>
      const tokenHash = createHash('sha256').update(token).digest('hex')
      if ('setup' in command) {
        const bypass = deps.env.VERCEL_AUTOMATION_BYPASS_SECRET
        if (!bypass || bypass.length < 8 || bypass.length > 1024 || /[\r\n\0]/.test(bypass))
          throw Error('Unavailable')
        const accepted = await rpc('register_conversation_media_processing_transport_v2', {
          p_target_url: `https://${deps.env.VERCEL_URL}`,
          p_source_sha: deps.env.MOBILE_CONVERSATION_PROCESSING_SOURCE_SHA,
          p_setup_token_sha256: tokenHash,
          p_bypass_secret: bypass,
        })
        return accepted === true
          ? response(200, { status: 'configured' })
          : response(401, { status: 'unauthorized' })
      }
      const grant = await rpc('claim_conversation_media_processing_job_v2', {
        p_dispatch_id: command.dispatch_id,
        p_token_sha256: tokenHash,
        p_source_sha: deps.env.MOBILE_CONVERSATION_PROCESSING_SOURCE_SHA,
      })
      if (grant === null) return response(401, { status: 'unauthorized' })
      const parsed = leaseSchema.parse(grant)
      if (
        parsed.dispatch_id !== command.dispatch_id ||
        parsed.source_sha !== deps.env.MOBILE_CONVERSATION_PROCESSING_SOURCE_SHA ||
        Date.parse(parsed.expires_at) <= now() ||
        Date.parse(parsed.expires_at) > now() + 305_000
      )
        throw Error('Unavailable')
      lease = parsed
      await guard()
      if (
        !privateConversationMediaWorkerEnabled(deps.env) ||
        (lease.kind === 'conversation_photo' && !conversationPhotoWorkerEnabled(deps.env))
      ) {
        await complete('defer', new Date(now() + 60_000).toISOString())
        return response(200, { status: 'deferred' })
      }
      const base = createPrivateMediaProcessingDependencies(client, deps.env, {
        async providerFetch(input, init) {
          await guard()
          const options = { ...init, duplex: 'half' as const }
          const request = new Request(input, options),
            url = new URL(request.url)
          const image =
            url.origin === 'https://openrouter.ai' && url.pathname === '/api/v1/chat/completions'
          const audio =
            url.origin === 'https://api.groq.com' &&
            url.pathname === '/openai/v1/audio/transcriptions'
          if (request.method !== 'POST' || !(image || audio)) throw Error('Unavailable')
          const reply = await fetch(request, {
            signal: AbortSignal.any([signal, request.signal]),
            redirect: 'error',
          })
          await guard()
          return reply
        },
      })
      const ports: PrivateConversationMediaProcessingPorts = {
        ...base,
        catalog: {
          async claimProcessing(scope, requestId) {
            await guard()
            const value = await base.catalog.claimProcessing(scope, requestId)
            await guard()
            return value
          },
          async findOwned(scope) {
            await guard()
            const value = await base.catalog.findOwned(scope)
            await guard()
            return value
          },
          async completeProcessing(scope, requestId, token, result) {
            await guard()
            const value = await base.catalog.completeProcessing(scope, requestId, token, result)
            await guard()
            return value
          },
          async failProcessing(scope, requestId, token, reason) {
            await guard()
            const value = await base.catalog.failProcessing(scope, requestId, token, reason)
            await guard()
            return value
          },
        },
        storage: {
          async download(bucket, path) {
            await guard()
            const bytes = await base.storage.download(bucket, path)
            await guard()
            return bytes
          },
        },
        providers: {
          async analyzeImage(input) {
            await guard(50_000)
            const value = await base.providers.analyzeImage(input)
            await guard()
            return value
          },
          async transcribeAudio(input) {
            await guard(75_000)
            const value = await base.providers.transcribeAudio(input)
            await guard()
            return value
          },
        },
      }
      const result = await processPrivateConversationMedia(ports, {
        userId: lease.user_id,
        assetId: lease.asset_id,
        requestId: lease.request_id,
      })
      if (result.status === 'busy') {
        const retry = Date.parse(result.retry_at)
        if (!Number.isFinite(retry)) throw Error('Unavailable')
        await complete('defer', new Date(Math.max(now() + 1000, retry + 1000)).toISOString())
        return response(200, { status: 'deferred' })
      }
      await complete('completed')
      return response(200, { status: 'completed' })
    } catch {
      // An uncertain completion may already have committed. Only durable
      // dispatcher recovery may inspect it; never overwrite it with failure.
      if (lease && !completionAttempted) {
        try {
          await complete('retry')
        } catch {
          /* durable lease expiry recovers */
        }
      }
      return response(503, { status: 'unavailable' })
    } finally {
      clearTimeout(timer)
      controller.abort()
    }
  }
}
