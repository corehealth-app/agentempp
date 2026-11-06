/** Authenticated neutral transport. Server configuration selects capability;
 * request JSON cannot choose a typed writer, owner, epoch or factual result. */
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import {
  type ConversationFeedbackPresentationNegotiation,
  conversationFeedbackPresentationMobileHeaders,
  negotiateConversationFeedbackPresentation,
} from './conversation-feedback-presentation-negotiation'
import { bindConversationIntake, conversationIntakeSchema } from './conversation-intake-contracts'
import type { ConversationIntakeLookup } from './conversation-intake-driver'
import { createOpenRouterConversationIntakeRouter } from './conversation-intake-router'
import { createConversationIntakeRuntime } from './conversation-intake-runtime'
import { createConversationIntakeSessionService } from './conversation-intake-session'
import { conversationMealCommandsEnabled } from './conversation-meal-command-routes'
import { createConversationMealReadonlyRuntime } from './conversation-meal-readonly-runtime'
import { conversationWorkoutCommandsEnabled } from './conversation-workout-command-routes'
import { workoutHash, workoutUUID } from './conversation-workout-contracts'
import { MobileApiError, mobileSuccess, readJsonBody } from './http'
import { createMobileRoute, createMobileRouteWithContext, type MobileRouteRuntime } from './route'

export function conversationIntakesEnabled(
  env: Record<string, string | undefined> = process.env,
): boolean {
  return (
    env.MOBILE_CONVERSATION_INTAKES_ENABLED === 'true' &&
    conversationMealCommandsEnabled(env) &&
    conversationWorkoutCommandsEnabled(env)
  )
}
export interface ConversationIntakeRoutePorts {
  readonly enabled?: () => boolean
  readonly service?: (
    db: ServiceClient,
    auth: MobileAuthContext,
    original: ConversationIntakeLookup,
  ) => Pick<ReturnType<typeof createConversationIntakeRuntime>, 'submit' | 'read'>
  readonly session?: (
    db: ServiceClient,
  ) => Pick<ReturnType<typeof createConversationIntakeSessionService>, 'read'>
}
interface IntakeRouteContext {
  params: Promise<{ intakeId: string }>
}
type Reply = Awaited<
  ReturnType<ReturnType<typeof createConversationIntakeRuntime>['submit' | 'read']>
>
function response(
  result: Reply,
  requestId: string,
  selected: ConversationFeedbackPresentationNegotiation,
) {
  const waiting =
    result.status === 'pending' ||
    result.status === 'held' ||
    (result.status === 'selected' && result.result.status === 'pending')
  return mobileSuccess(result, requestId, waiting ? 202 : 200, {
    'X-Conversation-Protocol': 'intake-v1',
    ...conversationFeedbackPresentationMobileHeaders(selected),
  })
}
function requireOriginalPatient(request: Request, owner: string) {
  if (workoutUUID.parse(request.headers.get('X-Conversation-Owner')) !== owner)
    throw new MobileApiError(
      409,
      'conversation_patient_changed',
      'The authenticated patient has changed',
    )
}
export function createConversationIntakeRoutes(
  ports: ConversationIntakeRoutePorts = {},
  runtime?: MobileRouteRuntime,
) {
  const readonlyRuntime = runtime ?? createConversationMealReadonlyRuntime(),
    enabled = ports.enabled?.bind(ports) ?? conversationIntakesEnabled,
    service =
      ports.service?.bind(ports) ??
      ((db, auth, original) =>
        createConversationIntakeRuntime(db, auth, original, {
          enabled,
          // Construction is lazy and synchronous. Provider work occurs only after
          // the actual intake driver's durable routing claim, never on GET/session.
          createRouter: () =>
            createOpenRouterConversationIntakeRouter(process.env.OPENROUTER_API_KEY ?? ''),
        })),
    session =
      ports.session?.bind(ports) ??
      ((db) => createConversationIntakeSessionService(db, { enabled })),
    available = () => {
      if (enabled() !== true)
        throw new MobileApiError(
          503,
          'conversation_intake_unavailable',
          'Conversation intake capability is unavailable',
        )
    }
  return Object.freeze({
    SESSION: createMobileRoute(async (context) => {
      available()
      return mobileSuccess(
        await session(context.supabase).read(context.auth),
        context.requestId,
        200,
        {
          'X-Conversation-Protocol': 'intake-v1',
        },
      )
    }, readonlyRuntime),
    POST: createMobileRoute(async (context) => {
      available()
      requireOriginalPatient(context.request, context.auth.userId)
      const epoch = workoutUUID.parse(context.request.headers.get('X-Conversation-Epoch')),
        body = conversationIntakeSchema.parse(await readJsonBody(context.request, 16384)),
        key = z
          .literal(`cintake1:${body.intake_id}`)
          .parse(context.request.headers.get('Idempotency-Key')),
        bound = bindConversationIntake(context.auth.userId, key, body),
        original = {
          ownerId: bound.ownerId,
          intakeId: bound.intakeId,
          inputHash: bound.inputHash,
          epoch,
        },
        selected = negotiateConversationFeedbackPresentation(context.request.headers)
      available()
      return response(
        await service(context.supabase, context.auth, original).submit(bound, selected),
        context.requestId,
        selected,
      )
    }, readonlyRuntime),
    GET: createMobileRouteWithContext<IntakeRouteContext>(async (context, route) => {
      available()
      requireOriginalPatient(context.request, context.auth.userId)
      const epoch = workoutUUID.parse(context.request.headers.get('X-Conversation-Epoch')),
        inputHash = workoutHash.parse(context.request.headers.get('X-Conversation-Input-Hash')),
        intakeId = workoutUUID.parse((await route.params).intakeId),
        original = { ownerId: context.auth.userId, intakeId, inputHash, epoch },
        selected = negotiateConversationFeedbackPresentation(context.request.headers)
      available()
      return response(
        await service(context.supabase, context.auth, original).read(selected),
        context.requestId,
        selected,
      )
    }, readonlyRuntime),
  })
}
