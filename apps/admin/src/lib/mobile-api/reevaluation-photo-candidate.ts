import { createHash } from 'node:crypto'
import {
  estimateSignupBodyFat,
  type SignupBodyFatEstimate,
} from '@mpp/agent/signup-body-fat-estimate'
import { z } from 'zod'
import { MobileApiError } from './http'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'

const poses = ['front', 'side', 'back'] as const
type Pose = (typeof poses)[number]
const pose = z.enum(poses)
const revision = z
  .string()
  .regex(/^[1-9][0-9]{0,18}$/)
  .refine((value) => value.length < 19 || value <= '9223372036854775807')
const hash = z.string().regex(/^[0-9a-f]{64}$/)
const documentKey = z.string().regex(/^[a-z][a-z0-9_]{0,99}$/)
const documentVersion = z.string().regex(/^[A-Za-z0-9._-]{1,64}$/)
const locale = z.enum(['pt-BR', 'en-US'])
const timestamp = z.string().refine((value) => {
  if (
    !/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z$/.test(value) ||
    value.startsWith('0000-')
  )
    return false
  const milliseconds = `${value.slice(0, 23)}Z`
  const date = new Date(milliseconds)
  return Number.isFinite(date.getTime()) && date.toISOString() === milliseconds
})
const consentIdentity = z
  .object({
    documentId: uuid,
    documentKey: z.literal('body_photo_reevaluation_consent'),
    version: documentVersion,
    locale,
    bodyHash: hash,
  })
  .strict()
const contextSchema = z
  .object({
    userId: uuid,
    signupGeneration: uuid,
    cycleId: uuid,
    cycleRevision: revision,
    currentConsent: consentIdentity.nullable(),
  })
  .strict()
const consent = z
  .object({
    acceptance_id: uuid,
    document_id: uuid,
    document_key: documentKey,
    version: documentVersion,
    locale,
    body_hash: hash,
    accepted_at: timestamp,
  })
  .strict()
const photo = z
  .object({
    asset_id: uuid,
    user_id: uuid,
    signup_generation: uuid,
    cycle_id: uuid,
    consent_acceptance_id: uuid,
    origin: z.literal('reevaluation_cycle_v1'),
    status: z.enum(['pending_upload', 'uploaded', 'processing', 'processed', 'failed', 'deleted']),
    created_at: timestamp,
    uploaded_at: timestamp.nullable(),
    processed_at: timestamp.nullable(),
    // The provider legitimately has notes/usage fields. Project only these
    // three fields; never expose or fingerprint its free text or private URLs.
    analysis: z
      .object({
        type: z.literal('body'),
        view: z.enum(['front', 'side', 'back', 'unknown']),
        bf_percent_estimate: z.number().finite().nullable(),
      })
      .strip()
      .nullable(),
  })
  .strict()
const snapshotSchema = z
  .object({
    version: z.literal(1),
    user_id: uuid,
    signup_generation: uuid,
    cycle_id: uuid,
    cycle_revision: revision,
    opened_at: timestamp,
    observed_at: timestamp,
    consent: consent.nullable(),
    photos: z.array(z.object({ pose, photo: photo.nullable() }).strict()).length(3),
  })
  .strict()

export type ReevaluationPhotoContext = z.infer<typeof contextSchema>
type UnavailableReason =
  | 'stale_cycle'
  | 'consent_required'
  | 'photos_incomplete'
  | 'photo_unreadable'
  | 'pose_mismatch'
  | 'reading_out_of_range'
export type ReevaluationPhotoCandidateResult =
  | { status: 'unavailable'; reason: UnavailableReason }
  | {
      status: 'ready'
      source_ids: Record<Pose, string>
      estimate: SignupBodyFatEstimate
      /** Photo evidence only, NOT a clinical review/confirmation fingerprint. */
      photo_fingerprint: string
    }

function invalid(): never {
  throw new MobileApiError(
    500,
    'mobile_reevaluation_photo_invalid_snapshot',
    'Unable to read reassessment photos',
  )
}
function parse<T>(schema: z.ZodType<T>, input: unknown): T {
  try {
    const result = schema.safeParse(input)
    if (result.success) return result.data
  } catch {
    // Never place validation details, provider fields or identifiers in errors.
  }
  return invalid()
}
function sameId(left: string, right: string): boolean {
  return left.toLowerCase() === right.toLowerCase()
}
function unavailable(reason: UnavailableReason): ReevaluationPhotoCandidateResult {
  return { status: 'unavailable', reason }
}

/** Pure server-only projection. SQL must establish the asset/cycle/consent
 * authority first and revalidate it again in the future atomic conclusion.
 * This function is not wired into routes, upload issuance or profile writers.
 */
export function resolveReevaluationPhotoCandidate(
  expected: ReevaluationPhotoContext,
  snapshot: unknown,
): ReevaluationPhotoCandidateResult {
  const context = parse(contextSchema, expected)
  const state = parse(snapshotSchema, snapshot)
  if (
    state.opened_at > state.observed_at ||
    new Set(state.photos.map((slot) => slot.pose)).size !== 3
  )
    invalid()
  const present = state.photos.flatMap((slot) => (slot.photo ? [slot.photo] : []))
  if (new Set(present.map((row) => row.asset_id.toLowerCase())).size !== present.length) invalid()
  if (
    !sameId(state.user_id, context.userId) ||
    !sameId(state.signup_generation, context.signupGeneration) ||
    !sameId(state.cycle_id, context.cycleId) ||
    state.cycle_revision !== context.cycleRevision
  )
    return unavailable('stale_cycle')

  for (const row of present) {
    if (
      !sameId(row.user_id, context.userId) ||
      !sameId(row.signup_generation, context.signupGeneration) ||
      !sameId(row.cycle_id, context.cycleId) ||
      row.created_at < state.opened_at ||
      row.created_at > state.observed_at ||
      (row.uploaded_at !== null &&
        (row.uploaded_at < row.created_at || row.uploaded_at > state.observed_at)) ||
      (row.processed_at !== null &&
        (row.uploaded_at === null ||
          row.processed_at < row.uploaded_at ||
          row.processed_at > state.observed_at)) ||
      (row.status === 'processed' && (row.uploaded_at === null || row.processed_at === null))
    )
      invalid()
  }
  const accepted = state.consent
  if (
    accepted &&
    (accepted.accepted_at < state.opened_at || accepted.accepted_at > state.observed_at)
  )
    invalid()
  const current = context.currentConsent
  if (
    !current ||
    !accepted ||
    !sameId(accepted.document_id, current.documentId) ||
    accepted.document_key !== current.documentKey ||
    accepted.version !== current.version ||
    accepted.locale !== current.locale ||
    accepted.body_hash !== current.bodyHash
  )
    return unavailable('consent_required')
  if (
    present.some(
      (row) =>
        row.created_at < accepted.accepted_at ||
        !sameId(row.consent_acceptance_id, accepted.acceptance_id),
    )
  )
    invalid()

  const readings: Array<{ pose: Pose; bodyFatPercent: number }> = []
  const evidence: Array<{
    pose: Pose
    asset_id: string
    created_at: string
    uploaded_at: string
    processed_at: string
    reading: number
  }> = []
  const sourceIds: Record<Pose, string> = { front: '', side: '', back: '' }
  for (const requested of poses) {
    const selected = state.photos.find((slot) => slot.pose === requested)?.photo
    if (!selected || selected.status === 'deleted') return unavailable('photos_incomplete')
    if (selected.status === 'failed') return unavailable('photo_unreadable')
    if (selected.status !== 'processed') return unavailable('photos_incomplete')
    const analysis = selected.analysis
    if (!analysis || analysis.bf_percent_estimate === null) return unavailable('photo_unreadable')
    if (analysis.view !== requested) return unavailable('pose_mismatch')
    // Chronology validation above already requires both values for processed.
    if (selected.uploaded_at === null || selected.processed_at === null) invalid()
    sourceIds[requested] = selected.asset_id.toLowerCase()
    readings.push({ pose: requested, bodyFatPercent: analysis.bf_percent_estimate })
    evidence.push({
      pose: requested,
      asset_id: sourceIds[requested],
      created_at: selected.created_at,
      uploaded_at: selected.uploaded_at,
      processed_at: selected.processed_at,
      reading: analysis.bf_percent_estimate,
    })
  }
  const estimate = estimateSignupBodyFat(readings)
  if (!estimate) invalid()
  if (!estimate.by_sex.masculino.usable || !estimate.by_sex.feminino.usable)
    return unavailable('reading_out_of_range')
  const fingerprint = createHash('sha256')
    .update(
      JSON.stringify({
        version: 1,
        user_id: context.userId.toLowerCase(),
        signup_generation: context.signupGeneration.toLowerCase(),
        cycle_id: context.cycleId.toLowerCase(),
        cycle_revision: context.cycleRevision,
        opened_at: state.opened_at,
        consent: {
          acceptance_id: accepted.acceptance_id.toLowerCase(),
          document_id: current.documentId.toLowerCase(),
          document_key: current.documentKey,
          version: current.version,
          locale: current.locale,
          body_hash: current.bodyHash,
          accepted_at: accepted.accepted_at,
        },
        sources: evidence,
      }),
    )
    .digest('hex')
  return { status: 'ready', source_ids: sourceIds, estimate, photo_fingerprint: fingerprint }
}
