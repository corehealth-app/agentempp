/** Separate protocol family. No old progress route/DTO/header is widened. */
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import { createConversationMealReadonlyRuntime } from './conversation-meal-readonly-runtime'
import { conversationWorkoutCommandsEnabled } from './conversation-workout-command-routes'
import { workoutHash, workoutUUID } from './conversation-workout-contracts'
import { MobileApiError, mobileSuccess, readJsonBody } from './http'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import {
  createMobileRoute,
  createMobileRouteWithContext,
  type MobileRouteContext,
  type MobileRouteRuntime,
} from './route'
import { parseTrainingExecutionCompletionCommand } from './training-execution-completion-contracts'
import {
  createTrainingExecutionCompletionService,
  type TrainingExecutionCompletionIdentity,
} from './training-execution-completion-runtime'
import { parseTrainingExecutionCommand } from './training-execution-kernel'
import { trainingExecutionEnabled } from './training-execution-routes'
import {
  trainingExecutionCursorSchema,
  trainingExecutionVerifiedLogin,
} from './training-execution-runtime'

interface Service {
  progress(key: string | null, body: unknown): Promise<unknown>
  home(cursor?: unknown): Promise<unknown>
  state(session: string, epoch: string): Promise<unknown>
  submit(key: string | null, body: unknown): Promise<unknown>
  read(identity: TrainingExecutionCompletionIdentity): Promise<unknown>
  cancel(identity: TrainingExecutionCompletionIdentity): Promise<unknown>
}
interface Ports {
  enabled?: () => boolean
  service?: (db: ServiceClient, auth: MobileAuthContext, authorize: () => Promise<void>) => Service
}
interface Path {
  params: Promise<{ sessionId: string; completionId?: string }>
}
const cancelSchema = z
  .object({
    schema: z.literal('training.execution.finish-cancel.v1'),
    session_id: workoutUUID,
    completion_id: workoutUUID,
    expected_epoch: workoutUUID,
    input_hash: workoutHash,
  })
  .strict()
export function trainingExecutionCompletionEnabled(
  env: Record<string, string | undefined> = process.env,
) {
  return (
    env.MOBILE_TRAINING_COMPLETION_ENABLED === 'true' &&
    trainingExecutionEnabled(env) &&
    conversationWorkoutCommandsEnabled(env)
  )
}
export function createTrainingExecutionCompletionRoutes(
  ports: Ports = {},
  runtime?: MobileRouteRuntime,
) {
  const base = runtime ?? createConversationMealReadonlyRuntime()
  const fixed: MobileRouteRuntime = Object.freeze({
    authenticate: base.authenticate.bind(base),
    authorizeEntitlement: base.authorizeEntitlement.bind(base),
    createServiceClient: base.createServiceClient.bind(base),
    createRequestId: base.createRequestId.bind(base),
  })
  const enabled = ports.enabled?.bind(ports) ?? trainingExecutionCompletionEnabled,
    service = ports.service?.bind(ports) ?? createTrainingExecutionCompletionService
  function available() {
    if (enabled() !== true)
      throw new MobileApiError(
        503,
        'training_completion_unavailable',
        'Training completion is not enabled.',
      )
  }
  function binding(context: MobileRouteContext) {
    available()
    const original = structuredClone(context.auth),
      owner = authenticatedReevaluationOwner(original),
      login = trainingExecutionVerifiedLogin(original)
    if (workoutUUID.parse(context.request.headers.get('X-Training-Owner')) !== owner)
      throw new MobileApiError(
        409,
        'training_execution_patient_changed',
        'The original patient has changed.',
      )
    const request = new Request(context.request.url, {
      method: context.request.method,
      headers: new Headers(context.request.headers),
    })
    async function authorize() {
      available()
      const current = await fixed.authenticate(request, context.supabase)
      if (
        current.accessToken !== original.accessToken ||
        current.authUserId !== original.authUserId ||
        current.identity.id !== original.authUserId ||
        current.patient.authUserId !== original.authUserId ||
        authenticatedReevaluationOwner(current) !== owner ||
        trainingExecutionVerifiedLogin(current) !== login
      )
        throw new MobileApiError(
          409,
          'training_execution_patient_changed',
          'The original authenticated patient has changed.',
        )
      await fixed.authorizeEntitlement(current, request, context.supabase)
      available()
    }
    return { authorize, original, service: () => service(context.supabase, original, authorize) }
  }
  function query(request: Request, home = false) {
    const search = new URL(request.url).searchParams
    for (const key of search.keys())
      if (!home || key !== 'cursor' || search.getAll(key).length !== 1)
        throw new MobileApiError(
          422,
          'training_completion_invalid_query',
          'A closed training query is required.',
        )
    const raw = search.get('cursor')
    if (raw === null) return undefined
    try {
      if (raw.length > 1024) throw Error()
      return trainingExecutionCursorSchema.parse(JSON.parse(raw))
    } catch {
      throw new MobileApiError(
        422,
        'training_execution_invalid_cursor',
        'The original history cursor is invalid.',
      )
    }
  }
  const epoch = (r: Request) => workoutUUID.parse(r.headers.get('X-Training-Epoch'))
  const response = (value: unknown, id: string) =>
    mobileSuccess(
      value,
      id,
      typeof value === 'object' &&
        value !== null &&
        'status' in value &&
        value.status === 'reserved'
        ? 202
        : 200,
      { 'X-Training-Execution': '2', 'X-Training-Completion': '1' },
    )
  return Object.freeze({
    HOME: createMobileRoute(async (c) => {
      const b = binding(c),
        cursor = query(c.request, true)
      await b.authorize()
      const value = await b.service().home(cursor)
      await b.authorize()
      return response(value, c.requestId)
    }, fixed),
    PROGRESS: createMobileRouteWithContext<Path>(async (c, p) => {
      const b = binding(c)
      query(c.request)
      const command = parseTrainingExecutionCommand(await readJsonBody(c.request, 16384)),
        path = await p.params,
        key = c.request.headers.get('Idempotency-Key')
      if (
        command.session_id !== workoutUUID.parse(path.sessionId) ||
        command.expected_epoch !== epoch(c.request)
      )
        throw new MobileApiError(
          409,
          'training_execution_scope_changed',
          'The original progress session has changed.',
        )
      z.literal(`texecution1:${command.operation_id}`).parse(key)
      await b.authorize()
      const value = await b.service().progress(key, command)
      await b.authorize()
      return response(value, c.requestId)
    }, fixed),
    STATE: createMobileRouteWithContext<Path>(async (c, p) => {
      const b = binding(c)
      query(c.request)
      const id = workoutUUID.parse((await p.params).sessionId),
        e = epoch(c.request)
      await b.authorize()
      const value = await b.service().state(id, e)
      await b.authorize()
      return response(value, c.requestId)
    }, fixed),
    POST: createMobileRoute(async (c) => {
      const b = binding(c)
      query(c.request)
      const command = parseTrainingExecutionCompletionCommand(await readJsonBody(c.request, 16384)),
        e = epoch(c.request),
        key = c.request.headers.get('Idempotency-Key')
      if (command.expected_epoch !== e)
        throw new MobileApiError(
          409,
          'training_execution_epoch_changed',
          'The original training scope has changed.',
        )
      z.literal(`tfinish1:${command.operation_id}`).parse(key)
      await b.authorize()
      const value = await b.service().submit(key, command)
      await b.authorize()
      return response(value, c.requestId)
    }, fixed),
    READ: createMobileRouteWithContext<Path>(async (c, p) => {
      const b = binding(c)
      query(c.request)
      const path = await p.params
      const identity = {
        session_id: workoutUUID.parse(path.sessionId),
        completion_id: workoutUUID.parse(path.completionId),
        epoch: epoch(c.request),
        input_hash: workoutHash.parse(c.request.headers.get('X-Training-Completion-Hash')),
      }
      await b.authorize()
      const value = await b.service().read(identity)
      await b.authorize()
      return response(value, c.requestId)
    }, fixed),
    CANCEL: createMobileRouteWithContext<Path>(async (c, p) => {
      const b = binding(c)
      query(c.request)
      const path = await p.params,
        body = cancelSchema.parse(await readJsonBody(c.request, 1024))
      if (
        body.session_id !== workoutUUID.parse(path.sessionId) ||
        body.completion_id !== workoutUUID.parse(path.completionId) ||
        body.expected_epoch !== epoch(c.request)
      )
        throw new MobileApiError(
          409,
          'training_completion_changed',
          'The original completion scope has changed.',
        )
      z.literal(`tcancel1:${body.completion_id}`).parse(c.request.headers.get('Idempotency-Key'))
      const identity = {
        session_id: body.session_id,
        completion_id: body.completion_id,
        epoch: body.expected_epoch,
        input_hash: body.input_hash,
      }
      await b.authorize()
      const value = await b.service().cancel(identity)
      await b.authorize()
      return response(value, c.requestId)
    }, fixed),
  })
}
