/** New command transport composition. GET only reads/reconciles. POST uses the
 * original epoch's fenced journal and never publishes raw historical feedback. */
import { isDeepStrictEqual } from 'node:util'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import {
  type ConversationJournalBinding,
  conversationJournalBindingSchema,
} from './conversation-command-candidate-contracts'
import {
  type BoundConversationMealCommand,
  bindConversationCommand,
} from './conversation-command-contracts'
import type { ConversationCommandJournal } from './conversation-command-journal'
import {
  type ConversationReadonlyAuth,
  createConversationCurrentScope,
} from './conversation-current-scope'
import type { ConversationFeedbackPresentationNegotiation } from './conversation-feedback-presentation-negotiation'
import type { ConversationFeedbackPresentationV2 } from './conversation-feedback-presentation-v2'
import {
  type ConversationFeedbackPublicCompositionFactory,
  createConversationFeedbackPublicComposition,
} from './conversation-feedback-public-composition'
import { conversationFeedbackV3WriterEnabled } from './conversation-feedback-server-policy'
import { createSupabaseConversationFencedJournal } from './conversation-fenced-journal'
import {
  projectSavedConversationMealCommandResult,
  type SavedConversationMealCommandResult,
} from './conversation-meal-command-result'
import {
  type ConversationMealDecisionAvailable,
  type ConversationMealDecisionStore,
  createSupabaseConversationMealDecisionStore,
  parseConversationMealDecisionReceipt,
} from './conversation-meal-decision-store'
import {
  type ConversationMealFeedbackPresentationService,
  createSupabaseConversationMealFeedbackPresentation,
} from './conversation-meal-feedback-presentation'
import type { ConversationMealEffectReceipt } from './conversation-meal-feedback-store'
import { freezeInterpretation } from './conversation-meal-interpretation-contracts'
import {
  type ConversationMealInterpreterPort,
  interpretPersistedConversationMeal,
} from './conversation-meal-interpretation-service'
import { createOpenRouterConversationMealInterpreter } from './conversation-meal-interpreter'
import { conversationJournalInstant } from './conversation-meal-journal-store'
import { registerPersistedConversationMeal } from './conversation-meal-registration-service'
import {
  type ConversationMealSemanticStore,
  createSupabaseConversationMealSemanticStore,
} from './conversation-meal-semantic-store'
import {
  type ConversationMealWriter,
  createSupabaseConversationMealWriter,
} from './conversation-meal-writer'
import {
  currentClinicalReadBinding,
  projectCurrentClinicalPublicPolicy,
} from './current-clinical-read-model'
import {
  type CurrentClinicalStateSource,
  captureCurrentClinicalState,
} from './current-clinical-state'
import { MobileApiError } from './http'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { createSupabaseCurrentClinicalStateSource } from './supabase-current-clinical-state'

const uuid = z
  .string()
  .uuid()
  .regex(/^[0-9a-f-]+$/u)
const hash = z.string().regex(/^[a-f0-9]{64}$/u)
const decision = z
  .object({
    reason: z.string().regex(/^[a-z_]{1,80}$/u),
    food_indexes: z.array(z.number().int().min(0).max(29)).max(30),
  })
  .strict()
export interface ConversationMealCommandState {
  readonly schema: 'conversation.meal-command-state.v1'
  readonly status: 'absent' | 'pending' | 'not_recorded'
  readonly owner_id: string
  readonly command_id: string
  readonly input_hash: string
  readonly epoch: string
  readonly reason?: string
  readonly food_indexes?: readonly number[]
}
export type NegotiatedSavedConversationMealCommandResult = Omit<
  SavedConversationMealCommandResult,
  'feedback'
> & { readonly feedback: ConversationFeedbackPresentationV2 | null }
export type ConversationMealCommandReply =
  | SavedConversationMealCommandResult
  | NegotiatedSavedConversationMealCommandResult
  | ConversationMealCommandState
export interface ConversationSessionObservation {
  readonly schema: 'conversation.session.v1'
  readonly auth_user_id: string
  readonly owner_id: string
  readonly epoch: string
  readonly observed_at: string
  readonly meal_command_protocol: 'conversation.command.v1'
}
export interface ConversationMealCommandServicePorts {
  writer?: ConversationMealWriter
  journal?: (originalEpoch: string) => ConversationCommandJournal
  clinical?: CurrentClinicalStateSource
  auth?: ConversationReadonlyAuth
  semantics?: ConversationMealSemanticStore
  createInterpreter?: () => ConversationMealInterpreterPort
  register?: typeof registerPersistedConversationMeal
  presentation?: ConversationMealFeedbackPresentationService
  decisions?: ConversationMealDecisionStore
  /** Trusted composition ports. Never populated from request headers/body. */
  feedbackV3?: ConversationFeedbackPublicCompositionFactory
  feedbackV3WriterEnabled?: () => boolean
}
function unavailable(): never {
  throw new MobileApiError(
    503,
    'conversation_command_unavailable',
    'Command processing is unavailable',
  )
}
function changed(): never {
  throw new MobileApiError(
    409,
    'conversation_command_changed',
    'The original command or account epoch has changed',
  )
}
function validatedBinding(
  raw: ConversationJournalBinding,
  c: BoundConversationMealCommand,
  epoch: string,
): ConversationJournalBinding {
  const b = conversationJournalBindingSchema.parse(structuredClone(raw))
  if (
    !isDeepStrictEqual(raw, b) ||
    b.owner_id !== c.ownerId ||
    b.command_id !== c.commandId ||
    b.input_hash !== c.inputHash
  )
    return unavailable()
  if (b.epoch !== epoch) return changed()
  return freezeInterpretation(b)
}
function context(auth: MobileAuthContext, expectedEpoch: string) {
  const who = freezeInterpretation(structuredClone(auth)),
    owner = authenticatedReevaluationOwner(who)
  return Object.freeze({ auth: who, owner, epoch: uuid.parse(expectedEpoch) })
}
function state(
  owner: string,
  id: string,
  inputHash: string,
  epoch: string,
  status: ConversationMealCommandState['status'],
  info?: z.infer<typeof decision>,
): ConversationMealCommandState {
  return freezeInterpretation({
    schema: 'conversation.meal-command-state.v1',
    status,
    owner_id: owner,
    command_id: id,
    input_hash: inputHash,
    epoch,
    ...(info ?? {}),
  })
}
const noNewProvider: ConversationMealInterpreterPort = Object.freeze({
  interpret: async () => unavailable(),
})
export function createConversationMealCommandService(
  db: ServiceClient,
  ports: ConversationMealCommandServicePorts = {},
) {
  const w = ports.writer ?? createSupabaseConversationMealWriter(db),
    writer: ConversationMealWriter = Object.freeze({
      readPrepared: w.readPrepared.bind(w),
      readEffect: w.readEffect.bind(w),
      prepare: w.prepare.bind(w),
      commit: w.commit.bind(w),
    })
  const journalFactory =
    ports.journal?.bind(ports) ??
    ((epoch: string) => createSupabaseConversationFencedJournal(db, epoch))
  const journalFor = (epoch: string): ConversationCommandJournal => {
    const j = journalFactory(epoch)
    const read = j.read.bind(j),
      admit = j.admit.bind(j),
      attach = j.attach.bind(j)
    return Object.freeze({
      async read(identity: Parameters<ConversationCommandJournal['read']>[0]) {
        const v = await read(identity)
        if (v.action === 'available' && v.binding.epoch !== epoch) return changed()
        return v
      },
      async admit(command: BoundConversationMealCommand) {
        const v = await admit(command)
        if ('binding' in v) validatedBinding(v.binding, command, epoch)
        return v
      },
      attach,
    })
  }
  // The driver performs recovery reads of its own. Fence EVERY returned
  // authority, including those after the first public read, before effects.
  const writerFor = (epoch: string): ConversationMealWriter =>
    Object.freeze({
      async readPrepared(command: BoundConversationMealCommand) {
        const v = await writer.readPrepared(command)
        if (v.action === 'available') validatedBinding(v.binding, command, epoch)
        return v
      },
      async readEffect(command: BoundConversationMealCommand) {
        // FX intentionally has no epoch. Recover its binding and receipt in the
        // same authoritative prepared read, never by inventing an FX field.
        const v = await writer.readPrepared(command)
        if (v.action === 'available') {
          validatedBinding(v.binding, command, epoch)
          if (v.receipt) return { action: 'available' as const, receipt: v.receipt }
        }
        return {
          action: v.action === 'stale_epoch' ? ('stale_epoch' as const) : ('absent' as const),
        }
      },
      async prepare(input: Parameters<ConversationMealWriter['prepare']>[0]) {
        if (input.source.epoch !== epoch) return changed()
        return writer.prepare(input)
      },
      commit: writer.commit,
    })
  const rootAuth = ports.auth
    ? Object.freeze({
        verifyAccessToken: ports.auth.verifyAccessToken.bind(ports.auth),
        loadPatient: ports.auth.loadPatient.bind(ports.auth),
        isAdmin: ports.auth.isAdmin.bind(ports.auth),
      })
    : undefined
  const cs = ports.clinical ?? createSupabaseCurrentClinicalStateSource(db),
    clinical = Object.freeze({ capture: cs.capture.bind(cs) })
  const ms = ports.semantics ?? createSupabaseConversationMealSemanticStore(db),
    semantics: ConversationMealSemanticStore = Object.freeze({
      read: ms.read.bind(ms),
      start: ms.start.bind(ms),
      commit: ms.commit.bind(ms),
      markUnknown: ms.markUnknown.bind(ms),
    })
  const register = ports.register?.bind(ports) ?? registerPersistedConversationMeal
  const ds = ports.decisions ?? createSupabaseConversationMealDecisionStore(db),
    decisions: ConversationMealDecisionStore = Object.freeze({
      read: ds.read.bind(ds),
      seal: ds.seal.bind(ds),
    })
  const ps = ports.presentation ?? createSupabaseConversationMealFeedbackPresentation(db),
    readPresentation = ps.readHistorical.bind(ps)
  const feedback3 =
      ports.feedbackV3?.bind(ports) ??
      ((auth: MobileAuthContext, epoch: string) =>
        createConversationFeedbackPublicComposition(db, auth, epoch, {
          clinical,
          ...(rootAuth ? { auth: rootAuth } : {}),
        })),
    writeFeedback3 = (
      ports.feedbackV3WriterEnabled?.bind(ports) ?? conversationFeedbackV3WriterEnabled
    )()
  const makeInterpreter =
    ports.createInterpreter?.bind(ports) ??
    (() => createOpenRouterConversationMealInterpreter(process.env.OPENROUTER_API_KEY ?? ''))
  const observe = async (owner: string, epoch: string) => {
    const observed = await captureCurrentClinicalState(clinical, {
      userId: owner,
      mode: 'profile',
      expectedEpoch: epoch,
    })
    if (observed.epoch !== epoch) return changed()
  }
  const saved = async (
    auth: MobileAuthContext,
    command: BoundConversationMealCommand,
    epoch: string,
    rawBinding: ConversationJournalBinding,
    receipt: ConversationMealEffectReceipt,
    selected: ConversationFeedbackPresentationNegotiation,
  ): Promise<ConversationMealCommandReply> => {
    const serverBinding = validatedBinding(rawBinding, command, epoch)
    const scope = createConversationCurrentScope(
        db,
        auth,
        { authUserId: auth.authUserId, ownerId: command.ownerId, epoch },
        { clinical, ...(rootAuth ? { auth: rootAuth } : {}) },
      ),
      before = await scope.observe()
    let feedback: unknown = null,
      v2: ConversationFeedbackPresentationV2 | null = null
    if (selected === '2') {
      try {
        v2 = freezeInterpretation(
          await feedback3(auth, epoch).readHistorical({
            auth,
            proof: { kind: 'meal.report', command, receipt, serverBinding },
          }),
        )
      } catch {
        /* optional enrichment cannot repeat a saved effect */
      }
      // A denied fresh token/admin/mapping/epoch is mandatory. Keep this
      // outside the optional catch and before any legacy presentation fallback.
      await scope.observe()
    }
    if (!v2) {
      try {
        feedback = freezeInterpretation(
          await readPresentation({ auth, command, receipt, serverBinding }),
        )
      } catch {
        /* factual ACK survives missing optional education */
      }
    }
    const final = await scope.observe()
    if (final) {
      if (v2) {
        const { observed_at: _latest, ...latest } = projectCurrentClinicalPublicPolicy(final),
          { observed_at: _shown, ...shown } = v2.current_policy,
          at = conversationJournalInstant(v2.provenance.observed_at)
        if (
          !isDeepStrictEqual(latest, shown) ||
          at < conversationJournalInstant(receipt.consumed_at) ||
          at < conversationJournalInstant(serverBinding.admitted_at) ||
          at > conversationJournalInstant(final.observed_at)
        )
          v2 = null
      }
      if (before && currentClinicalReadBinding(before) !== currentClinicalReadBinding(final))
        feedback = null
    }
    const result = projectSavedConversationMealCommandResult({
      auth,
      command,
      expectedEpoch: epoch,
      serverBinding,
      receipt,
      feedback,
    })
    return v2 ? freezeInterpretation({ ...result, feedback: v2 }) : result
  }
  const decisionIdentity = (command: BoundConversationMealCommand, epoch: string) =>
    Object.freeze({
      ownerId: command.ownerId,
      commandId: command.commandId,
      inputHash: command.inputHash,
      epoch,
    })
  const terminalReply = (
    command: BoundConversationMealCommand,
    epoch: string,
    v: ConversationMealDecisionAvailable,
  ) => {
    const b = validatedBinding(v.binding, command, epoch),
      d = parseConversationMealDecisionReceipt(v.decision, b)
    return state(command.ownerId, command.commandId, command.inputHash, epoch, 'not_recorded', {
      reason: d.reason,
      food_indexes: [...d.food_indexes],
    })
  }
  const readTerminal = async (command: BoundConversationMealCommand, epoch: string) => {
    const v = await decisions.read(decisionIdentity(command, epoch))
    if (v.action === 'available' && 'decision' in v) return terminalReply(command, epoch, v)
    if (v.action !== 'absent') return changed()
    return null
  }
  const sanitize = (e: unknown): never => {
    if (e instanceof MobileApiError) throw e
    return unavailable()
  }
  return Object.freeze({
    async session(auth: MobileAuthContext): Promise<ConversationSessionObservation> {
      try {
        const who = freezeInterpretation(structuredClone(auth)),
          owner = authenticatedReevaluationOwner(who),
          authUserId = uuid.parse(who.authUserId.toLowerCase()),
          observed = await captureCurrentClinicalState(clinical, { userId: owner, mode: 'profile' })
        if (!observed.epoch) return unavailable()
        return freezeInterpretation({
          schema: 'conversation.session.v1',
          auth_user_id: authUserId,
          owner_id: owner,
          epoch: observed.epoch,
          observed_at: observed.observed_at,
          meal_command_protocol: 'conversation.command.v1',
        })
      } catch (e) {
        return sanitize(e)
      }
    },
    async submit(
      auth: MobileAuthContext,
      key: string | null,
      raw: unknown,
      expectedEpoch: string,
      selected: ConversationFeedbackPresentationNegotiation = 'legacy',
    ): Promise<ConversationMealCommandReply> {
      try {
        const c = context(auth, expectedEpoch),
          command = bindConversationCommand(c.owner, key, structuredClone(raw)),
          journal = journalFor(c.epoch),
          fencedWriter = writerFor(c.epoch),
          prior = await fencedWriter.readPrepared(command)
        if (prior.action === 'stale_epoch') return changed()
        if (prior.action === 'available') {
          const b = validatedBinding(prior.binding, command, c.epoch)
          if (prior.receipt) return saved(c.auth, command, c.epoch, b, prior.receipt, selected)
        }
        const terminal = await readTerminal(command, c.epoch)
        if (terminal) return terminal
        if (prior.action !== 'available') await observe(c.owner, c.epoch)
        let interpreter = noNewProvider
        if (!(prior.action === 'available' && prior.resolved)) {
          const current = await semantics.read(command)
          if (current.action === 'absent') interpreter = makeInterpreter()
          else if (!('status' in current)) return changed()
          // Only a new durable claimed attempt inside the actual interpreter
          // may use the provider. Existing completed/unknown attempts never do.
        }
        const result = await register(db, c.auth, key, command.command, {
          writer: fencedWriter,
          journal,
          interpreter,
          ...(writeFeedback3
            ? {
                originalEnrichment: (() => {
                  type Bridge = ReturnType<ConversationFeedbackPublicCompositionFactory>
                  const legacy = (value: Awaited<ReturnType<Bridge['readRoot']>>) =>
                    value?.schema === 'registration.feedback.v3' ? null : value
                  // Construct optional bridge only inside the post-effect hook;
                  // a failed factory cannot prevent or retry factual recording.
                  return Object.freeze({
                    ensureOriginal: async (input: Parameters<Bridge['ensureRoot']>[0]) =>
                      legacy(await feedback3(c.auth, c.epoch).ensureRoot(input)),
                    readOriginal: async (input: Parameters<Bridge['readRoot']>[0]) =>
                      legacy(await feedback3(c.auth, c.epoch).readRoot(input)),
                  })
                })(),
              }
            : {}),
          interpret: async (bound, source) =>
            (
              await interpretPersistedConversationMeal(
                db,
                c.auth,
                `cmsg1:${bound.commandId}`,
                bound.command,
                {
                  interpreter,
                  store: semantics,
                  journal,
                  sources: { capture: async () => source },
                },
              )
            ).interpretation,
        })
        if (!isDeepStrictEqual(result.command, command)) return unavailable()
        if (result.status === 'saved')
          return saved(c.auth, command, c.epoch, result.serverBinding, result.receipt, selected)
        const current = await journal.read({ ownerId: c.owner, commandId: command.commandId })
        if (current.action !== 'available') return changed()
        validatedBinding(current.binding, command, c.epoch)
        if (!isDeepStrictEqual(current.source, command)) return unavailable()
        const info = decision.parse({
          reason: result.reason,
          food_indexes: [...result.foodIndexes],
        })
        if (new Set(info.food_indexes).size !== info.food_indexes.length) return unavailable()
        // A terminal reply needs the actual completed immutable model attempt,
        // including downstream nutrition/materialization refusals. Unknown or
        // unfinished provider work cannot manufacture a durable decision.
        const semantic = await semantics.read(command)
        if (semantic.action === 'stale_epoch') return changed()
        if (
          !('status' in semantic) ||
          semantic.status !== 'completed' ||
          !semantic.result ||
          !semantic.result_hash
        )
          return unavailable()
        if (
          semantic.epoch !== c.epoch ||
          semantic.owner_id !== c.owner ||
          semantic.command_id !== command.commandId ||
          semantic.input_hash !== command.inputHash
        )
          return changed()
        let sealed: Awaited<ReturnType<ConversationMealDecisionStore['seal']>>
        try {
          sealed = await decisions.seal(
            decisionIdentity(command, c.epoch),
            {
              sourceHash: semantic.source_hash,
              attemptId: semantic.attempt_id,
              resultHash: semantic.result_hash,
            },
            { schema: 'conversation.meal-decision.v1', status: 'not_recorded', ...info },
          )
        } catch {
          // The seal may have committed. Read once; never seal or register a
          // second time merely because its HTTP response was lost.
          try {
            const recovered = await readTerminal(command, c.epoch)
            if (recovered) return recovered
          } catch (readError) {
            if (readError instanceof MobileApiError && readError.status === 409) throw readError
          }
          throw new MobileApiError(
            409,
            'conversation_decision_reconciliation_required',
            'The original decision must be reconciled',
          )
        }
        if ('decision' in sealed && (sealed.action === 'sealed' || sealed.action === 'replay'))
          return terminalReply(command, c.epoch, sealed)
        if (sealed.action === 'decision_conflict') {
          const winner = await readTerminal(command, c.epoch)
          if (winner) return winner
        }
        if (sealed.action === 'resolved_conflict') {
          const winner = await fencedWriter.readPrepared(command)
          if (winner.action === 'available' && winner.receipt)
            return saved(c.auth, command, c.epoch, winner.binding, winner.receipt, selected)
        }
        return changed()
      } catch (e) {
        return sanitize(e)
      }
    },
    async read(
      auth: MobileAuthContext,
      commandId: string,
      originalHash: string,
      expectedEpoch: string,
      selected: ConversationFeedbackPresentationNegotiation = 'legacy',
    ): Promise<ConversationMealCommandReply> {
      try {
        const c = context(auth, expectedEpoch),
          id = uuid.parse(commandId),
          inputHash = hash.parse(originalHash),
          journal = journalFor(c.epoch),
          current = await journal.read({ ownerId: c.owner, commandId: id })
        if (current.action === 'stale_epoch') return changed()
        if (current.action === 'absent') {
          await observe(c.owner, c.epoch)
          return state(c.owner, id, inputHash, c.epoch, 'absent')
        }
        if (current.action !== 'available') return changed()
        const command = current.source
        if (
          command.ownerId !== c.owner ||
          command.commandId !== id ||
          command.inputHash !== inputHash
        )
          return changed()
        validatedBinding(current.binding, command, c.epoch)
        const prior = await writer.readPrepared(command)
        if (prior.action !== 'available') return changed()
        const b = validatedBinding(prior.binding, command, c.epoch)
        if (prior.receipt) return saved(c.auth, command, c.epoch, b, prior.receipt, selected)
        return (
          (await readTerminal(command, c.epoch)) ??
          state(c.owner, id, inputHash, c.epoch, 'pending')
        )
      } catch (e) {
        return sanitize(e)
      }
    },
  })
}
