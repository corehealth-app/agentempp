import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { conversationMealCommandsEnabled } from './conversation-meal-command-routes'
import { parseConversationMealEditInput } from './conversation-meal-edit-contracts'
import { createConversationMealEditPublicService } from './conversation-meal-edit-public-service'
import { createConversationMealReadonlyRuntime } from './conversation-meal-readonly-runtime'
import { MobileApiError, mobileSuccess, readJsonBody } from './http'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import {
  createMobileRouteWithContext,
  type MobileRouteContext,
  type MobileRouteRuntime,
} from './route'

const uuid = z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u)
const hash = z.string().regex(/^[a-f0-9]{64}$/u)
interface MealRoute {
  params: Promise<{ commandId: string }>
}
interface EditRoute {
  params: Promise<{ commandId: string; operationId: string }>
}
export interface ConversationMealEditPublicRoutePorts {
  readonly enabled?: () => boolean
  readonly service?: (
    db: ServiceClient,
  ) => Pick<
    ReturnType<typeof createConversationMealEditPublicService>,
    'readGroup' | 'execute' | 'reconcile'
  >
}
function requireOriginalPatient(request: Request, patient: string): void {
  const owner = uuid.parse(request.headers.get('X-Conversation-Owner'))
  if (owner !== patient)
    throw new MobileApiError(
      409,
      'conversation_patient_changed',
      'The authenticated patient has changed',
    )
}
function original(request: Request, commandId: string) {
  return {
    commandId: uuid.parse(commandId),
    inputHash: hash.parse(request.headers.get('X-Conversation-Input-Hash')),
    epoch: uuid.parse(request.headers.get('X-Conversation-Epoch')),
  }
}
async function editBody(request: Request, operationId: string) {
  z.literal(`cmedit1:${operationId}`).parse(request.headers.get('Idempotency-Key'))
  const raw = await readJsonBody(request, 16384)
  try {
    return parseConversationMealEditInput(raw)
  } catch {
    throw new MobileApiError(
      422,
      'conversation_meal_edit_invalid',
      'A valid closed edit input is required',
    )
  }
}
function response(value: unknown, requestId: string) {
  return mobileSuccess(value, requestId, 200, { 'X-Conversation-Protocol': 'meal-command-v1' })
}
/** Same explicit current-staging opt-in as command admission. No flag, SQL,
 * provider or app activation is performed by defining these adapters. */
export function createConversationMealEditPublicRoutes(
  ports: ConversationMealEditPublicRoutePorts = {},
  runtime: MobileRouteRuntime = createConversationMealReadonlyRuntime(),
) {
  const enabled = ports.enabled?.bind(ports) ?? conversationMealCommandsEnabled,
    service = ports.service?.bind(ports) ?? createConversationMealEditPublicService,
    reauthenticate = runtime.authenticate.bind(runtime)
  async function scopedResponse(context: MobileRouteContext, work: () => Promise<unknown>) {
    const original = Object.freeze({
      subject: context.auth.authUserId,
      patient: authenticatedReevaluationOwner(context.auth),
      token: context.auth.accessToken,
      // Authentication needs headers only. The reconciliation POST body has
      // already been consumed; it is neither copied nor replayed here.
      request: new Request(context.request.url, { headers: new Headers(context.request.headers) }),
    })
    const value = await work()
    const current = await reauthenticate(original.request, context.supabase)
    if (
      current.accessToken !== original.token ||
      current.authUserId !== original.subject ||
      current.identity.id !== original.subject ||
      current.patient.authUserId !== original.subject ||
      authenticatedReevaluationOwner(current) !== original.patient
    )
      throw new MobileApiError(
        409,
        'conversation_patient_changed',
        'The original authenticated patient has changed',
      )
    return response(value, context.requestId)
  }
  const available = () => {
    if (!enabled())
      throw new MobileApiError(
        503,
        'conversation_commands_unavailable',
        'Conversation command capability is unavailable',
      )
  }
  return Object.freeze({
    GROUP: createMobileRouteWithContext<MealRoute>(async (context, route) => {
      available()
      requireOriginalPatient(context.request, context.auth.userId)
      const identity = original(context.request, (await route.params).commandId)
      return scopedResponse(context, () =>
        service(context.supabase).readGroup(context.auth, identity),
      )
    }, runtime),
    EDIT: createMobileRouteWithContext<EditRoute>(async (context, route) => {
      available()
      requireOriginalPatient(context.request, context.auth.userId)
      const params = await route.params,
        identity = original(context.request, params.commandId),
        operationId = uuid.parse(params.operationId),
        body = await editBody(context.request, operationId)
      return scopedResponse(context, () =>
        service(context.supabase).execute(
          context.auth,
          identity,
          operationId,
          body,
          context.requestId,
        ),
      )
    }, runtime),
    RECONCILE: createMobileRouteWithContext<EditRoute>(async (context, route) => {
      available()
      requireOriginalPatient(context.request, context.auth.userId)
      const params = await route.params,
        identity = original(context.request, params.commandId),
        operationId = uuid.parse(params.operationId),
        body = await editBody(context.request, operationId)
      return scopedResponse(context, () =>
        service(context.supabase).reconcile(context.auth, identity, operationId, body),
      )
    }, runtime),
  })
}
