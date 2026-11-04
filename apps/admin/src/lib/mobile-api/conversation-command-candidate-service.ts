/** Durable candidate preparation only. No registration, daily effect, message,
 * reward, feedback or receipt-sealing writer is reachable through this service. */
import { isDeepStrictEqual } from 'node:util'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import {
  conversationJournalUnavailable,
  encodeConversationCandidate,
} from './conversation-command-candidate-contracts'
import {
  type BoundConversationMealCommand,
  bindConversationCommand,
} from './conversation-command-contracts'
import {
  type ConversationCommandJournal,
  type ConversationJournalRead,
  createSupabaseConversationCommandJournal,
} from './conversation-command-journal'
import { prepareConversationMealDraft } from './conversation-meal-preparation'
import { MobileApiError } from './http'
import { createSupabaseIdempotencyStore, type MobileIdempotencyStore } from './idempotency'
import type { MealDraftDependencies } from './meal-draft-service'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'

export interface ConversationCandidateDependencies {
  journal?: ConversationCommandJournal
  /** Existing distributed 10-minute work lease, never the permanent replay authority. */
  work?: MobileIdempotencyStore
  preparation: MealDraftDependencies
  prepare?: typeof prepareConversationMealDraft
}
function stale(): never {
  throw new MobileApiError(409, 'conversation_command_stale', 'This command is no longer active')
}
function conflict(): never {
  throw new MobileApiError(
    409,
    'conversation_command_conflict',
    'The command identity has different content',
  )
}
function inProgress(): never {
  throw new MobileApiError(
    409,
    'conversation_candidate_in_progress',
    'This command is still being prepared',
  )
}
function checkedRead(
  value: ConversationJournalRead,
  command: BoundConversationMealCommand,
): ConversationJournalRead {
  if (value.action === 'stale_epoch') return stale()
  if (
    value.action === 'available' &&
    (!isDeepStrictEqual(value.source, command) ||
      value.binding.input_hash !== command.inputHash ||
      value.binding.owner_id !== command.ownerId ||
      value.binding.command_id !== command.commandId)
  )
    return conflict()
  return value
}
function persisted(value: ConversationJournalRead): boolean {
  return (
    value.action === 'available' && value.state === 'candidate_attached' && value.candidate !== null
  )
}
/** Reopening/status only. It never initializes a command, lease or preparation. */
export async function readPersistedConversationMealCandidate(
  db: ServiceClient,
  auth: MobileAuthContext,
  commandId: string,
  journal: Pick<ConversationCommandJournal, 'read'> = createSupabaseConversationCommandJournal(db),
): Promise<ConversationJournalRead> {
  const ownerId = authenticatedReevaluationOwner(structuredClone(auth))
  const id = z
    .string()
    .uuid()
    .regex(/^[0-9a-f-]+$/u)
    .parse(commandId)
  return journal.read({ ownerId, commandId: id })
}
export async function preparePersistedConversationMealCandidate(
  db: ServiceClient,
  auth: MobileAuthContext,
  idempotencyKey: string | null,
  raw: unknown,
  dependencies: ConversationCandidateDependencies,
): Promise<ConversationJournalRead> {
  const who = structuredClone(auth)
  const owner = authenticatedReevaluationOwner(who)
  let command: BoundConversationMealCommand
  try {
    command = bindConversationCommand(owner, idempotencyKey, raw)
  } catch {
    throw new MobileApiError(
      422,
      'conversation_command_invalid',
      'A valid command identity and source are required',
    )
  }
  // Snapshot callbacks and dependency containers before the first await.
  const j = dependencies.journal ?? createSupabaseConversationCommandJournal(db)
  const journal = { read: j.read.bind(j), admit: j.admit.bind(j), attach: j.attach.bind(j) }
  const w = dependencies.work ?? createSupabaseIdempotencyStore(db)
  const work = { claim: w.claim.bind(w), complete: w.complete.bind(w) }
  const p = dependencies.preparation
  const preparation: MealDraftDependencies = Object.freeze({
    media: Object.freeze({ findOwned: p.media.findOwned.bind(p.media) }),
    extractor: p.extractor
      ? Object.freeze({ extract: p.extractor.extract.bind(p.extractor) })
      : null,
    confidenceThreshold: p.confidenceThreshold.bind(p),
  })
  const prepare = dependencies.prepare ?? prepareConversationMealDraft
  const read = async () =>
    checkedRead(await journal.read({ ownerId: owner, commandId: command.commandId }), command)
  let claimId: string | null = null
  let complete = false
  const finishWork = async () => {
    if (claimId && !complete) {
      complete = true
      try {
        await work.complete(claimId, owner, 200, {
          command_id: command.commandId,
          candidate_attached: true,
        })
      } catch {
        /* The durable candidate already won. HTTP-cache loss cannot repeat preparation. */
      }
    }
  }
  try {
    let current = await read()
    if (persisted(current)) return current
    if (current.action === 'absent') {
      try {
        const admission = await journal.admit(command)
        if (admission.action === 'stale_epoch') return stale()
        if (admission.action === 'input_conflict') return conflict()
      } catch (error) {
        // Admission may have committed before the response was lost. Recover
        // only by read; no blind second admission or preparation without proof.
        if (error instanceof MobileApiError && error.status === 409) throw error
        current = await read()
        if (current.action === 'absent') return conversationJournalUnavailable()
      }
      current = await read()
      if (persisted(current)) return current
      if (current.action === 'absent') return conversationJournalUnavailable()
    }
    // This lease limits distributed inference work only. Permanent journal
    // read above always wins, including beyond the HTTP cache's 24-hour TTL.
    const lease = await work.claim({
      userId: owner,
      idempotencyKey: `candidate:cmsg1:${command.commandId}`,
      method: 'POST',
      route: '/api/mobile/v1/conversation/commands/candidate',
      requestHash: command.inputHash,
    })
    if (lease.action === 'conflict') return conflict()
    if (lease.action !== 'claimed') {
      current = await read()
      if (persisted(current)) return current
      return inProgress()
    }
    claimId = lease.claimId
    // Another worker could have attached just before this fresh/expired lease.
    current = await read()
    if (persisted(current)) {
      await finishWork()
      return current
    }
    if (current.action === 'absent') return conversationJournalUnavailable()
    const result = await prepare(
      preparation,
      structuredClone(who),
      `cmsg1:${command.commandId}`,
      command.command,
    )
    const candidate = encodeConversationCandidate(command, result)
    try {
      const attached = await journal.attach(command, candidate.candidate)
      if (attached.action === 'stale_epoch') return stale()
      if (attached.action === 'input_conflict') return conflict()
      if (attached.action === 'absent') return conversationJournalUnavailable()
      // A concurrent first writer may win with a different candidate. Its
      // immutable result is canonical; do not overwrite/re-extract it.
    } catch (error) {
      if (error instanceof MobileApiError && error.status === 409) throw error
      current = await read()
      if (!persisted(current)) return conversationJournalUnavailable()
      await finishWork()
      return current
    }
    current = await read()
    if (!persisted(current)) return conversationJournalUnavailable()
    await finishWork()
    return current
  } catch (error) {
    if (claimId && !complete) {
      // A failed provider/cache response must not erase a result that another
      // worker stored. Return that result if a single reconciliation proves it.
      try {
        const saved = await read()
        if (persisted(saved)) {
          await finishWork()
          return saved
        }
      } catch {
        /* Keep the original conflict/unavailability, never private provider text. */
      }
      // The existing cache reuses row IDs after lease expiry; it cannot prove
      // this attempt still owns the acquisition. Never release a newer worker's
      // lease by that shared ID. An unresolved lease expires normally in 10m.
    }
    if (error instanceof MobileApiError && [403, 404, 409, 422].includes(error.status)) throw error
    return conversationJournalUnavailable()
  }
}
