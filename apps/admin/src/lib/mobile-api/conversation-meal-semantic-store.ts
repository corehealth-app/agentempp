/** Private service-only invocation state. A read/replay never grants permission
 * to call the provider. This transport has no domain writer or retry loop. */
import { isDeepStrictEqual } from 'node:util'
import type { Json, ServiceClient } from '@mpp/db'
import { z } from 'zod'
import {
  type BoundConversationMealCommand,
  bindConversationCommand,
} from './conversation-command-contracts'
import {
  freezeInterpretation,
  MEAL_INTERPRETATION_MAX_BYTES,
  MEAL_INTERPRETER_VERSION,
  mealInterpretationSchema,
} from './conversation-meal-interpretation-contracts'
import { MobileApiError } from './http'

const uuid = z
  .string()
  .uuid()
  .regex(/^[a-f0-9-]+$/u)
const hash = z.string().regex(/^[a-f0-9]{64}$/u)
const json: z.ZodType<Json> = z.lazy(() =>
  z.union([z.null(), z.boolean(), z.string(), z.number().finite(), z.array(json), z.record(json)]),
)
const terminalError = z.enum(['provider_outcome_unknown', 'provider_terminal_error'])
const recordSchema = z
  .object({
    action: z.enum(['claimed', 'available', 'replay', 'committed', 'reconciliation_required']),
    owner_id: uuid,
    command_id: uuid,
    attempt_id: uuid,
    interpreter_version: z.literal(MEAL_INTERPRETER_VERSION),
    input_hash: hash,
    source_hash: hash,
    epoch: uuid,
    status: z.enum(['started', 'completed', 'unknown', 'error']),
    result: mealInterpretationSchema.nullable(),
    result_hash: hash.nullable(),
    started_at: z.string().datetime({ offset: true }),
    finished_at: z.string().datetime({ offset: true }).nullable(),
    error_code: terminalError.nullable(),
  })
  .strict()
export type ConversationMealSemanticRecord = Readonly<z.infer<typeof recordSchema>>
type Refusal = {
  readonly action:
    | 'absent'
    | 'stale_epoch'
    | 'source_required'
    | 'source_conflict'
    | 'day_closed'
    | 'attempt_conflict'
}
export type ConversationMealSemanticOutcome = ConversationMealSemanticRecord | Refusal
export interface ConversationMealSemanticStore {
  read(command: BoundConversationMealCommand): Promise<ConversationMealSemanticOutcome>
  start(
    command: BoundConversationMealCommand,
    sourceHash: string,
  ): Promise<ConversationMealSemanticOutcome>
  commit(
    command: BoundConversationMealCommand,
    attemptId: string,
    result: unknown,
  ): Promise<ConversationMealSemanticOutcome>
  markUnknown(
    command: BoundConversationMealCommand,
    attemptId: string,
    errorCode: 'provider_outcome_unknown' | 'provider_terminal_error',
  ): Promise<ConversationMealSemanticOutcome>
}
function unavailable(): never {
  throw new MobileApiError(
    503,
    'conversation_meal_semantic_unavailable',
    'Meal interpretation state is unavailable',
  )
}
function bound(raw: BoundConversationMealCommand) {
  const copy = structuredClone(raw),
    result = bindConversationCommand(copy.ownerId, `cmsg1:${copy.commandId}`, copy.command)
  if (!isDeepStrictEqual(copy, result)) return unavailable()
  return result
}
function data(raw: unknown) {
  const response = z.object({ data: z.unknown(), error: z.unknown() }).parse(raw)
  if (response.error !== null) return unavailable()
  return structuredClone(response.data)
}
function decode(
  raw: unknown,
  command: BoundConversationMealCommand,
  actions: readonly string[],
  sourceHash?: string,
  attemptId?: string,
  submitted?: Json,
): ConversationMealSemanticOutcome {
  const empty = z
    .object({
      action: z.enum([
        'absent',
        'stale_epoch',
        'source_required',
        'source_conflict',
        'day_closed',
        'attempt_conflict',
      ]),
    })
    .strict()
    .safeParse(raw)
  if (empty.success) {
    if (!actions.includes(empty.data.action)) return unavailable()
    return freezeInterpretation(empty.data)
  }
  const result = recordSchema.parse(raw)
  if (
    !isDeepStrictEqual(raw, result) ||
    !actions.includes(result.action) ||
    result.owner_id !== command.ownerId ||
    result.command_id !== command.commandId ||
    result.input_hash !== command.inputHash ||
    (sourceHash !== undefined && result.source_hash !== sourceHash) ||
    (attemptId !== undefined && result.attempt_id !== attemptId)
  )
    return unavailable()
  const completed = result.status === 'completed'
  if (
    completed !== (result.result !== null && result.result_hash !== null) ||
    (!completed && (result.result !== null || result.result_hash !== null)) ||
    (result.status === 'started') !== (result.finished_at === null) ||
    (result.finished_at !== null &&
      Date.parse(result.finished_at) < Date.parse(result.started_at)) ||
    result.error_code !==
      (result.status === 'unknown'
        ? 'provider_outcome_unknown'
        : result.status === 'error'
          ? 'provider_terminal_error'
          : null) ||
    (result.action === 'claimed' && result.status !== 'started') ||
    (result.action === 'available' && !completed) ||
    (result.action === 'reconciliation_required' && completed) ||
    (result.action === 'committed' && result.status === 'started') ||
    (result.action === 'replay' && result.status === 'started')
  )
    return unavailable()
  const interpretation = result.result
  if (
    interpretation &&
    (interpretation.owner_id !== command.ownerId ||
      interpretation.command_id !== command.commandId ||
      interpretation.attempt_id !== result.attempt_id ||
      interpretation.input_hash !== command.inputHash ||
      interpretation.source_hash !== result.source_hash ||
      new Set(interpretation.source_units).size !== interpretation.source_units.length ||
      Buffer.byteLength(JSON.stringify(interpretation), 'utf8') > MEAL_INTERPRETATION_MAX_BYTES)
  )
    return unavailable()
  // SQL decides the first terminal winner before looking at a later payload.
  // A new success must echo the submitted immutable interpretation exactly.
  if (
    submitted !== undefined &&
    result.action === 'committed' &&
    (result.status !== 'completed' || !isDeepStrictEqual(interpretation, submitted))
  )
    return unavailable()
  return freezeInterpretation(result)
}

export function createSupabaseConversationMealSemanticStore(
  db: ServiceClient,
): ConversationMealSemanticStore {
  const rpc = db.rpc.bind(db)
  return Object.freeze({
    async read(raw: BoundConversationMealCommand) {
      try {
        const command = bound(raw)
        return decode(
          data(
            await rpc('read_conversation_meal_semantic_attempt', {
              p_user_id: command.ownerId,
              p_command_id: command.commandId,
              p_interpreter_version: MEAL_INTERPRETER_VERSION,
            }),
          ),
          command,
          ['available', 'reconciliation_required', 'absent', 'stale_epoch'],
        )
      } catch {
        return unavailable()
      }
    },
    async start(raw: BoundConversationMealCommand, rawHash: string) {
      try {
        const command = bound(raw),
          sourceHash = hash.parse(rawHash)
        return decode(
          data(
            await rpc('start_conversation_meal_semantic_attempt', {
              p_user_id: command.ownerId,
              p_command_id: command.commandId,
              p_interpreter_version: MEAL_INTERPRETER_VERSION,
              p_expected_source_hash: sourceHash,
            }),
          ),
          command,
          [
            'claimed',
            'replay',
            'reconciliation_required',
            'absent',
            'stale_epoch',
            'source_required',
            'source_conflict',
            'day_closed',
          ],
          sourceHash,
        )
      } catch {
        return unavailable()
      }
    },
    async commit(raw: BoundConversationMealCommand, rawAttempt: string, rawResult: unknown) {
      try {
        const command = bound(raw),
          attemptId = uuid.parse(rawAttempt),
          submitted = json.parse(structuredClone(rawResult))
        if (
          !isDeepStrictEqual(rawResult, submitted) ||
          Buffer.byteLength(JSON.stringify(submitted), 'utf8') > MEAL_INTERPRETATION_MAX_BYTES
        )
          return unavailable()
        return decode(
          data(
            await rpc('commit_conversation_meal_semantic_result', {
              p_user_id: command.ownerId,
              p_command_id: command.commandId,
              p_interpreter_version: MEAL_INTERPRETER_VERSION,
              p_attempt_id: attemptId,
              p_result: submitted,
            }),
          ),
          command,
          ['committed', 'replay', 'absent', 'stale_epoch', 'attempt_conflict'],
          undefined,
          attemptId,
          submitted,
        )
      } catch {
        return unavailable()
      }
    },
    async markUnknown(
      raw: BoundConversationMealCommand,
      rawAttempt: string,
      code: 'provider_outcome_unknown' | 'provider_terminal_error',
    ) {
      try {
        const command = bound(raw),
          attemptId = uuid.parse(rawAttempt),
          errorCode = terminalError.parse(code)
        return decode(
          data(
            await rpc('mark_conversation_meal_semantic_unknown', {
              p_user_id: command.ownerId,
              p_command_id: command.commandId,
              p_interpreter_version: MEAL_INTERPRETER_VERSION,
              p_attempt_id: attemptId,
              p_error_code: errorCode,
            }),
          ),
          command,
          ['committed', 'replay', 'absent', 'stale_epoch', 'attempt_conflict'],
          undefined,
          attemptId,
        )
      } catch {
        return unavailable()
      }
    },
  })
}
