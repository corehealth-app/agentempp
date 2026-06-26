/**
 * loadVisionPending — carrega a última foto de refeição analisada por vision
 * que AINDA NÃO virou meal_log nem pending.
 *
 * Extraído de pipeline.ts (audit 06-26 sprint pendentes Item 6) pra ganhar
 * teste ponta-a-ponta. Comportamento PRESERVADO byte-a-byte da implementação
 * original (audit 06-25 Bug B Roberto 25/06 — 2 fotos no mesmo turno).
 *
 * Cenário:
 *  - 2+ visions com mesmo provider_message_id (batch Promise.all) →
 *    agrega items (union dedup por nome normalizado) em um bucket.
 *  - Itera buckets do mais recente pro mais antigo, retorna o primeiro
 *    AINDA pendente (não consumido por meal_log OU pending).
 *  - "Consumido" = (a) match por pmid OU (b) overlap nome ≥ 50% normalizado.
 */

export type VisionPendingItem = {
  name: string
  quantity_g_estimate: number
  confidence: number
}

export type VisionPendingResult = {
  items: VisionPendingItem[]
  mealContext: string | null
  occurredAt: string
  ageMinutes: number
} | null

const WINDOW_MS = 4 * 60 * 60 * 1000 // 4h
const OVERLAP_THRESHOLD = 0.5
const MAX_VISIONS = 10

export const stripAccents = (s: string): string =>
  s.toLowerCase().normalize('NFD').replace(/\p{Diacritic}/gu, '').trim()

type VisionRow = {
  properties: {
    type?: string
    provider_message_id?: string | null
    meal_items?: VisionPendingItem[] | null
    meal_context?: string | null
  }
  occurred_at: string
}

type MealRow = {
  food_name: string
  provider_message_id?: string | null
  created_at: string
}

type PendRow = {
  id: string
  proposal?: { items?: Array<{ name?: string; food_name?: string }> } | null
  created_at: string
}

type Bucket = {
  pmid: string | null
  items: VisionPendingItem[]
  mealContext: string | null
  occurredAt: string
}

// Tipo mínimo do cliente — só o que loadVisionPending usa. Permite mock
// trivial no teste (objeto com método from() retornando builder fake).
// Audit 06-26 review MED 4: tipos estritos do PostgrestQueryBuilder são
// complexos demais pra simular aqui (perderia compat com o cliente real).
// Mantém `from: (t) => any` mas internamente sem casts adicionais (antes
// eram 3× `as any` repetidos no corpo da função).
export type VisionPendingSupabase = {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  from: (table: string) => any
}

/**
 * Implementação pura — recebe rows já materializados, sem I/O. Útil pra
 * testes unitários byte-a-byte. `loadVisionPending` (com I/O) só executa
 * as 3 queries e delega aqui.
 */
export function deriveVisionPending(
  visions: VisionRow[],
  mealRows: MealRow[],
  pendRows: PendRow[],
  nowMs: number,
): VisionPendingResult {
  if (visions.length === 0) return null

  // Bucket por pmid (cobre 2 fotos no mesmo webhook turn).
  const buckets = new Map<string, Bucket>()
  for (const v of visions) {
    if (v.properties.type !== 'meal') continue
    const mealItems = v.properties.meal_items
    if (!mealItems || mealItems.length === 0) continue
    const pmid = v.properties.provider_message_id ?? null
    const key = pmid ?? `_no_pmid_${v.occurred_at}`
    const existing = buckets.get(key)
    if (existing) {
      const existingNames = new Set(existing.items.map((it) => stripAccents(it.name)))
      for (const it of mealItems) {
        if (!existingNames.has(stripAccents(it.name))) {
          existing.items.push(it)
        }
      }
      if (!existing.mealContext && v.properties.meal_context) {
        existing.mealContext = v.properties.meal_context
      }
    } else {
      buckets.set(key, {
        pmid,
        items: [...mealItems],
        mealContext: v.properties.meal_context ?? null,
        occurredAt: v.occurred_at,
      })
    }
  }

  const orderedBuckets = Array.from(buckets.values()).sort((a, b) =>
    b.occurredAt.localeCompare(a.occurredAt),
  )

  for (const b of orderedBuckets) {
    const visionNames = new Set(b.items.map((it) => stripAccents(it.name)))
    const mealsAfterThis = mealRows.filter((r) => r.created_at >= b.occurredAt)
    const pendsAfterThis = pendRows.filter((p) => p.created_at >= b.occurredAt)

    // (a) match por pmid
    if (b.pmid && mealsAfterThis.some((r) => r.provider_message_id === b.pmid)) {
      continue
    }
    // (b) overlap nome ≥ 50%
    const consumedNames = new Set<string>()
    for (const r of mealsAfterThis) consumedNames.add(stripAccents(r.food_name))
    for (const p of pendsAfterThis) {
      for (const it of p.proposal?.items ?? []) {
        const nm = it.name ?? it.food_name ?? ''
        if (nm) consumedNames.add(stripAccents(nm))
      }
    }
    if (consumedNames.size > 0) {
      let overlap = 0
      for (const n of visionNames) {
        if (consumedNames.has(n)) overlap++
      }
      const overlapRatio = visionNames.size > 0 ? overlap / visionNames.size : 0
      if (overlapRatio >= OVERLAP_THRESHOLD) continue
    }

    const ageMinutes = Math.max(
      0,
      Math.round((nowMs - new Date(b.occurredAt).getTime()) / 60_000),
    )
    return {
      items: b.items,
      mealContext: b.mealContext,
      occurredAt: b.occurredAt,
      ageMinutes,
    }
  }
  return null
}

export async function loadVisionPending(
  supabase: VisionPendingSupabase,
  userId: string,
): Promise<VisionPendingResult> {
  const sinceIso = new Date(Date.now() - WINDOW_MS).toISOString()
  const { data: recentVisions } = await supabase
    .from('product_events')
    .select('properties, occurred_at')
    .eq('user_id', userId)
    .eq('event', 'vision.analyzed')
    .gte('occurred_at', sinceIso)
    .order('occurred_at', { ascending: false })
    .limit(MAX_VISIONS)
  const visions = (recentVisions ?? []) as VisionRow[]
  if (visions.length === 0) return null

  const oldestVisionIso = visions[visions.length - 1]!.occurred_at
  const [mealsAfter, pendingsAfter] = await Promise.all([
    supabase
      .from('meal_logs')
      .select('food_name, provider_message_id, created_at')
      .eq('user_id', userId)
      .gte('created_at', oldestVisionIso),
    supabase
      .from('pending_registrations')
      .select('id, proposal, created_at')
      .eq('user_id', userId)
      .gte('created_at', oldestVisionIso),
  ])
  const mealRows = (mealsAfter.data ?? []) as MealRow[]
  const pendRows = (pendingsAfter.data ?? []) as PendRow[]

  return deriveVisionPending(visions, mealRows, pendRows, Date.now())
}
