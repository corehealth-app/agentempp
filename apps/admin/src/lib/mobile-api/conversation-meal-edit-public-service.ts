/** Dormant authenticated facade. Read reconciliation never invokes the writer;
 * factual ACK projection does not depend on refreshed group/Today/education. */
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import {
  bindConversationMealEdit,
  bindConversationMealEditIdentity,
  type ConversationMealEditBinding,
} from './conversation-meal-edit-contracts'
import {
  type PublicConversationMealEditReply,
  projectConversationMealEditAbsent,
  projectConversationMealEditResult,
  projectConversationMealGroup,
} from './conversation-meal-edit-public'
import {
  type ConversationMealEditOriginal,
  createConversationMealEditService,
} from './conversation-meal-edit-service'
import {
  type ConversationMealEditStore,
  createSupabaseConversationMealEditStore,
} from './conversation-meal-edit-store'
import { freezeConversationWriter } from './conversation-meal-writer-contracts'
import { MobileApiError } from './http'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'

const uuid = z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u)
const originalSchema = z
  .object({ commandId: uuid, inputHash: z.string().regex(/^[a-f0-9]{64}$/u), epoch: uuid })
  .strict()
export interface ConversationMealEditPublicPorts {
  readonly store?: ConversationMealEditStore
  readonly writer?: Pick<ReturnType<typeof createConversationMealEditService>, 'execute'>
}
function refuse(action: string): never {
  throw new MobileApiError(
    409,
    `conversation_meal_edit_${action}`,
    'The meal edit state has changed; reconcile before continuing',
  )
}
function identity(auth: MobileAuthContext, original: ConversationMealEditOriginal) {
  const who = freezeConversationWriter(structuredClone(auth)),
    ownerId = authenticatedReevaluationOwner(who)
  try {
    const raw = originalSchema.parse(structuredClone(original))
    return {
      auth: who,
      original: freezeConversationWriter(raw),
      binding: bindConversationMealEditIdentity({ ownerId, ...raw }),
    }
  } catch {
    throw new MobileApiError(
      422,
      'conversation_meal_edit_invalid',
      'A valid original command identity is required',
    )
  }
}
function operation(binding: ConversationMealEditBinding, operationId: string, input: unknown) {
  try {
    return bindConversationMealEdit({ binding, operationId, input: structuredClone(input) })
  } catch {
    throw new MobileApiError(
      422,
      'conversation_meal_edit_invalid',
      'A valid original edit identity and closed input are required',
    )
  }
}
export function createConversationMealEditPublicService(
  db: ServiceClient,
  ports: ConversationMealEditPublicPorts = {},
) {
  const source = ports.store ?? createSupabaseConversationMealEditStore(db)
  const store: ConversationMealEditStore = Object.freeze({
    readState: source.readState.bind(source),
    readOperation: source.readOperation.bind(source),
    save: source.save.bind(source),
    undoSave: source.undoSave.bind(source),
    undoRegistration: source.undoRegistration.bind(source),
  })
  const writer = ports.writer ?? createConversationMealEditService(db, { store }),
    execute = writer.execute.bind(writer)
  return Object.freeze({
    async readGroup(auth: MobileAuthContext, original: ConversationMealEditOriginal) {
      const b = identity(auth, original),
        read = await store.readState(b.binding)
      if (read.action !== 'available') return refuse(read.action)
      return projectConversationMealGroup(b.auth, b.binding, read)
    },
    async execute(
      auth: MobileAuthContext,
      original: ConversationMealEditOriginal,
      operationId: string,
      rawInput: unknown,
      requestId: string,
    ) {
      const b = identity(auth, original),
        op = operation(b.binding, operationId, rawInput)
      const saved = await execute(b.auth, b.original, op.operationId, op.input, requestId)
      return projectConversationMealEditResult(b.auth, op, saved)
    },
    async reconcile(
      auth: MobileAuthContext,
      original: ConversationMealEditOriginal,
      operationId: string,
      rawInput: unknown,
    ): Promise<PublicConversationMealEditReply> {
      const b = identity(auth, original),
        op = operation(b.binding, operationId, rawInput)
      const read = await store.readOperation({
        binding: op.binding,
        operationId: op.operationId,
        input: op.input,
      })
      if (read.action === 'available')
        return projectConversationMealEditResult(b.auth, op, {
          status: 'saved',
          binding: read.binding,
          operationId: op.operationId,
          inputHash: op.inputHash,
          receipt: read.receipt,
        })
      if (read.action !== 'absent') return refuse(read.action)
      // The operation RPC's absent union contains no actual command binding.
      // One additional read proves current owner/epoch/original hash; a reset
      // between these reads cannot be retagged into a new absent intent.
      const current = await store.readState(op.binding)
      if (current.action !== 'available') return refuse(current.action)
      return projectConversationMealEditAbsent(b.auth, op, current.binding)
    },
  })
}
