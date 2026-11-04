/** Private command edit contracts. Full SQL rows are CAS evidence, never a
 * public DTO. Parsing supplies no authentication or nutritional authority. */
import { createHash } from 'node:crypto'
import { isDeepStrictEqual } from 'node:util'
import { getLocalDateString } from '@mpp/agent'
import type { Json } from '@mpp/db'
import { z } from 'zod'
import type { PrivateConfirmedMealState } from './confirmed-meal-read'
import {
  type ConversationJournalBinding,
  conversationJournalBindingSchema,
} from './conversation-command-candidate-contracts'
import type { BoundConversationMealCommand } from './conversation-command-contracts'
import {
  type ConversationMealEffectReceipt,
  parseConversationMealEffectReceipt,
} from './conversation-meal-feedback-store'
import {
  bindConversationWriterCommand,
  conversationWriterClock,
  freezeConversationWriter,
} from './conversation-meal-writer-contracts'
import { MobileApiError } from './http'

const uuid = z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u)
const hash = z.string().regex(/^[0-9a-f]{64}$/u)
const finite = z.number().finite()
const revision = finite.int().min(0).max(2147483647)
const mealType = z.enum(['cafe', 'almoco', 'lanche', 'jantar', 'ceia', 'outro'])
const date = z.string().date()
const clock = conversationWriterClock.refine((s) => !/\.\d{10}/u.test(s))
const names = z
  .string()
  .min(1)
  .max(160)
  .refine(
    (s) =>
      s.trim().length > 0 &&
      s === s.replace(/^ +| +$/gu, '') &&
      !Array.from(s).some((character) => {
        const code = character.charCodeAt(0)
        return (code < 32 && ![9, 10, 13].includes(code)) || code === 127
      }),
  )
const item = z
  .object({
    food_name: names,
    quantity_g: finite.positive().max(9999),
    user_kcal: finite.min(0).max(20000).optional(),
    quantity_basis: z.enum(['stated', 'visual_estimate', 'portion_reference']).optional(),
    candidate_id: z
      .string()
      .regex(/^c[0-9]{1,2}-[0-9a-f]{8}$/u)
      .optional(),
  })
  .strict()
const base = {
  schema: z.literal('conversation.meal-edit.v1'),
  expected_revision: revision,
  expected_version: z.string().regex(/^v1:[0-9a-f]{64}$/u),
}
const inputSchema = z.discriminatedUnion('kind', [
  z
    .object({
      ...base,
      kind: z.literal('save'),
      record_id: uuid,
      items: z.array(item).min(1).max(30),
    })
    .strict(),
  z.object({ ...base, kind: z.literal('undo_save'), target_operation_id: uuid }).strict(),
  z.object({ ...base, kind: z.literal('undo_registration') }).strict(),
])
export type ConversationMealEditInput = z.infer<typeof inputSchema>
export interface ConversationMealEditBinding {
  readonly ownerId: string
  readonly commandId: string
  readonly inputHash: string
  readonly epoch: string
  readonly originalCommand?: BoundConversationMealCommand
}
export interface BoundConversationMealEdit {
  readonly binding: ConversationMealEditBinding
  readonly operationId: string
  readonly input: ConversationMealEditInput
  readonly inputHash: string
}

export function conversationMealEditUnavailable(): never {
  throw new MobileApiError(
    503,
    'conversation_meal_edit_unavailable',
    'Meal edit state is unavailable',
  )
}
/** Preserve all private JSON, including reserved object keys. Never silently
 * strip undefined/functions or normalize SQL timestamp precision. */
export function detachConversationMealEditJson(raw: unknown): Json {
  const seen = new Set<object>()
  const check = (v: unknown, depth: number): void => {
    if (depth > 64) conversationMealEditUnavailable()
    if (v === null || typeof v === 'boolean') return
    if (typeof v === 'string') {
      for (let i = 0; i < v.length; i++) {
        const c = v.charCodeAt(i)
        if (c === 0) conversationMealEditUnavailable()
        if (c >= 0xd800 && c <= 0xdbff) {
          const next = v.charCodeAt(++i)
          if (!(next >= 0xdc00 && next <= 0xdfff)) conversationMealEditUnavailable()
        } else if (c >= 0xdc00 && c <= 0xdfff) conversationMealEditUnavailable()
      }
      return
    }
    if (typeof v === 'number' && Number.isFinite(v)) return
    if (typeof v !== 'object' || !v || seen.has(v)) conversationMealEditUnavailable()
    if (
      !Array.isArray(v) &&
      Object.getPrototypeOf(v) !== Object.prototype &&
      Object.getPrototypeOf(v) !== null
    )
      conversationMealEditUnavailable()
    seen.add(v)
    const keys = Reflect.ownKeys(v)
    for (const k of keys) {
      if (Array.isArray(v) && k === 'length') continue
      if (typeof k !== 'string') conversationMealEditUnavailable()
      if (Array.isArray(v) && (!/^(0|[1-9][0-9]*)$/u.test(k) || Number(k) >= v.length))
        conversationMealEditUnavailable()
      const descriptor = Object.getOwnPropertyDescriptor(v, k)
      if (!descriptor?.enumerable || !('value' in descriptor)) conversationMealEditUnavailable()
      check(k, depth + 1)
      check(descriptor.value, depth + 1)
    }
    if (Array.isArray(v) && keys.length !== v.length + 1) conversationMealEditUnavailable()
    seen.delete(v)
  }
  check(raw, 0)
  if (Buffer.byteLength(JSON.stringify(raw), 'utf8') > 1048576)
    return conversationMealEditUnavailable()
  return freezeConversationWriter(structuredClone(raw)) as Json
}
function exact<T>(schema: z.ZodType<T>, raw: unknown): T {
  const copy = detachConversationMealEditJson(raw),
    value = schema.parse(copy)
  if (!isDeepStrictEqual(value, copy)) return conversationMealEditUnavailable()
  return freezeConversationWriter(value)
}
export function bindConversationMealEditIdentity(
  raw: ConversationMealEditBinding,
): ConversationMealEditBinding {
  const s = z
    .object({
      ownerId: uuid,
      commandId: uuid,
      inputHash: hash,
      epoch: uuid,
      originalCommand: z.unknown().optional(),
    })
    .strict()
  const b = exact(s, raw)
  if (b.originalCommand !== undefined) {
    const c = bindConversationWriterCommand(b.originalCommand as BoundConversationMealCommand)
    if (c.ownerId !== b.ownerId || c.commandId !== b.commandId || c.inputHash !== b.inputHash)
      return conversationMealEditUnavailable()
    return freezeConversationWriter({ ...b, originalCommand: c })
  }
  return b as ConversationMealEditBinding
}
export function parseConversationMealEditInput(raw: unknown): ConversationMealEditInput {
  return exact(inputSchema, raw)
}
/** SQL canonical(jsonb) uses decimal scalar text. Expand the exact digits
 * JSON sends, without rounding the number or changing the submitted intent.
 * This closed DTO has ASCII keys, matching the SQL C-collation ordering. */
function editCanonical(value: unknown): string {
  if (typeof value === 'number') {
    const serialized = JSON.stringify(value)
    const exponent = /^(-?)([0-9]+)(?:\.([0-9]+))?e([+-]?[0-9]+)$/u.exec(serialized)
    if (!exponent) return serialized
    const [, sign, whole, fraction = '', power] = exponent
    const digits = whole + fraction
    const position = whole.length + Number(power)
    if (position <= 0) return `${sign}0.${'0'.repeat(-position)}${digits}`
    if (position >= digits.length) return sign + digits + '0'.repeat(position - digits.length)
    return `${sign}${digits.slice(0, position)}.${digits.slice(position)}`
  }
  if (value === null || typeof value !== 'object') return JSON.stringify(value)
  if (Array.isArray(value)) return `[${value.map(editCanonical).join(',')}]`
  return `{${Object.keys(value)
    .sort()
    .map(
      (key) => `${JSON.stringify(key)}:${editCanonical((value as Record<string, unknown>)[key])}`,
    )
    .join(',')}}`
}
export function bindConversationMealEdit(raw: {
  binding: ConversationMealEditBinding
  operationId: string
  input: unknown
}): BoundConversationMealEdit {
  const binding = bindConversationMealEditIdentity(raw.binding),
    operationId = uuid.parse(raw.operationId),
    input = parseConversationMealEditInput(raw.input)
  return freezeConversationWriter({
    binding,
    operationId,
    input,
    inputHash: createHash('sha256').update(editCanonical(input)).digest('hex'),
  })
}
export function parseConversationMealEditServerBinding(
  raw: unknown,
  expected: ConversationMealEditBinding,
): ConversationJournalBinding {
  const actual = exact(conversationJournalBindingSchema, raw)
  clock.parse(actual.admitted_at)
  if (
    actual.owner_id !== expected.ownerId ||
    actual.command_id !== expected.commandId ||
    actual.input_hash !== expected.inputHash ||
    actual.epoch !== expected.epoch
  )
    return conversationMealEditUnavailable()
  return actual
}

const originalSchema = z
  .object({
    schema: z.literal('conversation.meal-effect.v1'),
    owner_id: uuid,
    command_id: uuid,
    input_hash: hash,
    registration_id: uuid,
    provider_key: z.string(),
    meal_type: mealType,
    local_date: date,
    timezone: z.string().min(1),
    consumed_at: clock,
    log_ids: z.array(uuid).min(1).max(30),
    effect_version: z.string().regex(/^cmeal1:[0-9a-f]{64}$/u),
  })
  .strict()
function originalReceipt(
  raw: unknown,
  b: ConversationMealEditBinding,
): ConversationMealEffectReceipt {
  if (b.originalCommand) return parseConversationMealEffectReceipt(raw, b.originalCommand)
  const v = exact(originalSchema, raw)
  if (
    v.owner_id !== b.ownerId ||
    v.command_id !== b.commandId ||
    v.input_hash !== b.inputHash ||
    v.provider_key !== `conversation.meal/${b.ownerId}/${b.commandId}` ||
    new Set(v.log_ids).size !== v.log_ids.length ||
    getLocalDateString(v.timezone, new Date(v.consumed_at)) !== v.local_date
  )
    return conversationMealEditUnavailable()
  return v
}
const contextSchema = z
  .object({
    id: uuid,
    auth_user_id: uuid.nullable(),
    country: z.string().nullable(),
    country_confirmed: z.boolean(),
    timezone: z.string().nullable(),
    status: z.string(),
    wpp: z.string().nullable(),
    updated_at: clock,
  })
  .strict()
const snapshotSchema = z
  .object({
    id: uuid,
    user_id: uuid,
    date,
    calories_consumed: finite.int(),
    calories_target: finite.int().nullable(),
    protein_g: finite,
    carbs_g: finite,
    fat_g: finite,
    protein_target: finite.nullable(),
    daily_balance: finite.nullable(),
    day_closed: z.boolean(),
    day_status: z.string(),
    closed_at: clock.nullable(),
    created_at: clock,
    updated_at: clock,
    current_protocol: z.enum(['recomposicao', 'ganho_massa', 'manutencao']).nullable(),
    deficit_accumulated: finite,
    exercise_calories: finite,
    gap_reminder_sent_at: clock.nullable(),
    sleep_hours: finite.nullable(),
    steps: finite.nullable(),
    training_done: z.boolean(),
    water_consumed_ml: finite,
    xp_earned: finite,
  })
  .passthrough()
const logSchema = z
  .object({
    id: uuid,
    user_id: uuid,
    snapshot_id: uuid.nullable(),
    food_name: z.string(),
    quantity_g: finite.nullable(),
    kcal: finite.nullable(),
    protein_g: finite.nullable(),
    carbs_g: finite.nullable(),
    fat_g: finite.nullable(),
    confidence: finite.nullable(),
    food_db_id: finite.int().nullable(),
    consumed_at: clock,
    created_at: clock,
    meal_type: mealType.nullable(),
    image_url: z.string().nullable(),
    raw_message_id: uuid.nullable(),
    raw_provider_message_id: z.string().nullable(),
    source: z.string().nullable(),
  })
  .passthrough()
const stateSchema = z
  .object({
    context: contextSchema,
    snapshot: snapshotSchema,
    items: z.array(logSchema).min(1).max(30),
  })
  .strict()
export function parseConversationMealEditCurrentState(
  raw: unknown,
  binding: ConversationMealEditBinding,
): PrivateConfirmedMealState {
  const b = bindConversationMealEditIdentity(binding),
    copy = detachConversationMealEditJson(raw)
  // Validate known columns, return the ORIGINAL detached JSON. Row additions
  // must participate in SQL CAS even when this app version does not know them.
  const v = stateSchema.parse(copy)
  if (
    v.context.id !== b.ownerId ||
    v.context.status !== 'active' ||
    v.snapshot.user_id !== b.ownerId ||
    new Set(v.items.map((x) => x.id)).size !== v.items.length ||
    v.items.some(
      (x, i) =>
        x.user_id !== b.ownerId ||
        x.snapshot_id !== v.snapshot.id ||
        x.raw_provider_message_id !== `conversation.meal/${b.ownerId}/${b.commandId}` ||
        (i > 0 && x.id <= v.items[i - 1].id),
    )
  )
    return conversationMealEditUnavailable()
  return copy as unknown as PrivateConfirmedMealState
}

const ids = z
  .array(uuid)
  .max(30)
  .refine((v) => new Set(v).size === v.length)
const receiptSchema = z
  .object({
    schema: z.literal('conversation.meal-edit-effect.v1'),
    owner_id: uuid,
    command_id: uuid,
    operation_id: uuid,
    input_hash: hash,
    kind: z.enum(['saved', 'save_undone', 'registration_undone']),
    revision: revision.refine((n) => n > 0),
    applied_at: clock,
    undo_expires_at: clock.nullable(),
    target_operation_id: uuid.nullable(),
    removed_item_ids: ids.refine((v) => v.length > 0),
    new_item_ids: ids,
    next_record_id: uuid.nullable(),
    snapshot: z
      .object({
        id: uuid,
        date,
        calories_consumed: finite.int().nonnegative(),
        protein_g: finite.nonnegative(),
        carbs_g: finite.nonnegative(),
        fat_g: finite.nonnegative(),
        daily_balance: finite.nullable(),
      })
      .strict(),
  })
  .strict()
export type ConversationMealEditReceipt = Readonly<z.infer<typeof receiptSchema>>
function instant(raw: string): bigint {
  clock.parse(raw)
  const match = /\.(\d+)(?:Z|[+-]\d{2}:\d{2})$/u.exec(raw)
  return (
    BigInt(Math.floor(Date.parse(raw) / 1000)) * 1000000000n +
    BigInt((match?.[1] ?? '').padEnd(9, '0'))
  )
}
function receipt(raw: unknown, b: ConversationMealEditBinding): ConversationMealEditReceipt {
  const v = exact(receiptSchema, raw)
  if (
    v.owner_id !== b.ownerId ||
    v.command_id !== b.commandId ||
    v.new_item_ids.some((id) => v.removed_item_ids.includes(id))
  )
    return conversationMealEditUnavailable()
  if (v.kind === 'saved') {
    if (
      v.removed_item_ids.length !== 1 ||
      v.new_item_ids.length < 1 ||
      v.next_record_id !== v.new_item_ids[0] ||
      v.target_operation_id !== null ||
      v.undo_expires_at === null ||
      instant(v.undo_expires_at) - instant(v.applied_at) !== 300000000000n
    )
      return conversationMealEditUnavailable()
  } else {
    if (v.undo_expires_at !== null) return conversationMealEditUnavailable()
    if (
      v.kind === 'save_undone' &&
      (v.revision < 2 ||
        v.target_operation_id === null ||
        v.target_operation_id === v.operation_id ||
        v.new_item_ids.length !== 1 ||
        v.next_record_id !== v.new_item_ids[0])
    )
      return conversationMealEditUnavailable()
    if (
      v.kind === 'registration_undone' &&
      (v.revision !== 1 ||
        v.target_operation_id !== null ||
        v.new_item_ids.length !== 0 ||
        v.next_record_id !== null)
    )
      return conversationMealEditUnavailable()
  }
  return v
}
/** A qualified immutable journal row has no operation input body. Preserve
 * receipt invariants and actual original binding without inventing that body. */
export function parseConversationMealEditHistoricalReceipt(
  raw: unknown,
  binding: unknown,
): ConversationMealEditReceipt {
  try {
    const actual = exact(conversationJournalBindingSchema, binding)
    clock.parse(actual.admitted_at)
    const value = receipt(raw, {
      ownerId: actual.owner_id,
      commandId: actual.command_id,
      inputHash: actual.input_hash,
      epoch: actual.epoch,
    })
    if (instant(value.applied_at) < instant(actual.admitted_at))
      return conversationMealEditUnavailable()
    return value
  } catch {
    return conversationMealEditUnavailable()
  }
}
export function parseConversationMealEditReceipt(
  raw: unknown,
  operation: BoundConversationMealEdit,
): ConversationMealEditReceipt {
  const op = bindConversationMealEdit(operation)
  if (operation.inputHash !== op.inputHash) return conversationMealEditUnavailable()
  const v = receipt(raw, op.binding),
    kind = { save: 'saved', undo_save: 'save_undone', undo_registration: 'registration_undone' }[
      op.input.kind
    ]
  if (
    v.operation_id !== op.operationId ||
    v.input_hash !== op.inputHash ||
    v.kind !== kind ||
    v.revision !== op.input.expected_revision + 1 ||
    (op.input.kind === 'save' &&
      (v.removed_item_ids.length !== 1 || v.removed_item_ids[0] !== op.input.record_id)) ||
    (op.input.kind === 'undo_save' && v.target_operation_id !== op.input.target_operation_id)
  )
    return conversationMealEditUnavailable()
  return v
}

export interface ConversationMealEditState {
  readonly action: 'available'
  readonly binding: ConversationJournalBinding
  readonly originalReceipt: ConversationMealEffectReceipt
  readonly revision: number
  readonly currentState: PrivateConfirmedMealState | null
  readonly lineageCompatible: boolean
  readonly lastOperation: ConversationMealEditReceipt | null
  readonly registrationUndoExpiresAt: string
  readonly observedAt: string
}
const readStateSchema = z
  .object({
    action: z.literal('available'),
    command: conversationJournalBindingSchema,
    original_receipt: z.unknown(),
    revision,
    current_state: z.unknown().nullable(),
    lineage_compatible: z.boolean(),
    last_operation: z.unknown().nullable(),
    registration_undo_expires_at: clock,
    observed_at: clock,
  })
  .strict()
export function parseConversationMealEditState(
  raw: unknown,
  expected: ConversationMealEditBinding,
): ConversationMealEditState {
  const b = bindConversationMealEditIdentity(expected),
    v = exact(readStateSchema, raw),
    binding = parseConversationMealEditServerBinding(v.command, b)
  const original = originalReceipt(v.original_receipt, b),
    current =
      v.current_state === null ? null : parseConversationMealEditCurrentState(v.current_state, b)
  const last = v.last_operation === null ? null : receipt(v.last_operation, b)
  if (
    (v.revision === 0) !== (last === null) ||
    (last !== null &&
      (last.revision !== v.revision || instant(last.applied_at) > instant(v.observed_at))) ||
    instant(binding.admitted_at) > instant(v.observed_at) ||
    instant(original.consumed_at) > instant(v.observed_at) ||
    (current !== null && current.snapshot.date !== original.local_date)
  )
    return conversationMealEditUnavailable()
  return freezeConversationWriter({
    action: 'available',
    binding,
    originalReceipt: original,
    revision: v.revision,
    currentState: current,
    lineageCompatible: v.lineage_compatible,
    lastOperation: last,
    registrationUndoExpiresAt: v.registration_undo_expires_at,
    observedAt: v.observed_at,
  })
}
