import { z } from 'zod'
import { MobileApiError } from './http'

export const reevaluationCycleUuidSchema = z
  .string()
  .regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)

function civilDate(value: string): boolean {
  if (!/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(value) || value.startsWith('0000-')) return false
  const date = new Date(`${value}T00:00:00.000Z`)
  return Number.isFinite(date.getTime()) && date.toISOString() === `${value}T00:00:00.000Z`
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

const date = z.string().refine(civilDate)
// PostgreSQL validates membership in pg_timezone_names. Do not substitute the
// Node/ICU catalogue or infer a new timezone from the current patient profile.
const timezone = z
  .string()
  .min(1)
  .refine(
    (value) =>
      value === value.trim() &&
      Array.from(value).every((character) => {
        const code = character.charCodeAt(0)
        return code > 31 && code !== 127
      }),
  )
const revision = z
  .string()
  .regex(/^[1-9][0-9]{0,18}$/)
  .refine((value) => value.length < 19 || value <= '9223372036854775807')
const clock = z
  .object({ base_date: date, due_date: date, timezone })
  .strict()
  .refine((value) => {
    if (!civilDate(value.base_date) || value.base_date > '9999-12-17') return false
    const next = new Date(`${value.base_date}T00:00:00.000Z`)
    next.setUTCDate(next.getUTCDate() + 14)
    return next.toISOString().slice(0, 10) === value.due_date
  })
const regularCycle = z
  .object({
    id: reevaluationCycleUuidSchema,
    signup_generation: reevaluationCycleUuidSchema,
    revision,
    kind: z.literal('REGULAR'),
    status: z.enum(['open', 'collecting', 'review_ready']),
    base_date: date,
    due_date: date,
    timezone_at_open: timezone,
    opened_at: z.string().refine(utc6),
  })
  .strict()
// This only reads SQL's captured kind. Opening or promoting an occurrence is
// still a server authority; a client cannot select EARLY to bypass regular photos.
const cycle = z.discriminatedUnion('kind', [
  regularCycle,
  regularCycle.extend({ kind: z.literal('EARLY_FULL') }).strict(),
])
const transitionState = z
  .object({
    version: z.literal(1),
    availability: z.literal('available'),
    unavailable_reason: z.null(),
    clock: z
      .object({ base_date: date, due_date: date, timezone })
      .strict()
      .refine((value) => value.base_date <= '9999-12-17' && value.base_date === value.due_date),
    transition: z
      .object({
        kind: z.literal('legacy_transition'),
        generation: reevaluationCycleUuidSchema,
        epoch: reevaluationCycleUuidSchema,
        admitted_at: z.string().refine(utc6),
      })
      .strict(),
    cycle: regularCycle
      .extend({ kind: z.literal('TRANSITION_FULL') })
      .strict()
      .nullable(),
  })
  .strict()
  .refine(
    (value) =>
      !value.cycle ||
      (value.cycle.signup_generation.toLowerCase() === value.transition.generation.toLowerCase() &&
        value.cycle.opened_at >= value.transition.admitted_at),
  )
const state = z
  .union([
    transitionState,
    z
      .object({
        version: z.literal(1),
        availability: z.literal('available'),
        unavailable_reason: z.null(),
        clock,
        cycle: cycle.nullable(),
      })
      .strict(),
    z
      .object({
        version: z.literal(1),
        availability: z.literal('unavailable'),
        unavailable_reason: z.literal('not_due'),
        clock,
        cycle: cycle.nullable(),
      })
      .strict(),
    z
      .object({
        version: z.literal(1),
        availability: z.literal('unavailable'),
        unavailable_reason: z.enum(['onboarding_incomplete', 'anchor_unproven', 'disabled']),
        clock: z.null(),
        cycle: z.null(),
      })
      .strict(),
  ])
  .refine(
    (value) =>
      !value.cycle ||
      (value.cycle.base_date === value.clock?.base_date &&
        value.cycle.due_date === value.clock?.due_date &&
        value.cycle.timezone_at_open === value.clock?.timezone &&
        (value.cycle.kind !== 'EARLY_FULL' || value.availability === 'available')),
  )

export type ReevaluationCycleState = z.infer<typeof state>
export const disabledReevaluationCycleState: ReevaluationCycleState = Object.freeze({
  version: 1,
  availability: 'unavailable',
  unavailable_reason: 'disabled',
  clock: null,
  cycle: null,
})

export function parseReevaluationCycleState(input: unknown): ReevaluationCycleState {
  try {
    const result = state.safeParse(input)
    if (result.success) return result.data
  } catch {
    // No raw wire value or validation issue may enter a public error response.
  }
  throw new MobileApiError(
    500,
    'mobile_reevaluation_invalid_response',
    'Unable to read reevaluation state',
  )
}

export function parseReevaluationCycleRpcState(input: unknown): ReevaluationCycleState {
  const result = parseReevaluationCycleState(input)
  if (result.unavailable_reason === 'disabled')
    throw new MobileApiError(
      500,
      'mobile_reevaluation_invalid_response',
      'Unable to read reevaluation state',
    )
  return result
}
