/** Consumes the source captured by SQL. Never constructs a receipt, history,
 * generation or calendar boundary from a mutable profile or client intent. */
import {
  clinicalCivilDateSchema as date,
  clinicalTimestampSchema as instant,
} from '@mpp/core/reevaluation-clinical-safety'
import { z } from 'zod'

const uuid = z.string().uuid()
const zone = z
  .string()
  .min(1)
  .max(256)
  .refine(
    (value) =>
      value === value.trim() &&
      Array.from(value).every(
        (character) => character.charCodeAt(0) > 31 && character.charCodeAt(0) !== 127,
      ),
  )
export const clinicalGenerationAuthoritySchema = z.discriminatedUnion('kind', [
  z
    .object({
      kind: z.literal('signup_receipt'),
      generation: uuid,
      epoch: uuid,
      completed_at: instant,
      timezone_at_signup: zone,
    })
    .strict(),
  z
    .object({
      kind: z.literal('legacy_transition'),
      user_id: uuid,
      generation: uuid,
      epoch: uuid,
      admitted_at: instant,
      admitted_date: date,
      timezone_at_admission: zone,
      profile_completed_marker: instant.nullable(),
    })
    .strict(),
])

// Remain a shaped ZodObject for the strict FULL/first-phase extensions. The
// source is required and consumed; binding checks run at each actual reader.
export const clinicalGenerationAnchorSchema = z.object({
  signup_generation: uuid,
  signup_epoch: uuid,
  authority: clinicalGenerationAuthoritySchema,
})
const expectedSchema = z
  .object({ userId: uuid, profileCompletedAt: instant.nullable(), observedAt: instant })
  .strict()
function invalid(): never {
  throw new Error('Invalid clinical generation authority')
}
const same = (a: string, b: string) => a.toLowerCase() === b.toLowerCase()

export function readClinicalGenerationAuthority(raw: unknown, expected: unknown) {
  try {
    const anchor = clinicalGenerationAnchorSchema.parse(raw)
    const capture = expectedSchema.parse(expected)
    const source = anchor.authority
    if (
      !same(source.generation, anchor.signup_generation) ||
      !same(source.epoch, anchor.signup_epoch)
    )
      return invalid()
    if (source.kind === 'signup_receipt') {
      if (
        capture.profileCompletedAt === null ||
        source.completed_at !== capture.profileCompletedAt ||
        source.completed_at > capture.observedAt
      )
        return invalid()
    } else if (
      !same(source.user_id, capture.userId) ||
      source.profile_completed_marker !== capture.profileCompletedAt ||
      source.admitted_at > capture.observedAt ||
      (source.profile_completed_marker !== null &&
        source.profile_completed_marker > source.admitted_at)
    )
      return invalid()
    return Object.freeze(source)
  } catch {
    return invalid()
  }
}
