/** One STABLE RPC. Current Auth is supplied by the request's real sticky lane. */
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import {
  type ConversationJournalV3Outcome,
  type ConversationJournalV3Query,
  conversationJournalV3QuerySchema,
  parseConversationJournalV3Page,
} from './conversation-journal-v3-contracts'
import { workoutSnapshot } from './conversation-workout-contracts'
import { MobileApiError } from './http'
export interface ConversationJournalV3RPCPort {
  rpc(
    name: 'read_conversation_journal_page_v3',
    args: Readonly<Record<string, unknown>>,
  ): PromiseLike<unknown>
}
export interface ConversationJournalV3ScopePort {
  checkCurrentScope(identity: Readonly<{ ownerId: string; epoch: string }>): Promise<boolean>
}
export interface ConversationJournalV3Store {
  read(query: ConversationJournalV3Query): Promise<ConversationJournalV3Outcome>
}
const requiredJSON = z.unknown().refine((value) => value !== undefined),
  envelopeSchema = z.object({ data: requiredJSON, error: requiredJSON }).passthrough()
function unavailable(): never {
  throw new MobileApiError(
    503,
    'conversation_journal_unavailable',
    'Original conversation history is unavailable',
  )
}
export class ConversationJournalV3ScopeRefusal extends MobileApiError {
  constructor() {
    super(503, 'conversation_journal_unavailable', 'Original conversation history is unavailable')
  }
}
export function createConversationJournalV3Store(
  rpcPort: ConversationJournalV3RPCPort,
  scopePort: ConversationJournalV3ScopePort,
): ConversationJournalV3Store {
  if (typeof rpcPort?.rpc !== 'function' || typeof scopePort?.checkCurrentScope !== 'function')
    return unavailable()
  const rpc = rpcPort.rpc.bind(rpcPort),
    observe = scopePort.checkCurrentScope.bind(scopePort)
  let closed = false
  return Object.freeze({
    async read(raw: ConversationJournalV3Query) {
      if (closed) throw new ConversationJournalV3ScopeRefusal()
      let query: ConversationJournalV3Query
      try {
        query = workoutSnapshot(conversationJournalV3QuerySchema.parse(workoutSnapshot(raw)))
      } catch {
        return unavailable()
      }
      const who = workoutSnapshot({ ownerId: query.ownerId, epoch: query.epoch }),
        args = workoutSnapshot({
          p_user_id: who.ownerId,
          p_expected_epoch: who.epoch,
          p_limit: query.limit,
          p_cursor: query.cursor,
        })
      async function current() {
        if (closed) throw new ConversationJournalV3ScopeRefusal()
        try {
          if ((await observe(who)) !== true || closed)
            throw new Error('Original history scope changed')
        } catch {
          closed = true
          throw new ConversationJournalV3ScopeRefusal()
        }
      }
      await current()
      let snapshot: unknown
      try {
        // The post-observer must never see mutable SDK aliases before detaching.
        snapshot = workoutSnapshot(await rpc('read_conversation_journal_page_v3', args))
      } catch {
        await current()
        return unavailable()
      }
      await current()
      try {
        const response = envelopeSchema.parse(snapshot)
        if (response.error !== null) return unavailable()
        return parseConversationJournalV3Page(response.data, query)
      } catch {
        return unavailable()
      }
    },
  })
}
export function createSupabaseConversationJournalV3Store(
  db: ServiceClient,
  scope: ConversationJournalV3ScopePort,
): ConversationJournalV3Store {
  // Generated types do not declare this additive private reader yet.
  const rpc = db.rpc.bind(db) as unknown as ConversationJournalV3RPCPort['rpc']
  return createConversationJournalV3Store({ rpc }, scope)
}
