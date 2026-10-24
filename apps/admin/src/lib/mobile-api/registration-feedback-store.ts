import type { FlowStatusPhraseCursor } from '@mpp/agent/flow-curated-phrases'
import type {
  prepareRegistrationFeedback,
  RegistrationFeedback,
} from '@mpp/agent/registration-feedback'
import type { Json, ServiceClient } from '@mpp/db'
import { z } from 'zod'
import {
  createSupabaseFlowPhraseReplyStore,
  type FlowPhraseCursorSnapshot,
} from './flow-phrase-reply-store'

import {
  createSupabaseRegistrationFeedbackReceiptReader,
  parseRegistrationFeedback,
  type RegistrationFeedbackIdentity,
  type RegistrationFeedbackReceiptReader,
} from './registration-feedback-receipt'

export {
  parseRegistrationFeedback,
  type RegistrationFeedbackIdentity,
  type RegistrationFeedbackRead,
} from './registration-feedback-receipt'

function invalid(): never {
  throw new Error('Invalid registration feedback receipt')
}

export interface RegistrationFeedbackCommit extends RegistrationFeedbackIdentity {
  expectedProposal: Json
  expectedCursorRevision: string
  expectedCursor: FlowStatusPhraseCursor | null
  steps: ReturnType<typeof prepareRegistrationFeedback>['steps']
  feedback: RegistrationFeedback
}
export type RegistrationFeedbackCommitResult =
  | { action: 'committed' | 'replay'; feedback: RegistrationFeedback }
  | { action: 'cursor_conflict' | 'event_conflict' }
export interface RegistrationFeedbackStore extends RegistrationFeedbackReceiptReader {
  loadCursor(userId: string): Promise<FlowPhraseCursorSnapshot>
  commit(input: RegistrationFeedbackCommit): Promise<RegistrationFeedbackCommitResult>
}

/** Trusted-backend only. Construction never reads or advances the shared cursor. */
export function createSupabaseRegistrationFeedbackStore(
  supabase: ServiceClient,
): RegistrationFeedbackStore {
  const phrases = createSupabaseFlowPhraseReplyStore(supabase)
  const receipts = createSupabaseRegistrationFeedbackReceiptReader(supabase)
  return {
    loadCursor: phrases.loadCursor,
    readReceipt: receipts.readReceipt,
    async commit(input) {
      const feedback = parseRegistrationFeedback(input.feedback, input)
      const revision = z
        .string()
        .regex(/^(0|[1-9][0-9]*)$/u)
        .refine((value) => value.length <= 19 && BigInt(value) <= 9223372036854775807n)
        .parse(input.expectedCursorRevision)
      const copyCursor = (cursor: FlowStatusPhraseCursor) => ({
        ...cursor,
        usedTextKeys: [...cursor.usedTextKeys],
      })
      // The DTO was validated above; this conversion gives the RPC its Json type
      // without losing NaN, undefined or extra private fields during validation.
      const publicJson: Json = JSON.parse(JSON.stringify(feedback))
      const { data, error } = await supabase.rpc('commit_mobile_registration_feedback', {
        p_user_id: input.userId,
        p_registration_id: input.registrationId,
        p_expected_proposal: input.expectedProposal,
        p_expected_revision: revision,
        p_expected_cursor: input.expectedCursor === null ? null : copyCursor(input.expectedCursor),
        p_steps: input.steps.map((step) => ({
          receipt: { ...step.receipt, selection: { ...step.receipt.selection } },
          nextCursor: copyCursor(step.nextCursor),
        })),
        p_feedback: publicJson,
      })
      if (error) throw new Error('Unable to commit registration feedback receipt')
      const result = z
        .discriminatedUnion('action', [
          z.object({ action: z.literal('committed'), feedback: z.unknown() }).strict(),
          z.object({ action: z.literal('replay'), feedback: z.unknown() }).strict(),
          z.object({ action: z.literal('cursor_conflict') }).strict(),
          z.object({ action: z.literal('event_conflict') }).strict(),
        ])
        .parse(data)
      if (result.action !== 'committed' && result.action !== 'replay') return result
      const saved = parseRegistrationFeedback(result.feedback, input)
      if (result.action === 'committed' && JSON.stringify(saved) !== JSON.stringify(feedback))
        invalid()
      return { action: result.action, feedback: saved }
    },
  }
}
