/** Observe a genuine typed meal parent without admitting a linked answer.
 * The current question is a precondition, never permission to change facts. */
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import {
  type ConversationCurrentScopeDependencies,
  createConversationCurrentScope,
} from './conversation-current-scope'
import type { ConversationMealQuestion } from './conversation-meal-continuation-input'
import {
  type ConversationMealContinuationReadOutcome,
  conversationContinuationReadUnavailable,
  detachConversationContinuationReadJson,
  parseConversationMealContinuationRead,
  parseConversationMealContinuationReadIdentity,
} from './conversation-meal-continuation-read-contracts'
import {
  type ConversationMealContinuationReadStore,
  createSupabaseConversationMealContinuationReadStore,
} from './conversation-meal-continuation-read-store'
import { freezeInterpretation } from './conversation-meal-interpretation-contracts'
import { conversationJournalInstant } from './conversation-meal-journal-store'
import { MobileApiError } from './http'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'

type Available = Extract<ConversationMealContinuationReadOutcome, { action: 'available' }>
interface QuestionReadIdentity {
  readonly schema: 'conversation.meal-question-read.v1'
  readonly auth_user_id: string
  readonly owner_id: string
  readonly epoch: string
  readonly parent_command_id: string
  readonly parent_input_hash: string
  readonly parent_decision_hash: string
  readonly parent_binding: Available['parent']['binding']
  readonly head_revision: number
  readonly observed_at: string
}
export type ConversationMealQuestionRead = QuestionReadIdentity &
  (
    | {
        readonly status: 'needs_reply'
        readonly question: ConversationMealQuestion
        readonly reason: null
      }
    | {
        readonly status: 'closed'
        readonly question: null
        readonly reason: 'parent_fulfilled' | 'no_current_question'
      }
  )
export interface ConversationMealQuestionReadPorts extends ConversationCurrentScopeDependencies {
  readonly reader?: ConversationMealContinuationReadStore
}
const query = z.object({ parent_input_hash: z.string().regex(/^[a-f0-9]{64}$/u) }).strict()

function project(authUserId: string, state: Available): ConversationMealQuestionRead {
  const parent = state.parent.binding,
    common: QuestionReadIdentity = {
      schema: 'conversation.meal-question-read.v1',
      auth_user_id: authUserId,
      owner_id: parent.owner_id,
      epoch: parent.epoch,
      parent_command_id: parent.command_id,
      parent_input_hash: parent.input_hash,
      parent_decision_hash: state.parent.decision.decision_hash,
      parent_binding: parent,
      head_revision: state.head.revision,
      observed_at: state.observed_at,
    }
  if (state.head.fulfilled_by !== null)
    return freezeInterpretation({
      ...common,
      status: 'closed',
      question: null,
      reason: 'parent_fulfilled',
    })
  // The complete private parser currently requires a real question on every
  // unfulfilled eligible head. Absence is not converted into invented authority.
  if (state.head.question === null) return conversationContinuationReadUnavailable()
  return freezeInterpretation({
    ...common,
    status: 'needs_reply',
    question: state.head.question,
    reason: null,
  })
}

export function createConversationMealQuestionReadService(
  db: ServiceClient,
  ports: ConversationMealQuestionReadPorts = {},
) {
  const rpc = db.rpc.bind(db),
    from = db.from.bind(db),
    sdk = new Proxy(db, {
      get(target, key, receiver) {
        if (key === 'rpc') return rpc
        if (key === 'from') return from
        return Reflect.get(target, key, receiver)
      },
    }),
    reader = ports.reader ?? createSupabaseConversationMealContinuationReadStore(sdk),
    read = reader.read.bind(reader),
    dependencies: ConversationCurrentScopeDependencies = Object.freeze({
      ...(ports.auth
        ? {
            auth: Object.freeze({
              verifyAccessToken: ports.auth.verifyAccessToken.bind(ports.auth),
              loadPatient: ports.auth.loadPatient.bind(ports.auth),
              isAdmin: ports.auth.isAdmin.bind(ports.auth),
            }),
          }
        : {}),
      ...(ports.clinical
        ? { clinical: Object.freeze({ capture: ports.clinical.capture.bind(ports.clinical) }) }
        : {}),
    })
  return Object.freeze({
    async read(
      who: MobileAuthContext,
      parentCommandId: string,
      epoch: string,
      rawQuery: unknown,
    ): Promise<ConversationMealQuestionRead> {
      const auth = freezeInterpretation(
          detachConversationContinuationReadJson(who) as MobileAuthContext,
        ),
        input = query.parse(detachConversationContinuationReadJson(rawQuery)),
        identity = parseConversationMealContinuationReadIdentity({
          ownerId: authenticatedReevaluationOwner(auth),
          parentCommandId,
          parentInputHash: input.parent_input_hash,
          epoch,
        }),
        scope = createConversationCurrentScope(
          sdk,
          auth,
          {
            ...identity,
            authUserId: auth.authUserId,
          },
          dependencies,
        ),
        before = await scope.observe()
      let raw: unknown
      try {
        // Pin the complete read before any asynchronous post-read observation.
        raw = detachConversationContinuationReadJson(await read(identity))
      } catch {
        await scope.observe()
        return conversationContinuationReadUnavailable()
      }
      const after = await scope.observe(),
        state = parseConversationMealContinuationRead(raw, identity)
      if (state.action !== 'available')
        throw new MobileApiError(
          409,
          `conversation_meal_question_${state.action}`,
          'The original linked meal question is unavailable',
        )
      const at = conversationJournalInstant(state.observed_at)
      if (
        at < conversationJournalInstant(before.observed_at) ||
        at > conversationJournalInstant(after.observed_at)
      )
        return conversationContinuationReadUnavailable()
      return project(auth.authUserId, state)
    },
  })
}
