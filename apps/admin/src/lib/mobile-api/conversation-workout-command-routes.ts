/** Separate workout transport; the original meal DTO/protocol stays literal.
 * Target selection is server configuration, never request authority. */
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import {
  type ConversationFeedbackPresentationNegotiation,
  conversationFeedbackPresentationMobileHeaders,
  negotiateConversationFeedbackPresentation,
} from './conversation-feedback-presentation-negotiation'
import { createConversationMealReadonlyRuntime } from './conversation-meal-readonly-runtime'
import { createConversationWorkoutCommandService } from './conversation-workout-command-service'
import {
  conversationWorkoutCommandSchema,
  workoutHash,
  workoutUUID,
} from './conversation-workout-contracts'
import { resolveCurrentClinicalRuntime } from './current-clinical-runtime-switch'
import { MobileApiError, mobileSuccess, readJsonBody } from './http'
import { createMobileRoute, createMobileRouteWithContext, type MobileRouteRuntime } from './route'
import { resolveWorkoutRegistration } from './workout-registration-switch'

export function conversationWorkoutCommandsEnabled(
  env: Record<string, string | undefined> = process.env,
): boolean {
  return (
    env.MOBILE_CONVERSATION_WORKOUT_COMMANDS_ENABLED === 'true' &&
    env.MOBILE_CONVERSATION_COMMANDS_ENABLED === 'true' &&
    resolveCurrentClinicalRuntime(env).mode === 'current' &&
    resolveWorkoutRegistration(env)
  )
}
export interface ConversationWorkoutCommandRoutePorts {
  readonly enabled?: () => boolean
  readonly service?: (
    db: ServiceClient,
  ) => Pick<
    ReturnType<typeof createConversationWorkoutCommandService>,
    'submit' | 'read' | 'session'
  >
}
interface CommandRouteContext {
  params: Promise<{ commandId: string }>
}
type Reply = Awaited<
  ReturnType<ReturnType<typeof createConversationWorkoutCommandService>['submit' | 'read']>
>
function response(
  result: Reply,
  requestId: string,
  selected: ConversationFeedbackPresentationNegotiation,
) {
  return mobileSuccess(result, requestId, result.status === 'pending' ? 202 : 200, {
    'X-Conversation-Protocol': 'workout-command-v1',
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
export function createConversationWorkoutCommandRoutes(
  ports: ConversationWorkoutCommandRoutePorts = {},
  runtime?: MobileRouteRuntime,
) {
  const readonlyRuntime = runtime ?? createConversationMealReadonlyRuntime(),
    enabled = ports.enabled?.bind(ports) ?? conversationWorkoutCommandsEnabled,
    service = ports.service?.bind(ports) ?? createConversationWorkoutCommandService,
    available = () => {
      if (!enabled())
        throw new MobileApiError(
          503,
          'conversation_workouts_unavailable',
          'Conversation workout capability is unavailable',
        )
    }
  return Object.freeze({
    SESSION: createMobileRoute(async (context) => {
      available()
      return mobileSuccess(
        await service(context.supabase).session(context.auth),
        context.requestId,
        200,
        {
          'X-Conversation-Protocol': 'workout-command-v1',
        },
      )
    }, readonlyRuntime),
    POST: createMobileRoute(async (context) => {
      available()
      requireOriginalPatient(context.request, context.auth.userId)
      const epoch = workoutUUID.parse(context.request.headers.get('X-Conversation-Epoch')),
        command = conversationWorkoutCommandSchema.parse(
          await readJsonBody(context.request, 16384),
        ),
        key = z
          .literal(`cmsg1:${command.command_id}`)
          .parse(context.request.headers.get('Idempotency-Key'))
      const selected = negotiateConversationFeedbackPresentation(context.request.headers),
        api = service(context.supabase)
      return response(
        selected === '2'
          ? await api.submit(context.auth, key, command, epoch, selected)
          : await api.submit(context.auth, key, command, epoch),
        context.requestId,
        selected,
      )
    }, readonlyRuntime),
    GET: createMobileRouteWithContext<CommandRouteContext>(async (context, route) => {
      available()
      requireOriginalPatient(context.request, context.auth.userId)
      const epoch = workoutUUID.parse(context.request.headers.get('X-Conversation-Epoch')),
        inputHash = workoutHash.parse(context.request.headers.get('X-Conversation-Input-Hash')),
        commandId = workoutUUID.parse((await route.params).commandId)
      const selected = negotiateConversationFeedbackPresentation(context.request.headers),
        api = service(context.supabase)
      return response(
        selected === '2'
          ? await api.read(context.auth, commandId, inputHash, epoch, selected)
          : await api.read(context.auth, commandId, inputHash, epoch),
        context.requestId,
        selected,
      )
    }, readonlyRuntime),
  })
}
