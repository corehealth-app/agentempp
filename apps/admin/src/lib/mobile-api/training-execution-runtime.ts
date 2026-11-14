import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import { MobileApiError } from './http'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { trainingExecutionInstant } from './training-execution-instant'
import {
  projectTrainingExecutionPlan,
  readTrainingExecutionScope,
  readTrainingExecutionSession,
} from './training-execution-kernel'
import {
  createTrainingExecutionStore,
  type TrainingExecutionPersistencePort,
} from './training-execution-store'

const uuid = z
  .string()
  .uuid()
  .transform((v) => v.toLowerCase())
export const trainingExecutionCursorSchema = z
  .object({
    owner_id: uuid,
    epoch: uuid,
    time_zone: z.string().min(1).max(100),
    updated_at: z.string().datetime({ offset: true }),
    session_id: uuid,
  })
  .strict()
const summarySchema = z
  .object({
    id: uuid,
    revision: z.number().int().min(0),
    local_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    started_at: z.string().datetime({ offset: true }),
    updated_at: z.string().datetime({ offset: true }),
    plan_id: uuid,
    day_index: z.number().int().min(0).max(6),
    day_label: z.string().min(1).max(80),
    total_exercises: z.number().int().min(1).max(20),
    completed_exercises: z.number().int().min(0).max(20),
  })
  .strict()
const homeCaptureSchema = z
  .object({
    scope: z.unknown(),
    plan: z.unknown().nullable(),
    sessions: z.array(summarySchema).max(20),
    next_cursor: trainingExecutionCursorSchema.nullable(),
  })
  .strict()
/** Only called after the runtime's real Supabase getUser verification. Decode
 * the signed token's login reference, never ownership/roles from JWT metadata. */
export function trainingExecutionVerifiedLogin(auth: MobileAuthContext) {
  try {
    const pieces = auth.accessToken.split('.'),
      encoded = pieces[1]
    if (
      pieces.length !== 3 ||
      auth.accessToken.length > 16384 ||
      typeof encoded !== 'string' ||
      !/^[A-Za-z0-9_-]+$/.test(encoded)
    )
      throw Error()
    const claims = z
      .object({ sub: uuid, session_id: uuid })
      .passthrough()
      .parse(JSON.parse(Buffer.from(encoded, 'base64url').toString('utf8')))
    if (
      claims.sub !== auth.authUserId ||
      auth.identity.id !== claims.sub ||
      auth.patient.authUserId !== claims.sub
    )
      throw Error()
    return claims.session_id
  } catch {
    throw new MobileApiError(
      401,
      'training_execution_auth_unavailable',
      'A valid original login session is required.',
    )
  }
}
function unavailable(): never {
  throw new MobileApiError(
    503,
    'training_execution_unavailable',
    'Training execution is unavailable. Refresh before continuing.',
  )
}
export function createTrainingExecutionService(
  db: ServiceClient,
  originalAuth: MobileAuthContext,
  authorize: () => Promise<void>,
) {
  const auth = structuredClone(originalAuth),
    owner = authenticatedReevaluationOwner(auth),
    login = trainingExecutionVerifiedLogin(auth)
  const raw = db as unknown as {
    rpc(name: string, args: Record<string, unknown>): PromiseLike<{ data: unknown; error: unknown }>
  }
  const call = async (name: string, args: Record<string, unknown>) => {
    await authorize()
    return raw.rpc(name, { ...args, p_auth_session_id: login })
  }
  const port: TrainingExecutionPersistencePort = {
    rpc(name, args) {
      return call(`${name}_authenticated`, args)
    },
  }
  const store = createTrainingExecutionStore(port, { owner, auth: auth.authUserId })
  function originalScope(value: unknown) {
    const s = readTrainingExecutionScope(value)
    if (s.owner_id !== owner || s.auth_user_id !== auth.authUserId) return unavailable()
    return s
  }
  return Object.freeze({
    async home(rawCursor?: unknown) {
      const cursor = rawCursor === undefined ? null : trainingExecutionCursorSchema.parse(rawCursor)
      const result = await call('read_training_execution_home_authenticated', {
        p_user_id: owner,
        p_auth_user_id: auth.authUserId,
        p_cursor: cursor,
      })
      if (result.error != null) {
        const e = z.object({ code: z.string() }).passthrough().safeParse(result.error)
        if (e.success && e.data.code === '42501')
          throw new MobileApiError(
            401,
            'training_execution_auth_unavailable',
            'The original login session is no longer available.',
          )
        if (e.success && e.data.code === '40001')
          throw new MobileApiError(
            409,
            'training_execution_scope_changed',
            'Refresh the original training scope.',
          )
        return unavailable()
      }
      let input: z.infer<typeof homeCaptureSchema>
      try {
        if (Buffer.byteLength(JSON.stringify(result.data), 'utf8') > 1048576) return unavailable()
        input = homeCaptureSchema.parse(result.data)
      } catch {
        return unavailable()
      }
      const scope = originalScope(input.scope),
        tail = input.sessions.at(-1)
      if (
        new Set(input.sessions.map((s) => s.id)).size !== input.sessions.length ||
        input.sessions.some(
          (s) =>
            s.completed_exercises > s.total_exercises ||
            s.local_date > scope.current_local_date ||
            trainingExecutionInstant(s.started_at) > trainingExecutionInstant(s.updated_at) ||
            trainingExecutionInstant(s.updated_at) > trainingExecutionInstant(scope.observed_at),
        )
      )
        return unavailable()
      if (
        input.next_cursor &&
        (input.sessions.length !== 20 ||
          !tail ||
          input.next_cursor.owner_id !== owner ||
          input.next_cursor.epoch !== scope.epoch ||
          input.next_cursor.time_zone !== scope.time_zone ||
          input.next_cursor.updated_at !== tail.updated_at ||
          input.next_cursor.session_id !== tail.id)
      )
        return unavailable()
      return {
        schema: 'training.execution-home.v1' as const,
        scope,
        plan: input.plan === null ? null : projectTrainingExecutionPlan(input.plan, scope),
        sessions: input.sessions,
        next_cursor: input.next_cursor,
      }
    },
    async read(id: string) {
      const context = (await store.read(id)).context,
        scope = originalScope(context.scope)
      if (context.session === null)
        throw new MobileApiError(
          404,
          'training_execution_not_found',
          'Training execution is not available in this account.',
        )
      return {
        schema: 'training.execution-read.v1' as const,
        scope,
        session: readTrainingExecutionSession(context.session, scope),
      }
    },
    mutate: store.mutate,
  })
}
