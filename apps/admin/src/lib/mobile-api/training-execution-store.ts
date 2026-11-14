/** Backend-only port. No route, client ownership input or automatic retry.
 * A transport failure after commit is uncertain; repeat the SAME operation UUID. */
import { isDeepStrictEqual } from 'node:util'
import { z } from 'zod'
import { MobileApiError } from './http'
import {
  parseTrainingExecutionCommand,
  parseTrainingExecutionPersistence,
  prepareTrainingExecutionMutation,
} from './training-execution-kernel'

export interface TrainingExecutionPersistencePort {
  rpc(
    name: 'capture_training_execution_context' | 'commit_training_execution_mutation',
    args: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: unknown }>
}
const captureSchema = z
  .object({
    context_hash: z.string().regex(/^[0-9a-f]{64}$/),
    context: z
      .object({
        plan: z.unknown().nullable(),
        scope: z.unknown(),
        session: z.unknown().nullable(),
        prior_receipt: z.unknown().nullable(),
      })
      .strict(),
  })
  .strict()
function unavailable(): never {
  throw new MobileApiError(
    503,
    'training_execution_store_unavailable',
    'Training progress is unavailable. Retry the same operation after reconnecting.',
  )
}
export function createTrainingExecutionStore(
  port: TrainingExecutionPersistencePort,
  identity: { owner: string; auth: string },
) {
  const original = Object.freeze(
    z.object({ owner: z.string().uuid(), auth: z.string().uuid() }).strict().parse(identity),
  )
  async function rpc(
    name: Parameters<TrainingExecutionPersistencePort['rpc']>[0],
    args: Record<string, unknown>,
  ) {
    let result: Awaited<ReturnType<TrainingExecutionPersistencePort['rpc']>>
    try {
      result = await port.rpc(name, args)
    } catch (error) {
      if (error instanceof MobileApiError) throw error
      return unavailable()
    }
    if (result.error != null) {
      const code = z.object({ code: z.string() }).passthrough().safeParse(result.error)
      if (code.success && code.data.code === '42501')
        throw new MobileApiError(
          401,
          'training_execution_auth_unavailable',
          'The original login session is no longer available.',
        )
      if (code.success && code.data.code === '40001')
        throw new MobileApiError(
          409,
          'training_execution_context_changed',
          'Refresh the original training session before changing it.',
        )
      return unavailable()
    }
    return result.data
  }
  async function capture(session: string, operation: string) {
    const data = await rpc('capture_training_execution_context', {
      p_user_id: original.owner,
      p_auth_user_id: original.auth,
      p_session_id: session,
      p_operation_id: operation,
    })
    try {
      if (Buffer.byteLength(JSON.stringify(data), 'utf8') > 1048576) return unavailable()
      return captureSchema.parse(data)
    } catch {
      return unavailable()
    }
  }
  return Object.freeze({
    /** Internal server context only; not an HTTP response DTO. */
    async read(session: string) {
      const id = z.string().uuid().parse(session).toLowerCase()
      return capture(id, id)
    },
    async mutate(rawCommand: unknown) {
      const command = parseTrainingExecutionCommand(rawCommand)
      const captured = await capture(command.session_id, command.operation_id)
      const prepared = prepareTrainingExecutionMutation({ ...captured.context, command })
      if (
        prepared.session.owner_id !== original.owner ||
        prepared.session.auth_user_id !== original.auth
      )
        return unavailable()
      const data = await rpc('commit_training_execution_mutation', {
        p_user_id: original.owner,
        p_auth_user_id: original.auth,
        p_command: command,
        p_context_hash: captured.context_hash,
        p_observed_at: prepared.session.updated_at,
        p_prepared: prepared,
      })
      const result = parseTrainingExecutionPersistence(data, command, original)
      if (result.status !== 'replayed' && !isDeepStrictEqual(result, prepared)) return unavailable()
      if (prepared.status === 'replayed' && !isDeepStrictEqual(result.receipt, prepared.receipt))
        return unavailable()
      return result
    },
  })
}
