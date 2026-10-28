/** Explicit signup admission. Public transport exists; runtime remains dormant. */
import { healthRiskSetSchema } from '@mpp/core/health-check'
import { clinicalTimestampSchema } from '@mpp/core/reevaluation-clinical-safety'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import { onboardingDocumentActionInputSchema } from './contracts'
import { parseHealthRiskDeclaration } from './health-hold-contracts'
import { MobileApiError } from './http'
import { reevaluationCycleUuidSchema } from './reevaluation-cycle-contracts'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'

const uuid = reevaluationCycleUuidSchema.transform((value) => value.toLowerCase())
const locale = z.enum(['pt-BR', 'en-US'])
const requestKey = z
  .string()
  .regex(/^osc1:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
const actions = z
  .array(onboardingDocumentActionInputSchema)
  .min(1)
  .max(16)
  .refine((values) => new Set(values.map((value) => value.document_key)).size === values.length)
  .transform((values) =>
    values.sort((a, b) =>
      a.document_key < b.document_key ? -1 : a.document_key > b.document_key ? 1 : 0,
    ),
  )
const commandBase = z
  .object({
    version: z.literal(1),
    operation_key: uuid,
    intent_id: uuid,
    request_key: requestKey,
    locale,
    document_actions: actions,
    risks: healthRiskSetSchema,
  })
  .strict()
const commandSchema = commandBase.refine((value) =>
  value.document_actions.every((action) => action.locale === value.locale),
)
/** Header owns the operation key; no client owner/epoch/clock/ordinary answers. */
export const signupHealthAdmissionInputSchema = commandBase
  .omit({ operation_key: true })
  .refine((value) => value.document_actions.every((action) => action.locale === value.locale))
export type SignupHealthCommand = z.infer<typeof commandSchema>
const ownedErrors = new WeakSet<MobileApiError>()
export function signupHealthError(
  kind: 'input' | 'changed' | 'documents_changed' | 'busy' | 'unavailable' = 'unavailable',
) {
  const error = new MobileApiError(
    kind === 'input' ? 422 : kind === 'unavailable' ? 503 : 409,
    `mobile_signup_health_${kind}`,
    'Health declaration unavailable',
  )
  ownedErrors.add(error)
  return error
}
export function parseSignupHealthCommand(input: unknown): SignupHealthCommand {
  const parsed = commandSchema.safeParse(input)
  if (!parsed.success) throw signupHealthError('input')
  return parsed.data
}
export interface SignupHealthRepository {
  /** One atomic attempt, including original-receipt resolution before epoch/policy checks. */
  admit(userId: string, command: Readonly<SignupHealthCommand>): Promise<unknown>
}
interface Dependencies {
  readonly enabled: boolean
  readonly repository: SignupHealthRepository
}
const receiptSchema = z
  .object({
    id: uuid,
    intent_id: uuid,
    request_key: requestKey,
    epoch: uuid,
    locale,
    requirement_set_id: uuid,
    document_actions: actions,
    risks: healthRiskSetSchema,
    health_operation_key: uuid,
    admitted_at: clinicalTimestampSchema,
  })
  .strict()
const envelope = z
  .object({
    version: z.literal(1),
    user_id: uuid,
    operation_key: uuid,
    receipt: receiptSchema,
    declaration: z.unknown(),
  })
  .strict()
function unavailable(): never {
  throw signupHealthError()
}
function readResult(raw: unknown, owner: string, command: SignupHealthCommand) {
  const result = envelope.parse(raw)
  const receipt = result.receipt
  if (
    result.user_id !== owner ||
    result.operation_key !== command.operation_key ||
    receipt.intent_id !== command.intent_id ||
    receipt.request_key !== command.request_key ||
    receipt.locale !== command.locale ||
    JSON.stringify(receipt.document_actions) !== JSON.stringify(command.document_actions) ||
    JSON.stringify(receipt.risks) !== JSON.stringify(command.risks)
  )
    unavailable()
  const declaration = parseHealthRiskDeclaration(
    result.declaration,
    owner,
    receipt.health_operation_key,
    command.risks,
  )
  if (declaration.receipt.declared_at !== receipt.admitted_at) unavailable()
  // The epoch and the independent risk-operation namespace are private authority.
  const { epoch: _epoch, health_operation_key: _healthKey, ...acknowledgement } = receipt
  return {
    availability: 'available' as const,
    version: 1 as const,
    operation_key: result.operation_key,
    receipt: acknowledgement,
    state: declaration.state,
  }
}
export function createSignupHealthAdmissionService(dependencies: Dependencies) {
  return {
    async admit(auth: MobileAuthContext, input: unknown) {
      const owner = authenticatedReevaluationOwner(auth).toLowerCase()
      const parsed = commandSchema.safeParse(input)
      if (!parsed.success)
        throw new MobileApiError(
          422,
          'mobile_signup_health_invalid_request',
          'Explicit documents and marked risks required',
        )
      if (dependencies.enabled !== true)
        return { availability: 'unavailable' as const, reason: 'disabled' as const }
      const command = parsed.data
      for (const action of command.document_actions) Object.freeze(action)
      Object.freeze(command.document_actions)
      Object.freeze(command.risks)
      Object.freeze(command)
      try {
        const repository = dependencies.repository
        const admit = repository.admit.bind(repository)
        // Do not call the existing intent.verify before this: old-epoch replay
        // must acknowledge the original without recording a new declaration.
        return readResult(await admit(owner, command), owner, command)
      } catch (error) {
        if (error instanceof MobileApiError && ownedErrors.has(error)) throw error
        return unavailable()
      }
    },
  }
}
