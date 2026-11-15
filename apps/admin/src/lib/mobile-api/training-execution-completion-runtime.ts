/** Original-Auth public finish/read/cancel service. Every HTTP caller must use
 * the normal authenticated patient/entitlement runtime. Private SQL proofs are
 * projected explicitly; the existing workout service owns optional feedback. */
import { isDeepStrictEqual } from 'node:util'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import { createConversationCurrentScope } from './conversation-current-scope'
import { createConversationFeedbackPublicComposition } from './conversation-feedback-public-composition'
import { conversationFeedbackV3WriterEnabled } from './conversation-feedback-server-policy'
import { conversationJournalInstant } from './conversation-meal-journal-store'
import {
  type ConversationWorkoutCommandDependencies,
  createConversationWorkoutCommandService,
} from './conversation-workout-command-service'
import type { CapturedConversationWorkoutSource } from './conversation-workout-contracts'
import {
  workoutClock,
  workoutHash,
  workoutSnapshot,
  workoutUUID,
} from './conversation-workout-contracts'
import type { ConversationWorkoutEffect } from './conversation-workout-writer'
import { projectCurrentClinicalPublicPolicy } from './current-clinical-read-model'
import type { CurrentClinicalSnapshot } from './current-clinical-state'
import { MobileApiError } from './http'
import { hashMobileRequest } from './idempotency'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import {
  createTrainingExecutionCompletionBackend,
  type TrainingExecutionCompletionRPC,
} from './training-execution-completion-backend'
import {
  type BoundTrainingExecutionCompletion,
  bindTrainingExecutionCompletion,
} from './training-execution-completion-contracts'
import {
  type PublicTrainingExecutionCompletion,
  projectTrainingExecutionCompletion,
  type TrainingExecutionCompletionDecision,
} from './training-execution-completion-public'
import {
  parseTrainingExecutionFinishResolutionRequest,
  projectTrainingExecutionFinishResolution,
} from './training-execution-finish-resolution'
import { trainingExecutionInstant } from './training-execution-instant'
import {
  parseTrainingExecutionCommand,
  projectTrainingExecutionPlan,
  readTrainingExecutionScope,
  readTrainingExecutionSession,
} from './training-execution-kernel'
import { projectTrainingExecutionProgressReconciliation } from './training-execution-progress-reconciliation'
import {
  createTrainingExecutionService,
  trainingExecutionCursorSchema,
  trainingExecutionVerifiedLogin,
} from './training-execution-runtime'

const homeSummary = z
  .object({
    id: workoutUUID,
    revision: z.number().int().min(0).max(2147483647),
    local_date: z.string().date(),
    started_at: workoutClock,
    updated_at: workoutClock,
    plan_id: workoutUUID,
    day_index: z.number().int().min(0).max(6),
    day_label: z.string().min(1).max(80),
    total_exercises: z.number().int().min(1).max(20),
    completed_exercises: z.number().int().min(0).max(20),
    phase: z.enum(['in_progress', 'abandoned', 'completed']),
    day_closed: z.boolean(),
    completion: z
      .object({
        id: workoutUUID,
        input_hash: workoutHash,
        status: z.enum(['reserved', 'completed']),
      })
      .strict()
      .nullable(),
  })
  .strict()
const homeCapture = z
  .object({
    scope: z.unknown(),
    plan: z.unknown().nullable(),
    sessions: z.array(homeSummary).max(20),
    next_cursor: trainingExecutionCursorSchema.nullable(),
  })
  .strict()

export const trainingExecutionCompletionIdentitySchema = z
  .object({
    session_id: workoutUUID,
    completion_id: workoutUUID,
    epoch: workoutUUID,
    input_hash: workoutHash,
  })
  .strict()
export type TrainingExecutionCompletionIdentity = z.infer<
  typeof trainingExecutionCompletionIdentitySchema
>
function unavailable(): never {
  throw new MobileApiError(
    503,
    'training_completion_unavailable',
    'The original completion is unavailable. Keep the same operation for recovery.',
  )
}
function trusted<T>(decode: () => T): T {
  try {
    return decode()
  } catch {
    return unavailable()
  }
}
function changed(): never {
  throw new MobileApiError(
    409,
    'training_completion_changed',
    'The original training completion has changed.',
  )
}
// Apply the same final policy/time fence as the frozen workout facade without
// changing that facade's exports or certified executable surface.
function currentCompletionFeedback(
  value: PublicTrainingExecutionCompletion['feedback'],
  state: CurrentClinicalSnapshot,
  effect: ConversationWorkoutEffect,
): PublicTrainingExecutionCompletion['feedback'] {
  if (!value) return null
  const { observed_at: _latest, ...latest } = projectCurrentClinicalPublicPolicy(state),
    { observed_at: _shown, ...shown } = value.current_policy,
    at = conversationJournalInstant(value.provenance.observed_at)
  return isDeepStrictEqual(latest, shown) &&
    at >= conversationJournalInstant(effect.receipt.committed_at) &&
    at <= conversationJournalInstant(state.observed_at)
    ? value
    : null
}
export function createTrainingExecutionCompletionService(
  db: ServiceClient,
  original: MobileAuthContext,
  authorize: () => Promise<void>,
  dependencies: ConversationWorkoutCommandDependencies = {},
) {
  const auth = workoutSnapshot(original),
    owner = authenticatedReevaluationOwner(auth),
    login = trainingExecutionVerifiedLogin(auth)
  const rpc = db.rpc.bind(db) as unknown as TrainingExecutionCompletionRPC['rpc']
  const workout = createConversationWorkoutCommandService(db, dependencies)
  const feedbackComposition =
    dependencies.feedbackV3?.bind(dependencies) ??
    ((who: MobileAuthContext, epoch: string) =>
      createConversationFeedbackPublicComposition(db, who, epoch, dependencies))
  const feedbackEnabled = (
    dependencies.feedbackV3WriterEnabled?.bind(dependencies) ?? conversationFeedbackV3WriterEnabled
  )()
  function originalScope(raw: unknown, epoch: string) {
    const scope = trusted(() => readTrainingExecutionScope(raw))
    if (scope.owner_id !== owner || scope.auth_user_id !== auth.authUserId || scope.epoch !== epoch)
      return changed()
    return scope
  }
  function lane(epoch: string) {
    const scope = createConversationCurrentScope(
      db,
      auth,
      { authUserId: auth.authUserId, ownerId: owner, epoch },
      dependencies,
    )
    async function current() {
      await authorize()
      const state = await scope.observe()
      await authorize()
      return state
    }
    // The private backend already checks this same sticky current scope
    // immediately before and after each RPC. Do not stack a second pair of
    // provider observations around it. Direct public reads use the fenced port.
    const transport: TrainingExecutionCompletionRPC = {
      async rpc(name, args) {
        const result = workoutSnapshot(await rpc(name, args))
        const envelope = trusted(() =>
          z.object({ data: z.unknown(), error: z.unknown() }).passthrough().parse(result),
        )
        if (envelope.error !== null) {
          const e = z.object({ code: z.string() }).passthrough().safeParse(envelope.error)
          if (e.success && e.data.code === '42501')
            throw new MobileApiError(
              401,
              'training_execution_auth_unavailable',
              'The original login is no longer available.',
            )
          if (e.success && e.data.code === '40001') return changed()
          return unavailable()
        }
        return envelope
      },
    }
    const port: TrainingExecutionCompletionRPC = {
      async rpc(name, args) {
        await current()
        const result = await transport.rpc(name, args)
        await current()
        return result
      },
    }
    const backend = createTrainingExecutionCompletionBackend(transport, {
      owner_id: owner,
      auth_user_id: auth.authUserId,
      auth_session_id: login,
      async checkCurrentScope() {
        await current()
        return true
      },
    })
    return { current, port, backend }
  }
  async function lookup(raw: TrainingExecutionCompletionIdentity) {
    const id = trainingExecutionCompletionIdentitySchema.parse(workoutSnapshot(raw)),
      l = lane(id.epoch)
    await l.current()
    const rawValue = await l.port.rpc('read_training_execution_completion_authenticated', {
      p_user_id: owner,
      p_auth_user_id: auth.authUserId,
      p_auth_session_id: login,
      p_completion_id: id.completion_id,
    })
    const data = trusted(() => z.object({ data: z.unknown() }).passthrough().parse(rawValue).data)
    if (
      trusted(() => z.object({ action: z.string() }).passthrough().parse(data)).action === 'absent'
    )
      throw new MobileApiError(
        404,
        'training_completion_not_found',
        'This completion is not available in the original account.',
      )
    const command = trusted(
      () =>
        z
          .object({ completion: z.object({ command: z.unknown() }).passthrough() })
          .passthrough()
          .parse(data).completion.command,
    )
    const bound = trusted(() =>
      bindTrainingExecutionCompletion(owner, `tfinish1:${id.completion_id}`, command),
    )
    if (
      bound.command.operation_id !== id.completion_id ||
      bound.command.session_id !== id.session_id ||
      bound.command.expected_epoch !== id.epoch ||
      bound.inputHash !== id.input_hash
    )
      return changed()
    trusted(() => projectTrainingExecutionCompletion(data, bound, auth.authUserId))
    return { ...l, bound, data }
  }
  async function present(
    raw: unknown,
    bound: BoundTrainingExecutionCompletion,
    current: () => Promise<CurrentClinicalSnapshot>,
    recovery: {
      source: CapturedConversationWorkoutSource
      prepared: unknown
      effect: ConversationWorkoutEffect
    } | null,
    decision: TrainingExecutionCompletionDecision | null = null,
  ): Promise<PublicTrainingExecutionCompletion> {
    let value: PublicTrainingExecutionCompletion
    try {
      value = projectTrainingExecutionCompletion(raw, bound, auth.authUserId)
    } catch {
      return unavailable()
    }
    let feedback = value.feedback
    if (value.status === 'completed' && value.workout) {
      try {
        if (recovery) {
          // The completed transaction has already independently proved source,
          // preparation, effect and the linked training ACK. Use those proofs
          // in the existing current-safe reader instead of reconciling the
          // entire workout domain a second time merely to render feedback.
          const composition = feedbackComposition(auth, bound.command.expected_epoch)
          if (feedbackEnabled) {
            try {
              await composition.ensureWorkout(recovery)
            } catch {
              /* Optional canonical education never changes the domain receipt. */
            }
          }
          feedback = await composition.readHistorical({
            auth,
            proof: {
              kind: 'workout.report',
              source: recovery.source,
              prepared: recovery.prepared,
              effect: recovery.effect,
            },
          })
        } else {
          const result = await workout.read(
            auth,
            bound.command.operation_id,
            bound.workout.inputHash,
            bound.command.expected_epoch,
            '2',
          )
          if (
            result.status === 'saved' &&
            result.registration.workout_id === value.workout.workout_id &&
            result.registration.registration_id === value.workout.registration_id &&
            result.command_id === value.completion_id &&
            result.input_hash === bound.workout.inputHash &&
            result.epoch === value.epoch
          )
            feedback = result.feedback
        }
      } catch {
        /* Optional feedback never repeats/invalidates the official workout. */
      }
    }
    const final = await current() // mandatory failures cannot be swallowed by optional enrichment
    if (recovery) feedback = currentCompletionFeedback(feedback, final, recovery.effect)
    return workoutSnapshot({ ...value, feedback, decision })
  }
  return Object.freeze({
    async resolveFinish(key: string | null, raw: unknown) {
      const body = parseTrainingExecutionFinishResolutionRequest(raw)
      if (key !== `tresolve1:${body.mode}:${body.command.operation_id}`)
        throw new MobileApiError(
          422,
          'training_execution_invalid_key',
          'The original resolution key is required.',
        )
      const bound = bindTrainingExecutionCompletion(
        owner,
        `tfinish1:${body.command.operation_id}`,
        body.command,
      )
      // Resolving an old command is not authority to write under its old
      // clinical epoch. Bind the original live login to the current profile;
      // the immutable nested command remains independently bound by SQL.
      await authorize()
      const discovery = await workout.session(auth),
        l = lane(discovery.epoch)
      const envelope = await l.port.rpc(
        body.mode === 'observe'
          ? 'observe_training_execution_finish_authenticated'
          : 'withdraw_training_execution_finish_authenticated',
        {
          p_user_id: owner,
          p_auth_user_id: auth.authUserId,
          p_auth_session_id: login,
          p_command: bound.command,
        },
      )
      const data = trusted(() => z.object({ data: z.unknown() }).passthrough().parse(envelope).data)
      const value = trusted(() =>
        projectTrainingExecutionFinishResolution(data, bound, auth.authUserId, body.mode),
      )
      if (value.scope.epoch !== discovery.epoch) return changed()
      if (
        body.mode === 'withdraw' &&
        value.status !== 'withdrawn' &&
        !(value.status === 'available' && value.completion?.status !== 'reserved')
      )
        return unavailable()
      let current = value.current,
        completion = value.completion
      // Enrich only a proven current completion through the existing readonly
      // workout reader. No resolver, education writer or second registration.
      if (value.current?.completion?.status === 'completed') {
        const context = trusted(
          () =>
            z
              .object({
                state: z
                  .object({
                    action: z.literal('completion'),
                    context: z.unknown(),
                  })
                  .strict(),
              })
              .passthrough()
              .parse(data).state.context,
        )
        const command = trusted(
          () =>
            z
              .object({ completion: z.object({ command: z.unknown() }).passthrough() })
              .passthrough()
              .parse(context).completion.command,
        )
        const currentBound = trusted(() =>
          bindTrainingExecutionCompletion(
            owner,
            `tfinish1:${value.current?.completion?.completion_id}`,
            command,
          ),
        )
        const enriched = await present(context, currentBound, l.current, null)
        current = { ...value.current, completion: enriched }
        if (value.completion?.completion_id === enriched.completion_id)
          completion = { ...value.completion, feedback: enriched.feedback }
      }
      await l.current()
      return workoutSnapshot({ ...value, current, completion })
    },
    async progress(key: string | null, raw: unknown) {
      const command = parseTrainingExecutionCommand(workoutSnapshot(raw))
      if (key !== `texecution1:${command.operation_id}`)
        throw new MobileApiError(
          422,
          'training_execution_invalid_key',
          'The original progress key is required.',
        )
      const l = lane(command.expected_epoch)
      async function observe() {
        const response = await l.port.rpc('reconcile_training_execution_progress_authenticated', {
          p_user_id: owner,
          p_auth_user_id: auth.authUserId,
          p_auth_session_id: login,
          p_command: command,
        })
        const data = trusted(
          () => z.object({ data: z.unknown() }).passthrough().parse(response).data,
        )
        return trusted(() =>
          projectTrainingExecutionProgressReconciliation(data, command, {
            owner,
            auth: auth.authUserId,
          }),
        )
      }
      async function response(
        proof: Awaited<ReturnType<typeof observe>>,
        status: 'created' | 'updated' | 'replayed' | 'pending' | 'not_applied',
      ) {
        await l.current()
        return workoutSnapshot({
          schema: 'training.execution-mutation.v2' as const,
          status,
          scope: proof.action === 'available' ? proof.current.scope : proof.scope,
          operation_id: command.operation_id,
          input_hash: hashMobileRequest(command),
          receipt: proof.action === 'available' ? proof.receipt : null,
          current: proof.current,
        })
      }
      const before = await observe()
      if (before.action === 'available') return response(before, 'replayed')
      const current = before.current
      if (
        current &&
        (current.session.phase !== 'in_progress' ||
          (command.schema === 'training.execution.update.v1' &&
            command.expected_revision < current.session.revision))
      )
        return response(before, 'not_applied')
      if (
        command.schema === 'training.execution.start.v1' &&
        command.expected_local_date < before.scope.current_local_date
      )
        return response(before, 'not_applied')
      if (current?.completion?.status === 'reserved') return response(before, 'pending')
      // A start state without its atomic original receipt is not a generic
      // rejection capability. Do not normalize unknown store history.
      if (current && command.schema === 'training.execution.start.v1') return unavailable()
      let written: Awaited<ReturnType<ReturnType<typeof createTrainingExecutionService>['mutate']>>
      try {
        written = await createTrainingExecutionService(db, auth, async () => {
          await l.current()
        }).mutate(command)
      } catch (error) {
        // The original writer may have committed before a lost reply. This
        // is observation only: never submit a second mutation automatically.
        const recovered = await observe()
        if (recovered.action === 'available') return response(recovered, 'replayed')
        throw error
      }
      const after = await observe()
      if (after.action !== 'available' || !isDeepStrictEqual(after.receipt, written.receipt))
        return unavailable()
      return response(after, written.status)
    },
    async home(rawCursor?: unknown) {
      const cursor =
        rawCursor === undefined
          ? null
          : trainingExecutionCursorSchema.parse(workoutSnapshot(rawCursor))
      await authorize()
      const discovery = await workout.session(auth),
        l = lane(discovery.epoch)
      if (cursor && (cursor.owner_id !== owner || cursor.epoch !== discovery.epoch))
        return changed()
      await l.current()
      const envelope = await l.port.rpc('read_training_execution_home_v2_authenticated', {
        p_user_id: owner,
        p_auth_user_id: auth.authUserId,
        p_auth_session_id: login,
        p_cursor: cursor,
      })
      const data = trusted(() => {
        if (Buffer.byteLength(JSON.stringify(envelope), 'utf8') > 2_097_152) return unavailable()
        return homeCapture.parse(z.object({ data: z.unknown() }).passthrough().parse(envelope).data)
      })
      const scope = originalScope(data.scope, discovery.epoch),
        tail = data.sessions.at(-1)
      if (
        new Set(data.sessions.map((s) => s.id)).size !== data.sessions.length ||
        data.sessions.some((s, i) => {
          const previous = data.sessions[i - 1]
          const at = trainingExecutionInstant
          return (
            s.completed_exercises > s.total_exercises ||
            s.local_date > scope.current_local_date ||
            at(s.started_at) > at(s.updated_at) ||
            at(s.updated_at) > at(scope.observed_at) ||
            (s.phase === 'completed') !== (s.completion?.status === 'completed') ||
            (s.phase === 'abandoned' && s.completion !== null) ||
            (previous &&
              (at(s.updated_at) > at(previous.updated_at) ||
                (s.updated_at === previous.updated_at && s.id >= previous.id)))
          )
        })
      )
        return unavailable()
      if (
        data.next_cursor &&
        (data.sessions.length !== 20 ||
          !tail ||
          data.next_cursor.owner_id !== owner ||
          data.next_cursor.epoch !== scope.epoch ||
          data.next_cursor.time_zone !== scope.time_zone ||
          data.next_cursor.updated_at !== tail.updated_at ||
          data.next_cursor.session_id !== tail.id)
      )
        return unavailable()
      const plan =
        data.plan === null ? null : trusted(() => projectTrainingExecutionPlan(data.plan, scope))
      await l.current()
      return workoutSnapshot({
        schema: 'training.execution-home.v2' as const,
        scope,
        plan,
        sessions: data.sessions,
        next_cursor: data.next_cursor,
      })
    },
    async state(sessionId: string, expectedEpoch: string) {
      const id = workoutUUID.parse(sessionId),
        epoch = workoutUUID.parse(expectedEpoch),
        l = lane(epoch)
      await l.current()
      const envelope = await l.port.rpc('read_training_execution_state_v2_authenticated', {
        p_user_id: owner,
        p_auth_user_id: auth.authUserId,
        p_auth_session_id: login,
        p_session_id: id,
      })
      const data = trusted(() => z.object({ data: z.unknown() }).passthrough().parse(envelope).data)
      const action = trusted(
        () => z.object({ action: z.string() }).passthrough().parse(data).action,
      )
      if (action === 'absent')
        throw new MobileApiError(
          404,
          'training_execution_not_found',
          'The original execution is not available.',
        )
      if (action === 'progress') {
        const p = trusted(() =>
          z
            .object({ action: z.literal('progress'), scope: z.unknown(), session: z.unknown() })
            .strict()
            .parse(data),
        )
        const scope = originalScope(p.scope, epoch),
          session = trusted(() => readTrainingExecutionSession(p.session, scope))
        if (session.id !== id) return changed()
        await l.current()
        return workoutSnapshot({
          schema: 'training.execution-state.v2' as const,
          scope,
          session,
          completion: null,
        })
      }
      if (action !== 'completion') return unavailable()
      const rawContext = trusted(
        () =>
          z
            .object({ action: z.literal('completion'), context: z.unknown() })
            .strict()
            .parse(data).context,
      )
      const command = trusted(
        () =>
          z
            .object({ completion: z.object({ command: z.unknown() }).passthrough() })
            .passthrough()
            .parse(rawContext).completion.command,
      )
      const parsed = trusted(() =>
        z.object({ operation_id: workoutUUID }).passthrough().parse(command),
      )
      const bound = trusted(() =>
        bindTrainingExecutionCompletion(owner, `tfinish1:${parsed.operation_id}`, command),
      )
      if (bound.command.session_id !== id || bound.command.expected_epoch !== epoch)
        return changed()
      const completion = await present(rawContext, bound, l.current, null)
      if (completion.status === 'cancelled' || completion.session === null) return unavailable()
      return workoutSnapshot({
        schema: 'training.execution-state.v2' as const,
        scope: completion.scope,
        session: completion.session,
        completion,
      })
    },
    async submit(key: string | null, raw: unknown) {
      const bound = bindTrainingExecutionCompletion(owner, key, raw),
        l = lane(bound.command.expected_epoch)
      // submitAtomic already owns this same original-scope callback before and
      // after its transaction. Do not duplicate those provider observations.
      let result: Awaited<ReturnType<typeof l.backend.submitAtomic>>
      try {
        result = await l.backend.submitAtomic(bound)
      } catch (error) {
        // One transaction may have committed before its response was lost.
        // Recover only through the exact original read; never retry a writer.
        await l.current()
        const recovered = await lookup({
          session_id: bound.command.session_id,
          completion_id: bound.command.operation_id,
          epoch: bound.command.expected_epoch,
          input_hash: bound.inputHash,
        })
        const proof = trusted(() =>
          projectTrainingExecutionCompletion(recovered.data, bound, auth.authUserId),
        )
        if (proof.status === 'completed' || proof.status === 'cancelled')
          return present(recovered.data, bound, recovered.current, null)
        throw error
      }
      if (result.status === 'saved') return present(result.completion, bound, l.current, result)
      if (result.status === 'needs_reply' || result.status === 'not_reported') {
        // No performed effect exists for these semantic outcomes. Safe SQL
        // cancellation releases the exact reservation; a corrected accepted
        // report will get a new operation rather than changing this one.
        const cancelled = await l.backend.cancel(bound)
        const decision: TrainingExecutionCompletionDecision =
          result.status === 'needs_reply'
            ? {
                status: 'needs_reply',
                question: { field: result.question.field, text: result.question.text },
              }
            : { status: 'not_recorded', reason: result.reason }
        return present(cancelled, bound, l.current, null, decision)
      }
      const found = await lookup({
        session_id: bound.command.session_id,
        completion_id: bound.command.operation_id,
        epoch: bound.command.expected_epoch,
        input_hash: bound.inputHash,
      })
      return present(found.data, bound, found.current, null)
    },
    async read(raw: TrainingExecutionCompletionIdentity) {
      const found = await lookup(raw)
      return present(found.data, found.bound, found.current, null)
    },
    async cancel(raw: TrainingExecutionCompletionIdentity) {
      const found = await lookup(raw),
        result = await found.backend.cancel(found.bound)
      return present(result, found.bound, found.current, null)
    },
  })
}
