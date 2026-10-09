/** Dedicated Flow subpath: no IO or consumer activation, no global-barrel catalog. */

import {
  FLOW_CURATED_PHRASE_CATALOG,
  type FlowPhraseCatalog,
} from './flow-curated-phrase-catalog.js'
import {
  createFlowPhraseRotationState,
  type FlowPhraseRequest,
  type FlowPhraseRotationState,
  selectFlowCuratedPhrase,
} from './flow-curated-phrase-selector.js'
import { type FlowPresentationObjective, projectFlowMetricAnswer } from './flow-public-metrics.js'
import { projectFlowPublicNames } from './flow-public-names.js'

export { FLOW_CURATED_PHRASE_CATALOG } from './flow-curated-phrase-catalog.js'
export type { FlowPhraseRequest, FlowPhraseRotationState } from './flow-curated-phrase-selector.js'
export {
  createFlowPhraseRotationState,
  selectFlowCuratedPhrase,
} from './flow-curated-phrase-selector.js'

export type FlowStatusPhraseCursor = Omit<FlowPhraseRotationState, 'replayByEventKey'>
export type FlowStatusPhraseReceipt = FlowPhraseRotationState['replayByEventKey'][string] & {
  eventKey: string
}
export type FlowStatusPhraseReplyRequest = Extract<FlowPhraseRequest, { kind: 'incentive' }> & {
  slot: 'any'
  statusText: string
  authority: FlowPresentationObjective & {
    dailyTargets: { calories_target: number | null; protein_target: number | null }
  }
}

/** New publication only. A persisted event replay must be resolved by its store first. */
export function prepareFlowStatusPhraseReply(
  request: FlowStatusPhraseReplyRequest,
  cursor: FlowStatusPhraseCursor | null,
  catalog: FlowPhraseCatalog = FLOW_CURATED_PHRASE_CATALOG,
): { content: string; nextCursor: FlowStatusPhraseCursor; receipt: FlowStatusPhraseReceipt } {
  if (request.kind !== 'incentive' || request.slot !== 'any') {
    throw new Error('Flow status phrase requires incentive/any')
  }
  if (!request.statusText.trim()) throw new Error('Flow status base is empty')
  const state: FlowPhraseRotationState =
    cursor === null
      ? createFlowPhraseRotationState(request.userId, catalog.version)
      : { ...cursor, replayByEventKey: {} }
  const selected = selectFlowCuratedPhrase(request, state, catalog)
  if (!Object.hasOwn(selected.nextState.replayByEventKey, request.eventKey)) {
    throw new Error(`Unable to prepare Flow status phrase: ${selected.reason}`)
  }
  const receipt = selected.nextState.replayByEventKey[request.eventKey]
  if (!receipt) throw new Error(`Unable to prepare Flow status phrase: ${selected.reason}`)
  const text =
    selected.phrase === null ? request.statusText : `${request.statusText}\n\n${selected.phrase}`
  const named = projectFlowPublicNames(text, { accountName: request.accountName }).text
  const content = projectFlowMetricAnswer(
    named,
    request.authority.dailyTargets,
    request.locale ?? null,
    false,
    undefined,
    { currentProtocol: request.authority.currentProtocol },
  )
  // The private rotation key must identify the phrase the person will actually see.
  if (selected.phrase !== null && !content.endsWith(`\n\n${selected.phrase}`)) {
    throw new Error('Flow status phrase changed during public projection')
  }
  const { replayByEventKey: _receipts, ...nextCursor } = selected.nextState
  return { content, nextCursor, receipt: { eventKey: request.eventKey, ...receipt } }
}
