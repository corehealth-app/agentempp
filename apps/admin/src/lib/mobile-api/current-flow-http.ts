/** Closed opt-in Flow boundary. Default routes remain untouched until atomic activation. */
import { flowClinicalGuidanceAllowed, type MobileFlowClinicalPort } from '@mpp/agent'
import type { FlowPresentationObjective } from '@mpp/agent/flow-public-metrics'
import type { ServiceClient } from '@mpp/db'
import {
  type FlowChatRouteDependencies,
  handleFlowChatGet,
  handleFlowChatPost,
  publicMessage,
} from '@/app/api/mobile/v1/flow/chat/handler'
import { readClinicalRepresentation } from './clinical-representation'
import { flowChatInputSchema, flowChatLimitSchema } from './contracts'
import {
  currentClinicalReadBinding,
  projectCurrentClinicalPublicPolicy,
  requireCurrentClinicalRepresentation,
} from './current-clinical-read-model'
import {
  type CurrentClinicalSnapshot,
  captureCurrentClinicalState,
  currentClinicalError,
  projectCurrentClinicalState,
  readCurrentClinicalState,
} from './current-clinical-state'
import {
  type CurrentFlowClinicalDependencies,
  createCurrentFlowClinicalPort,
} from './current-flow-clinical-port'
import { bindCurrentFlowDraftAuthority } from './current-flow-draft-authority'
import { createCurrentFlowShortcutGuard } from './current-flow-draft-shortcut'
import type { FlowChatDependencies } from './flow-chat-service'
import { MobileApiError, readJsonBody } from './http'
import { requireIdempotencyKey } from './idempotency'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { createMobileRoute, type MobileRouteContext, type MobileRouteRuntime } from './route'

export interface CurrentFlowHttpDependencies {
  clinical: CurrentFlowClinicalDependencies
  createChatDependencies(
    context: MobileRouteContext,
    clinical: MobileFlowClinicalPort,
  ): FlowChatDependencies
  loadHistory: FlowChatRouteDependencies['loadHistory']
  sendMessage: FlowChatRouteDependencies['sendMessage']
  executeIdempotent: FlowChatRouteDependencies['executeIdempotent']
  now(): Date
}
function record(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === 'object' && !Array.isArray(value)
}
function freeze<T>(value: T): T {
  if (value && typeof value === 'object') {
    for (const v of Object.values(value)) freeze(v)
    Object.freeze(value)
  }
  return value
}
function objective(state: CurrentClinicalSnapshot): FlowPresentationObjective {
  return {
    currentProtocol: state.phase_origin.kind === 'assigned' ? state.phase_origin.phase : null,
    clinicalPolicy: projectCurrentClinicalPublicPolicy(state),
  }
}
export function createCurrentFlowRoutes(
  options: {
    readonly enabled: boolean
    createDependencies(client: ServiceClient, owner: string): CurrentFlowHttpDependencies
  },
  runtime?: MobileRouteRuntime,
) {
  const enabled = options.enabled === true,
    createDependencies = options.createDependencies.bind(options)
  const fixed =
    runtime &&
    Object.freeze({
      authenticate: runtime.authenticate.bind(runtime),
      authorizeEntitlement: runtime.authorizeEntitlement.bind(runtime),
      createServiceClient: runtime.createServiceClient.bind(runtime),
      createRequestId: runtime.createRequestId.bind(runtime),
    })
  function scope(raw: MobileRouteContext, method: 'GET' | 'POST') {
    if (!enabled) throw new MobileApiError(404, 'current_flow_disabled', 'Current Flow unavailable')
    const request = raw.request.clone(),
      url = request.url,
      auth = freeze(structuredClone(raw.auth)),
      owner = authenticatedReevaluationOwner(auth),
      representation = readClinicalRepresentation(url)
    const keys = [...representation.search.keys()]
    if (
      keys.some((key) => method === 'POST' || key !== 'limit') ||
      representation.search.getAll('limit').length > 1
    )
      throw new MobileApiError(422, 'validation_failed', 'Unexpected query parameter')
    if (method === 'GET') flowChatLimitSchema.parse(representation.search.get('limit') ?? '50')
    const clean = new URL(url)
    clean.searchParams.delete('clinical_policy')
    const context = Object.freeze({ ...raw, auth, request: new Request(clean, request) })
    const supplied = createDependencies(context.supabase, owner),
      source = Object.freeze({
        capture: supplied.clinical.state.capture.bind(supplied.clinical.state),
      })
    const clinical = Object.freeze({
      admission: supplied.clinical.admission
        ? Object.freeze({
            establish: supplied.clinical.admission.establish.bind(supplied.clinical.admission),
          })
        : undefined,
      state: source,
      createReadModel: supplied.clinical.createReadModel.bind(supplied.clinical),
      applyDaily: supplied.clinical.applyDaily.bind(supplied.clinical),
      closeDays: supplied.clinical.closeDays.bind(supplied.clinical),
      periodRows: supplied.clinical.periodRows.bind(supplied.clinical),
      drafts: bindCurrentFlowDraftAuthority(supplied.clinical.drafts),
    })
    const createChat = supplied.createChatDependencies.bind(supplied),
      loadHistory = supplied.loadHistory.bind(supplied),
      sendMessage = supplied.sendMessage.bind(supplied),
      executeIdempotent = supplied.executeIdempotent.bind(supplied),
      now = supplied.now.bind(supplied)
    // The port always reads current authority internally. Legacy HTTP clients are
    // independently gated before and after the operation; no legacy formula port.
    const internal = new URL(url)
    internal.searchParams.set('clinical_policy', 'current_clinical_v1')
    const internalContext = Object.freeze({
      ...context,
      request: new Request(internal, context.request.clone()),
    })
    let port: ReturnType<typeof createCurrentFlowClinicalPort> | undefined
    const inner = () => (port ??= createCurrentFlowClinicalPort(internalContext, clinical))
    const lazyPort = Object.freeze({
      read: () => inner().read(),
      period: (p: 'semana' | 'mes') => inner().period(p),
      revalidate: () => inner().revalidate(),
      drafts: Object.freeze({
        lookup: (input: Parameters<NonNullable<MobileFlowClinicalPort['drafts']>['lookup']>[0]) =>
          inner().drafts.lookup(input),
        create: (input: Parameters<NonNullable<MobileFlowClinicalPort['drafts']>['create']>[0]) =>
          inner().drafts.create(input),
      }),
    })
    return {
      context,
      owner,
      representation,
      source,
      admission: clinical.admission,
      shortcut: createCurrentFlowShortcutGuard(owner, clinical.drafts),
      dependencies: (before: CurrentClinicalSnapshot): FlowChatRouteDependencies =>
        Object.freeze({
          createChatDependencies: () => createChat(internalContext, lazyPort),
          loadHistory,
          sendMessage,
          executeIdempotent,
          now,
          loadPresentationContext: async () => objective(before),
        }),
    }
  }
  async function capture(s: ReturnType<typeof scope>) {
    return captureCurrentClinicalState(s.source, { userId: s.owner, mode: 'profile' })
  }
  function requireFlowRepresentation(s: ReturnType<typeof scope>, state: CurrentClinicalSnapshot) {
    requireCurrentClinicalRepresentation(
      projectCurrentClinicalState(state),
      s.representation.compatible,
    )
  }
  async function establish(s: ReturnType<typeof scope>) {
    const before = await capture(s)
    requireFlowRepresentation(s, before)
    const state = s.admission
      ? readCurrentClinicalState(await s.admission.establish(before, s.source), s.owner)
      : before
    requireFlowRepresentation(s, state)
    return state
  }
  function unchanged(before: CurrentClinicalSnapshot, after: CurrentClinicalSnapshot) {
    if (
      after.observed_at < before.observed_at ||
      currentClinicalReadBinding(before) !== currentClinicalReadBinding(after)
    )
      throw currentClinicalError('changed')
  }
  async function present(
    s: ReturnType<typeof scope>,
    response: Response,
    method: 'GET' | 'POST',
    before: CurrentClinicalSnapshot,
  ) {
    if (!response.ok) return response
    let packet: unknown
    try {
      packet = await response.clone().json()
    } catch {
      throw currentClinicalError('invalid_response')
    }
    if (
      !record(packet) ||
      !record(packet.data) ||
      packet.data.conversation_id !== 'flow' ||
      !record(packet.meta) ||
      packet.meta.api_version !== 'v1'
    )
      throw currentClinicalError('invalid_response')
    let after = await capture(s)
    unchanged(before, after)
    requireFlowRepresentation(s, after)
    const data = structuredClone(packet.data)
    if (method === 'GET') {
      if (!Array.isArray(data.messages)) throw currentClinicalError('invalid_response')
      data.messages = data.messages.map((message) =>
        publicMessage(message, s.context.auth.patient.locale, objective(after)),
      )
    } else {
      if (!record(data.message) || data.message.role !== 'assistant')
        throw currentClinicalError('invalid_response')
      if (data.draft !== null && data.draft !== undefined) {
        if (
          !record(data.draft) ||
          typeof data.draft.id !== 'string' ||
          (data.draft.domain !== 'training' && data.draft.domain !== 'nutrition')
        )
          throw currentClinicalError('invalid_response')
        if (
          !flowClinicalGuidanceAllowed(projectCurrentClinicalPublicPolicy(after), data.draft.domain)
        )
          data.draft = null
        else {
          try {
            data.draft = await s.shortcut(
              requireIdempotencyKey(s.context.request),
              { id: data.draft.id, domain: data.draft.domain },
              after,
            )
          } catch {
            data.draft = null
          } // Optional lookup cannot repeat/revoke the accepted turn.
          const final = await capture(s)
          unchanged(after, final)
          requireFlowRepresentation(s, final)
          after = final
        }
      }
      data.message = publicMessage(
        data.message,
        s.context.auth.patient.locale,
        objective(after),
        record(data.draft),
      )
    }
    if (s.representation.compatible)
      data.clinical_policy = projectCurrentClinicalPublicPolicy(after)
    else delete data.clinical_policy
    const headers = new Headers(response.headers)
    headers.delete('Content-Length')
    return Response.json(
      { ...packet, data },
      { status: response.status, statusText: response.statusText, headers },
    )
  }
  const GET = createMobileRoute(async (raw) => {
    const s = scope(raw, 'GET'),
      before = await establish(s)
    const response = await handleFlowChatGet(s.context, s.dependencies(before))
    return present(s, response, 'GET', before)
  }, fixed)
  const POST = createMobileRoute(async (raw) => {
    const s = scope(raw, 'POST')
    requireIdempotencyKey(s.context.request)
    flowChatInputSchema.parse(await readJsonBody(s.context.request.clone(), 16 * 1024))
    const before = await establish(s)
    const response = await handleFlowChatPost(s.context, s.dependencies(before))
    if (!response.ok) return response
    // A fresh presentation observation starts AFTER the accepted command/cache.
    // Failure here must never release an accepted HTTP claim or resend the turn.
    const presentation = await capture(s)
    requireFlowRepresentation(s, presentation)
    return present(s, response, 'POST', presentation)
  }, fixed)
  return Object.freeze({ GET, POST })
}
