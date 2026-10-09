import { getLocalDateString } from '@mpp/agent'
import type { ServiceClient, Tables } from '@mpp/db'
import type { MobileAuthContext } from './auth'
import { resourceIdSchema } from './contracts'
import { MobileApiError } from './http'
import { hashMobileRequest } from './idempotency'

export interface PrivateConfirmedMealState {
  context: Pick<
    Tables<'users'>,
    | 'id'
    | 'auth_user_id'
    | 'country'
    | 'country_confirmed'
    | 'timezone'
    | 'status'
    | 'wpp'
    | 'updated_at'
  >
  snapshot: Tables<'daily_snapshots'>
  items: Tables<'meal_logs'>[]
}

export interface ConfirmedMealRecord {
  record_id: string
  scope: 'group' | 'item'
  expected_version: string
  item_ids: string[]
  items: Pick<
    Tables<'meal_logs'>,
    | 'id'
    | 'food_name'
    | 'quantity_g'
    | 'kcal'
    | 'protein_g'
    | 'carbs_g'
    | 'fat_g'
    | 'consumed_at'
    | 'meal_type'
    | 'source'
  >[]
  local_date: string
  timezone: string
  day_closed: boolean
  editable: boolean
  edit_block_reason: 'MEAL_DAY_NOT_EDITABLE' | null
}

function readUnavailable(): MobileApiError {
  return new MobileApiError(
    503,
    'MEAL_READ_UNAVAILABLE',
    'O registro não pôde ser carregado. Tente novamente.',
  )
}

function contextChanged(): MobileApiError {
  return new MobileApiError(409, 'MEAL_CONTEXT_CHANGED', 'Atualize o registro antes de continuar.')
}

/** Complete server-only state for the transactional comparison, never a public DTO. */
export async function loadPrivateConfirmedMealState(
  supabase: ServiceClient,
  auth: MobileAuthContext,
  recordId: string,
): Promise<PrivateConfirmedMealState> {
  const id = resourceIdSchema.parse(recordId).toLowerCase()
  const [userResult, anchorResult] = await Promise.all([
    supabase
      .from('users')
      .select('id,auth_user_id,country,country_confirmed,timezone,status,wpp,updated_at')
      .eq('id', auth.userId)
      .maybeSingle(),
    supabase.from('meal_logs').select('*').eq('user_id', auth.userId).eq('id', id).maybeSingle(),
  ])
  if (userResult.error || anchorResult.error) throw readUnavailable()
  const context = userResult.data
  if (
    !context ||
    context.id !== auth.userId ||
    context.auth_user_id !== auth.authUserId ||
    context.status !== 'active'
  )
    throw contextChanged()
  const anchor = anchorResult.data
  if (!anchor || anchor.user_id !== auth.userId || anchor.id !== id || !anchor.snapshot_id) {
    throw new MobileApiError(404, 'MEAL_RECORD_NOT_FOUND', 'Registro não encontrado.')
  }
  const snapshotQuery = supabase
    .from('daily_snapshots')
    .select('*')
    .eq('user_id', auth.userId)
    .eq('id', anchor.snapshot_id)
    .maybeSingle()
  const groupQuery =
    anchor.raw_provider_message_id === null
      ? Promise.resolve({ data: [anchor], error: null })
      : supabase
          .from('meal_logs')
          .select('*')
          .eq('user_id', auth.userId)
          .eq('snapshot_id', anchor.snapshot_id)
          .eq('raw_provider_message_id', anchor.raw_provider_message_id)
          .order('id')
          .limit(31)
  const [snapshotResult, groupResult] = await Promise.all([snapshotQuery, groupQuery])
  if (snapshotResult.error || groupResult.error) throw readUnavailable()
  const snapshot = snapshotResult.data
  const items = groupResult.data
  if (
    !snapshot ||
    snapshot.user_id !== auth.userId ||
    snapshot.id !== anchor.snapshot_id ||
    !items ||
    !items.some((item) => item.id === id) ||
    items.some(
      (item) =>
        item.user_id !== auth.userId ||
        item.snapshot_id !== snapshot.id ||
        item.raw_provider_message_id !== anchor.raw_provider_message_id,
    )
  ) {
    throw new MobileApiError(
      409,
      'MEAL_SELECTION_CONFLICT',
      'O registro mudou. Carregue novamente.',
    )
  }
  if (items.length > 30) {
    throw new MobileApiError(
      409,
      'MEAL_GROUP_LIMIT_EXCEEDED',
      'Este registro ultrapassa o limite de alimentos.',
    )
  }
  return {
    context,
    snapshot,
    items: [...items].sort((left, right) => left.id.localeCompare(right.id)),
  }
}

export function privateConfirmedMealVersion(state: PrivateConfirmedMealState): string {
  return `v1:${hashMobileRequest({
    context: state.context,
    snapshot: state.snapshot,
    items: [...state.items].sort((left, right) => left.id.localeCompare(right.id)),
  })}`
}

export async function loadConfirmedMealRecord(
  supabase: ServiceClient,
  auth: MobileAuthContext,
  recordId: string,
  now = new Date(),
): Promise<ConfirmedMealRecord> {
  const state = await loadPrivateConfirmedMealState(supabase, auth, recordId)
  const timezone = state.context.timezone
  if (!timezone || !Number.isFinite(now.getTime())) throw contextChanged()
  let datesMatch: boolean
  try {
    const today = getLocalDateString(timezone, now)
    datesMatch =
      state.snapshot.date === today &&
      state.items.every(
        (item) => getLocalDateString(timezone, new Date(item.consumed_at)) === today,
      )
  } catch {
    throw contextChanged()
  }
  const editable = !state.snapshot.day_closed && datesMatch
  return {
    record_id: recordId.toLowerCase(),
    scope: state.items[0].raw_provider_message_id === null ? 'item' : 'group',
    expected_version: privateConfirmedMealVersion(state),
    item_ids: state.items.map((item) => item.id),
    items: state.items.map((item) => ({
      id: item.id,
      food_name: item.food_name,
      quantity_g: item.quantity_g,
      kcal: item.kcal,
      protein_g: item.protein_g,
      carbs_g: item.carbs_g,
      fat_g: item.fat_g,
      consumed_at: item.consumed_at,
      meal_type: item.meal_type,
      source: item.source,
    })),
    local_date: state.snapshot.date,
    timezone,
    day_closed: state.snapshot.day_closed,
    editable,
    edit_block_reason: editable ? null : 'MEAL_DAY_NOT_EDITABLE',
  }
}
