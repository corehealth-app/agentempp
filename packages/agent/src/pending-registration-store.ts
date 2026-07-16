import type { Database, Json, ServiceClient } from '@mpp/db'
import { throwIfQueryFailed } from './db-query-error.js'
import { foodNamesReferToSameItem } from './meal-replacement-target.js'
import type { MealItem } from './post-registration-message.js'

export type PendingMealRow = {
  id: string
  proposal: Json | null
  created_at: string
}

export type EditedPendingMealRow = {
  id: string
  proposal: Json | null
  resolved_at: string | null
}

export type ConfirmedPendingMealRow = {
  id: string
  proposal: Json | null
  resolved_at: string | null
}

type RegisteredMealRow = {
  id: string
  food_name: string
  quantity_g: number | string | null
  kcal: number | string | null
  protein_g: number | string | null
  carbs_g: number | string | null
  fat_g: number | string | null
  source: string | null
  food_db_id: number | null
  consumed_at: string
  created_at: string
  raw_provider_message_id: string | null
}

export type RecentRegisteredMeal = {
  groupKey: string
  items: MealItem[]
}

export async function loadRecentPendingMeal(
  supabase: ServiceClient,
  userId: string,
  now: Date = new Date(),
): Promise<PendingMealRow | null> {
  const lookback = new Date(now.getTime() - 5 * 60 * 1000).toISOString()
  const { data, error } = await supabase
    .from('pending_registrations')
    .select('id, proposal, created_at')
    .eq('user_id', userId)
    .eq('status', 'pending')
    .eq('proposal->>kind', 'meal')
    .gte('created_at', lookback)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle()

  throwIfQueryFailed(error, 'recent pending meal lookup failed')
  return (data as PendingMealRow | null) ?? null
}

export async function loadRecentEditedMealPending(
  supabase: ServiceClient,
  userId: string,
  mealType: string,
  now: Date = new Date(),
): Promise<EditedPendingMealRow | null> {
  const lookback = new Date(now.getTime() - 30 * 60 * 1000).toISOString()
  const { data, error } = await supabase
    .from('pending_registrations')
    .select('id, proposal, resolved_at')
    .eq('user_id', userId)
    .eq('status', 'edited')
    .eq('proposal->>kind', 'meal')
    .eq('proposal->>mealType', mealType)
    .gte('resolved_at', lookback)
    .order('resolved_at', { ascending: false })
    .limit(1)
    .maybeSingle()

  throwIfQueryFailed(error, 'recent edited pending meal lookup failed')
  return (data as EditedPendingMealRow | null) ?? null
}

export async function loadRecentConfirmedMealPending(
  supabase: ServiceClient,
  userId: string,
  mealType: string,
  now: Date = new Date(),
  correctedFoodNames: string[] = [],
): Promise<ConfirmedPendingMealRow | null> {
  const lookback = new Date(now.getTime() - 30 * 60 * 1000).toISOString()
  const { data, error } = await supabase
    .from('pending_registrations')
    .select('id, proposal, resolved_at')
    .eq('user_id', userId)
    .eq('status', 'confirmed')
    .eq('proposal->>kind', 'meal')
    .eq('proposal->>mealType', mealType)
    .gte('resolved_at', lookback)
    .order('resolved_at', { ascending: false })
    .limit(5)

  throwIfQueryFailed(error, 'recent confirmed pending meal lookup failed')
  const rows = Array.isArray(data)
    ? (data as ConfirmedPendingMealRow[])
    : data
      ? [data as ConfirmedPendingMealRow]
      : []
  if (correctedFoodNames.length === 0) return rows[0] ?? null

  return (
    rows.find((row) => {
      const proposal = row.proposal as { items?: Array<{ name?: string }> } | null
      const itemNames = (proposal?.items ?? [])
        .map((item) => item.name?.trim() ?? '')
        .filter(Boolean)
      return correctedFoodNames.every((correctedName) =>
        itemNames.some((itemName) => foodNamesReferToSameItem(itemName, correctedName)),
      )
    }) ?? null
  )
}

export async function loadRecentRegisteredMeal(
  supabase: ServiceClient,
  userId: string,
  mealType: string,
  now: Date = new Date(),
  correctedFoodNames: string[] = [],
): Promise<RecentRegisteredMeal | null> {
  const lookback = new Date(now.getTime() - 30 * 60 * 1000).toISOString()
  const { data, error } = await supabase
    .from('meal_logs')
    .select(
      'id, food_name, quantity_g, kcal, protein_g, carbs_g, fat_g, source, food_db_id, consumed_at, created_at, raw_provider_message_id',
    )
    .eq('user_id', userId)
    .eq('meal_type', mealType as Database['public']['Enums']['meal_type_enum'])
    .gte('created_at', lookback)
    .order('created_at', { ascending: false })
    .limit(60)

  throwIfQueryFailed(error, 'recent registered meal lookup failed')
  const rows = (Array.isArray(data) ? data : data ? [data] : []) as RegisteredMealRow[]
  const groups = new Map<string, RegisteredMealRow[]>()
  for (const row of rows) {
    const key = row.raw_provider_message_id
      ? `provider:${row.raw_provider_message_id}`
      : `time:${row.consumed_at}`
    groups.set(key, [...(groups.get(key) ?? []), row])
  }

  const candidates = [...groups.entries()]
    .filter(([, groupRows]) =>
      correctedFoodNames.every((correctedName) =>
        groupRows.some((row) => foodNamesReferToSameItem(row.food_name, correctedName)),
      ),
    )
    .sort(
      ([, left], [, right]) =>
        Math.max(...right.map((row) => Date.parse(row.created_at) || 0)) -
        Math.max(...left.map((row) => Date.parse(row.created_at) || 0)),
    )

  for (const [groupKey, groupRows] of candidates) {
    const items = groupRows.map((row): MealItem | null => {
      const quantity = Number(row.quantity_g)
      const kcal = Number(row.kcal)
      const protein = Number(row.protein_g)
      const carbs = Number(row.carbs_g)
      const fat = Number(row.fat_g)
      if (
        !Number.isFinite(quantity) ||
        quantity <= 0 ||
        !Number.isFinite(kcal) ||
        !Number.isFinite(protein) ||
        !Number.isFinite(carbs) ||
        !Number.isFinite(fat)
      ) {
        return null
      }
      return {
        name: row.food_name,
        food_db_id: row.food_db_id,
        nutrition_source: row.source,
        quantity_g: quantity,
        display_qty: null,
        display_unit: null,
        kcal,
        protein_g: protein,
        carbs_g: carbs,
        fat_g: fat,
      }
    })
    if (items.every((item): item is MealItem => item !== null)) {
      return { groupKey, items }
    }
  }

  return null
}

export async function cancelOpenPendingRegistrations(
  supabase: ServiceClient,
  userId: string,
  resolvedAt: Date = new Date(),
): Promise<void> {
  const { error } = await supabase
    .from('pending_registrations')
    .update({ status: 'cancelled', resolved_at: resolvedAt.toISOString() })
    .eq('user_id', userId)
    .eq('status', 'pending')

  throwIfQueryFailed(error, 'open pending cancellation failed')
}

export async function createPendingRegistration(
  supabase: ServiceClient,
  input: {
    userId: string
    proposal: Json
    expiresAt: string
    requestKey?: string | null
  },
): Promise<string> {
  const { data, error } = await (
    supabase as unknown as {
      rpc: (
        name: string,
        params: Record<string, unknown>,
      ) => Promise<{ data: unknown; error: unknown }>
    }
  ).rpc('replace_pending_registration_atomic', {
    p_user_id: input.userId,
    p_proposal: input.proposal,
    p_expires_at: input.expiresAt,
    p_request_key: input.requestKey ?? null,
  })

  throwIfQueryFailed(error, 'pending registration transaction failed')
  const pendingId = (data as { pending_id?: string } | null)?.pending_id
  if (!pendingId) throw new Error('pending registration insert returned no id')
  return pendingId
}
