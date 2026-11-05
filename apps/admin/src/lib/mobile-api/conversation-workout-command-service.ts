import { isDeepStrictEqual } from 'node:util'
/** Guarded command composition. No route/capability is installed here. A
 * factual workout ACK never contains private capture, clinical state or raw
 * canonical feedback. Rich presentation is a separately negotiated concern. */
import type { ServiceClient } from '@mpp/db'
import type { MobileAuthContext } from './auth'
import {
  authenticateConversationPatientReadonly,
  type ConversationCurrentScopeDependencies,
  createConversationCurrentScope,
  createConversationReadonlyAuth,
} from './conversation-current-scope'
import type { ConversationFeedbackPresentationNegotiation } from './conversation-feedback-presentation-negotiation'
import type {
  ConversationFeedbackPresentationV2,
  ConversationFeedbackPresentationV2Proof,
} from './conversation-feedback-presentation-v2'
import {
  type ConversationFeedbackPublicCompositionFactory,
  createConversationFeedbackPublicComposition,
} from './conversation-feedback-public-composition'
import { conversationFeedbackV3WriterEnabled } from './conversation-feedback-server-policy'
import { conversationJournalInstant } from './conversation-meal-journal-store'
import { resolveConversationWorkoutReport } from './conversation-workout-authority'
import { createSupabaseConversationWorkoutBackend } from './conversation-workout-backend'
import {
  bindConversationWorkoutCommand,
  parseConversationWorkoutSource,
  workoutHash,
  workoutSnapshot,
  workoutUUID,
} from './conversation-workout-contracts'
import {
  type ConversationWorkoutReadIdentity,
  createSupabaseConversationWorkoutReadStore,
} from './conversation-workout-read'
import type { ConversationWorkoutEffect } from './conversation-workout-writer'
import { projectCurrentClinicalPublicPolicy } from './current-clinical-read-model'
import { type CurrentClinicalSnapshot, captureCurrentClinicalState } from './current-clinical-state'
import { MobileApiError } from './http'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { createSupabaseCurrentClinicalStateSource } from './supabase-current-clinical-state'

function context(auth: MobileAuthContext, commandId: string, inputHash: string, epoch: string) {
  const who = workoutSnapshot(auth),
    identity = workoutSnapshot({
      ownerId: authenticatedReevaluationOwner(who),
      commandId: workoutUUID.parse(commandId),
      inputHash: workoutHash.parse(inputHash),
      epoch: workoutUUID.parse(epoch),
    })
  return { auth: who, identity }
}
function publicIdentity(identity: ConversationWorkoutReadIdentity) {
  return {
    owner_id: identity.ownerId,
    command_id: identity.commandId,
    input_hash: identity.inputHash,
    epoch: identity.epoch,
  }
}
function state(
  identity: ConversationWorkoutReadIdentity,
  status: 'absent' | 'pending' | 'not_recorded' | 'needs_reply',
  detail?: {
    reason?: string
    question?: Readonly<{ key: string; field: 'activity' | 'duration_min'; text: string }>
  },
) {
  return workoutSnapshot({
    schema: 'conversation.workout-command-state.v1' as const,
    status,
    ...publicIdentity(identity),
    ...detail,
  })
}
function saved(
  identity: ConversationWorkoutReadIdentity,
  effect: ConversationWorkoutEffect,
  feedback: ConversationFeedbackPresentationV2 | null = null,
) {
  const receipt = effect.receipt
  if (
    receipt.owner_id !== identity.ownerId ||
    receipt.command_id !== identity.commandId ||
    receipt.registration_id !== identity.commandId ||
    receipt.input_hash !== identity.inputHash ||
    receipt.epoch !== identity.epoch
  )
    throw new MobileApiError(
      503,
      'conversation_workout_unavailable',
      'Original workout is unavailable',
    )
  return workoutSnapshot({
    schema: 'conversation.workout-command-result.v1' as const,
    status: 'saved' as const,
    ...publicIdentity(identity),
    registration: {
      provenance: receipt.provenance,
      registration_id: receipt.registration_id,
      workout_id: receipt.workout_id,
      performed_at: receipt.performed_at,
      local_date: receipt.local_date,
      time_zone: receipt.time_zone,
      committed_at: receipt.committed_at,
      effect_version: receipt.effect_version,
    },
    activity: { kind: 'workout' as const, log_id: receipt.workout_id, ...receipt.activity },
    feedback,
  })
}
function currentWorkoutPresentation(
  value: ConversationFeedbackPresentationV2 | null,
  state: CurrentClinicalSnapshot,
  effect: ConversationWorkoutEffect,
): ConversationFeedbackPresentationV2 | null {
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

function decisionState(
  identity: ConversationWorkoutReadIdentity,
  decision: ReturnType<typeof resolveConversationWorkoutReport>,
) {
  if (decision.status === 'needs_reply')
    return state(identity, 'needs_reply', { question: decision.question })
  if (decision.status === 'not_reported')
    return state(identity, 'not_recorded', { reason: decision.reason })
  return state(identity, 'pending', { reason: 'reconciliation_required' })
}

export interface ConversationWorkoutCommandDependencies
  extends ConversationCurrentScopeDependencies {
  readonly feedbackV3?: ConversationFeedbackPublicCompositionFactory
  readonly feedbackV3WriterEnabled?: () => boolean
}

export function createConversationWorkoutCommandService(
  db: ServiceClient,
  dependencies: ConversationWorkoutCommandDependencies = {},
) {
  const scopeDependencies: ConversationCurrentScopeDependencies = Object.freeze({
    ...(dependencies.auth
      ? {
          auth: Object.freeze({
            verifyAccessToken: dependencies.auth.verifyAccessToken.bind(dependencies.auth),
            loadPatient: dependencies.auth.loadPatient.bind(dependencies.auth),
            isAdmin: dependencies.auth.isAdmin.bind(dependencies.auth),
          }),
        }
      : {}),
    ...(dependencies.clinical
      ? {
          clinical: Object.freeze({
            capture: dependencies.clinical.capture.bind(dependencies.clinical),
          }),
        }
      : {}),
  })
  const feedback =
      dependencies.feedbackV3?.bind(dependencies) ??
      ((auth: MobileAuthContext, epoch: string) =>
        createConversationFeedbackPublicComposition(db, auth, epoch, scopeDependencies)),
    writeFeedback = (
      dependencies.feedbackV3WriterEnabled?.bind(dependencies) ??
      conversationFeedbackV3WriterEnabled
    )()
  async function enrich(
    auth: MobileAuthContext,
    epoch: string,
    proof: Extract<ConversationFeedbackPresentationV2Proof, { kind: 'workout.report' }>,
    selected: ConversationFeedbackPresentationNegotiation,
    allowWrite: boolean,
  ): Promise<ConversationFeedbackPresentationV2 | null> {
    if (!allowWrite && selected !== '2') return null
    try {
      const composition = feedback(auth, epoch),
        ensure = composition.ensureWorkout.bind(composition),
        read = composition.readHistorical.bind(composition)
      if (allowWrite) {
        try {
          await ensure({ source: proof.source, prepared: proof.prepared, effect: proof.effect })
        } catch {
          /* optional feedback cannot invalidate a durable effect */
        }
      }
      return selected === '2' ? workoutSnapshot(await read({ auth, proof })) : null
    } catch {
      return null
    }
  }
  return Object.freeze({
    async session(originalAuth: MobileAuthContext) {
      const who = workoutSnapshot(originalAuth),
        owner = authenticatedReevaluationOwner(who),
        current = await authenticateConversationPatientReadonly(
          new Request('https://conversation.invalid/current-workout-session', {
            headers: { Authorization: `Bearer ${who.accessToken}` },
          }),
          scopeDependencies.auth ?? createConversationReadonlyAuth(db),
        )
      if (current.authUserId !== who.authUserId || current.userId !== owner)
        throw new MobileApiError(
          409,
          'conversation_patient_changed',
          'The original account has changed',
        )
      const observed = await captureCurrentClinicalState(
        scopeDependencies.clinical ?? createSupabaseCurrentClinicalStateSource(db),
        { userId: owner, mode: 'profile' },
      )
      if (!observed.epoch)
        throw new MobileApiError(
          503,
          'conversation_workout_unavailable',
          'Workout session is unavailable',
        )
      const scope = createConversationCurrentScope(
          db,
          who,
          { authUserId: who.authUserId, ownerId: owner, epoch: observed.epoch },
          scopeDependencies,
        ),
        after = await scope.observe()
      if (
        conversationJournalInstant(after.observed_at) <
        conversationJournalInstant(observed.observed_at)
      )
        throw new MobileApiError(
          503,
          'conversation_scope_unavailable',
          'Current session observation is unavailable',
        )
      return workoutSnapshot({
        schema: 'conversation.workout-session.v1' as const,
        auth_user_id: who.authUserId,
        owner_id: owner,
        epoch: observed.epoch,
        observed_at: after.observed_at,
        workout_command_protocol: 'conversation.command.v1' as const,
      })
    },
    async submit(
      auth: MobileAuthContext,
      key: string | null,
      raw: unknown,
      epoch: string,
      selected: ConversationFeedbackPresentationNegotiation = 'legacy',
    ) {
      const who = workoutSnapshot(auth),
        command = bindConversationWorkoutCommand(authenticatedReevaluationOwner(who), key, raw),
        c = context(who, command.commandId, command.inputHash, epoch),
        scope = createConversationCurrentScope(
          db,
          c.auth,
          { authUserId: c.auth.authUserId, ...c.identity },
          scopeDependencies,
        ),
        backend = createSupabaseConversationWorkoutBackend(db, {
          checkCurrentScope: () => scope.check(),
        })
      // Surface mandatory Auth/epoch failures before any physical domain call.
      await scope.observe()
      const result = await backend.report(command, c.identity.epoch)
      // A domain outcome cannot erase a sticky mandatory scope refusal.
      await scope.observe()
      if (result.status === 'saved') {
        const presentation = await enrich(
          c.auth,
          c.identity.epoch,
          {
            kind: 'workout.report',
            source: result.source,
            prepared: result.prepared,
            effect: result.effect,
          },
          selected,
          writeFeedback,
        )
        const final = await scope.observe()
        return saved(
          c.identity,
          result.effect,
          currentWorkoutPresentation(presentation, final, result.effect),
        )
      }
      if (result.status === 'needs_reply' || result.status === 'not_reported')
        return decisionState(c.identity, result)
      return state(c.identity, 'pending', { reason: 'reconciliation_required' })
    },
    async read(
      auth: MobileAuthContext,
      commandId: string,
      inputHash: string,
      epoch: string,
      selected: ConversationFeedbackPresentationNegotiation = 'legacy',
    ) {
      const c = context(auth, commandId, inputHash, epoch),
        prior = await createSupabaseConversationWorkoutReadStore(
          db,
          c.auth,
          c.identity,
          scopeDependencies,
        ).read()
      if (prior.action === 'absent') return state(c.identity, 'absent')
      if (prior.action !== 'available')
        throw new MobileApiError(
          409,
          'conversation_workout_changed',
          'The original workout identity has changed',
        )
      if (prior.effect) {
        const effect = { action: 'available' as const, ...prior.effect }
        if (!prior.source || !prior.preparation)
          throw new MobileApiError(
            503,
            'conversation_workout_unavailable',
            'Original workout is unavailable',
          )
        const command = bindConversationWorkoutCommand(
            c.identity.ownerId,
            `cmsg1:${c.identity.commandId}`,
            prior.source.context.source_input,
          ),
          source = parseConversationWorkoutSource(command, prior.source),
          presentation = await enrich(
            c.auth,
            c.identity.epoch,
            { kind: 'workout.report', source, prepared: prior.preparation.prepared, effect },
            selected,
            false,
          )
        const final = await createConversationCurrentScope(
          db,
          c.auth,
          { authUserId: c.auth.authUserId, ...c.identity },
          scopeDependencies,
        ).observe()
        return saved(c.identity, effect, currentWorkoutPresentation(presentation, final, effect))
      }
      if (prior.source && prior.preparation) {
        const command = bindConversationWorkoutCommand(
            c.identity.ownerId,
            `cmsg1:${c.identity.commandId}`,
            prior.source.context.source_input,
          ),
          source = parseConversationWorkoutSource(command, prior.source)
        return decisionState(c.identity, resolveConversationWorkoutReport(source))
      }
      return state(c.identity, 'pending', { reason: 'reconciliation_required' })
    },
  })
}
