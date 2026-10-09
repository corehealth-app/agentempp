import {
  calcMealMacros,
  getLocalDateString,
  isUnresolvedNutritionSource,
  type MealItemInput,
  type MealItem as OfficialMealItem,
  reconcilePendingMealEdit,
} from '@mpp/agent'
import type { Json, ServiceClient, Tables } from '@mpp/db'
import type { MobileAuthContext } from './auth'
import { type PrivateConfirmedMealState, privateConfirmedMealVersion } from './confirmed-meal-read'
import type { RegistrationProposalInput } from './contracts'
import { MobileApiError } from './http'
import { hashMobileRequest } from './idempotency'

type MealItem = Extract<RegistrationProposalInput, { kind: 'meal' }>['items'][number]
type MealRow = Tables<'meal_logs'>
export type ConfirmedMealCommand =
  | { method: 'PATCH'; body: { expected_version: string; item_ids: string[]; items: MealItem[] } }
  | { method: 'DELETE'; body: { expected_version: string; item_ids: string[] } }

export type ConfirmedMealNutritionMode = 'quantity_only' | 'recalculated'

export interface PreparedConfirmedMealMutation {
  expectedState: PrivateConfirmedMealState
  calculatedItems: Json | null
  // Authenticated server-only RPC fields. Never parsed from the client's command.
  nutritionMode: ConfirmedMealNutritionMode | null
  quantityChange: { quantity_g: number } | null
}

function normalizedQuantityIdentity(name: string): string {
  // Same exact normalization as the existing reconciler; no fuzzy/preparation stripping.
  return name
    .toLowerCase()
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .replace(/\s+/g, ' ')
    .trim()
}

function officialNumber(value: number | null): value is number {
  return value !== null && Number.isFinite(value) && value >= 0
}

function quantityNutrition(row: MealRow, newQuantity: number): Json {
  if (
    !officialNumber(row.quantity_g) ||
    row.quantity_g <= 0 ||
    row.quantity_g > 9999 ||
    !officialNumber(row.kcal) ||
    row.kcal > 99999 ||
    !officialNumber(row.protein_g) ||
    row.protein_g > 9999 ||
    !officialNumber(row.carbs_g) ||
    row.carbs_g > 9999 ||
    !officialNumber(row.fat_g) ||
    row.fat_g > 9999 ||
    row.kcal > row.quantity_g * 9.5 + 5 ||
    row.protein_g + row.carbs_g + row.fat_g > row.quantity_g * 1.1 + 5 ||
    (row.confidence !== null &&
      (!Number.isFinite(row.confidence) || row.confidence < 0 || row.confidence > 1)) ||
    ((row.source === 'canonical_exact' || row.source === 'canonical_fuzzy') &&
      row.food_db_id === null) ||
    isUnresolvedNutritionSource(row.source)
  ) {
    throw new MobileApiError(
      422,
      'MEAL_NUTRITION_UNRESOLVED',
      'Os valores oficiais deste alimento precisam ser revisados.',
    )
  }
  // Do not change the requested quantity through implicit physical-column rounding.
  // Existing numeric6,2 cannot represent0.001g; root validates this guard against real PG.
  if (
    !Number.isFinite(newQuantity) ||
    newQuantity <= 0 ||
    newQuantity > 9999 ||
    Math.round(newQuantity * 100) / 100 !== newQuantity
  ) {
    throw new MobileApiError(
      422,
      'MEAL_QUANTITY_NOT_REPRESENTABLE',
      'Informe a quantidade em gramas com até duas casas decimais.',
    )
  }
  const previous: OfficialMealItem = {
    name: row.food_name,
    quantity_g: row.quantity_g,
    kcal: row.kcal,
    protein_g: row.protein_g,
    carbs_g: row.carbs_g,
    fat_g: row.fat_g,
    food_db_id: row.food_db_id,
    nutrition_source: row.source,
    ...(row.source === 'user_kcal' ? { user_kcal: row.kcal } : {}),
  }
  const reconciled = reconcilePendingMealEdit({
    previousItems: [previous],
    resolvedItems: [{ ...previous, quantity_g: newQuantity }],
    currentExplicitKcalFoods: new Set(),
  })
  const item = reconciled.items[0]
  if (
    !item ||
    reconciled.items.length !== 1 ||
    item.name !== row.food_name ||
    item.nutrition_source !== row.source ||
    item.food_db_id !== row.food_db_id ||
    !Number.isFinite(item.kcal) ||
    item.kcal < 0 ||
    item.kcal > 99999 ||
    [item.protein_g, item.carbs_g, item.fat_g].some(
      (value) => !Number.isFinite(value) || value < 0 || value > 9999,
    ) ||
    item.kcal > newQuantity * 9.5 + 5 ||
    item.protein_g + item.carbs_g + item.fat_g > newQuantity * 1.1 + 5
  ) {
    throw new MobileApiError(
      422,
      'MEAL_NUTRITION_UNRESOLVED',
      'A proporção oficial não pôde ser preservada.',
    )
  }
  return [
    {
      food_name: row.food_name,
      quantity_g: item.quantity_g,
      kcal: item.kcal,
      protein_g: item.protein_g,
      carbs_g: item.carbs_g,
      fat_g: item.fat_g,
      food_db_id: row.food_db_id,
      source: row.source,
      confidence: row.confidence,
    },
  ]
}

export function confirmedMealCommandIdentity(recordId: string, command: ConfirmedMealCommand) {
  const route = `/api/mobile/v1/meal-records/${recordId.toLowerCase()}`
  // Validated input only. No fresh DB context, time, or calculated macros in this hash.
  return {
    route,
    method: command.method,
    requestHash: hashMobileRequest({ method: command.method, route, body: command.body }),
  }
}

export async function findCompletedConfirmedMealReceipt(
  supabase: ServiceClient,
  auth: MobileAuthContext,
  idempotencyKey: string,
  identity: ReturnType<typeof confirmedMealCommandIdentity>,
): Promise<{ status: number; body: Json } | null> {
  const { data, error } = await supabase
    .from('mobile_api_idempotency')
    .select('*')
    .eq('user_id', auth.userId)
    .eq('idempotency_key', idempotencyKey)
    .maybeSingle()
  if (error)
    throw new MobileApiError(
      503,
      'IDEMPOTENCY_READ_UNAVAILABLE',
      'Tente novamente com a mesma chave.',
    )
  if (!data) return null
  // An expired completed receipt keeps its original identity. No target/calculation reads first.
  if (
    data.request_method !== identity.method ||
    data.request_route !== identity.route ||
    data.request_hash !== identity.requestHash
  ) {
    throw new MobileApiError(409, 'IDEMPOTENCY_KEY_CONFLICT', 'A chave pertence a outra operação.')
  }
  if (data.state !== 'completed') return null
  if (data.response_status === null || data.response_body === null) {
    throw new MobileApiError(
      503,
      'IDEMPOTENCY_RECEIPT_INVALID',
      'O resultado não pôde ser verificado.',
    )
  }
  return { status: data.response_status, body: data.response_body }
}

export async function prepareConfirmedMealMutation(
  supabase: ServiceClient,
  auth: MobileAuthContext,
  recordId: string,
  command: ConfirmedMealCommand,
  state: PrivateConfirmedMealState,
  now: Date,
): Promise<PreparedConfirmedMealMutation> {
  // The caller MUST run findCompletedConfirmedMealReceipt before loading this fresh state.
  const context = state.context
  if (
    context.id !== auth.userId ||
    context.auth_user_id !== auth.authUserId ||
    context.status !== 'active'
  ) {
    throw new MobileApiError(409, 'MEAL_CONTEXT_CHANGED', 'Atualize o registro antes de continuar.')
  }
  if (privateConfirmedMealVersion(state) !== command.body.expected_version) {
    throw new MobileApiError(
      409,
      'MEAL_VERSION_CONFLICT',
      'O registro mudou. Revise os dados atuais.',
    )
  }
  const selectedIds = command.body.item_ids.map((id) => id.toLowerCase())
  if (
    selectedIds.length < 1 ||
    selectedIds.length > 30 ||
    new Set(selectedIds).size !== selectedIds.length ||
    !state.items.some((item) => item.id.toLowerCase() === recordId.toLowerCase()) ||
    selectedIds.some((id) => !state.items.some((item) => item.id.toLowerCase() === id)) ||
    state.items.some(
      (item) => item.user_id !== auth.userId || item.snapshot_id !== state.snapshot.id,
    ) ||
    state.snapshot.user_id !== auth.userId
  ) {
    throw new MobileApiError(
      409,
      'MEAL_SELECTION_CONFLICT',
      'A seleção não pertence a este registro.',
    )
  }
  if (!context.timezone || !Number.isFinite(now.getTime())) {
    throw new MobileApiError(409, 'MEAL_CONTEXT_CHANGED', 'Atualize o fuso antes de continuar.')
  }
  const timezone = context.timezone
  let today: string
  try {
    today = getLocalDateString(timezone, now)
    if (
      state.snapshot.day_closed ||
      state.snapshot.date !== today ||
      state.items.some((item) => getLocalDateString(timezone, new Date(item.consumed_at)) !== today)
    ) {
      throw new MobileApiError(
        409,
        'MEAL_DAY_NOT_EDITABLE',
        'Somente registros do dia atual aberto podem ser alterados.',
      )
    }
  } catch (error) {
    if (error instanceof MobileApiError) throw error
    if (error instanceof RangeError) {
      throw new MobileApiError(
        409,
        'MEAL_CONTEXT_CHANGED',
        'O fuso ou a data do registro é inválido.',
      )
    }
    throw error
  }
  if (command.method === 'DELETE')
    return {
      expectedState: state,
      calculatedItems: null,
      nutritionMode: null,
      quantityChange: null,
    }
  if (selectedIds.length !== 1 || selectedIds[0] !== recordId.toLowerCase()) {
    throw new MobileApiError(422, 'MEAL_SINGLE_ITEM_REQUIRED', 'Edite um alimento por operação.')
  }
  if (command.body.items.some((item) => item.use_nutrition_label === true)) {
    throw new MobileApiError(
      422,
      'NUTRITION_LABEL_SOURCE_REQUIRED',
      'Esta edição não aceita uma nova fonte de rótulo.',
    )
  }
  const anchor = state.items.find((item) => item.id.toLowerCase() === recordId.toLowerCase())
  const onlyInput = command.body.items.length === 1 ? command.body.items[0] : undefined
  if (
    anchor &&
    onlyInput &&
    onlyInput.user_kcal === undefined &&
    normalizedQuantityIdentity(onlyInput.food_name) === normalizedQuantityIdentity(anchor.food_name)
  ) {
    return {
      expectedState: state,
      calculatedItems: quantityNutrition(anchor, onlyInput.quantity_g),
      nutritionMode: 'quantity_only',
      quantityChange: { quantity_g: onlyInput.quantity_g },
    }
  }
  if (!context.country_confirmed || !context.country?.trim()) {
    throw new MobileApiError(
      409,
      'COUNTRY_REQUIRED',
      'Confirme o país antes de recalcular a refeição.',
    )
  }
  const input: MealItemInput[] = command.body.items.map((item) => ({
    food_name: item.food_name,
    quantity_g: item.quantity_g,
    ...(item.user_kcal === undefined ? {} : { user_kcal: item.user_kcal }),
  }))
  // Existing resolver is not pure: it may append existing product_events while preparing.
  // The RPC compares country/context again under locks before any meal/snapshot mutation.
  const calculated = await calcMealMacros(supabase, input, context.country, auth.userId)
  if (
    calculated.items.length < 1 ||
    calculated.items.length > 30 ||
    calculated.items.some((item) => isUnresolvedNutritionSource(item.source))
  ) {
    throw new MobileApiError(
      422,
      'MEAL_NUTRITION_UNRESOLVED',
      'Revise o alimento antes de confirmar a edição.',
    )
  }
  if (state.items.length - 1 + calculated.items.length > 30) {
    throw new MobileApiError(
      422,
      'MEAL_GROUP_LIMIT_EXCEEDED',
      'A edição ultrapassa o limite de alimentos deste registro.',
    )
  }
  const calculatedItems: Json = calculated.items.map((item) => ({
    food_name: item.food_name,
    food_db_id: item.matched_taco_id,
    quantity_g: item.quantity_g,
    kcal: item.kcal,
    protein_g: item.protein_g,
    carbs_g: item.carbs_g,
    fat_g: item.fat_g,
    source: item.source,
    confidence: item.similarity,
  }))
  return {
    expectedState: state,
    calculatedItems,
    nutritionMode: 'recalculated',
    quantityChange: null,
  }
}

// Integration contract, not a hidden outer executeIdempotent wrapper:
// 1 authenticate/strict-parse -> compute command identity -> read completed receipt.
// 2 if absent: root fresh private state -> version check -> prepare -> single transactional RPC.
// 3 preparation error: read completed receipt at most once, then preserve original error/form.
// 4 RPC ambiguity: same key/input only; no automatic re-send after a successful receipt.
// 5 Success+GET failure keeps receipt and retries GET alone; caller never trusts client macros.
//    Recovery GET uses the official receipt next_record_id; null means the group became empty.
// 6 Replay HTTP: stored data; current meta.request_id/X-Request-Id, no-store/Vary Authorization,
//    Idempotency-Replayed=true. This candidate does not install a new route or SDK RPC type.
