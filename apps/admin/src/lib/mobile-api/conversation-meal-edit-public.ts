/** Public factual edit projections only. Full C11 rows, clinical snapshots and
 * saved historical balances never cross this boundary. Current guidance stays
 * on the existing current-policy readers; an edit ACK needs no follow-up GET. */
import { isDeepStrictEqual } from 'node:util'
import { getLocalDateString } from '@mpp/agent'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import { privateConfirmedMealVersion } from './confirmed-meal-read'
import {
  type BoundConversationMealEdit,
  bindConversationMealEdit,
  bindConversationMealEditIdentity,
  type ConversationMealEditBinding,
  type ConversationMealEditReceipt,
  detachConversationMealEditJson,
  parseConversationMealEditReceipt,
  parseConversationMealEditServerBinding,
  parseConversationMealEditState,
} from './conversation-meal-edit-contracts'
import {
  conversationWriterClock,
  freezeConversationWriter,
} from './conversation-meal-writer-contracts'
import { MobileApiError } from './http'
import { mobileQuantityFields } from './mobile-quantity-display'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'

const uuid = z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u)
const hash = z.string().regex(/^[a-f0-9]{64}$/u)
const revision = z.number().int().min(0).max(2147483647)
const clock = conversationWriterClock.refine((s) => !/\.\d{10}/u.test(s))
const nonnegative = z.number().finite().nonnegative().max(Number.MAX_SAFE_INTEGER)
const ids = z
  .array(uuid)
  .max(30)
  .refine((v) => new Set(v).size === v.length)
const effectSchema = z
  .object({
    schema: z.literal('conversation.meal-edit-effect-public.v1'),
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
  })
  .strict()
export type PublicConversationMealEditEffect = Readonly<z.infer<typeof effectSchema>>
const reason = z.enum([
  'current_group_unavailable',
  'day_closed',
  'not_current_day',
  'invalid_timezone',
  'revision_exhausted',
  'version_changed',
  'undo_expired',
  'no_save_to_undo',
])
const actionSchema = z.discriminatedUnion('allowed', [
  z.object({ allowed: z.literal(true) }).strict(),
  z.object({ allowed: z.literal(false), reason }).strict(),
])
type Availability = z.infer<typeof actionSchema>
const itemSchema = z
  .object({
    id: uuid,
    food_name: z
      .string()
      .min(1)
      .max(240)
      .refine((s) => s.trim().length > 0),
    quantity_g: nonnegative.positive().max(9999).nullable(),
    quantity_display: z
      .object({
        unit: z.enum(['mL', 'unit', 'scoop']),
        grams_per_unit: nonnegative.positive(),
        reference_id: z.string().min(1).max(240),
        estimated: z.literal(true),
      })
      .strict()
      .nullable(),
    kcal: nonnegative.nullable(),
    protein_g: nonnegative.nullable(),
    carbs_g: nonnegative.nullable(),
    fat_g: nonnegative.nullable(),
    source: z.string().min(1).max(80).nullable(),
    consumed_at: clock,
    meal_type: z.enum(['cafe', 'almoco', 'lanche', 'jantar', 'ceia', 'outro']).nullable(),
  })
  .strict()
const groupSchema = z
  .object({
    schema: z.literal('conversation.meal-group.v1'),
    owner_id: uuid,
    command_id: uuid,
    input_hash: hash,
    epoch: uuid,
    admitted_at: clock,
    observed_at: clock,
    original_receipt: z.unknown(),
    revision,
    lineage_compatible: z.boolean(),
    current: z
      .object({
        expected_version: z.string().regex(/^v1:[a-f0-9]{64}$/u),
        local_date: z.string().date(),
        timezone: z.string().nullable(),
        day_closed: z.boolean(),
        items: z.array(itemSchema).min(1).max(30),
      })
      .strict()
      .nullable(),
    last_operation: effectSchema.nullable(),
    registration_undo_expires_at: clock,
    actions: z
      .object({ save: actionSchema, undo_registration: actionSchema, undo_save: actionSchema })
      .strict(),
  })
  .strict()
const versionedGroupSchema = z.union([
  groupSchema,
  groupSchema.extend({ schema: z.literal('conversation.meal-group.v2') }),
])
export type PublicConversationMealGroup = Readonly<
  Omit<z.infer<typeof versionedGroupSchema>, 'original_receipt'> & {
    original_receipt: ReturnType<typeof parseConversationMealEditState>['originalReceipt']
  }
>
const resultSchema = z
  .object({
    schema: z.literal('conversation.meal-edit-result.v1'),
    status: z.literal('saved'),
    owner_id: uuid,
    command_id: uuid,
    input_hash: hash,
    epoch: uuid,
    receipt: effectSchema,
  })
  .strict()
export type PublicConversationMealEditResult = Readonly<z.infer<typeof resultSchema>>
const absentSchema = z
  .object({
    schema: z.literal('conversation.meal-edit-state.v1'),
    status: z.literal('absent'),
    owner_id: uuid,
    command_id: uuid,
    input_hash: hash,
    epoch: uuid,
    operation_id: uuid,
    operation_input_hash: hash,
  })
  .strict()
export type PublicConversationMealEditAbsent = Readonly<z.infer<typeof absentSchema>>
export type PublicConversationMealEditReply =
  | PublicConversationMealEditResult
  | PublicConversationMealEditAbsent

function unavailable(): never {
  throw new MobileApiError(
    503,
    'conversation_meal_edit_unavailable',
    'Meal edit state is unavailable',
  )
}
function closed<T>(schema: z.ZodType<T>, raw: unknown): T {
  const copy = detachConversationMealEditJson(raw),
    value = schema.parse(copy)
  if (!isDeepStrictEqual(copy, value) || Buffer.byteLength(JSON.stringify(value), 'utf8') > 65536)
    return unavailable()
  return freezeConversationWriter(value)
}
function original(auth: MobileAuthContext, binding: ConversationMealEditBinding) {
  const who = freezeConversationWriter(structuredClone(auth)),
    b = bindConversationMealEditIdentity(binding)
  if (b.ownerId !== authenticatedReevaluationOwner(who)) return unavailable()
  return { who, binding: b }
}
function instant(s: string): bigint {
  clock.parse(s)
  const match = /\.(\d+)(?:Z|[+-]\d{2}:\d{2})$/u.exec(s)
  return (
    BigInt(Math.floor(Date.parse(s) / 1000)) * 1000000000n +
    BigInt((match?.[1] ?? '').padEnd(9, '0'))
  )
}
/** Whitelist an ALREADY qualified actual SQL receipt. This codec supplies no
 * persistence, owner or original-operation proof; callers must establish those
 * through the private store/journal receipt decoder before invoking it. */
export function projectConversationMealEditEffect(
  receipt: ConversationMealEditReceipt,
): PublicConversationMealEditEffect {
  return closed(effectSchema, {
    schema: 'conversation.meal-edit-effect-public.v1',
    owner_id: receipt.owner_id,
    command_id: receipt.command_id,
    operation_id: receipt.operation_id,
    input_hash: receipt.input_hash,
    kind: receipt.kind,
    revision: receipt.revision,
    applied_at: receipt.applied_at,
    undo_expires_at: receipt.undo_expires_at,
    target_operation_id: receipt.target_operation_id,
    removed_item_ids: receipt.removed_item_ids,
    new_item_ids: receipt.new_item_ids,
    next_record_id: receipt.next_record_id,
  })
}
const stateEnvelope = z
  .object({
    action: z.literal('available'),
    binding: z.unknown(),
    originalReceipt: z.unknown(),
    revision: z.unknown(),
    currentState: z.unknown().nullable(),
    lineageCompatible: z.unknown(),
    lastOperation: z.unknown().nullable(),
    registrationUndoExpiresAt: z.unknown(),
    observedAt: z.unknown(),
  })
  .strict()
export function projectConversationMealGroup(
  auth: MobileAuthContext,
  expected: ConversationMealEditBinding,
  input: unknown,
): PublicConversationMealGroup {
  try {
    const { who, binding } = original(auth, expected),
      raw = closed(stateEnvelope, input)
    const s = parseConversationMealEditState(
      {
        action: raw.action,
        command: raw.binding,
        original_receipt: raw.originalReceipt,
        revision: raw.revision,
        current_state: raw.currentState,
        lineage_compatible: raw.lineageCompatible,
        last_operation: raw.lastOperation,
        registration_undo_expires_at: raw.registrationUndoExpiresAt,
        observed_at: raw.observedAt,
      },
      binding,
    )
    const current = s.currentState
    if (current !== null && current.context.auth_user_id !== who.authUserId) return unavailable()
    let blocked: z.infer<typeof reason> | null = null
    if (current === null) blocked = 'current_group_unavailable'
    else {
      try {
        const timezone = current.context.timezone
        if (!timezone) blocked = 'invalid_timezone'
        else {
          const today = getLocalDateString(timezone, new Date(s.observedAt))
          if (current.snapshot.day_closed) blocked = 'day_closed'
          else if (
            current.snapshot.date !== today ||
            current.items.some(
              (row) => getLocalDateString(timezone, new Date(row.consumed_at)) !== today,
            )
          )
            blocked = 'not_current_day'
          else if (s.revision === 2147483647) blocked = 'revision_exhausted'
        }
      } catch {
        blocked = 'invalid_timezone'
      }
    }
    const availability = (why: z.infer<typeof reason> | null): Availability =>
      why ? { allowed: false, reason: why } : { allowed: true }
    const undoOriginal =
      blocked ??
      (s.revision !== 0 || !s.lineageCompatible
        ? 'version_changed'
        : instant(s.registrationUndoExpiresAt) <= instant(s.observedAt)
          ? 'undo_expired'
          : null)
    const last = s.lastOperation
    const undoSave =
      blocked ??
      (!last || last.kind !== 'saved'
        ? 'no_save_to_undo'
        : !s.lineageCompatible
          ? 'version_changed'
          : last.undo_expires_at === null || instant(last.undo_expires_at) <= instant(s.observedAt)
            ? 'undo_expired'
            : null)
    const value = closed(versionedGroupSchema, {
      schema:
        s.binding.command_protocol === 'conversation.clarification.v1'
          ? 'conversation.meal-group.v2'
          : 'conversation.meal-group.v1',
      owner_id: binding.ownerId,
      command_id: binding.commandId,
      input_hash: binding.inputHash,
      epoch: binding.epoch,
      admitted_at: s.binding.admitted_at,
      observed_at: s.observedAt,
      original_receipt: s.originalReceipt,
      revision: s.revision,
      lineage_compatible: s.lineageCompatible,
      current:
        current === null
          ? null
          : {
              expected_version: privateConfirmedMealVersion(current),
              local_date: current.snapshot.date,
              timezone: current.context.timezone,
              day_closed: current.snapshot.day_closed,
              items: current.items.map((row) => ({
                id: row.id,
                food_name: row.food_name,
                quantity_g: row.quantity_g,
                quantity_display: mobileQuantityFields(row.food_name).quantity_display ?? null,
                kcal: row.kcal,
                protein_g: row.protein_g,
                carbs_g: row.carbs_g,
                fat_g: row.fat_g,
                source: row.source,
                consumed_at: row.consumed_at,
                meal_type: row.meal_type,
              })),
            },
      last_operation: last === null ? null : projectConversationMealEditEffect(last),
      registration_undo_expires_at: s.registrationUndoExpiresAt,
      actions: {
        save: availability(blocked),
        undo_registration: availability(undoOriginal),
        undo_save: availability(undoSave),
      },
    })
    return freezeConversationWriter({ ...value, original_receipt: s.originalReceipt })
  } catch {
    return unavailable()
  }
}
export function projectConversationMealEditResult(
  auth: MobileAuthContext,
  operation: BoundConversationMealEdit,
  input: unknown,
): PublicConversationMealEditResult {
  try {
    const op = bindConversationMealEdit(operation),
      { binding } = original(auth, op.binding)
    if (operation.inputHash !== op.inputHash) return unavailable()
    const raw = closed(
      z
        .object({
          status: z.literal('saved'),
          binding: z.unknown(),
          operationId: uuid,
          inputHash: hash,
          receipt: z.unknown(),
        })
        .strict(),
      input,
    )
    parseConversationMealEditServerBinding(raw.binding, binding)
    if (raw.operationId !== op.operationId || raw.inputHash !== op.inputHash) return unavailable()
    return closed(resultSchema, {
      schema: 'conversation.meal-edit-result.v1',
      status: 'saved',
      owner_id: binding.ownerId,
      command_id: binding.commandId,
      input_hash: binding.inputHash,
      epoch: binding.epoch,
      receipt: projectConversationMealEditEffect(parseConversationMealEditReceipt(raw.receipt, op)),
    })
  } catch {
    return unavailable()
  }
}
/** Only after an absent operation read and a real current command state read.
 * Headers alone cannot prove an existing original binding. */
export function projectConversationMealEditAbsent(
  auth: MobileAuthContext,
  operation: BoundConversationMealEdit,
  actualBinding: unknown,
): PublicConversationMealEditAbsent {
  try {
    const op = bindConversationMealEdit(operation),
      { binding } = original(auth, op.binding)
    if (operation.inputHash !== op.inputHash) return unavailable()
    parseConversationMealEditServerBinding(actualBinding, binding)
    return closed(absentSchema, {
      schema: 'conversation.meal-edit-state.v1',
      status: 'absent',
      owner_id: binding.ownerId,
      command_id: binding.commandId,
      input_hash: binding.inputHash,
      epoch: binding.epoch,
      operation_id: op.operationId,
      operation_input_hash: op.inputHash,
    })
  } catch {
    return unavailable()
  }
}
