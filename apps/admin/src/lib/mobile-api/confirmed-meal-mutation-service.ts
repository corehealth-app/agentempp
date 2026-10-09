import type { Json } from '@mpp/db'
import { z } from 'zod'
import {
  type ConfirmedMealCommand,
  confirmedMealCommandIdentity,
  findCompletedConfirmedMealReceipt,
  prepareConfirmedMealMutation,
} from './confirmed-meal-mutation-preparation'
import {
  loadPrivateConfirmedMealState,
  type PrivateConfirmedMealState,
} from './confirmed-meal-read'
import { MobileApiError, mobileSuccess } from './http'
import { requireIdempotencyKey } from './idempotency'
import type { MobileRouteContext } from './route'

const idsSchema = z
  .array(z.string().uuid())
  .max(30)
  .refine((ids) => new Set(ids).size === ids.length)
const receiptSchema = z
  .object({
    data: z
      .object({
        record_id: z.string().uuid(),
        operation: z.enum(['updated', 'deleted']),
        removed_item_ids: idsSchema.refine((ids) => ids.length > 0),
        new_item_ids: idsSchema,
        next_record_id: z.string().uuid().nullable(),
        snapshot: z
          .object({
            id: z.string().uuid(),
            date: z.string().date(),
            calories_consumed: z.number().int().nonnegative(),
            protein_g: z.number().finite().nonnegative(),
            carbs_g: z.number().finite().nonnegative(),
            fat_g: z.number().finite().nonnegative(),
            daily_balance: z.number().finite().nullable(),
          })
          .strict(),
      })
      .strict(),
    meta: z
      .object({ api_version: z.literal('v1'), request_id: z.string().min(1).max(128) })
      .strict(),
  })
  .strict()

function invalidReceipt(): MobileApiError {
  return new MobileApiError(
    503,
    'MEAL_RECEIPT_INVALID',
    'O resultado não pôde ser verificado. Tente novamente com a mesma chave.',
  )
}

export function parseConfirmedMealReceipt(
  body: unknown,
  recordId: string,
  method: ConfirmedMealCommand['method'],
  selected: string[],
): z.infer<typeof receiptSchema>['data'] {
  const result = receiptSchema.safeParse(body)
  if (!result.success) throw invalidReceipt()
  const data = result.data.data
  if (
    data.record_id !== recordId ||
    data.operation !== (method === 'PATCH' ? 'updated' : 'deleted') ||
    data.removed_item_ids.length !== selected.length ||
    selected.some((id) => !data.removed_item_ids.includes(id)) ||
    data.new_item_ids.some((id) => data.removed_item_ids.includes(id)) ||
    (method === 'PATCH' &&
      (data.new_item_ids.length === 0 ||
        data.next_record_id === null ||
        !data.new_item_ids.includes(data.next_record_id))) ||
    (method === 'DELETE' &&
      (data.new_item_ids.length !== 0 ||
        (data.next_record_id !== null && data.removed_item_ids.includes(data.next_record_id))))
  ) {
    throw invalidReceipt()
  }
  return data
}

interface ConfirmedMealRpcParameters {
  p_user_id: string
  p_idempotency_key: string
  p_request_method: string
  p_request_route: string
  p_request_hash: string
  p_record_id: string
  p_expected_version: string
  p_item_ids: string[]
  p_expected_state: Json
  p_calculated_items: Json | null
  p_nutrition_mode: string | null
  p_quantity_change: { quantity_g: number } | null
  p_request_id: string
}
// One bounded binding for the unpublished RPC; no global Database loosening.
type ConfirmedMealRpc = (
  name: 'mutate_mobile_confirmed_meal',
  parameters: ConfirmedMealRpcParameters,
) => PromiseLike<{ data: unknown; error: { code?: string; message: string } | null }>

function responseFromReceipt(
  context: MobileRouteContext,
  recordId: string,
  command: ConfirmedMealCommand,
  result: { status: number; body: unknown },
  replay: boolean,
  expectedState?: PrivateConfirmedMealState,
): Response {
  if (result.status !== 200) throw invalidReceipt()
  const receipt = parseConfirmedMealReceipt(
    result.body,
    recordId,
    command.method,
    command.body.item_ids,
  )
  // A fresh result must belong to the snapshot and group prepared for this operation.
  // A replay keeps its original receipt even if the live snapshot/group has since changed.
  if (expectedState) {
    const survivors = expectedState.items.filter((item) => !command.body.item_ids.includes(item.id))
    if (
      receipt.snapshot.id !== expectedState.snapshot.id ||
      receipt.snapshot.date !== expectedState.snapshot.date ||
      (command.method === 'DELETE' &&
        (survivors.length === 0
          ? receipt.next_record_id !== null
          : !survivors.some((item) => item.id === receipt.next_record_id)))
    )
      throw invalidReceipt()
  }
  return mobileSuccess(
    receipt,
    context.requestId,
    200,
    replay ? { 'Idempotency-Replayed': 'true' } : undefined,
  )
}

export async function mutateConfirmedMeal(
  context: MobileRouteContext,
  recordId: string,
  command: ConfirmedMealCommand,
  now = new Date(),
): Promise<Response> {
  const key = requireIdempotencyKey(context.request)
  const identity = confirmedMealCommandIdentity(recordId, command)
  const findReceipt = () =>
    findCompletedConfirmedMealReceipt(context.supabase, context.auth, key, identity)
  const completed = await findReceipt()
  if (completed) return responseFromReceipt(context, recordId, command, completed, true)
  let prepared: Awaited<ReturnType<typeof prepareConfirmedMealMutation>>
  try {
    const state = await loadPrivateConfirmedMealState(context.supabase, context.auth, recordId)
    prepared = await prepareConfirmedMealMutation(
      context.supabase,
      context.auth,
      recordId,
      command,
      state,
      now,
    )
  } catch (error) {
    // A peer may have completed while preparation read old/removed state. Bounded read only.
    let receipt: Awaited<ReturnType<typeof findReceipt>> = null
    try {
      receipt = await findReceipt()
    } catch {
      /* Keep the original actionable error. */
    }
    if (receipt) return responseFromReceipt(context, recordId, command, receipt, true)
    throw error
  }
  const rpc = context.supabase.rpc.bind(context.supabase) as unknown as ConfirmedMealRpc
  const { data, error } = await rpc('mutate_mobile_confirmed_meal', {
    p_user_id: context.auth.userId,
    p_idempotency_key: key,
    p_request_method: command.method,
    p_request_route: identity.route,
    p_request_hash: identity.requestHash,
    p_record_id: recordId,
    p_expected_version: command.body.expected_version,
    p_item_ids: command.body.item_ids,
    p_expected_state: prepared.expectedState as unknown as Json,
    p_calculated_items: prepared.calculatedItems,
    p_nutrition_mode: prepared.nutritionMode,
    p_quantity_change: prepared.quantityChange,
    p_request_id: context.requestId,
  })
  if (error) {
    if (error.code === '40001')
      throw new MobileApiError(
        409,
        'MEAL_VERSION_CONFLICT',
        'O registro mudou. Revise os dados atuais.',
      )
    if (error.code === '55P03')
      throw new MobileApiError(
        409,
        'IDEMPOTENCY_REQUEST_IN_PROGRESS',
        'A operação está em andamento. Tente novamente com a mesma chave.',
      )
    if (error.code === '22023' && error.message === 'mobile meal resulting group exceeds30items') {
      throw new MobileApiError(
        422,
        'MEAL_GROUP_LIMIT_EXCEEDED',
        'A edição ultrapassa o limite de alimentos deste registro.',
      )
    }
    throw new MobileApiError(
      503,
      'MEAL_MUTATION_UNAVAILABLE',
      'O resultado não pôde ser verificado. Tente novamente com a mesma chave.',
    )
  }
  const parsed = z
    .discriminatedUnion('action', [
      z.object({ action: z.literal('conflict') }).strict(),
      z.object({ action: z.literal('in_progress') }).strict(),
      z
        .object({
          action: z.literal('completed'),
          response_status: z.literal(200),
          response_body: z.unknown(),
        })
        .strict(),
      z
        .object({
          action: z.literal('replay'),
          response_status: z.literal(200),
          response_body: z.unknown(),
        })
        .strict(),
    ])
    .safeParse(data)
  if (!parsed.success) throw invalidReceipt()
  if (parsed.data.action === 'conflict')
    throw new MobileApiError(409, 'IDEMPOTENCY_KEY_CONFLICT', 'A chave pertence a outra operação.')
  if (parsed.data.action === 'in_progress')
    throw new MobileApiError(
      409,
      'IDEMPOTENCY_REQUEST_IN_PROGRESS',
      'A operação está em andamento. Tente novamente com a mesma chave.',
    )
  return responseFromReceipt(
    context,
    recordId,
    command,
    {
      status: parsed.data.response_status,
      body: parsed.data.response_body,
    },
    parsed.data.action === 'replay',
    parsed.data.action === 'completed' ? prepared.expectedState : undefined,
  )
}
