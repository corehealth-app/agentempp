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
import {
  type ConversationIntakeMediaNegotiation,
  conversationIntakeMediaEnabled,
  negotiateConversationIntakeMedia,
} from './conversation-intake-media-negotiation'
import { createOpenRouterConversationIntakeRouter } from './conversation-intake-router'
import { createConversationIntakeRuntime } from './conversation-intake-runtime'
import { createConversationIntakeSessionService } from './conversation-intake-session'
import { conversationMealCommandsEnabled } from './conversation-meal-command-routes'
import { createConversationMealReadonlyRuntime } from './conversation-meal-readonly-runtime'
import {
  CONVERSATION_TURNS_HEADER,
  conversationTurnRepliesRequested,
} from './conversation-turn-replies'
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
  readonly mediaEnabled?: () => boolean
  readonly service?: (
    db: ServiceClient,
    auth: MobileAuthContext,
    original: ConversationIntakeLookup,
    turns?: boolean,
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
  selectedMedia: ConversationIntakeMediaNegotiation = 'legacy',
  turns = false,
) {
  const waiting =
    result.status === 'pending' ||
    result.status === 'held' ||
    (result.status === 'selected' && result.result.status === 'pending')
  const headers = conversationFeedbackPresentationMobileHeaders(selected)
  const vary = [
    headers.Vary ?? 'Authorization',
    ...(selectedMedia === '1' ? ['X-Conversation-Media-Provenance'] : []),
    ...(turns ? [CONVERSATION_TURNS_HEADER] : []),
  ].join(', ')
  return mobileSuccess(result, requestId, waiting ? 202 : 200, {
    'X-Conversation-Protocol': 'intake-v1',
    ...headers,
    ...(selectedMedia === '1'
      ? {
          'X-Conversation-Media-Provenance': '1',
        }
      : {}),
    ...(turns ? { [CONVERSATION_TURNS_HEADER]: '1' } : {}),
    Vary: vary,
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
    mediaEnabled = ports.mediaEnabled?.bind(ports) ?? conversationIntakeMediaEnabled,
    service =
      ports.service?.bind(ports) ??
      ((db, auth, original, turnRepliesEnabled = false) =>
        createConversationIntakeRuntime(db, auth, original, {
          enabled,
          mediaEnabled,
          turnRepliesEnabled,
          privateMediaCatalogEnabled: () =>
            process.env.MOBILE_CONVERSATION_PRIVATE_CATALOG_ENABLED === 'true',
          // Construction is lazy and synchronous. Provider work occurs only after
          // the actual intake driver's durable routing claim, never on GET/session.
          createRouter: () =>
            createOpenRouterConversationIntakeRouter(
              process.env.OPENROUTER_API_KEY ?? '',
              undefined,
              undefined,
              async (ownerId, date) => {
                const { data, error } = await db
                  .from('daily_snapshots')
                  .select('day_closed')
                  .eq('user_id', ownerId)
                  .eq('date', date)
                  .maybeSingle()
                return !error && data?.day_closed === true
              },
            ),
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
        selected = negotiateConversationFeedbackPresentation(context.request.headers),
        selectedMedia = negotiateConversationIntakeMedia(context.request.headers),
        turns = conversationTurnRepliesRequested(context.request.headers)
      available()
      return response(
        await (turns
          ? service(context.supabase, context.auth, original, true).submit(
              bound,
              selected,
              selectedMedia,
              true,
            )
          : selectedMedia === 'legacy'
            ? service(context.supabase, context.auth, original).submit(bound, selected)
            : service(context.supabase, context.auth, original).submit(
                bound,
                selected,
                selectedMedia,
              )),
        context.requestId,
        selected,
        selectedMedia,
        turns,
      )
    }, readonlyRuntime),
    GET: createMobileRouteWithContext<IntakeRouteContext>(async (context, route) => {
      available()
      requireOriginalPatient(context.request, context.auth.userId)
      const epoch = workoutUUID.parse(context.request.headers.get('X-Conversation-Epoch')),
        inputHash = workoutHash.parse(context.request.headers.get('X-Conversation-Input-Hash')),
        intakeId = workoutUUID.parse((await route.params).intakeId),
        original = { ownerId: context.auth.userId, intakeId, inputHash, epoch },
        selected = negotiateConversationFeedbackPresentation(context.request.headers),
        selectedMedia = negotiateConversationIntakeMedia(context.request.headers),
        turns = conversationTurnRepliesRequested(context.request.headers)
      available()
      return response(
        await (turns
          ? service(context.supabase, context.auth, original, true).read(
              selected,
              selectedMedia,
              true,
            )
          : selectedMedia === 'legacy'
            ? service(context.supabase, context.auth, original).read(selected)
            : service(context.supabase, context.auth, original).read(selected, selectedMedia)),
        context.requestId,
        selected,
        selectedMedia,
        turns,
      )
    }, readonlyRuntime),
  })
}
