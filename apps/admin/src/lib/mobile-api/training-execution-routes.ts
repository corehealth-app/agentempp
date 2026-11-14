import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import { createConversationMealReadonlyRuntime } from './conversation-meal-readonly-runtime'
import { MobileApiError, mobileSuccess, readJsonBody } from './http'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import {
  createMobileRoute,
  createMobileRouteWithContext,
  type MobileRouteContext,
  type MobileRouteRuntime,
} from './route'
import { parseTrainingExecutionCommand } from './training-execution-kernel'
import {
  createTrainingExecutionService,
  trainingExecutionCursorSchema,
  trainingExecutionVerifiedLogin,
} from './training-execution-runtime'

interface Service {
  home(cursor?: unknown): Promise<unknown>
  read(id: string): Promise<unknown>
  mutate(command: unknown): Promise<unknown>
}
interface Ports {
  enabled?: () => boolean
  service?: (db: ServiceClient, auth: MobileAuthContext, authorize: () => Promise<void>) => Service
}
const uuid = z
  .string()
  .uuid()
  .transform((v) => v.toLowerCase())
export function trainingExecutionEnabled(env: Record<string, string | undefined> = process.env) {
  return env.MOBILE_TRAINING_EXECUTION_ENABLED === 'true'
}
export function createTrainingExecutionRoutes(ports: Ports = {}, runtime?: MobileRouteRuntime) {
  const base = runtime ?? createConversationMealReadonlyRuntime()
  const fixed: MobileRouteRuntime = Object.freeze({
    authenticate: base.authenticate.bind(base),
    authorizeEntitlement: base.authorizeEntitlement.bind(base),
    createServiceClient: base.createServiceClient.bind(base),
    createRequestId: base.createRequestId.bind(base),
  })
  const enabled = ports.enabled?.bind(ports) ?? trainingExecutionEnabled
  const service = ports.service?.bind(ports) ?? createTrainingExecutionService
  function available() {
    if (enabled() !== true)
      throw new MobileApiError(
        503,
        'training_execution_unavailable',
        'Training execution is unavailable.',
      )
  }
  function binding(context: MobileRouteContext) {
    available()
    const original = structuredClone(context.auth),
      owner = authenticatedReevaluationOwner(original)
    if (uuid.parse(context.request.headers.get('X-Training-Owner')) !== owner)
      throw new MobileApiError(
        409,
        'training_execution_patient_changed',
        'The original patient has changed.',
      )
    const login = trainingExecutionVerifiedLogin(original)
    // Re-authentication needs the original headers/path, not a transfer of the
    // POST body stream (which must remain readable exactly once below).
    const request = new Request(context.request.url, {
      method: context.request.method,
      headers: new Headers(context.request.headers),
    })
    return {
      original,
      owner,
      async authorize() {
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
            'The original patient has changed.',
          )
        await fixed.authorizeEntitlement(current, request, context.supabase)
        available()
      },
    }
  }
  function closedQuery(request: Request, allowCursor: boolean) {
    const query = new URL(request.url).searchParams
    for (const key of query.keys())
      if (!allowCursor || key !== 'cursor' || query.getAll(key).length !== 1)
        throw new MobileApiError(
          422,
          'training_execution_invalid_query',
          'A closed training execution query is required.',
        )
    if (!query.has('cursor')) return undefined
    const raw = query.get('cursor')
    if (raw === null || raw.length > 1024)
      throw new MobileApiError(
        422,
        'training_execution_invalid_query',
        'The training cursor is invalid.',
      )
    try {
      return trainingExecutionCursorSchema.parse(JSON.parse(raw))
    } catch {
      throw new MobileApiError(
        422,
        'training_execution_invalid_query',
        'The training cursor is invalid.',
      )
    }
  }
  const response = (value: unknown, id: string) =>
    mobileSuccess(value, id, 200, { 'X-Training-Execution': '1' })
  return Object.freeze({
    HOME: createMobileRoute(async (context) => {
      const bound = binding(context),
        cursor = closedQuery(context.request, true)
      await bound.authorize()
      const value = await service(context.supabase, bound.original, bound.authorize).home(cursor)
      await bound.authorize()
      return response(value, context.requestId)
    }, fixed),
    GET: createMobileRouteWithContext<{ params: Promise<{ sessionId: string }> }>(
      async (context, route) => {
        const bound = binding(context)
        closedQuery(context.request, false)
        const id = uuid.parse((await route.params).sessionId)
        await bound.authorize()
        const value = await service(context.supabase, bound.original, bound.authorize).read(id)
        await bound.authorize()
        return response(value, context.requestId)
      },
      fixed,
    ),
    POST: createMobileRoute(async (context) => {
      const bound = binding(context)
      closedQuery(context.request, false)
      const command = parseTrainingExecutionCommand(await readJsonBody(context.request, 16384))
      if (uuid.parse(context.request.headers.get('X-Training-Epoch')) !== command.expected_epoch)
        throw new MobileApiError(
          409,
          'training_execution_epoch_changed',
          'The original execution scope has changed.',
        )
      z.literal(`texecution1:${command.operation_id}`).parse(
        context.request.headers.get('Idempotency-Key'),
      )
      await bound.authorize()
      const value = await service(context.supabase, bound.original, bound.authorize).mutate(command)
      await bound.authorize()
      return response(value, context.requestId)
    }, fixed),
  })
}
