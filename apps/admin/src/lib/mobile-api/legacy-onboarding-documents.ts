/** Legal actions only. A historical signup marker is never part of this command. */
import { clinicalTimestampSchema as instant } from '@mpp/core/reevaluation-clinical-safety'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import { onboardingDocumentActionInputSchema } from './contracts'
import { MobileApiError } from './http'
import { reevaluationCycleUuidSchema } from './reevaluation-cycle-contracts'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'

const uuid = reevaluationCycleUuidSchema.transform((s) => s.toLowerCase())
const actions = z
  .array(onboardingDocumentActionInputSchema)
  .min(1)
  .max(16)
  .refine((rows) => new Set(rows.map((a) => a.document_key)).size === rows.length)
  .transform((rows) =>
    rows.sort((a, b) =>
      a.document_key < b.document_key ? -1 : a.document_key > b.document_key ? 1 : 0,
    ),
  )
const base = z
  .object({
    version: z.literal(1),
    operation_key: uuid,
    locale: z.enum(['pt-BR', 'en-US']),
    document_actions: actions,
  })
  .strict()
const commandSchema = base.refine((c) => c.document_actions.every((a) => a.locale === c.locale))
export const legacyDocumentInputSchema = base
  .omit({ operation_key: true })
  .refine((c) => c.document_actions.every((a) => a.locale === c.locale))
export type LegacyDocumentCommand = z.infer<typeof commandSchema>
const ownedErrors = new WeakSet<MobileApiError>()
export function legacyDocumentError(
  kind: 'input' | 'changed' | 'busy' | 'documents_changed' | 'unavailable' = 'unavailable',
) {
  const error = new MobileApiError(
    kind === 'input' ? 422 : kind === 'unavailable' ? 503 : 409,
    `mobile_legacy_documents_${kind}`,
    'Required notices could not be accepted',
  )
  ownedErrors.add(error)
  return error
}
export function parseLegacyDocumentCommand(raw: unknown): LegacyDocumentCommand {
  const result = commandSchema.safeParse(raw)
  if (!result.success) throw legacyDocumentError('input')
  for (const a of result.data.document_actions) Object.freeze(a)
  Object.freeze(result.data.document_actions)
  return Object.freeze(result.data)
}
export interface LegacyDocumentRepository {
  /** Atomic SQL resolves its durable original receipt before current source/publication. */
  accept(owner: string, command: Readonly<LegacyDocumentCommand>): Promise<unknown>
}
const receiptAction = onboardingDocumentActionInputSchema
  .extend({
    purpose: z.string().regex(/^[a-z][a-z0-9_]{0,159}$/),
    acted_at: instant,
  })
  .strict()
const envelope = z
  .object({
    version: z.literal(1),
    user_id: uuid,
    operation_key: uuid,
    receipt: z
      .object({
        id: uuid,
        locale: z.enum(['pt-BR', 'en-US']),
        accepted_at: instant,
        document_actions: z.array(receiptAction).min(1).max(16),
      })
      .strict(),
  })
  .strict()
export function createLegacyDocumentService(repository: LegacyDocumentRepository) {
  const accept = repository.accept.bind(repository)
  return Object.freeze({
    async accept(auth: MobileAuthContext, raw: unknown) {
      const owner = authenticatedReevaluationOwner(structuredClone(auth)).toLowerCase()
      const command = parseLegacyDocumentCommand(raw)
      try {
        const response = await accept(owner, command)
        const text = JSON.stringify(response)
        if (!text || text.length > 32768) throw legacyDocumentError()
        const result = envelope.parse(JSON.parse(text))
        const actualActions = actions.parse(
          result.receipt.document_actions.map(({ purpose: _p, acted_at: _a, ...a }) => a),
        )
        if (
          result.user_id !== owner ||
          result.operation_key !== command.operation_key ||
          result.receipt.locale !== command.locale ||
          JSON.stringify(actualActions) !== JSON.stringify(command.document_actions) ||
          result.receipt.document_actions.some((a) => a.acted_at > result.receipt.accepted_at)
        )
          throw legacyDocumentError()
        return {
          version: result.version,
          operation_key: result.operation_key,
          receipt: result.receipt,
        }
      } catch (error) {
        if (error instanceof MobileApiError && ownedErrors.has(error)) throw error
        throw legacyDocumentError()
      }
    },
  })
}
