import { createHash } from 'node:crypto'
import type { ServiceClient } from '@mpp/db'
import { idempotencyKeySchema } from './contracts'
import { MobileApiError } from './http'
import type { MobileRouteContext } from './route'

interface ClaimInput {
  idempotencyKey: string
  method: string
  requestHash: string
  route: string
  userId: string
}

export type IdempotencyClaim =
  | { action: 'claimed'; claimId: string }
  | { action: 'conflict' }
  | { action: 'in_progress' }
  | { action: 'replay'; body: unknown; status: number }

export interface MobileIdempotencyStore {
  claim(input: ClaimInput): Promise<IdempotencyClaim>
  complete(claimId: string, userId: string, status: number, body: unknown): Promise<void>
  fail(claimId: string, userId: string): Promise<void>
}

interface ExecuteIdempotentOptions {
  refreshReplay?: (claim: Extract<IdempotencyClaim, { action: 'replay' }>) => Promise<Response>
  responseBodyForStorage?: (body: unknown) => unknown
}

type RpcResult = Promise<{
  data: unknown
  error: { message: string } | null
}>

type UntypedRpc = (functionName: string, params: Record<string, unknown>) => RpcResult

function canonicalJson(value: unknown): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value)
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`

  return `{${Object.entries(value)
    .filter(([, entry]) => entry !== undefined)
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([key, entry]) => `${JSON.stringify(key)}:${canonicalJson(entry)}`)
    .join(',')}}`
}

export function hashMobileRequest(payload: unknown): string {
  return createHash('sha256').update(canonicalJson(payload)).digest('hex')
}

function parseClaim(data: unknown): IdempotencyClaim {
  if (!data || typeof data !== 'object') throw new Error('Invalid idempotency claim response')
  const record = data as Record<string, unknown>

  if (record.action === 'claimed' && typeof record.claim_id === 'string') {
    return { action: 'claimed', claimId: record.claim_id }
  }
  if (record.action === 'conflict') return { action: 'conflict' }
  if (record.action === 'in_progress') return { action: 'in_progress' }
  if (
    record.action === 'replay' &&
    typeof record.response_status === 'number' &&
    record.response_body !== undefined
  ) {
    return {
      action: 'replay',
      status: record.response_status,
      body: record.response_body,
    }
  }

  throw new Error('Unknown idempotency claim action')
}

export function createSupabaseIdempotencyStore(supabase: ServiceClient): MobileIdempotencyStore {
  const rpc = supabase.rpc.bind(supabase) as unknown as UntypedRpc

  return {
    async claim(input) {
      const { data, error } = await rpc('claim_mobile_api_request', {
        p_user_id: input.userId,
        p_idempotency_key: input.idempotencyKey,
        p_request_method: input.method,
        p_request_route: input.route,
        p_request_hash: input.requestHash,
      })
      if (error) throw new Error(`Unable to claim mobile request: ${error.message}`)
      return parseClaim(data)
    },
    async complete(claimId, userId, status, body) {
      const { data, error } = await rpc('complete_mobile_api_request', {
        p_claim_id: claimId,
        p_user_id: userId,
        p_response_status: status,
        p_response_body: body,
      })
      if (error || data !== true) throw new Error('Unable to complete mobile request claim')
    },
    async fail(claimId, userId) {
      const { error } = await rpc('fail_mobile_api_request', {
        p_claim_id: claimId,
        p_user_id: userId,
      })
      if (error) throw new Error('Unable to release mobile request claim')
    },
  }
}

function replayBody(body: unknown, requestId: string): unknown {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return body
  const record = body as Record<string, unknown>
  if (!record.meta || typeof record.meta !== 'object' || Array.isArray(record.meta)) return body

  return {
    ...record,
    meta: { ...(record.meta as Record<string, unknown>), request_id: requestId },
  }
}

function replayResponse(claim: Extract<IdempotencyClaim, { action: 'replay' }>, requestId: string) {
  return Response.json(replayBody(claim.body, requestId), {
    status: claim.status,
    headers: {
      'Cache-Control': 'no-store',
      'Content-Type': 'application/json; charset=utf-8',
      'Idempotency-Replayed': 'true',
      Vary: 'Authorization',
      'X-Request-Id': requestId,
    },
  })
}

function markResponseAsReplay(response: Response, requestId: string): Response {
  const headers = new Headers(response.headers)
  headers.set('Cache-Control', 'no-store')
  headers.set('Idempotency-Replayed', 'true')
  headers.set('Vary', 'Authorization')
  headers.set('X-Request-Id', requestId)
  return new Response(response.body, { status: response.status, headers })
}

async function releaseClaim(
  store: MobileIdempotencyStore,
  claimId: string,
  userId: string,
): Promise<void> {
  try {
    await store.fail(claimId, userId)
  } catch {
    // The original operation error remains the actionable failure.
  }
}

export async function executeIdempotent(
  context: MobileRouteContext,
  validatedPayload: unknown,
  store: MobileIdempotencyStore,
  operation: () => Promise<Response>,
  options: ExecuteIdempotentOptions = {},
): Promise<Response> {
  const rawKey = context.request.headers.get('idempotency-key')
  if (!rawKey) {
    throw new MobileApiError(400, 'missing_idempotency_key', 'Idempotency-Key is required')
  }

  const parsedKey = idempotencyKeySchema.safeParse(rawKey)
  if (!parsedKey.success) {
    throw new MobileApiError(400, 'invalid_idempotency_key', 'Idempotency-Key is invalid')
  }

  const claim = await store.claim({
    idempotencyKey: parsedKey.data,
    method: context.request.method.toUpperCase(),
    route: new URL(context.request.url).pathname,
    requestHash: hashMobileRequest(validatedPayload),
    userId: context.auth.userId,
  })

  if (claim.action === 'conflict') {
    throw new MobileApiError(
      409,
      'idempotency_key_conflict',
      'Idempotency-Key was already used for another request',
    )
  }
  if (claim.action === 'in_progress') {
    throw new MobileApiError(
      409,
      'idempotency_request_in_progress',
      'A request with this Idempotency-Key is still in progress',
    )
  }
  if (claim.action === 'replay') {
    if (options.refreshReplay) {
      return markResponseAsReplay(await options.refreshReplay(claim), context.requestId)
    }
    return replayResponse(claim, context.requestId)
  }

  try {
    const response = await operation()
    if (response.status >= 500) {
      await releaseClaim(store, claim.claimId, context.auth.userId)
      return response
    }

    let body: unknown
    try {
      body = await response.clone().json()
    } catch {
      await releaseClaim(store, claim.claimId, context.auth.userId)
      throw new MobileApiError(
        500,
        'idempotency_response_invalid',
        'Mutation returned a non-JSON response',
      )
    }

    await store.complete(
      claim.claimId,
      context.auth.userId,
      response.status,
      options.responseBodyForStorage?.(body) ?? body,
    )
    return response
  } catch (error) {
    await releaseClaim(store, claim.claimId, context.auth.userId)
    throw error
  }
}

export function executeSupabaseIdempotent(
  context: MobileRouteContext,
  validatedPayload: unknown,
  operation: () => Promise<Response>,
  options: ExecuteIdempotentOptions = {},
): Promise<Response> {
  return executeIdempotent(
    context,
    validatedPayload,
    createSupabaseIdempotencyStore(context.supabase),
    operation,
    options,
  )
}
