import { createHash } from 'node:crypto'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { MobileApiError } from './http'

export interface CaptureFlowInboundInput {
  readonly userId: string
  readonly requestKey: string
  readonly text: string
}

export interface FlowInboundAuthorityMessage {
  readonly id: string
  readonly direction: 'in'
  readonly content: string
  readonly delivery_status: string | null
  readonly raw_payload: Readonly<Record<string, unknown>>
  readonly created_at: string
}

export type FlowInboundProbeResult =
  | { readonly status: 'unbound' }
  | { readonly status: 'bound'; readonly inbound: FlowInboundAuthorityMessage }

export type FlowInboundPersistResult = {
  readonly status: 'inserted' | 'reused'
  readonly inbound: FlowInboundAuthorityMessage
}

export interface CapturedFlowInboundAuthority extends CaptureFlowInboundInput {
  readonly admissionId: string
  probe(): Promise<FlowInboundProbeResult>
  persist(input: {
    readonly requestId: string
    readonly startedAt: string
  }): Promise<FlowInboundPersistResult>
}

export interface FlowInboundAuthoritySource {
  capture(input: CaptureFlowInboundInput): Promise<CapturedFlowInboundAuthority>
}

/** Request-local wiring must never turn a missing or mixed handle into legacy execution. */
export function assertCapturedFlowInboundAuthority(
  handle: CapturedFlowInboundAuthority | undefined,
  input: CaptureFlowInboundInput,
): asserts handle is CapturedFlowInboundAuthority {
  if (
    !handle ||
    handle.userId.toLowerCase() !== input.userId.toLowerCase() ||
    handle.requestKey !== input.requestKey ||
    handle.text !== input.text
  )
    throw invalidInput()
}

/** A point-in-time replay gate, not a transaction with HTTP, provider or OUT. */
export async function verifyCapturedFlowInboundReplay(
  handle: CapturedFlowInboundAuthority,
  inboundId?: string,
): Promise<void> {
  const result = await handle.probe()
  if (
    result.status !== 'bound' ||
    (inboundId !== undefined && result.inbound.id.toLowerCase() !== inboundId.toLowerCase())
  )
    throw new MobileApiError(
      409,
      'flow_request_authority_conflict',
      'Flow request authority could not be verified',
    )
}

type RefusalReason =
  | 'invalid_admission'
  | 'stale_epoch'
  | 'unproved_inbound'
  | 'inbound_mismatch'
  | 'request_content_conflict'

/** Private diagnostic properties are never put in MobileApiError.details. */
export class FlowInboundAuthorityRefusal extends MobileApiError {
  constructor(
    readonly outcome: 'forbidden' | 'conflict',
    readonly reason: RefusalReason,
  ) {
    super(409, 'flow_request_authority_conflict', 'Flow request authority could not be verified')
  }
}

const uuidSchema = z
  .string()
  .regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)
const keySchema = z.string().regex(/^[A-Za-z0-9._:-]{8,128}$/)

/** Validate the civil calendar, but retain the original ISO3/ISO6 string. */
function utcTimestamp(value: string, digits: 3 | 6): boolean {
  const pattern =
    digits === 3
      ? /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$/
      : /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z$/
  if (!pattern.test(value) || value.startsWith('0000-')) return false
  const milliseconds = digits === 6 ? `${value.slice(0, 23)}Z` : value
  const date = new Date(milliseconds)
  return Number.isFinite(date.getTime()) && date.toISOString() === milliseconds
}

const captureSchema = z
  .object({
    userId: uuidSchema,
    requestKey: keySchema,
    text: z.string().min(1).max(4000),
  })
  .strict()
const persistSchema = z
  .object({
    requestId: keySchema,
    startedAt: z.string().refine((value) => utcTimestamp(value, 3)),
  })
  .strict()
const admissionSchema = z
  .object({
    ownerID: uuidSchema,
    admissionID: uuidSchema,
    epoch: uuidSchema,
    requestNamespace: z.literal('mobile_flow_turn'),
    requestKey: keySchema,
    requestHash: z.string().regex(/^[0-9a-f]{64}$/),
    admittedAt: z.string().refine((value) => utcTimestamp(value, 6)),
  })
  .strict()
const conflictSchema = z
  .object({
    status: z.literal('conflict'),
    reason: z.literal('request_content_conflict'),
  })
  .strict()
const admissionReplySchema = z.discriminatedUnion('status', [
  z.object({ status: z.enum(['admitted', 'reused']), admission: admissionSchema }).strict(),
  z.object({ status: z.literal('forbidden'), reason: z.literal('stale_epoch') }).strict(),
  conflictSchema,
])

type JSONValue = string | number | boolean | null | JSONValue[] | { [key: string]: JSONValue }
function isJSONValue(value: unknown): value is JSONValue {
  if (value === null || typeof value === 'string' || typeof value === 'boolean') return true
  if (typeof value === 'number') return Number.isFinite(value)
  if (Array.isArray(value)) return Array.from(value).every(isJSONValue)
  if (typeof value !== 'object') return false
  const prototype = Object.getPrototypeOf(value)
  return (
    (prototype === Object.prototype || prototype === null) &&
    Object.values(value).every(isJSONValue)
  )
}
// Validation only: cloning through z.record would silently remove nested __proto__ keys.
const jsonSchema = z.custom<JSONValue>(isJSONValue)
const rawPayloadSchema = z
  .object({
    request_id: jsonSchema.optional(),
    conversation_id: jsonSchema.optional(),
    attempt_started_at: jsonSchema.optional(),
    provider_started_at: jsonSchema.optional(),
    retry_started_at: jsonSchema.optional(),
    last_retry_at: jsonSchema.optional(),
  })
  .strict()
const inboundSchema = z
  .object({
    id: uuidSchema,
    direction: z.literal('in'),
    content: z.string().min(1).max(4000),
    delivery_status: z.string().nullable(),
    raw_payload: rawPayloadSchema,
    created_at: z.string().refine((value) => utcTimestamp(value, 3) || utcTimestamp(value, 6)),
  })
  .strict()
const accessReplySchema = z.discriminatedUnion('status', [
  z.object({ status: z.literal('unbound') }).strict(),
  z.object({ status: z.enum(['bound', 'inserted', 'reused']), inbound: inboundSchema }).strict(),
  z
    .object({
      status: z.literal('forbidden'),
      reason: z.enum(['invalid_admission', 'stale_epoch', 'unproved_inbound', 'inbound_mismatch']),
    })
    .strict(),
  conflictSchema,
])

type RpcName = 'admit_workout_strength_request' | 'access_workout_strength_flow_inbound'
type AuthorityRpc = (
  name: RpcName,
  parameters: Record<string, unknown>,
) => PromiseLike<{
  data: unknown
  error: unknown
}>

function invalidInput(): MobileApiError {
  return new MobileApiError(
    500,
    'flow_request_authority_invalid_input',
    'Invalid Flow request authority input',
  )
}
function invalidResponse(): MobileApiError {
  return new MobileApiError(
    500,
    'flow_request_authority_invalid_response',
    'Invalid Flow request authority response',
  )
}
function unavailable(): MobileApiError {
  return new MobileApiError(
    500,
    'flow_request_authority_unavailable',
    'Unable to verify Flow request authority',
  )
}

function parse<T>(schema: z.ZodType<T>, input: unknown, failure = invalidResponse): T {
  try {
    const result = schema.safeParse(input)
    if (result.success) return result.data
  } catch {
    // A malformed internal wire must never escape as a public 422 with private field paths.
  }
  throw failure()
}

/** Injection seam only: production Flow composition does not instantiate it. */
export function createFlowInboundAuthoritySource(
  supabase: ServiceClient,
): FlowInboundAuthoritySource {
  // These RPCs intentionally use a narrow binding instead of changing generated global DB types.
  const rpc = supabase.rpc.bind(supabase) as unknown as AuthorityRpc
  async function invoke(name: RpcName, parameters: Record<string, unknown>): Promise<unknown> {
    let response: Awaited<ReturnType<AuthorityRpc>>
    try {
      response = await rpc(name, parameters)
    } catch {
      throw unavailable()
    }
    if (
      !response ||
      typeof response !== 'object' ||
      !Object.hasOwn(response, 'data') ||
      !Object.hasOwn(response, 'error')
    )
      throw invalidResponse()
    if (response.error !== null) throw unavailable()
    return response.data
  }

  return Object.freeze({
    async capture(input: CaptureFlowInboundInput): Promise<CapturedFlowInboundAuthority> {
      const { userId, requestKey, text } = parse(captureSchema, input, invalidInput)
      const hash = createHash('sha256').update(text, 'utf8').digest('hex')
      const reply = parse(
        admissionReplySchema,
        await invoke('admit_workout_strength_request', {
          p_user_id: userId,
          p_request_key: requestKey,
          p_request_hash: hash,
        }),
      )
      if (reply.status === 'forbidden' || reply.status === 'conflict') {
        throw new FlowInboundAuthorityRefusal(reply.status, reply.reason)
      }
      const receipt = reply.admission
      if (
        receipt.ownerID.toLowerCase() !== userId.toLowerCase() ||
        receipt.requestKey !== requestKey ||
        receipt.requestHash !== hash
      )
        throw invalidResponse()
      const admissionId = receipt.admissionID
      let observedInboundId: string | null = null

      async function access(
        mode: 'probe' | 'persist',
        requestId: string | null,
        startedAt: string | null,
      ) {
        const result = parse(
          accessReplySchema,
          await invoke('access_workout_strength_flow_inbound', {
            p_user_id: userId,
            p_admission_id: admissionId,
            p_text: text,
            p_mode: mode,
            p_request_id: requestId,
            p_started_at: startedAt,
          }),
        )
        if (result.status === 'forbidden' || result.status === 'conflict') {
          throw new FlowInboundAuthorityRefusal(result.status, result.reason)
        }
        if (result.status === 'unbound') {
          if (mode !== 'probe' || observedInboundId !== null) throw invalidResponse()
          return result
        }
        if (
          (mode === 'probe' ? result.status !== 'bound' : result.status === 'bound') ||
          result.inbound.content !== text
        )
          throw invalidResponse()
        if (result.status === 'inserted') {
          // Only a fresh IN can grant this execution ownership. S17I initializes all five
          // attempt fields atomically; an existing/reused IN may carry later operational JSON.
          const payload = result.inbound.raw_payload
          if (
            result.inbound.created_at !== startedAt ||
            result.inbound.delivery_status !== 'processing' ||
            Object.keys(payload).length !== 5 ||
            payload.request_id !== requestId ||
            payload.conversation_id !== 'flow' ||
            payload.attempt_started_at !== startedAt ||
            payload.provider_started_at !== null ||
            !Array.isArray(payload.retry_started_at) ||
            payload.retry_started_at.length !== 0
          )
            throw invalidResponse()
        }
        const id = result.inbound.id.toLowerCase()
        if (observedInboundId !== null && observedInboundId !== id) throw invalidResponse()
        observedInboundId = id
        return result
      }

      return Object.freeze({
        userId,
        requestKey,
        text,
        admissionId,
        async probe(): Promise<FlowInboundProbeResult> {
          const result = await access('probe', null, null)
          if (result.status === 'unbound') return result
          if (result.status !== 'bound') throw invalidResponse()
          return { status: result.status, inbound: result.inbound }
        },
        async persist(input: {
          readonly requestId: string
          readonly startedAt: string
        }): Promise<FlowInboundPersistResult> {
          const { requestId, startedAt } = parse(persistSchema, input, invalidInput)
          const result = await access('persist', requestId, startedAt)
          if (result.status !== 'inserted' && result.status !== 'reused') throw invalidResponse()
          return { status: result.status, inbound: result.inbound }
        },
      })
    },
  })
}
