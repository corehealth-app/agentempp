import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { createConversationMediaExpiryDependencies } from './conversation-media-expiry-debt.js'
import { cleanupExpiredMedia } from './media-retention.js'
import { createPrivateConversationPurgeDependencies } from './private-conversation-media-account-purge.js'
import { createPrivateMediaDisposalV2 } from './private-conversation-media-disposal.js'
import { cleanupReevaluationPhotos } from './reevaluation-photo-cleanup.js'
import { createReevaluationPhotoCleanupDependencies } from './supabase-reevaluation-photo-cleanup.js'
import { purgeDeletedUsers } from './user-deletion-purge.js'

const uuid = z
  .string()
  .uuid()
  .refine((value) => value === value.toLowerCase())
const commandSchema = z.object({ dispatch_id: uuid }).strict()
const leaseSchema = z
  .object({
    schema: z.literal('conversation.media-maintenance-lease.v1'),
    dispatch_id: uuid,
    lease_id: uuid,
    lane: z.enum(['private', 'ordinary', 'recurring', 'accounts']),
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
  return new Response(JSON.stringify(value), {
    status,
    headers: { 'content-type': 'application/json', 'cache-control': 'no-store' },
  })
}
/** Scheduler-free, backend-only transport. SQL alone chooses the lane and
 * consumes a short-lived capability. No request supplies an owner or path.
 * The real SDK must bind every fetch to the shared signal and assertActive;
 * an uncertain timeout retains the existing durable media obligations. */
export function createConversationMediaMaintenanceHandler(deps: Dependencies) {
  const now = deps.now ?? Date.now
  function assertTarget() {
    if (
      deps.env.SUPABASE_URL !== 'https://xitugspwfxkcluxvrdeg.supabase.co' ||
      deps.env.MOBILE_CONVERSATION_MAINTENANCE_BRIDGE_ENABLED !== 'true'
    )
      throw Error('Maintenance unavailable')
  }
  return async (request: Request): Promise<Response> => {
    if (request.method !== 'POST') return response(405, { status: 'method_not_allowed' })
    try {
      assertTarget()
    } catch {
      return response(503, { status: 'unavailable' })
    }
    const token = request.headers.get('x-performe-maintenance-token') ?? ''
    if (
      !/^[0-9a-f]{64}$/.test(token) ||
      request.headers.get('content-type')?.split(';')[0] !== 'application/json' ||
      Number(request.headers.get('content-length') ?? 0) > 256
    )
      return response(400, { status: 'invalid_request' })
    let command: z.infer<typeof commandSchema>
    try {
      // Never buffer an unbounded body, including chunked requests.
      const reader = request.body?.getReader()
      if (!reader) throw Error('Invalid request')
      let bodyTimedOut = false
      const bodyTimer = setTimeout(() => {
        bodyTimedOut = true
        void reader.cancel().catch(() => {})
      }, 5000)
      const chunks: Uint8Array[] = []
      let length = 0
      try {
        for (;;) {
          const item = await reader.read()
          if (item.done) break
          length += item.value.length
          if (length > 256) throw Error('Invalid request')
          chunks.push(item.value)
        }
      } finally {
        clearTimeout(bodyTimer)
        await reader.cancel()
      }
      if (bodyTimedOut) throw Error('Invalid request')
      const body = new Uint8Array(length)
      let offset = 0
      for (const chunk of chunks) {
        body.set(chunk, offset)
        offset += chunk.length
      }
      command = commandSchema.parse(JSON.parse(new TextDecoder().decode(body)))
    } catch {
      return response(400, { status: 'invalid_request' })
    }
    const controller = new AbortController()
    const deadline = now() + 55000
    const timer = setTimeout(() => controller.abort(), 55000)
    let lease: Lease | undefined
    function assertActive() {
      assertTarget()
      if (
        controller.signal.aborted ||
        now() >= deadline ||
        (lease && now() >= Date.parse(lease.expires_at))
      )
        throw Error('Maintenance unavailable')
    }
    let api:
      | {
          rpc(
            name: string,
            args: Record<string, unknown>,
          ): PromiseLike<{ data: unknown; error: unknown }>
        }
      | undefined
    let completionAttempted = false
    async function complete(outcome: 'completed' | 'retry') {
      assertActive()
      if (!api || !lease) throw Error('Maintenance unavailable')
      completionAttempted = true
      const result = await api.rpc('complete_conversation_media_maintenance', {
        p_dispatch_id: lease.dispatch_id,
        p_lease_id: lease.lease_id,
        p_outcome: outcome,
      })
      assertActive()
      if (!result || result.error !== null || result.data !== true)
        throw Error('Maintenance unavailable')
    }
    try {
      assertActive()
      const hash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token))
      const sha256 = [...new Uint8Array(hash)].map((x) => x.toString(16).padStart(2, '0')).join('')
      const client = deps.createClient({ signal: controller.signal, assertActive })
      api = client as unknown as NonNullable<typeof api>
      const grant = await api.rpc('claim_conversation_media_maintenance', {
        p_dispatch_id: command.dispatch_id,
        p_token_sha256: sha256,
      })
      assertActive()
      if (!grant || grant.error !== null) throw Error('Maintenance unavailable')
      if (grant.data === null) return response(401, { status: 'unauthorized' })
      const parsed = leaseSchema.parse(grant.data)
      if (
        parsed.dispatch_id !== command.dispatch_id ||
        Date.parse(parsed.expires_at) <= now() ||
        Date.parse(parsed.expires_at) > now() + 65000
      )
        throw Error('Maintenance unavailable')
      lease = parsed
      assertActive()
      let summary: unknown
      switch (lease.lane) {
        case 'private': {
          const result = await createPrivateMediaDisposalV2(client, assertActive).sweep(100)
          summary = { ...result, issuanceReconciled: false }
          break
        }
        case 'ordinary': {
          const result = await cleanupExpiredMedia(
            createConversationMediaExpiryDependencies(client),
          )
          summary = { swept: result.deleted, issuanceReconciled: false }
          break
        }
        case 'recurring': {
          const result = await cleanupReevaluationPhotos(
            createReevaluationPhotoCleanupDependencies(client),
          )
          if (
            ['timeout', 'unavailable', 'invalid_receipt', 'invalid_input'].includes(result.stopped)
          )
            throw Error('Maintenance unavailable')
          summary = result
          break
        }
        case 'accounts':
          summary = await purgeDeletedUsers(
            createPrivateConversationPurgeDependencies(client, assertActive),
          )
          break
      }
      assertActive()
      await complete('completed')
      return response(200, { status: 'completed', lane: lease.lane, summary })
    } catch {
      if (lease && !completionAttempted) {
        try {
          await complete('retry')
        } catch {
          /* Lease timeout is recovered by SQL. */
        }
      }
      return response(503, { status: 'unavailable' })
    } finally {
      clearTimeout(timer)
      controller.abort()
    }
  }
}
