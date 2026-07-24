import { createHmac, timingSafeEqual } from 'node:crypto'
import {
  type EntitlementPlan,
  type NormalizedEntitlementEvent,
  normalizedEntitlementEventSchema,
} from '@mpp/core'
import { z } from 'zod'

const SIGNATURE_TOLERANCE_SECONDS = 5 * 60
const PLAN_SCHEMA = z.enum(['trial', 'mensal', 'anual'])
const CONTROLLED_ID = /^[A-Za-z0-9._:/-]{1,200}$/

export class RevenueCatWebhookError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message)
    this.name = 'RevenueCatWebhookError'
  }
}

type SignatureVerificationInput = {
  body: string
  header: string | null
  secret: string
  now?: Date
}

export function verifyRevenueCatSignature({
  body,
  header,
  secret,
  now = new Date(),
}: SignatureVerificationInput): void {
  if (!header) {
    throw new RevenueCatWebhookError(401, 'invalid_signature', 'RevenueCat signature is missing')
  }

  const parts = header.split(',').map((part) => part.trim())
  if (parts.length !== 2) {
    throw new RevenueCatWebhookError(401, 'invalid_signature', 'RevenueCat signature is invalid')
  }

  const timestampParts = parts.filter((part) => part.startsWith('t='))
  const signatureParts = parts.filter((part) => part.startsWith('v1='))
  if (timestampParts.length !== 1 || signatureParts.length !== 1) {
    throw new RevenueCatWebhookError(401, 'invalid_signature', 'RevenueCat signature is ambiguous')
  }

  const timestampText = timestampParts[0]?.slice(2) ?? ''
  const suppliedDigest = signatureParts[0]?.slice(3) ?? ''
  if (!/^\d{1,16}$/.test(timestampText) || !/^[a-f0-9]{64}$/i.test(suppliedDigest)) {
    throw new RevenueCatWebhookError(401, 'invalid_signature', 'RevenueCat signature is invalid')
  }

  const timestamp = Number(timestampText)
  const nowSeconds = Math.floor(now.getTime() / 1000)
  if (!Number.isSafeInteger(timestamp) || !Number.isFinite(nowSeconds)) {
    throw new RevenueCatWebhookError(401, 'invalid_signature', 'RevenueCat timestamp is invalid')
  }
  if (Math.abs(nowSeconds - timestamp) > SIGNATURE_TOLERANCE_SECONDS) {
    throw new RevenueCatWebhookError(401, 'invalid_signature', 'RevenueCat timestamp is stale')
  }

  const expectedDigest = createHmac('sha256', secret).update(`${timestampText}.${body}`).digest()
  const suppliedBuffer = Buffer.from(suppliedDigest, 'hex')
  if (
    expectedDigest.length !== suppliedBuffer.length ||
    !timingSafeEqual(expectedDigest, suppliedBuffer)
  ) {
    throw new RevenueCatWebhookError(401, 'invalid_signature', 'RevenueCat signature is invalid')
  }
}

const productPlanMapSchema = z
  .record(z.string().regex(CONTROLLED_ID), PLAN_SCHEMA)
  .superRefine((mapping, context) => {
    const entries = Object.entries(mapping)
    if (entries.length < 1 || entries.length > 32) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'RevenueCat product map must contain between 1 and 32 entries',
      })
    }
  })

export function parseRevenueCatProductPlanMap(value: string): Record<string, EntitlementPlan> {
  let parsed: unknown
  try {
    parsed = JSON.parse(value)
  } catch {
    throw new RevenueCatWebhookError(
      503,
      'provider_not_configured',
      'RevenueCat product map is invalid',
    )
  }

  const result = productPlanMapSchema.safeParse(parsed)
  if (!result.success) {
    throw new RevenueCatWebhookError(
      503,
      'provider_not_configured',
      'RevenueCat product map is invalid',
    )
  }
  return Object.fromEntries(Object.entries(result.data))
}

const revenueCatEnvelopeSchema = z.object({
  api_version: z.literal('1.0'),
  event: z.object({
    id: z.string().min(1).max(200),
    type: z.string().min(1).max(100),
    app_user_id: z.string().uuid(),
    entitlement_ids: z.array(z.string().min(1).max(200)).max(32).nullable(),
    environment: z.enum(['SANDBOX', 'PRODUCTION']),
    event_timestamp_ms: z.number().int().positive(),
    expiration_at_ms: z.number().int().positive().nullable(),
    purchased_at_ms: z.number().int().positive(),
    grace_period_expiration_at_ms: z.number().int().positive().nullable().optional(),
    product_id: z.string().min(1).max(200),
    original_transaction_id: z.string().min(1).max(200),
    period_type: z.enum(['TRIAL', 'INTRO', 'NORMAL', 'PROMOTIONAL', 'PREPAID']),
    store: z.string().min(1).max(50),
  }),
})

export type RevenueCatNormalizationConfiguration = {
  expectedEnvironment: 'sandbox' | 'production'
  entitlementKey: string
  productPlanMap: Record<string, EntitlementPlan>
}

export type RevenueCatNormalizationResult =
  | { kind: 'apply'; event: NormalizedEntitlementEvent }
  | { kind: 'ignored'; reason: 'state_neutral_event' | 'billing_issue_without_grace' }

function fromEpochMilliseconds(value: number, field: string): string {
  const date = new Date(value)
  if (!Number.isFinite(date.getTime())) {
    throw new RevenueCatWebhookError(400, 'invalid_payload', `Invalid RevenueCat ${field}`)
  }
  return date.toISOString()
}

export function normalizeRevenueCatEvent(
  payload: unknown,
  configuration: RevenueCatNormalizationConfiguration,
): RevenueCatNormalizationResult {
  const parsed = revenueCatEnvelopeSchema.safeParse(payload)
  if (!parsed.success) {
    throw new RevenueCatWebhookError(400, 'invalid_payload', 'Invalid RevenueCat payload')
  }

  const event = parsed.data.event
  const actualEnvironment = event.environment === 'SANDBOX' ? 'sandbox' : 'production'
  if (actualEnvironment !== configuration.expectedEnvironment) {
    throw new RevenueCatWebhookError(403, 'environment_mismatch', 'RevenueCat environment mismatch')
  }
  if (event.type === 'TRANSFER') {
    throw new RevenueCatWebhookError(
      503,
      'reconciliation_required',
      'RevenueCat transfer requires reconciliation',
    )
  }
  if (event.store !== 'APP_STORE' && event.store !== 'TEST_STORE') {
    throw new RevenueCatWebhookError(422, 'unsupported_store', 'Unsupported RevenueCat store')
  }
  if (!event.entitlement_ids?.includes(configuration.entitlementKey)) {
    throw new RevenueCatWebhookError(422, 'unknown_entitlement', 'Unknown RevenueCat entitlement')
  }

  if (
    event.type === 'PRODUCT_CHANGE' ||
    event.type === 'SUBSCRIPTION_PAUSED' ||
    event.type === 'TEST'
  ) {
    return { kind: 'ignored', reason: 'state_neutral_event' }
  }

  const plan = configuration.productPlanMap[event.product_id]
  if (!plan) {
    throw new RevenueCatWebhookError(422, 'unknown_product', 'Unknown RevenueCat product')
  }

  if (event.type === 'BILLING_ISSUE' && !event.grace_period_expiration_at_ms) {
    return { kind: 'ignored', reason: 'billing_issue_without_grace' }
  }

  let status: NormalizedEntitlementEvent['status']
  let cancelAtPeriodEnd = false
  switch (event.type) {
    case 'INITIAL_PURCHASE':
      status = event.period_type === 'TRIAL' ? 'trialing' : 'active'
      break
    case 'RENEWAL':
    case 'UNCANCELLATION':
    case 'SUBSCRIPTION_EXTENDED':
      status = 'active'
      break
    case 'CANCELLATION':
      status = 'canceled'
      cancelAtPeriodEnd = true
      break
    case 'EXPIRATION':
      status = 'expired'
      break
    case 'BILLING_ISSUE':
      status = 'grace_period'
      break
    default:
      throw new RevenueCatWebhookError(
        503,
        'reconciliation_required',
        'RevenueCat event requires reconciliation',
      )
  }

  if (event.expiration_at_ms === null) {
    throw new RevenueCatWebhookError(400, 'invalid_payload', 'Subscription expiry is required')
  }

  const normalized = normalizedEntitlementEventSchema.safeParse({
    event_id: event.id,
    event_type: event.type,
    user_id: event.app_user_id,
    entitlement_key: configuration.entitlementKey,
    source: 'revenuecat',
    source_reference: event.original_transaction_id,
    status,
    plan,
    environment: actualEnvironment,
    occurred_at: fromEpochMilliseconds(event.event_timestamp_ms, 'event timestamp'),
    starts_at: fromEpochMilliseconds(event.purchased_at_ms, 'purchase timestamp'),
    access_expires_at: fromEpochMilliseconds(event.expiration_at_ms, 'expiration timestamp'),
    grace_expires_at: event.grace_period_expiration_at_ms
      ? fromEpochMilliseconds(event.grace_period_expiration_at_ms, 'grace timestamp')
      : null,
    cancel_at_period_end: cancelAtPeriodEnd,
  })
  if (!normalized.success) {
    throw new RevenueCatWebhookError(400, 'invalid_payload', 'Invalid RevenueCat payload')
  }

  return { kind: 'apply', event: normalized.data }
}
