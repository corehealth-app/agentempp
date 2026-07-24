import { z } from 'zod'

export const entitlementStatusSchema = z.enum([
  'active',
  'trialing',
  'grace_period',
  'expired',
  'canceled',
  'grandfathered',
  'manual_comp',
  'blocked',
])

export const entitlementSourceSchema = z.enum([
  'stripe',
  'apple_storekit',
  'revenuecat',
  'manual',
  'legacy',
])

export const entitlementEnvironmentSchema = z.enum(['sandbox', 'production', 'internal'])
export const entitlementPlanSchema = z.enum(['trial', 'mensal', 'anual'])

export type EntitlementStatus = z.infer<typeof entitlementStatusSchema>
export type EntitlementSource = z.infer<typeof entitlementSourceSchema>
export type EntitlementEnvironment = z.infer<typeof entitlementEnvironmentSchema>
export type EntitlementPlan = z.infer<typeof entitlementPlanSchema>

const dateTimeSchema = z.string().datetime({ offset: true })
const nullableDateTimeSchema = dateTimeSchema.nullable()
const controlledIdentifierSchema = z
  .string()
  .trim()
  .min(1)
  .max(200)
  .regex(/^[A-Za-z0-9._:/-]+$/)

export const entitlementDecisionSchema = z
  .object({
    entitlement: controlledIdentifierSchema,
    has_active_access: z.boolean(),
    status: entitlementStatusSchema,
    source: entitlementSourceSchema.nullable(),
    plan: entitlementPlanSchema.nullable(),
    access_expires_at: nullableDateTimeSchema,
    grace_expires_at: nullableDateTimeSchema,
    cancel_at_period_end: z.boolean(),
    reason: z
      .string()
      .min(1)
      .max(64)
      .regex(/^[a-z][a-z0-9_]*$/),
    decision_at: dateTimeSchema,
  })
  .strict()

export type EntitlementDecision = z.infer<typeof entitlementDecisionSchema>

export const normalizedEntitlementEventSchema = z
  .object({
    event_id: controlledIdentifierSchema,
    event_type: controlledIdentifierSchema,
    user_id: z.string().uuid(),
    entitlement_key: controlledIdentifierSchema,
    source: entitlementSourceSchema,
    source_reference: controlledIdentifierSchema,
    status: entitlementStatusSchema,
    plan: entitlementPlanSchema.nullable(),
    environment: entitlementEnvironmentSchema,
    occurred_at: dateTimeSchema,
    starts_at: nullableDateTimeSchema,
    access_expires_at: nullableDateTimeSchema,
    grace_expires_at: nullableDateTimeSchema,
    cancel_at_period_end: z.boolean(),
  })
  .strict()
  .superRefine((event, context) => {
    const startsAt = event.starts_at === null ? null : Date.parse(event.starts_at)
    const expiresAt = event.access_expires_at === null ? null : Date.parse(event.access_expires_at)
    const graceAt = event.grace_expires_at === null ? null : Date.parse(event.grace_expires_at)

    if (startsAt !== null && expiresAt !== null && startsAt > expiresAt) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['access_expires_at'],
        message: 'access_expires_at cannot precede starts_at',
      })
    }
    if (expiresAt !== null && graceAt !== null && graceAt < expiresAt) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['grace_expires_at'],
        message: 'grace_expires_at cannot precede access_expires_at',
      })
    }
  })

export type NormalizedEntitlementEvent = z.infer<typeof normalizedEntitlementEventSchema>

type EntitlementEventOrder = {
  occurredAt: string
  eventId: string
}

export function compareEntitlementEventOrder(
  left: EntitlementEventOrder,
  right: EntitlementEventOrder,
): -1 | 0 | 1 {
  const leftTime = Date.parse(left.occurredAt)
  const rightTime = Date.parse(right.occurredAt)
  if (!Number.isFinite(leftTime) || !Number.isFinite(rightTime)) {
    throw new Error('Entitlement event order requires valid timestamps')
  }
  if (leftTime !== rightTime) return leftTime > rightTime ? 1 : -1
  if (left.eventId === right.eventId) return 0
  return left.eventId > right.eventId ? 1 : -1
}
