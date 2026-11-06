/** Inert, private BFF adapter for the stored SQL source. No admission, daily
 * initialization, semantic authority, domain writer or public route lives here. */
import { isDeepStrictEqual } from 'node:util'
import type {
  MealCalculationAuditEvent,
  MealCalculationAuditSink,
  MealHistoryRow,
  MealNutritionSourceReader,
} from '@mpp/agent'
import type { Json, ServiceClient } from '@mpp/db'
import { z } from 'zod'
import {
  type BoundConversationMealCommand,
  bindConversationCommand,
  conversationMealExecutionCommandSchema,
} from './conversation-command-contracts'
import {
  assertConversationIntakeMediaCapture,
  conversationIntakeMediaProjectionSchema,
} from './conversation-intake-media-origin'
import { MobileApiError } from './http'

const uuid = z
  .string()
  .uuid()
  .regex(/^[0-9a-f-]+$/u)
const hash = z.string().regex(/^[a-f0-9]{64}$/u)
const finite = z.number().finite()
const json: z.ZodType<Json> = z.lazy(() =>
  z.union([z.null(), z.boolean(), z.string(), finite, z.array(json), z.record(json)]),
)
const jsonObject = z.record(json)
const legacyContextSchema = z
  .object({
    schema: z.literal('conversation.meal-source.v1'),
    owner_id: uuid,
    command_id: uuid,
    input_hash: hash,
    epoch: uuid,
    source_input: conversationMealExecutionCommandSchema,
    source_units: z
      .array(z.enum(['command_text', 'media_caption', 'media_transcript', 'vision_items']))
      .min(1)
      .max(4),
    source_evidence: jsonObject,
    media: jsonObject.nullable(),
    catalog: jsonObject,
    owner: jsonObject,
    clinical: jsonObject,
    day: jsonObject,
  })
  .strict()
const contextSchema = z.union([
  legacyContextSchema,
  legacyContextSchema
    .extend({
      schema: z.literal('conversation.meal-source.v2'),
      source_input: conversationMealExecutionCommandSchema,
      source_units: z
        .array(
          z.enum([
            'command_text',
            'media_caption',
            'media_context',
            'media_transcript',
            'vision_items',
          ]),
        )
        .min(1)
        .max(4),
      intake_projection: conversationIntakeMediaProjectionSchema,
    })
    .strict(),
])
type SourceContext = z.infer<typeof contextSchema>
export interface ConversationMealSourceReceipt {
  readonly id: string
  readonly hash: string
}
export interface CapturedConversationMealSource {
  readonly action: 'captured' | 'replay'
  readonly sourceHash: string
  readonly capturedAt: string
  readonly epoch: string
  /** Private stored context, NOT a CurrentClinicalAuthority or public feedback.
   * Deeper clinical/semantic validation belongs to the future preparer. */
  readonly context: Readonly<SourceContext>
  readonly sourceReader: MealNutritionSourceReader
  sourceReceipts(): readonly ConversationMealSourceReceipt[]
  readonly auditSink: MealCalculationAuditSink
  auditEvents(): readonly MealCalculationAuditEvent[]
}
export interface ConversationMealSourceFactory {
  /** Caller must first admit the command. SQL checks its current durable epoch. */
  capture(command: BoundConversationMealCommand): Promise<CapturedConversationMealSource>
}

class SourceFailure extends MobileApiError {
  constructor(code = 'unavailable', status = 503) {
    super(status, `conversation_meal_source_${code}`, 'Conversation meal source is unavailable')
  }
}
function refuse(error?: unknown): never {
  if (error instanceof SourceFailure) throw error
  throw new SourceFailure()
}
function freeze<T>(value: T): T {
  if (value !== null && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child)
    Object.freeze(value)
  }
  return value
}
function detached<T>(value: T): T {
  return freeze(structuredClone(value))
}

/** Nanosecond comparison preserves PostgreSQL sub-millisecond boundaries;
 * Date.parse alone would admit a row one microsecond after the cutoff. */
function instant(value: string): bigint {
  const match =
    /^(\d{4}-\d{2}-\d{2})T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.(\d{1,9}))?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)$/u.exec(
      value,
    )
  if (!match || value.startsWith('0000')) return refuse()
  const civil = new Date(`${match[1]}T00:00:00.000Z`),
    time = Date.parse(value)
  if (
    !Number.isFinite(civil.getTime()) ||
    civil.toISOString().slice(0, 10) !== match[1] ||
    !Number.isFinite(time)
  )
    return refuse()
  return BigInt(time) * 1_000_000n + BigInt((match[2] ?? '').padEnd(9, '0').slice(3))
}
const clock = z.string().refine((value) => {
  try {
    instant(value)
    return true
  } catch {
    return false
  }
})
const captureSchema = z
  .object({
    action: z.enum(['captured', 'replay']),
    source_hash: hash,
    captured_at: clock,
    context: contextSchema,
  })
  .strict()
const rowSchema = z
  .object({
    id: uuid,
    user_id: uuid,
    created_at: clock,
    food_name: z.string(),
    food_db_id: finite.int().safe().nullable(),
    quantity_g: finite.nullable(),
    kcal: finite.nullable(),
    protein_g: finite.nullable(),
    carbs_g: finite.nullable(),
    fat_g: finite.nullable(),
    source: z.enum(['canonical_exact', 'canonical_fuzzy', 'user_kcal']),
    food_db: z.object({ is_verified: z.boolean().nullable() }).strict().nullable(),
  })
  .strict()
const lookupSchema = z
  .object({
    action: z.enum(['captured', 'replay']),
    owner_id: uuid,
    command_id: uuid,
    source_receipt_id: uuid,
    source_receipt_hash: hash,
    as_of: clock,
    rows: z.array(rowSchema).max(50),
  })
  .strict()
const auditSchema = z
  .object({
    user_id: uuid,
    event: z.enum([
      'meal_calc.approved_nutrition_rejected',
      'meal_calc.user_kcal_rejected',
      'meal_calc.history_reused',
    ]),
    properties: z.record(json.optional()),
  })
  .strict()
function bound(raw: BoundConversationMealCommand): BoundConversationMealCommand {
  const original = structuredClone(raw)
  const command = bindConversationCommand(
    original.ownerId,
    `cmsg1:${original.commandId}`,
    original.command,
  )
  if (!isDeepStrictEqual(command, original)) return refuse()
  return detached(command)
}
function rpcData(raw: unknown, refusals: readonly string[]): unknown {
  const envelope = z.object({ data: z.unknown(), error: z.unknown() }).parse(raw)
  if (envelope.error !== null) {
    const code =
      envelope.error && typeof envelope.error === 'object' && 'code' in envelope.error
        ? envelope.error.code
        : null
    if (code === '55P03') throw new SourceFailure('busy')
    if (code === '40001') throw new SourceFailure('conflict', 409)
    return refuse()
  }
  const value = structuredClone(envelope.data)
  if (
    value &&
    typeof value === 'object' &&
    'action' in value &&
    refusals.includes(String(value.action))
  ) {
    const refusal = z
      .object({ action: z.enum(refusals as [string, ...string[]]) })
      .strict()
      .parse(value)
    throw new SourceFailure(refusal.action, 409)
  }
  return value
}
function validateLookup(
  kind: string,
  foodName: unknown,
): asserts kind is 'trusted_recent' | 'exact_median' {
  if (kind === 'trusted_recent' && foodName === null) return
  if (
    kind === 'exact_median' &&
    typeof foodName === 'string' &&
    foodName.length <= 250 &&
    foodName.trim().length &&
    !Array.from(foodName).some((char) => {
      const n = char.charCodeAt(0)
      return (n < 32 && ![9, 10, 13].includes(n)) || n === 127
    })
  )
    return
  return refuse()
}

export function createSupabaseConversationMealSourceFactory(
  db: ServiceClient,
): ConversationMealSourceFactory {
  // Capture the actual SDK method, not a later mutable property lookup.
  const rpc = db.rpc.bind(db)
  return Object.freeze({
    async capture(original: BoundConversationMealCommand): Promise<CapturedConversationMealSource> {
      try {
        const command = bound(original)
        const rawCapture = rpcData(
          await rpc('capture_conversation_meal_source', {
            p_user_id: command.ownerId,
            p_command_id: command.commandId,
          }),
          ['absent', 'stale_epoch', 'day_closed'],
        )
        return createConversationMealStoredSourcePorts(
          rpc as ConversationMealNutritionRpc,
          command,
          rawCapture,
          { kind: 'original' },
        )
      } catch (error) {
        return refuse(error)
      }
    },
  })
}

/** Internal shared source-port seam. The lookup protocol is closed; it never
 * captures or supplies Auth/source/write authority. The original factory and
 * linked-source adapter must first validate their actual stored bindings. */
export type ConversationMealNutritionRpc = (
  ...args:
    | [
        name: 'read_conversation_meal_nutrition_source',
        args: {
          p_user_id: string
          p_command_id: string
          p_kind: string
          p_food_name: string | null
        },
      ]
    | [
        name: 'read_conversation_meal_continuation_nutrition_source',
        args: {
          p_user_id: string
          p_reply_id: string
          p_kind: string
          p_food_name: string | null
        },
      ]
) => PromiseLike<unknown>
const portLookup = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('original') }).strict(),
  z.object({ kind: z.literal('continuation'), replyId: uuid }).strict(),
])
export function createConversationMealStoredSourcePorts(
  rpc: ConversationMealNutritionRpc,
  original: BoundConversationMealCommand,
  rawCapture: unknown,
  rawLookup: z.infer<typeof portLookup>,
): CapturedConversationMealSource {
  try {
    const command = bound(original),
      lookup = portLookup.parse(structuredClone(rawLookup))
    const nutritionCommandId = lookup.kind === 'original' ? command.commandId : lookup.replyId
    const captured = captureSchema.parse(rawCapture)
    // Opaque private JSON must survive validation unchanged. A decoder
    // dropping a reserved key is a refusal, never a rewritten SQL source.
    if (!isDeepStrictEqual(captured, rawCapture)) return refuse()
    const context = captured.context
    if (
      context.owner_id !== command.ownerId ||
      context.command_id !== command.commandId ||
      context.input_hash !== command.inputHash ||
      !isDeepStrictEqual(context.source_input, command.command) ||
      new Set(context.source_units).size !== context.source_units.length
    )
      return refuse()
    if (
      command.command.source.channel === 'text' &&
      (!isDeepStrictEqual(context.source_units, ['command_text']) || context.media !== null)
    )
      return refuse()
    if ('intake_origin' in command.command) assertConversationIntakeMediaCapture(command, context)
    else if (context.schema !== 'conversation.meal-source.v1') return refuse()
    const asOf = captured.captured_at,
      cutoff = instant(asOf)
    const receipts = new Map<string, ConversationMealSourceReceipt>()
    const lookups = new Map<string, { id: string; hash: string; rows: readonly MealHistoryRow[] }>()
    const receiptLookups = new Map<string, string>()
    const audits: MealCalculationAuditEvent[] = []
    const sourceReader: MealNutritionSourceReader = Object.freeze({
      ownerId: command.ownerId,
      asOf,
      async read(
        kind: 'trusted_recent' | 'exact_median',
        foodName: string | null,
      ): Promise<readonly MealHistoryRow[]> {
        try {
          validateLookup(kind, foodName)
          const key = JSON.stringify([kind, foodName])
          const result = lookupSchema.parse(
            rpcData(
              lookup.kind === 'original'
                ? await rpc('read_conversation_meal_nutrition_source', {
                    p_user_id: command.ownerId,
                    p_command_id: command.commandId,
                    p_kind: kind,
                    p_food_name: foodName,
                  })
                : await rpc('read_conversation_meal_continuation_nutrition_source', {
                    p_user_id: command.ownerId,
                    p_reply_id: lookup.replyId,
                    p_kind: kind,
                    p_food_name: foodName,
                  }),
              lookup.kind === 'original'
                ? ['absent', 'stale_epoch', 'source_required', 'source_conflict', 'sealed']
                : [
                    'absent',
                    'stale_epoch',
                    'source_required',
                    'source_conflict',
                    'sealed',
                    'event_conflict',
                  ],
            ),
          )
          if (
            result.owner_id !== command.ownerId ||
            result.command_id !== nutritionCommandId ||
            result.as_of !== asOf ||
            result.rows.length > (kind === 'trusted_recent' ? 50 : 20)
          )
            return refuse()
          const seen = new Set<string>()
          let previous: { at: bigint; id: string } | undefined
          for (const row of result.rows) {
            const at = instant(row.created_at)
            if (
              row.user_id !== command.ownerId ||
              seen.has(row.id) ||
              at > cutoff ||
              at < cutoff - 30n * 86_400_000_000_000n ||
              (row.food_db_id === null) !== (row.food_db === null) ||
              (kind === 'trusted_recent' && !(row.kcal !== null && row.kcal > 0)) ||
              (previous && (at > previous.at || (at === previous.at && row.id > previous.id)))
            )
              return refuse()
            seen.add(row.id)
            previous = { at, id: row.id }
          }
          const rows = detached(result.rows)
          const current = {
            id: result.source_receipt_id,
            hash: result.source_receipt_hash,
            rows,
          }
          const old = lookups.get(key),
            other = receiptLookups.get(current.id)
          if ((old && !isDeepStrictEqual(old, current)) || (other !== undefined && other !== key))
            return refuse()
          lookups.set(key, current)
          receiptLookups.set(current.id, key)
          receipts.set(current.id, Object.freeze({ id: current.id, hash: current.hash }))
          return rows
        } catch (error) {
          return refuse(error)
        }
      },
    })
    const auditSink: MealCalculationAuditSink = async (event) => {
      try {
        const copy = auditSchema.parse(structuredClone(event))
        if (copy.user_id !== command.ownerId) return refuse()
        audits.push(detached(copy))
      } catch (error) {
        return refuse(error)
      }
    }
    return Object.freeze({
      action: captured.action,
      sourceHash: captured.source_hash,
      capturedAt: asOf,
      epoch: context.epoch,
      context: detached(context),
      sourceReader,
      sourceReceipts: () => Object.freeze([...receipts.values()]),
      auditSink,
      auditEvents: () => Object.freeze([...audits]),
    })
  } catch (error) {
    return refuse(error)
  }
}
