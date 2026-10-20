import {
  type ResolveStrengthWeekTargetInput,
  resolveStrengthWeekTarget,
} from '@mpp/core/strength-training-week'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { MobileApiError } from './http'

export type StrengthWeekUUID = string
export type StrengthWeekLocalMonday = string
/** DB formats UTC with exactly 6 fractional digits; never convert to Date. */
export type StrengthWeekTimestamp = string
/** Positive decimal PostgreSQL bigint string; never convert to Number. */
export type StrengthWeekSourceOrder = string
export type StrengthWeekStoredDays = 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7
export type StrengthWeekAcceptedPlanDays = 1 | 2 | 3 | 4 | 5 | 6 | 7
export type StrengthWeekSourceKind = 'accepted_plan' | 'informed_frequency'

export interface StrengthWeekScopeReceipt {
  readonly user_id: StrengthWeekUUID
  readonly generation: StrengthWeekUUID
  readonly predecessor_generation: StrengthWeekUUID | null
  readonly opened_at: StrengthWeekTimestamp
  readonly closed_at: StrengthWeekTimestamp | null
}

export interface StrengthWeekReceiptBase {
  readonly source_version_id: StrengthWeekUUID
  readonly user_id: StrengthWeekUUID
  readonly generation: StrengthWeekUUID
  readonly source_order: StrengthWeekSourceOrder
  readonly observed_at: StrengthWeekTimestamp
  readonly observed_timezone: string
  readonly effective_week_start: StrengthWeekLocalMonday
}

export type StrengthWeekSourceReceipt =
  | (StrengthWeekReceiptBase & {
      readonly source_kind: 'accepted_plan'
      readonly fact: 'value'
      readonly planned_days: StrengthWeekAcceptedPlanDays
      readonly source_entity_id: StrengthWeekUUID
      readonly source_valid_until: StrengthWeekTimestamp | null
    })
  | (StrengthWeekReceiptBase & {
      readonly source_kind: 'informed_frequency'
      readonly fact: 'value'
      readonly planned_days: StrengthWeekStoredDays
      readonly source_entity_id: null
      readonly source_valid_until: null
    })
  | (StrengthWeekReceiptBase & {
      readonly source_kind: StrengthWeekSourceKind
      readonly fact: 'absent'
      readonly planned_days: null
      readonly source_entity_id: null
      readonly source_valid_until: null
    })

export type StrengthWeekSourceFact<Kind extends StrengthWeekSourceKind> =
  | { readonly coverage: 'unknown' }
  | {
      readonly coverage: 'covered'
      readonly receipt: StrengthWeekSourceReceipt & { readonly source_kind: Kind }
    }

export type StrengthWeekProofEntry =
  | { readonly coverage: 'unknown' }
  | {
      readonly coverage: 'covered'
      readonly source_version_id: StrengthWeekUUID
      readonly source_order: StrengthWeekSourceOrder
    }

export interface StrengthWeekSourceProof {
  readonly plan: StrengthWeekProofEntry
  readonly frequency: StrengthWeekProofEntry
}

export type StrengthWeekProposal =
  | {
      readonly source: 'accepted_plan'
      readonly planned_days: StrengthWeekAcceptedPlanDays
      readonly source_key: StrengthWeekUUID
    }
  | {
      readonly source: 'informed_frequency'
      readonly planned_days: StrengthWeekStoredDays
      readonly source_key: StrengthWeekUUID
    }
  | {
      readonly source: 'absent'
      readonly planned_days: null
      readonly source_key: null
    }

export type StrengthWeekTarget = StrengthWeekProposal & {
  readonly target_id: StrengthWeekUUID
  readonly user_id: StrengthWeekUUID
  readonly generation: StrengthWeekUUID
  readonly week_start: StrengthWeekLocalMonday
  readonly timezone_at_freeze: string
  readonly frozen_at: StrengthWeekTimestamp
  readonly source_proof: StrengthWeekSourceProof
}

export interface StrengthWeekContextBase {
  readonly user_id: StrengthWeekUUID
  readonly generation: StrengthWeekUUID
  readonly timezone: string
  readonly week_start: StrengthWeekLocalMonday
  readonly observed_at: StrengthWeekTimestamp
}

export type StrengthWeekContext =
  | (StrengthWeekContextBase & {
      readonly kind: 'existing_target'
      readonly target: StrengthWeekTarget
    })
  | (StrengthWeekContextBase & {
      readonly kind: 'source_facts'
      /** Official civil Monday as UTC with six fractional digits, supplied by SQL. */
      readonly week_start_at: StrengthWeekTimestamp
      readonly plan: StrengthWeekSourceFact<'accepted_plan'>
      readonly frequency: StrengthWeekSourceFact<'informed_frequency'>
      readonly source_proof: StrengthWeekSourceProof
    })

export type StrengthWeekUnavailableReason =
  | 'missing_scope'
  | 'history_incomplete'
  | 'calendar_unsupported'

export type StrengthWeekConflictReason =
  | 'generation_changed'
  | 'timezone_changed'
  | 'week_changed'
  | 'source_proof_changed'
  | 'proposal_mismatch'

export type StrengthWeekReadResult =
  | { readonly status: 'disabled' }
  | { readonly status: 'unavailable'; readonly reason: StrengthWeekUnavailableReason }
  | { readonly status: 'ready'; readonly context: StrengthWeekContext }

export type StrengthWeekFreezeResult =
  | { readonly status: 'disabled' }
  | { readonly status: 'unavailable'; readonly reason: StrengthWeekUnavailableReason }
  | { readonly status: 'conflict'; readonly reason: StrengthWeekConflictReason }
  | { readonly status: 'frozen'; readonly target: StrengthWeekTarget }
  | { readonly status: 'reused'; readonly target: StrengthWeekTarget }

/** Disabled exists only in the local repository, never in SQL RPC output. */
export type StrengthWeekReadRpcResult = Exclude<
  StrengthWeekReadResult,
  { readonly status: 'disabled' }
>
export type StrengthWeekFreezeRpcResult = Exclude<
  StrengthWeekFreezeResult,
  { readonly status: 'disabled' }
>

export interface StrengthWeekFreezeInput {
  readonly userId: StrengthWeekUUID
  readonly expectedGeneration: StrengthWeekUUID
  readonly expectedTimezone: string
  readonly expectedWeekStart: StrengthWeekLocalMonday
  readonly sourceProof: StrengthWeekSourceProof
  readonly proposal: StrengthWeekProposal
}

export type StrengthWeekFreezePreparation =
  | Exclude<StrengthWeekReadResult, { readonly status: 'ready' }>
  | { readonly status: 'prepared'; readonly input: StrengthWeekFreezeInput }

export interface StrengthWeekRepositoryOptions {
  readonly enabled?: boolean
}

export interface StrengthWeekRepository {
  readContext(userId: StrengthWeekUUID): Promise<StrengthWeekReadResult>
  compareAndFreeze(input: StrengthWeekFreezeInput): Promise<StrengthWeekFreezeResult>
}

/** SQL wire parameters only; there is no public clock override. */
export interface StrengthWeekReadRpcParameters {
  readonly p_user_id: StrengthWeekUUID
}

export interface StrengthWeekFreezeRpcParameters {
  readonly p_user_id: StrengthWeekUUID
  readonly p_expected_generation: StrengthWeekUUID
  readonly p_expected_timezone: string
  readonly p_expected_week_start: StrengthWeekLocalMonday
  readonly p_source_proof: StrengthWeekSourceProof
  readonly p_proposal: StrengthWeekProposal
}

export type StrengthWeekErrorCode =
  | 'strength_week_invalid_input'
  | 'strength_week_patient_not_found'
  | 'strength_week_access_denied'
  | 'strength_week_transaction_conflict'
  | 'strength_week_data_access_failed'
  | 'strength_week_invalid_response'

/** Narrow local RPC binding, not a generated Database modification. */
export interface StrengthWeekRpcResponse {
  readonly data: unknown
  readonly error: { readonly code?: string; readonly message: string } | null
}

export interface StrengthWeekRpc {
  (
    name: 'get_mobile_strength_week_context',
    parameters: StrengthWeekReadRpcParameters,
  ): PromiseLike<StrengthWeekRpcResponse>
  (
    name: 'freeze_mobile_strength_week_target',
    parameters: StrengthWeekFreezeRpcParameters,
  ): PromiseLike<StrengthWeekRpcResponse>
}

const uuidSchema = z
  .string()
  .regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
const timezoneSchema = z
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
const bigintMaximum = '9223372036854775807'
const sourceOrderSchema = z
  .string()
  .refine(
    (value) =>
      /^[1-9][0-9]*$/.test(value) &&
      (value.length < bigintMaximum.length ||
        (value.length === bigintMaximum.length && value <= bigintMaximum)),
  )

function leapYear(year: number): boolean {
  return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0)
}
function validCivilDate(value: string): boolean {
  if (!/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(value)) return false
  const year = Number(value.slice(0, 4))
  const month = Number(value.slice(5, 7))
  const day = Number(value.slice(8, 10))
  if (year < 1 || month < 1 || month > 12 || day < 1) return false
  const days = month === 2 ? (leapYear(year) ? 29 : 28) : [4, 6, 9, 11].includes(month) ? 30 : 31
  return day <= days
}
function validMonday(value: string): boolean {
  if (!validCivilDate(value)) return false
  const year = Number(value.slice(0, 4))
  const month = Number(value.slice(5, 7))
  const day = Number(value.slice(8, 10))
  const previousYear = year - 1
  let elapsed =
    365 * previousYear +
    Math.floor(previousYear / 4) -
    Math.floor(previousYear / 100) +
    Math.floor(previousYear / 400)
  for (let priorMonth = 1; priorMonth < month; priorMonth++) {
    elapsed +=
      priorMonth === 2 ? (leapYear(year) ? 29 : 28) : [4, 6, 9, 11].includes(priorMonth) ? 30 : 31
  }
  // Gregorian 0001-01-01 is Monday; this is civil arithmetic, never a UTC instant.
  return (elapsed + day - 1) % 7 === 0
}
const mondaySchema = z.string().refine(validMonday)
const timestampSchema = z.string().refine((value) => {
  if (!/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z$/.test(value))
    return false
  return (
    validCivilDate(value.slice(0, 10)) &&
    Number(value.slice(11, 13)) <= 23 &&
    Number(value.slice(14, 16)) <= 59 &&
    Number(value.slice(17, 19)) <= 59
  )
})
const planDaysSchema = z.union([
  z.literal(1),
  z.literal(2),
  z.literal(3),
  z.literal(4),
  z.literal(5),
  z.literal(6),
  z.literal(7),
])
const frequencyDaysSchema = z.union([
  z.literal(0),
  z.literal(1),
  z.literal(2),
  z.literal(3),
  z.literal(4),
  z.literal(5),
  z.literal(6),
  z.literal(7),
])
const unknownProofSchema = z.object({ coverage: z.literal('unknown') }).strict()
const coveredProofSchema = z
  .object({
    coverage: z.literal('covered'),
    source_version_id: uuidSchema,
    source_order: sourceOrderSchema,
  })
  .strict()
const proofEntrySchema = z.discriminatedUnion('coverage', [unknownProofSchema, coveredProofSchema])
const sourceProofSchema = z.object({ plan: proofEntrySchema, frequency: proofEntrySchema }).strict()
const planProposalShape = {
  source: z.literal('accepted_plan'),
  planned_days: planDaysSchema,
  source_key: uuidSchema,
}
const frequencyProposalShape = {
  source: z.literal('informed_frequency'),
  planned_days: frequencyDaysSchema,
  source_key: uuidSchema,
}
const absentProposalShape = {
  source: z.literal('absent'),
  planned_days: z.null(),
  source_key: z.null(),
}
const proposalSchema = z.discriminatedUnion('source', [
  z.object(planProposalShape).strict(),
  z.object(frequencyProposalShape).strict(),
  z.object(absentProposalShape).strict(),
])
const targetShape = {
  target_id: uuidSchema,
  user_id: uuidSchema,
  generation: uuidSchema,
  week_start: mondaySchema,
  timezone_at_freeze: timezoneSchema,
  frozen_at: timestampSchema,
  source_proof: sourceProofSchema,
}
const targetSchema = z.discriminatedUnion('source', [
  z.object({ ...targetShape, ...planProposalShape }).strict(),
  z.object({ ...targetShape, ...frequencyProposalShape }).strict(),
  z.object({ ...targetShape, ...absentProposalShape }).strict(),
])
const receiptShape = {
  source_version_id: uuidSchema,
  user_id: uuidSchema,
  generation: uuidSchema,
  source_order: sourceOrderSchema,
  observed_at: timestampSchema,
  observed_timezone: timezoneSchema,
  effective_week_start: mondaySchema,
}
const planReceiptSchema = z.discriminatedUnion('fact', [
  z
    .object({
      ...receiptShape,
      source_kind: z.literal('accepted_plan'),
      fact: z.literal('value'),
      planned_days: planDaysSchema,
      source_entity_id: uuidSchema,
      source_valid_until: timestampSchema.nullable(),
    })
    .strict(),
  z
    .object({
      ...receiptShape,
      source_kind: z.literal('accepted_plan'),
      fact: z.literal('absent'),
      planned_days: z.null(),
      source_entity_id: z.null(),
      source_valid_until: z.null(),
    })
    .strict(),
])
const frequencyReceiptSchema = z.discriminatedUnion('fact', [
  z
    .object({
      ...receiptShape,
      source_kind: z.literal('informed_frequency'),
      fact: z.literal('value'),
      planned_days: frequencyDaysSchema,
      source_entity_id: z.null(),
      source_valid_until: z.null(),
    })
    .strict(),
  z
    .object({
      ...receiptShape,
      source_kind: z.literal('informed_frequency'),
      fact: z.literal('absent'),
      planned_days: z.null(),
      source_entity_id: z.null(),
      source_valid_until: z.null(),
    })
    .strict(),
])
const planFactSchema = z.discriminatedUnion('coverage', [
  unknownProofSchema,
  z.object({ coverage: z.literal('covered'), receipt: planReceiptSchema }).strict(),
])
const frequencyFactSchema = z.discriminatedUnion('coverage', [
  unknownProofSchema,
  z.object({ coverage: z.literal('covered'), receipt: frequencyReceiptSchema }).strict(),
])
const contextShape = {
  user_id: uuidSchema,
  generation: uuidSchema,
  timezone: timezoneSchema,
  week_start: mondaySchema,
  observed_at: timestampSchema,
}
const contextSchema = z.discriminatedUnion('kind', [
  z.object({ ...contextShape, kind: z.literal('existing_target'), target: targetSchema }).strict(),
  z
    .object({
      ...contextShape,
      kind: z.literal('source_facts'),
      week_start_at: timestampSchema,
      plan: planFactSchema,
      frequency: frequencyFactSchema,
      source_proof: sourceProofSchema,
    })
    .strict(),
])
const unavailableSchema = z
  .object({
    status: z.literal('unavailable'),
    reason: z.enum(['missing_scope', 'history_incomplete', 'calendar_unsupported']),
  })
  .strict()
const readResultSchema = z.discriminatedUnion('status', [
  unavailableSchema,
  z.object({ status: z.literal('ready'), context: contextSchema }).strict(),
])
const freezeResultSchema = z.discriminatedUnion('status', [
  unavailableSchema,
  z
    .object({
      status: z.literal('conflict'),
      reason: z.enum([
        'generation_changed',
        'timezone_changed',
        'week_changed',
        'source_proof_changed',
        'proposal_mismatch',
      ]),
    })
    .strict(),
  z.object({ status: z.literal('frozen'), target: targetSchema }).strict(),
  z.object({ status: z.literal('reused'), target: targetSchema }).strict(),
])
const freezeInputSchema = z
  .object({
    userId: uuidSchema,
    expectedGeneration: uuidSchema,
    expectedTimezone: timezoneSchema,
    expectedWeekStart: mondaySchema,
    sourceProof: sourceProofSchema,
    proposal: proposalSchema,
  })
  .strict()

function invalidInput(): MobileApiError {
  return new MobileApiError(422, 'strength_week_invalid_input', 'Invalid strength week input')
}
function invalidResponse(): MobileApiError {
  return new MobileApiError(500, 'strength_week_invalid_response', 'Invalid strength week response')
}
function dataAccessFailed(): MobileApiError {
  return new MobileApiError(500, 'strength_week_data_access_failed', 'Strength week lookup failed')
}
function providerError(error: NonNullable<StrengthWeekRpcResponse['error']>): MobileApiError {
  if (error.code === '22023' && error.message === 'invalid_mobile_strength_week_input')
    return invalidInput()
  if (error.code === 'P0002' && error.message === 'mobile_strength_week_patient_not_found') {
    return new MobileApiError(404, 'strength_week_patient_not_found', 'Patient profile not found')
  }
  if (error.code === '42501') {
    return new MobileApiError(403, 'strength_week_access_denied', 'Strength week access denied')
  }
  if (error.code === '40001' || error.code === '40P01' || error.code === '55P03') {
    return new MobileApiError(
      409,
      'strength_week_transaction_conflict',
      'Strength week transaction changed; read again',
    )
  }
  return dataAccessFailed()
}
function parse<T>(schema: z.ZodType<T>, value: unknown, failure: () => MobileApiError): T {
  try {
    const result = schema.safeParse(value)
    if (result.success) return result.data
  } catch {
    // Treat non-JSON getters/proxies just like invalid shape, never leak their error.
  }
  throw failure()
}
async function callRpc(
  client: ServiceClient,
  invoke: (rpc: StrengthWeekRpc) => PromiseLike<StrengthWeekRpcResponse>,
): Promise<unknown> {
  let response: StrengthWeekRpcResponse
  try {
    // Local binding only; generated/global Database stays unchanged.
    const rpc = client.rpc.bind(client) as unknown as StrengthWeekRpc
    response = await invoke(rpc)
  } catch {
    throw dataAccessFailed()
  }
  if (response === null || typeof response !== 'object') throw invalidResponse()
  if (response.error !== null) {
    if (typeof response.error !== 'object' || response.error === undefined) throw dataAccessFailed()
    throw providerError(response.error)
  }
  return response.data
}
function proofEntryEqual(left: StrengthWeekProofEntry, right: StrengthWeekProofEntry): boolean {
  if (left.coverage !== right.coverage) return false
  return (
    left.coverage === 'unknown' ||
    (right.coverage === 'covered' &&
      left.source_version_id === right.source_version_id &&
      left.source_order === right.source_order)
  )
}
function proofEqual(left: StrengthWeekSourceProof, right: StrengthWeekSourceProof): boolean {
  return proofEntryEqual(left.plan, right.plan) && proofEntryEqual(left.frequency, right.frequency)
}
function proposalEqual(left: StrengthWeekProposal, right: StrengthWeekProposal): boolean {
  return (
    left.source === right.source &&
    left.planned_days === right.planned_days &&
    left.source_key === right.source_key
  )
}
function distinctProofSources(proof: StrengthWeekSourceProof): boolean {
  const { plan, frequency } = proof
  return (
    plan.coverage === 'unknown' ||
    frequency.coverage === 'unknown' ||
    (plan.source_version_id !== frequency.source_version_id &&
      plan.source_order !== frequency.source_order)
  )
}
function targetConsistent(target: StrengthWeekTarget): boolean {
  if (!distinctProofSources(target.source_proof)) return false
  const { plan, frequency } = target.source_proof
  if (target.source === 'accepted_plan') {
    return plan.coverage === 'covered' && target.source_key === plan.source_version_id
  }
  if (target.source === 'informed_frequency') {
    return (
      plan.coverage === 'covered' &&
      frequency.coverage === 'covered' &&
      target.source_key === frequency.source_version_id
    )
  }
  return plan.coverage === 'covered' && frequency.coverage === 'covered'
}
function targetOwned(
  target: StrengthWeekTarget,
  userId: string,
  generation: string,
  weekStart: string,
): boolean {
  return (
    target.user_id === userId &&
    target.generation === generation &&
    target.week_start === weekStart &&
    targetConsistent(target)
  )
}
function receiptMatches(
  fact: StrengthWeekSourceFact<StrengthWeekSourceKind>,
  proof: StrengthWeekProofEntry,
  context: StrengthWeekContextBase,
): boolean {
  if (fact.coverage === 'unknown') return proof.coverage === 'unknown'
  const receipt = fact.receipt
  return (
    receipt.user_id === context.user_id &&
    receipt.generation === context.generation &&
    receipt.effective_week_start <= context.week_start &&
    proof.coverage === 'covered' &&
    receipt.source_version_id === proof.source_version_id &&
    receipt.source_order === proof.source_order
  )
}
function contextConsistent(context: StrengthWeekContext, userId: string): boolean {
  if (context.user_id !== userId) return false
  if (context.kind === 'existing_target')
    return targetOwned(context.target, userId, context.generation, context.week_start)
  if (!distinctProofSources(context.source_proof)) return false
  if (
    !receiptMatches(context.plan, context.source_proof.plan, context) ||
    !receiptMatches(context.frequency, context.source_proof.frequency, context)
  )
    return false
  // SQL supplies the official calendar and source coverage. Validate the facts it
  // returned; do not infer missing history or inspect any live profile/plan here.
  if (context.week_start_at > context.observed_at) return false
  if (context.plan.coverage !== 'covered') return false
  const plan = context.plan.receipt
  if (plan.observed_timezone !== context.timezone) return false
  if (
    plan.fact === 'value' &&
    (plan.source_valid_until === null || plan.source_valid_until >= context.week_start_at)
  )
    return true
  // Preserve the selected expired plan and its proof. Frequency is required
  // when that plan does not apply at the official start of this exact week.
  return (
    context.frequency.coverage === 'covered' &&
    context.frequency.receipt.observed_timezone === context.timezone
  )
}

/**
 * Pure preparation only. Even an existing winner is revalidated by the future
 * caller through compareAndFreeze. Publish only its returned frozen/reused
 * target, never this proposal or the target observed by an earlier read.
 */
export function prepareStrengthWeekFreeze(
  read: StrengthWeekReadResult,
): StrengthWeekFreezePreparation {
  if (read.status === 'disabled') return { status: 'disabled' }
  const result = parse(readResultSchema, read, invalidResponse)
  if (result.status === 'unavailable') return result
  const context = result.context
  if (!contextConsistent(context, context.user_id)) throw invalidResponse()

  const scope = { ownerKey: context.user_id, weekStartDate: context.week_start }
  let input: ResolveStrengthWeekTargetInput
  let sourceProof: StrengthWeekSourceProof
  if (context.kind === 'existing_target') {
    const target = context.target
    input = {
      scope,
      existingRecord: {
        ...scope,
        source: target.source,
        plannedDays: target.planned_days,
        sourceKey: target.source_key,
      },
      effectiveSources: null,
    }
    sourceProof = target.source_proof
  } else {
    // Coverage and ownership were checked above. Keep the expired receipt in
    // the original proof while projecting no applicable plan into the core.
    const plan = context.plan.coverage === 'covered' ? context.plan.receipt : null
    const frequency = context.frequency.coverage === 'covered' ? context.frequency.receipt : null
    const applicablePlan =
      plan?.fact === 'value' &&
      (plan.source_valid_until === null || plan.source_valid_until >= context.week_start_at)
    input = {
      scope,
      existingRecord: null,
      effectiveSources: {
        ...scope,
        plan: applicablePlan
          ? {
              ownerKey: plan.user_id,
              sourceKey: plan.source_version_id,
              state: 'accepted',
              daysPerWeek: plan.planned_days,
            }
          : null,
        informedFrequency:
          frequency?.fact === 'value'
            ? {
                ownerKey: frequency.user_id,
                sourceKey: frequency.source_version_id,
                daysPerWeek: frequency.planned_days,
              }
            : null,
      },
    }
    sourceProof = context.source_proof
  }
  const resolved = resolveStrengthWeekTarget(input)
  if (resolved.status !== 'propose_new' && resolved.status !== 'reuse_existing')
    throw invalidResponse()
  const proposal = parse(
    proposalSchema,
    {
      source: resolved.record.source,
      planned_days: resolved.record.plannedDays,
      source_key: resolved.record.sourceKey,
    },
    invalidResponse,
  )
  return {
    status: 'prepared',
    input: {
      userId: context.user_id,
      expectedGeneration: context.generation,
      expectedTimezone: context.timezone,
      expectedWeekStart: context.week_start,
      sourceProof,
      proposal,
    },
  }
}

export function createStrengthWeekRepository(
  client: ServiceClient,
  options?: StrengthWeekRepositoryOptions,
): StrengthWeekRepository {
  const enabled = options?.enabled === true
  return {
    async readContext(userId) {
      if (!enabled) return { status: 'disabled' }
      const owner = parse(uuidSchema, userId, invalidInput)
      const raw = await callRpc(client, (rpc) =>
        rpc('get_mobile_strength_week_context', { p_user_id: owner }),
      )
      const result = parse(readResultSchema, raw, invalidResponse)
      if (result.status === 'ready' && !contextConsistent(result.context, owner))
        throw invalidResponse()
      return result
    },
    async compareAndFreeze(input) {
      if (!enabled) return { status: 'disabled' }
      const expected = parse(freezeInputSchema, input, invalidInput)
      const raw = await callRpc(client, (rpc) =>
        rpc('freeze_mobile_strength_week_target', {
          p_user_id: expected.userId,
          p_expected_generation: expected.expectedGeneration,
          p_expected_timezone: expected.expectedTimezone,
          p_expected_week_start: expected.expectedWeekStart,
          p_source_proof: expected.sourceProof,
          p_proposal: expected.proposal,
        }),
      )
      const result = parse(freezeResultSchema, raw, invalidResponse)
      if (result.status === 'frozen' || result.status === 'reused') {
        if (
          !targetOwned(
            result.target,
            expected.userId,
            expected.expectedGeneration,
            expected.expectedWeekStart,
          )
        )
          throw invalidResponse()
        if (
          result.status === 'frozen' &&
          (result.target.timezone_at_freeze !== expected.expectedTimezone ||
            !proposalEqual(result.target, expected.proposal) ||
            !proofEqual(result.target.source_proof, expected.sourceProof))
        )
          throw invalidResponse()
      }
      return result
    },
  }
}
