/** Read-only history composition. Historical rows never become outbox ACKs,
 * answer leases, new submissions, reconstructed inputs or current authority. */
import { isDeepStrictEqual } from 'node:util'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import {
  assertConversationReadonlyNonAdmin,
  type ConversationCurrentScopeDependencies,
  createConversationCurrentScope,
  createConversationReadonlyAuth,
  parseConversationReadonlyIdentity,
  parseConversationReadonlyPatient,
} from './conversation-current-scope'
import type { ConversationFeedbackPresentationV2 } from './conversation-feedback-presentation-v2'
import { createConversationFeedbackPublicComposition } from './conversation-feedback-public-composition'
import {
  type ConversationJournalV3Page,
  decodeConversationJournalV3Cursor,
  encodeConversationJournalV3Cursor,
} from './conversation-journal-v3-contracts'
import { createSupabaseConversationJournalV3Store } from './conversation-journal-v3-store'
import { createSupabaseConversationMealContinuationFeedback } from './conversation-meal-continuation-feedback'
import {
  type ConversationMealFeedbackPresentation,
  createSupabaseConversationMealFeedbackPresentation,
} from './conversation-meal-feedback-presentation'
import { conversationJournalInstant } from './conversation-meal-journal-store'
import {
  createConversationMealThreadPageService,
  type NegotiatedPublicConversationMealThreadEvent,
} from './conversation-meal-thread-page-service'
import type { ConversationMealThreadDescriptor } from './conversation-meal-thread-page-store'
import { createConversationWorkoutCommandService } from './conversation-workout-command-service'
import { workoutSnapshot, workoutUUID } from './conversation-workout-contracts'
import {
  currentClinicalReadBinding,
  projectCurrentClinicalPublicPolicy,
} from './current-clinical-read-model'
import type { CurrentClinicalRequest, CurrentClinicalStateSource } from './current-clinical-state'
import { MobileApiError } from './http'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { createSupabaseCurrentClinicalStateSource } from './supabase-current-clinical-state'

type WorkoutService = ReturnType<typeof createConversationWorkoutCommandService>
type SavedWorkout = Extract<Awaited<ReturnType<WorkoutService['read']>>, { status: 'saved' }>
export interface ConversationJournalV3Request {
  readonly epoch: string
  readonly limit: number
  readonly cursor: string | null
}
type MealEvent = NegotiatedPublicConversationMealThreadEvent
type MealQuestion = NonNullable<ConversationMealThreadDescriptor['continuation']>['question']
type HistoricalQuestion<T> = T extends unknown
  ? Omit<T, 'schema' | 'question_key' | 'revision'>
  : never
type ObservedQuestion =
  | Readonly<{ field: string; text: string }>
  | HistoricalQuestion<NonNullable<MealQuestion>>
type ObservedInput = Readonly<
  | { channel: 'text'; text: string }
  | { channel: 'media'; caption: string | null }
  | { channel: 'structured'; answer: Extract<MealEvent, { kind: 'reply' }>['body']['answer'] }
>
type MealReceipt =
  | NonNullable<Extract<MealEvent, { kind: 'report' }>['receipt']>
  | Extract<MealEvent, { kind: 'fulfillment' }>['receipt']
type MealRecord = Readonly<{
  kind: 'meal'
  registration_id: string
  meal_type: MealReceipt['meal_type']
  local_date: string
  log_ids: readonly string[]
  effect_version: string
}>
type EditReceipt = Extract<MealEvent, { kind: 'edit' }>['receipt']
type EditRecord = Readonly<{
  kind: 'meal_edit'
  operation_id: string
  change: EditReceipt['kind']
  revision: number
  applied_at: string
  target_operation_id: string | null
  removed_item_ids: readonly string[]
  new_item_ids: readonly string[]
  next_record_id: string | null
}>
export interface PublicConversationJournalV3Entry {
  readonly event_id: string
  readonly at: string
  readonly thread_id: string
  readonly kind: 'intake' | 'workout' | 'report' | 'reply' | 'reply_result' | 'fulfillment' | 'edit'
  readonly lineage: Readonly<{
    kind: 'intake' | 'workout.report' | 'meal.report' | 'meal.clarify' | 'meal.edit'
    intake_id: string | null
    command_id: string | null
    parent_command_id: string | null
    origin_epoch: string
  }>
  readonly input: ObservedInput | null
  readonly outcome: Readonly<{
    status: 'pending' | 'not_recorded' | 'needs_reply' | 'clarification_required' | 'registered'
    reason?: string
    observed_question?: ObservedQuestion | null
    record?:
      | Readonly<{
          kind: 'workout'
          registration: SavedWorkout['registration']
          activity: SavedWorkout['activity']
        }>
      | MealRecord
      | EditRecord
    feedback: ConversationFeedbackPresentationV2 | ConversationMealFeedbackPresentation | null
  }>
}
export interface PublicConversationJournalV3Page {
  readonly schema: 'conversation.journal-page.v3'
  readonly mode: 'historical'
  readonly auth_user_id: string
  readonly owner_id: string
  readonly epoch: string
  readonly observed_at: string
  readonly items: readonly PublicConversationJournalV3Entry[]
  readonly has_more: boolean
  readonly next_cursor: string | null
}
const requestSchema = z
  .object({
    epoch: workoutUUID,
    limit: z.number().int().min(1).max(25),
    cursor: z.string().min(1).max(1024).nullable(),
  })
  .strict()
const readonlyRPCs = new Set([
  'read_conversation_journal_page_v3',
  'reconcile_conversation_workout',
  'capture_mobile_registration_feedback_v3',
  'read_mobile_registration_feedback_v3',
  'read_conversation_meal_feedback_source',
  'read_conversation_meal_feedback_v2',
])
function unavailable(): MobileApiError {
  return new MobileApiError(
    503,
    'conversation_journal_unavailable',
    'Original conversation history is unavailable',
  )
}
function changed(): MobileApiError {
  return new MobileApiError(
    409,
    'conversation_journal_changed',
    'The current history account or policy has changed',
  )
}
function requireValue<T>(value: T | null | undefined): T {
  if (value == null) throw unavailable()
  return value
}
function observedInput(
  source: { channel: 'text'; text: string } | { channel: 'media'; caption?: string },
): ObservedInput {
  return source.channel === 'text'
    ? { channel: 'text', text: source.text }
    : { channel: 'media', caption: source.caption ?? null }
}
export function createConversationJournalV3Service(
  db: ServiceClient,
  dependencies: ConversationCurrentScopeDependencies = {},
) {
  const originalRpc = db.rpc.bind(db),
    originalFrom = db.from.bind(db),
    originalAuth = dependencies.auth ?? createConversationReadonlyAuth(db),
    verify = originalAuth.verifyAccessToken.bind(originalAuth),
    load = originalAuth.loadPatient.bind(originalAuth),
    admin = originalAuth.isAdmin.bind(originalAuth),
    originalClinical = dependencies.clinical ?? createSupabaseCurrentClinicalStateSource(db),
    capture = originalClinical.capture.bind(originalClinical)
  let closed: MobileApiError | null = null
  return Object.freeze({
    async read(
      original: MobileAuthContext,
      raw: ConversationJournalV3Request,
    ): Promise<PublicConversationJournalV3Page> {
      if (closed) throw closed
      const who = workoutSnapshot(original),
        owner = authenticatedReevaluationOwner(who),
        request = requestSchema.parse(workoutSnapshot(raw)),
        identity = workoutSnapshot({
          authUserId: workoutUUID.parse(who.authUserId),
          ownerId: owner,
          epoch: request.epoch,
        }),
        query = workoutSnapshot({
          ownerId: owner,
          epoch: request.epoch,
          limit: request.limit,
          cursor:
            request.cursor === null
              ? null
              : decodeConversationJournalV3Cursor(request.cursor, owner, request.epoch),
        })
      async function checked<T>(read: () => Promise<T>): Promise<T> {
        if (closed) throw closed
        try {
          const result = workoutSnapshot(await read())
          if (closed) throw closed
          return result
        } catch (error) {
          closed ??= error instanceof MobileApiError ? error : unavailable()
          throw closed
        }
      }
      const auth = Object.freeze({
          verifyAccessToken: (token: string) =>
            checked(async () => {
              if (token !== who.accessToken) throw changed()
              const value = parseConversationReadonlyIdentity(workoutSnapshot(await verify(token)))
              if (value.id !== who.authUserId) throw changed()
              return value
            }),
          loadPatient: (subject: string) =>
            checked(async () => {
              if (subject !== who.authUserId) throw changed()
              const value = parseConversationReadonlyPatient(
                workoutSnapshot(await load(subject)),
                subject,
              )
              if (value.id !== owner) throw changed()
              return value
            }),
          isAdmin: (subject: string) =>
            checked(async () => {
              if (subject !== who.authUserId) throw changed()
              assertConversationReadonlyNonAdmin(await admin(subject))
              return false
            }),
        }),
        lane = createConversationCurrentScope(db, who, identity, { auth, clinical: { capture } })
      async function observe() {
        if (closed) throw closed
        try {
          return workoutSnapshot(await lane.observe(identity))
        } catch (error) {
          closed ??= error instanceof MobileApiError ? error : unavailable()
          throw closed
        }
      }
      const clinical: CurrentClinicalStateSource = Object.freeze({
          async capture(expected: Readonly<CurrentClinicalRequest>) {
            if (
              expected.userId !== owner ||
              expected.mode !== 'profile' ||
              expected.expectedEpoch !== request.epoch
            ) {
              closed = changed()
              throw closed
            }
            // This is a fresh actual observation, not a cached/fabricated clinical clock.
            return observe()
          },
        }),
        rpc = async (...parameters: Parameters<ServiceClient['rpc']>) => {
          const [name, rawArgs, rawOptions] = parameters
          if (!readonlyRPCs.has(name)) {
            closed = unavailable()
            throw closed
          }
          const args = rawArgs === undefined ? undefined : workoutSnapshot(rawArgs),
            options = rawOptions === undefined ? undefined : workoutSnapshot(rawOptions)
          await observe()
          try {
            const value = workoutSnapshot(
              await (parameters.length > 2
                ? originalRpc(name, args, options)
                : parameters.length > 1
                  ? originalRpc(name, args)
                  : originalRpc(name)),
            )
            await observe()
            return value
          } catch (error) {
            await observe()
            throw error
          }
        },
        sdk = new Proxy(db, {
          get(target, key) {
            if (key === 'rpc') return rpc
            if (key === 'from') return originalFrom
            const value = Reflect.get(target, key, target)
            return typeof value === 'function' ? value.bind(target) : value
          },
        }),
        feedbackV3 = (input: MobileAuthContext, epoch: string) => {
          if (!isDeepStrictEqual(input, who) || epoch !== request.epoch) {
            closed = changed()
            throw closed
          }
          return createConversationFeedbackPublicComposition(sdk, who, request.epoch, {
            auth,
            clinical,
          })
        },
        store = createSupabaseConversationJournalV3Store(sdk, {
          async checkCurrentScope(candidate) {
            if (!isDeepStrictEqual(candidate, { ownerId: owner, epoch: request.epoch })) {
              closed = changed()
              throw closed
            }
            await observe()
            return true
          },
        })
      let page: ConversationJournalV3Page | null = null
      try {
        const before = await observe(),
          mealService = createConversationMealThreadPageService(sdk, {
            clinical,
            feedbackV3,
            presentation: createSupabaseConversationMealFeedbackPresentation(sdk, {
              clinicalSource: clinical,
            }),
            linkedPresentation: {
              async readHistorical(input) {
                const pinned = workoutSnapshot(input)
                if (!isDeepStrictEqual(pinned.auth, who)) {
                  closed = changed()
                  throw closed
                }
                return createSupabaseConversationMealContinuationFeedback(sdk, {
                  clinicalSource: clinical,
                  async checkCurrentScope(candidate) {
                    if (!isDeepStrictEqual(workoutSnapshot(candidate), pinned)) {
                      closed = changed()
                      throw closed
                    }
                    await observe()
                    return true
                  },
                }).readHistorical(pinned)
              },
            },
            store: {
              async read(expected) {
                if (
                  page ||
                  !isDeepStrictEqual(expected, {
                    ownerId: owner,
                    epoch: request.epoch,
                    limit: 25,
                    cursor: null,
                  })
                )
                  throw unavailable()
                const result = await store.read(query)
                if (result.action !== 'available') {
                  if (result.action === 'cursor_conflict')
                    throw new MobileApiError(
                      409,
                      'conversation_journal_cursor_conflict',
                      'The original history cursor is unavailable',
                    )
                  throw result.action === 'event_conflict' ? unavailable() : changed()
                }
                page = result
                return result.mealPage
              },
            },
          }),
          mealView = await mealService.read(
            who,
            { epoch: request.epoch, limit: 25, cursor: null },
            '2',
          ),
          actualPage = requireValue<ConversationJournalV3Page>(page),
          workout = createConversationWorkoutCommandService(sdk, { auth, clinical, feedbackV3 }),
          intakes = new Map(actualPage.intakes.map((i) => [i.bound.intakeId, i])),
          workouts = new Map(actualPage.workouts.map((w) => [w.bound.commandId, w])),
          entries: PublicConversationJournalV3Entry[] = []
        if (mealView.has_more)
          throw new MobileApiError(
            503,
            'conversation_journal_entry_too_large',
            'The history projection requires a smaller page',
          )
        async function workoutOutcome(
          commandId: string,
        ): Promise<PublicConversationJournalV3Entry['outcome']> {
          const original = requireValue(workouts.get(commandId)),
            b = original.binding,
            result = workoutSnapshot(
              await workout.read(who, b.command_id, b.input_hash, b.epoch, '2'),
            )
          if (
            result.owner_id !== owner ||
            result.command_id !== b.command_id ||
            result.input_hash !== b.input_hash ||
            result.epoch !== b.epoch
          )
            throw unavailable()
          if (result.status === 'saved')
            return {
              status: 'registered',
              record: {
                kind: 'workout',
                registration: result.registration,
                activity: result.activity,
              },
              feedback: result.feedback,
            }
          if (result.status === 'absent') throw unavailable()
          return {
            status: result.status,
            ...('reason' in result ? { reason: result.reason } : {}),
            ...(result.question
              ? { observed_question: { field: result.question.field, text: result.question.text } }
              : {}),
            feedback: null,
          }
        }
        const mealEvents = new Map(mealView.items.map((e) => [e.event_id, e])),
          mealThreads = new Map(mealView.threads.map((t) => [t.thread_id, t]))
        function question(q: MealQuestion): ObservedQuestion | null {
          if (!q) return null
          const { schema: _schema, question_key: _key, revision: _revision, ...observed } = q
          return observed
        }
        function mealRecord(r: MealReceipt): MealRecord {
          return {
            kind: 'meal',
            registration_id: r.registration_id,
            meal_type: r.meal_type,
            local_date: r.local_date,
            log_ids: r.log_ids,
            effect_version: r.effect_version,
          }
        }
        function mealOutcome(
          e: MealEvent,
          t: ConversationMealThreadDescriptor,
        ): PublicConversationJournalV3Entry['outcome'] {
          if (e.kind === 'report')
            return {
              status: e.status,
              ...(e.receipt ? { record: mealRecord(e.receipt) } : {}),
              ...(e.status === 'not_recorded' && t.terminal_receipt
                ? { reason: t.terminal_receipt.reason }
                : {}),
              ...(t.continuation?.question
                ? { observed_question: question(t.continuation.question) }
                : {}),
              feedback: e.feedback,
            }
          if (e.kind === 'fulfillment')
            return { status: 'registered', record: mealRecord(e.receipt), feedback: e.feedback }
          if (e.kind === 'reply')
            return {
              status: 'pending',
              reason: 'reply_observed',
              observed_question: question(e.question),
              feedback: null,
            }
          if (e.kind === 'reply_result')
            return {
              status: e.status === 'needs_reply' ? 'needs_reply' : 'pending',
              reason: e.status === 'needs_reply' ? 'reply_required' : 'preparation_observed',
              observed_question: question(e.next_question),
              feedback: null,
            }
          const r = e.receipt
          return {
            status: 'registered',
            record: {
              kind: 'meal_edit',
              operation_id: r.operation_id,
              change: r.kind,
              revision: r.revision,
              applied_at: r.applied_at,
              target_operation_id: r.target_operation_id,
              removed_item_ids: r.removed_item_ids,
              new_item_ids: r.new_item_ids,
              next_record_id: r.next_record_id,
            },
            feedback: null,
          }
        }
        for (const item of actualPage.items) {
          let entry: PublicConversationJournalV3Entry
          if (item.kind === 'intake') {
            const i = requireValue(intakes.get(item.intake_id)),
              d = i.selection?.decision,
              child = i.selection?.command
            let outcome: PublicConversationJournalV3Entry['outcome']
            if (!d)
              outcome = {
                status: 'pending',
                reason: i.claimed ? 'routing_reconciliation_required' : 'intake_pending',
                feedback: null,
              }
            else if (d.kind === 'not_reported' || d.kind === 'clarification_required')
              outcome = {
                status: d.kind === 'not_reported' ? 'not_recorded' : 'clarification_required',
                reason: d.reason,
                ...('question' in d ? { observed_question: d.question } : {}),
                feedback: null,
              }
            else if (child?.kind === 'workout.report')
              outcome = await workoutOutcome(child.command_id)
            else if (child?.kind === 'meal.report') {
              const e = requireValue(mealEvents.get(`command/${child.command_id}`)),
                t = requireValue(mealThreads.get(child.command_id))
              if (e.kind !== 'report') throw unavailable()
              outcome = mealOutcome(e, t)
            } else throw unavailable()
            entry = {
              event_id: item.event_id,
              at: item.at,
              thread_id: i.bound.intakeId,
              kind: 'intake',
              lineage: {
                kind: 'intake',
                intake_id: i.bound.intakeId,
                command_id: child?.command_id ?? null,
                parent_command_id: null,
                origin_epoch: i.binding.epoch,
              },
              input: observedInput(i.bound.input.source),
              outcome,
            }
          } else if (item.kind === 'workout') {
            const w = requireValue(workouts.get(item.command_id))
            entry = {
              event_id: item.event_id,
              at: item.at,
              thread_id: w.bound.commandId,
              kind: 'workout',
              lineage: {
                kind: 'workout.report',
                intake_id: null,
                command_id: w.bound.commandId,
                parent_command_id: null,
                origin_epoch: w.binding.epoch,
              },
              input: observedInput(w.bound.command.source),
              outcome: await workoutOutcome(w.bound.commandId),
            }
          } else {
            const e = requireValue(mealEvents.get(item.event_id)),
              t = requireValue(mealThreads.get(e.thread_id)),
              child =
                e.kind === 'reply' || e.kind === 'reply_result' || e.kind === 'fulfillment'
                  ? e.child_binding
                  : e.kind === 'edit'
                    ? e.effect_binding
                    : null,
              originalIntake =
                item.intake_id === null ? null : requireValue(intakes.get(item.intake_id))
            entry = {
              event_id: item.event_id,
              at: item.at,
              thread_id: originalIntake?.bound.intakeId ?? e.thread_id,
              kind: e.kind,
              lineage: {
                kind:
                  e.kind === 'edit'
                    ? 'meal.edit'
                    : child?.kind === 'meal.clarify'
                      ? 'meal.clarify'
                      : 'meal.report',
                intake_id: item.intake_id,
                command_id: child?.command_id ?? e.thread_id,
                parent_command_id: child?.kind === 'meal.clarify' ? e.thread_id : null,
                origin_epoch: t.parent_binding.epoch,
              },
              input:
                e.kind === 'report'
                  ? observedInput(t.original_command.source)
                  : e.kind === 'reply'
                    ? { channel: 'structured', answer: e.body.answer }
                    : null,
              outcome: mealOutcome(e, t),
            }
          }
          entries.push(workoutSnapshot(entry))
        }
        const after = await observe(),
          instant = conversationJournalInstant
        if (
          currentClinicalReadBinding(before) !== currentClinicalReadBinding(after) ||
          instant(actualPage.observedAt) < instant(before.observed_at) ||
          instant(actualPage.observedAt) > instant(after.observed_at)
        )
          throw changed()
        const current = projectCurrentClinicalPublicPolicy(after)
        for (const e of entries) {
          const f = e.outcome.feedback
          if (f) {
            const { observed_at: _current, ...a } = current,
              { observed_at: _shown, ...b } = f.current_policy
            if (
              !isDeepStrictEqual(a, b) ||
              instant(f.provenance.observed_at) < instant(before.observed_at) ||
              instant(f.provenance.observed_at) > instant(after.observed_at)
            )
              throw changed()
          }
          if (
            e.outcome.record?.kind === 'workout' &&
            instant(e.outcome.record.registration.committed_at) > instant(after.observed_at)
          )
            throw unavailable()
        }
        const visible: PublicConversationJournalV3Entry[] = [],
          packet = (more: boolean, cursor: string | null): PublicConversationJournalV3Page => ({
            schema: 'conversation.journal-page.v3',
            mode: 'historical',
            auth_user_id: who.authUserId,
            owner_id: owner,
            epoch: request.epoch,
            observed_at: after.observed_at,
            items: visible,
            has_more: more,
            next_cursor: cursor,
          }),
          cursorFor = (e: PublicConversationJournalV3Entry) =>
            encodeConversationJournalV3Cursor(owner, request.epoch, { at: e.at, id: e.event_id })
        for (let index = 0; index < entries.length; index++) {
          const e = requireValue(entries[index]),
            more = actualPage.hasMore || index < entries.length - 1
          visible.push(e)
          if (
            Buffer.byteLength(JSON.stringify(packet(more, more ? cursorFor(e) : null)), 'utf8') >
            240000
          ) {
            visible.pop()
            const last = visible.at(-1)
            if (!last)
              throw new MobileApiError(
                503,
                'conversation_journal_entry_too_large',
                'The original history entry exceeds the page limit',
              )
            return workoutSnapshot(packet(true, cursorFor(last)))
          }
        }
        return workoutSnapshot(
          packet(
            actualPage.hasMore,
            actualPage.hasMore && visible.length ? cursorFor(requireValue(visible.at(-1))) : null,
          ),
        )
      } catch (error) {
        if (closed) throw closed
        if (error instanceof MobileApiError) throw error
        throw unavailable()
      }
    },
  })
}
