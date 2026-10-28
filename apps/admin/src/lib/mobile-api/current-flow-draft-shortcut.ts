/** Optional draft shortcut projection, after the original turn/cache. Reads only:
 * never initialize the numeric Flow port or repeat a previously accepted turn. */
import type { ServiceClient } from '@mpp/db'
import { currentClinicalReadBinding } from './current-clinical-read-model'
import { type CurrentClinicalSnapshot, currentClinicalError } from './current-clinical-state'
import {
  bindCurrentFlowDraftAuthority,
  type CurrentFlowDraftAuthority,
  createSupabaseCurrentFlowDraftAuthority,
  currentFlowDraftBinding,
  readCurrentFlowDraftContext,
  readCurrentFlowStoredDraft,
} from './current-flow-draft-authority'
import {
  createSupabaseFlowDraftLookup,
  type FlowDraftLookup,
  type FlowTurnDraft,
  scopedFlowProviderMessageId,
} from './flow-chat-service'

async function checked(
  authority: CurrentFlowDraftAuthority,
  owner: string,
  turn: string,
  candidate: FlowTurnDraft,
  expectedState?: CurrentClinicalSnapshot,
): Promise<FlowTurnDraft | null> {
  const fixed = { id: candidate.id, domain: candidate.domain },
    before = readCurrentFlowDraftContext(await authority.capture(), owner)
  if (
    expectedState &&
    currentClinicalReadBinding(expectedState) !== currentClinicalReadBinding(before.state)
  )
    throw currentClinicalError('changed')
  if (!before.allowed[fixed.domain]) return null
  const requestKey =
      turn + (fixed.domain === 'training' ? ':propoe_plano_treino' : ':propoe_plano_dieta'),
    sourceMessageId = await authority.findTurn({ domain: fixed.domain, requestKey }),
    raw = await authority.lookup({
      domain: fixed.domain,
      requestKey,
      sourceMessageId,
      expected: before,
    })
  if (raw === null) return null
  const stored = readCurrentFlowStoredDraft(raw)
  if (stored.id !== fixed.id || !['needs_completion', 'ready_for_review'].includes(stored.status))
    return null
  const after = readCurrentFlowDraftContext(await authority.capture(), owner)
  if (
    after.state.observed_at < before.state.observed_at ||
    currentFlowDraftBinding(before) !== currentFlowDraftBinding(after)
  )
    throw currentClinicalError('changed')
  return Object.freeze(fixed)
}
export function createCurrentFlowShortcutGuard(owner: string, source: CurrentFlowDraftAuthority) {
  const authority = bindCurrentFlowDraftAuthority(source)
  return async (requestKey: string, candidate: FlowTurnDraft, state: CurrentClinicalSnapshot) =>
    checked(authority, owner, scopedFlowProviderMessageId(owner, requestKey), candidate, state)
}
export function createCurrentFlowDraftLookup(
  owner: string,
  source: CurrentFlowDraftAuthority,
  candidates: FlowDraftLookup,
): FlowDraftLookup {
  const authority = bindCurrentFlowDraftAuthority(source),
    find = candidates.findForTurn.bind(candidates)
  return Object.freeze({
    async findForTurn(userId: string, turn: string) {
      if (userId !== owner) throw currentClinicalError('changed')
      const before = readCurrentFlowDraftContext(await authority.capture(), owner)
      if (!before.allowed.training && !before.allowed.nutrition) return null
      const candidate = await find(owner, turn)
      return candidate === null ? null : checked(authority, owner, turn, candidate, before.state)
    },
  })
}
export function createSupabaseCurrentFlowDraftLookup(
  client: ServiceClient,
  owner: string,
): FlowDraftLookup {
  // The legacy candidate selector reads only id/domain and keeps its ordering.
  // It is location only: the SQL origin/binding check certifies the shortcut.
  const candidateClient = { from: client.from.bind(client) } as unknown as ServiceClient
  return createCurrentFlowDraftLookup(
    owner,
    createSupabaseCurrentFlowDraftAuthority(client, owner),
    createSupabaseFlowDraftLookup(candidateClient),
  )
}
