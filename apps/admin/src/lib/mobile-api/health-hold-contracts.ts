import {
  HEALTH_RISK_CODES,
  healthRiskCodeSchema,
  healthRiskSetSchema,
} from '@mpp/core/health-check'
import { z } from 'zod'
import { MobileApiError } from './http'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'

export type HealthHoldFailureKind =
  | 'identity_invalid'
  | 'invalid_input'
  | 'invalid_response'
  | 'unavailable'
  | 'state_changed'
const failures = Object.freeze({
  identity_invalid: 403,
  invalid_input: 422,
  invalid_response: 500,
  unavailable: 503,
  state_changed: 409,
})
export function healthHoldFailure(kind: HealthHoldFailureKind): MobileApiError {
  return new MobileApiError(
    failures[kind],
    `mobile_health_hold_${kind}`,
    'Unable to access health safety state',
  )
}
/** Never forward an arbitrary repository/provider error, even if it has an API-error shape. */
export function sanitizeHealthHoldFailure(error: unknown): MobileApiError {
  for (const kind of Object.keys(failures) as HealthHoldFailureKind[]) {
    if (
      error instanceof MobileApiError &&
      error.code === `mobile_health_hold_${kind}` &&
      error.status === failures[kind]
    )
      return healthHoldFailure(kind)
  }
  return healthHoldFailure('unavailable')
}

function utc6(value: string): boolean {
  if (
    !/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z$/.test(value) ||
    value.startsWith('0000-')
  )
    return false
  const milliseconds = `${value.slice(0, 23)}Z`
  const date = new Date(milliseconds)
  return Number.isFinite(date.getTime()) && date.toISOString() === milliseconds
}
const timestamp = z.string().refine(utc6)
const revision = z
  .string()
  .regex(/^(0|[1-9][0-9]{0,18})$/)
  .refine((value) => value.length < 19 || value <= '9223372036854775807')
const positiveRevision = revision.refine((value) => value !== '0')
const canonicalCodes = (items: readonly string[]) =>
  JSON.stringify(HEALTH_RISK_CODES.filter((code) => items.includes(code))) === JSON.stringify(items)
const item = z.object({ code: healthRiskCodeSchema, declared_at: timestamp }).strict()
const snapshot = z
  .object({
    version: z.literal(1),
    user_id: uuid,
    safety_revision: revision,
    hold_active: z.boolean(),
    declared_no_plan: z.boolean(),
    hide_protein: z.boolean(),
    last_declared_at: timestamp.nullable(),
    items: z.array(item).max(8),
  })
  .strict()
  .refine((state) => {
    const codes = state.items.map((entry) => entry.code)
    if (
      !canonicalCodes(codes) ||
      state.hold_active !== codes.length > 0 ||
      state.declared_no_plan !== codes.includes('pregnant_or_breastfeeding') ||
      state.hide_protein !== codes.includes('professional_diet')
    )
      return false
    if (state.safety_revision === '0') return !state.hold_active && state.last_declared_at === null
    return (
      state.last_declared_at !== null &&
      state.items.every((entry) => entry.declared_at <= (state.last_declared_at ?? ''))
    )
  })
const receipt = z
  .object({
    id: uuid,
    operation_key: uuid,
    safety_revision: positiveRevision,
    declared_at: timestamp,
    items: z.array(healthRiskCodeSchema).min(1).max(8).refine(canonicalCodes),
  })
  .strict()
const declaration = z
  .object({ version: z.literal(1), user_id: uuid, receipt, state: snapshot })
  .strict()
export type HealthHoldSnapshot = z.infer<typeof snapshot>
export type HealthRiskDeclaration = z.infer<typeof declaration>

export function parseHealthHoldSnapshot(input: unknown, userId: string): HealthHoldSnapshot {
  try {
    const result = snapshot.safeParse(input)
    if (
      uuid.safeParse(userId).success &&
      result.success &&
      result.data.user_id.toLowerCase() === userId.toLowerCase()
    )
      return result.data
  } catch {
    /* Validation issues and raw wire values must never enter an error. */
  }
  throw healthHoldFailure('invalid_response')
}

export function parseHealthRiskDeclaration(
  input: unknown,
  userId: string,
  operationKey: string,
  items: unknown,
): HealthRiskDeclaration {
  try {
    const expected = healthRiskSetSchema.safeParse(items)
    const parsed = declaration.safeParse(input)
    if (
      uuid.safeParse(userId).success &&
      uuid.safeParse(operationKey).success &&
      expected.success &&
      parsed.success
    ) {
      const result = parsed.data
      const state = parseHealthHoldSnapshot(result.state, userId)
      const current = BigInt(state.safety_revision)
      const original = BigInt(result.receipt.safety_revision)
      if (
        result.user_id.toLowerCase() !== userId.toLowerCase() ||
        result.receipt.operation_key.toLowerCase() !== operationKey.toLowerCase() ||
        JSON.stringify(result.receipt.items) !== JSON.stringify(expected.data) ||
        current < original ||
        state.last_declared_at === null ||
        state.last_declared_at < result.receipt.declared_at
      )
        throw healthHoldFailure('invalid_response')
      // Same revision is the actual declaration, never a synthetic/partial clearance.
      if (
        current === original &&
        (!state.hold_active ||
          state.last_declared_at !== result.receipt.declared_at ||
          !result.receipt.items.every((code) =>
            state.items.some(
              (entry) => entry.code === code && entry.declared_at === result.receipt.declared_at,
            ),
          ))
      )
        throw healthHoldFailure('invalid_response')
      // A newer FULL may later clear items; an old receipt must not rearm them.
      if (
        current > original &&
        state.items.some(
          (entry) =>
            result.receipt.items.includes(entry.code) &&
            entry.declared_at < result.receipt.declared_at,
        )
      )
        throw healthHoldFailure('invalid_response')
      return result
    }
  } catch {
    /* Never include raw flags, owner, database errors or Zod issues. */
  }
  throw healthHoldFailure('invalid_response')
}
