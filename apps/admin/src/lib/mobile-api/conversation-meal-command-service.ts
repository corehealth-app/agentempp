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
import { createSupabaseConversationFencedJournal } from './conversation-fenced-journal'
import {
  projectSavedConversationMealCommandResult,
  type SavedConversationMealCommandResult,
} from './conversation-meal-command-result'
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
export type ConversationMealCommandReply =
  | SavedConversationMealCommandResult
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
  semantics?: ConversationMealSemanticStore
  createInterpreter?: () => ConversationMealInterpreterPort
  register?: typeof registerPersistedConversationMeal
  presentation?: ConversationMealFeedbackPresentationService
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
  const ps = ports.presentation ?? createSupabaseConversationMealFeedbackPresentation(db),
    readPresentation = ps.readHistorical.bind(ps)
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
  ): Promise<SavedConversationMealCommandResult> => {
    const serverBinding = validatedBinding(rawBinding, command, epoch)
    let feedback: unknown = null
    try {
      feedback = await readPresentation({ auth, command, receipt, serverBinding })
    } catch {
      /* Optional current observation/enrichment never retries a saved effect. */
    }
    return projectSavedConversationMealCommandResult({
      auth,
      command,
      expectedEpoch: epoch,
      serverBinding,
      receipt,
      feedback,
    })
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
          if (prior.receipt) return saved(c.auth, command, c.epoch, b, prior.receipt)
        } else await observe(c.owner, c.epoch)
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
          return saved(c.auth, command, c.epoch, result.serverBinding, result.receipt)
        const current = await journal.read({ ownerId: c.owner, commandId: command.commandId })
        if (current.action !== 'available') return changed()
        validatedBinding(current.binding, command, c.epoch)
        if (!isDeepStrictEqual(current.source, command)) return unavailable()
        const info = decision.parse({
          reason: result.reason,
          food_indexes: [...result.foodIndexes],
        })
        if (new Set(info.food_indexes).size !== info.food_indexes.length) return unavailable()
        return state(c.owner, command.commandId, command.inputHash, c.epoch, 'not_recorded', info)
      } catch (e) {
        return sanitize(e)
      }
    },
    async read(
      auth: MobileAuthContext,
      commandId: string,
      originalHash: string,
      expectedEpoch: string,
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
        if (prior.receipt) return saved(c.auth, command, c.epoch, b, prior.receipt)
        return state(c.owner, id, inputHash, c.epoch, 'pending')
      } catch (e) {
        return sanitize(e)
      }
    },
  })
}
