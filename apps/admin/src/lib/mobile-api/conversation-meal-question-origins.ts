import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import {
  type ConversationCurrentScopeDependencies,
  createConversationCurrentScope,
} from './conversation-current-scope'
import type { ConversationIntakeBinding } from './conversation-intake-contracts'
import {
  decodeConversationJournalV3Cursor,
  encodeConversationJournalV3Cursor,
} from './conversation-journal-v3-contracts'
import { createSupabaseConversationJournalV3Store } from './conversation-journal-v3-store'
import { freezeInterpretation } from './conversation-meal-interpretation-contracts'
import { conversationJournalInstant } from './conversation-meal-journal-store'
import { workoutSnapshot, workoutUUID } from './conversation-workout-contracts'
import { MobileApiError } from './http'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'

export interface ConversationMealQuestionOrigin {
  readonly intake: ConversationIntakeBinding
  readonly selection: Readonly<{
    kind: 'meal.report'
    source_hash: string
    decision_hash: string
    selected_at: string
    command: Readonly<{
      kind: 'meal.report'
      owner_id: string
      command_id: string
      input_hash: string
      epoch: string
      admitted_at: string
    }>
  }>
  readonly source:
    | Readonly<{ channel: 'text'; text: string }>
    | Readonly<{ channel: 'media'; caption: string | null }>
}
export interface ConversationMealQuestionOriginsPage {
  readonly schema: 'conversation.meal-question-origins.v1'
  readonly mode: 'lookup_only'
  readonly auth_user_id: string
  readonly owner_id: string
  readonly epoch: string
  readonly observed_at: string
  readonly items: readonly ConversationMealQuestionOrigin[]
  readonly has_more: boolean
  readonly next_cursor: string | null
}
const requestSchema = z
  .object({
    limit: z.number().int().min(1).max(25),
    cursor: z.string().min(1).max(1024).nullable(),
  })
  .strict()
function unavailable(): never {
  throw new MobileApiError(
    503,
    'conversation_meal_question_origins_unavailable',
    'Original meal questions are unavailable',
  )
}

/** The historical page locates an immutable origin, never an answer lease.
 * Its complete existing parser verifies actual intake→typed-child lineage.
 * A separate fresh parent read and existing POST still fence the real answer. */
export function createConversationMealQuestionOriginsService(
  db: ServiceClient,
  dependencies: ConversationCurrentScopeDependencies = {},
) {
  const rpc = db.rpc.bind(db),
    from = db.from.bind(db),
    sdk = new Proxy(db, {
      get(target, key, receiver) {
        if (key === 'rpc') return rpc
        if (key === 'from') return from
        return Reflect.get(target, key, receiver)
      },
    })
  return Object.freeze({
    async read(
      original: MobileAuthContext,
      rawEpoch: string,
      rawInput: unknown,
    ): Promise<ConversationMealQuestionOriginsPage> {
      const who = workoutSnapshot(original),
        owner = authenticatedReevaluationOwner(who),
        epoch = workoutUUID.parse(rawEpoch),
        input = requestSchema.parse(workoutSnapshot(rawInput)),
        cursor =
          input.cursor === null
            ? null
            : decodeConversationJournalV3Cursor(input.cursor, owner, epoch),
        scope = createConversationCurrentScope(
          sdk,
          who,
          { authUserId: who.authUserId, ownerId: owner, epoch },
          dependencies,
        )
      let first: bigint | null = null,
        last: bigint | null = null,
        scopeFailure: unknown
      const reader = createSupabaseConversationJournalV3Store(sdk, {
        async checkCurrentScope(identity) {
          if (identity.ownerId !== owner || identity.epoch !== epoch) return unavailable()
          try {
            const state = await scope.observe(),
              at = conversationJournalInstant(state.observed_at)
            first ??= at
            last = at
            return true
          } catch (error) {
            scopeFailure = error
            throw error
          }
        },
      })
      let page: Awaited<ReturnType<typeof reader.read>>
      try {
        page = await reader.read({ ownerId: owner, epoch, limit: input.limit, cursor })
      } catch (error) {
        throw scopeFailure ?? error
      }
      if (page.action !== 'available')
        throw new MobileApiError(
          409,
          'conversation_meal_question_origins_changed',
          'The original conversation has changed',
        )
      const observed = conversationJournalInstant(page.observedAt)
      if (first === null || last === null || observed < first || observed > last)
        return unavailable()
      const primaryIDs = new Set(
          page.items.filter((item) => item.kind === 'intake').map((item) => item.intake_id),
        ),
        items: ConversationMealQuestionOrigin[] = []
      for (const intake of page.intakes) {
        if (!primaryIDs.has(intake.bound.intakeId)) continue
        const selection = intake.selection,
          child = selection?.command
        if (!selection || child?.kind !== 'meal.report') continue
        const thread = page.mealPage.threads.find((value) => value.thread_id === child.command_id),
          head = thread?.continuation
        if (
          !thread?.terminal_receipt ||
          !['missing_quantity', 'meal_type_required'].includes(thread.terminal_receipt.reason) ||
          !head ||
          head.fulfilled_by !== null ||
          head.question === null
        )
          continue
        const source = intake.bound.input.source
        items.push({
          intake: intake.binding,
          selection: {
            kind: 'meal.report',
            source_hash: selection.source_hash,
            decision_hash: selection.decision_hash,
            selected_at: selection.selected_at,
            command: {
              kind: 'meal.report',
              owner_id: child.owner_id,
              command_id: child.command_id,
              input_hash: child.input_hash,
              epoch: child.epoch,
              admitted_at: child.admitted_at,
            },
          },
          source:
            source.channel === 'text'
              ? { channel: 'text', text: source.text }
              : { channel: 'media', caption: source.caption ?? null },
        })
      }
      // Preserve the physical event order rather than the private dependency
      // array's order, which can include descendants or be independently sorted.
      const order = new Map(
        page.items.map((item, index) => [item.kind === 'intake' ? item.intake_id : null, index]),
      )
      items.sort(
        (a, b) => (order.get(a.intake.intake_id) ?? 0) - (order.get(b.intake.intake_id) ?? 0),
      )
      return freezeInterpretation({
        schema: 'conversation.meal-question-origins.v1',
        mode: 'lookup_only',
        auth_user_id: who.authUserId,
        owner_id: owner,
        epoch,
        observed_at: page.observedAt,
        items,
        has_more: page.hasMore,
        next_cursor:
          page.nextCursor === null
            ? null
            : encodeConversationJournalV3Cursor(owner, epoch, page.nextCursor),
      })
    },
  })
}
