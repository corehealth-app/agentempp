/**
 * Pipeline de processamento de refeição.
 *
 * Recebe lista de itens (nome + quantidade) → faz match na food_db (TACO) →
 * calcula macros determinísticamente.
 *
 * ADR-006: cálculos saem da TACO, não do LLM.
 */
import type { ServiceClient } from '@mpp/db'

export interface MealItemInput {
  food_name: string
  quantity_g: number
}

export interface MealItemMatched {
  food_name: string
  matched_taco_name: string
  matched_taco_id: number | null
  quantity_g: number
  kcal: number
  protein_g: number
  carbs_g: number
  fat_g: number
  fiber_g: number
  similarity: number
  source: 'taco' | 'llm_estimate' | 'no_match'
}

export interface MealCalcResult {
  items: MealItemMatched[]
  totals: {
    kcal: number
    protein_g: number
    carbs_g: number
    fat_g: number
    fiber_g: number
  }
  warnings: string[]
}

/**
 * Match fuzzy via pg_trgm.
 * Threshold de 0.3 (ajustável). Acima disso confiamos no match.
 */
async function matchFood(
  supabase: ServiceClient,
  name: string,
  country: string = 'BR',
): Promise<{
  id: number | null
  name_pt: string | null
  similarity: number
  kcal_per_100g: number | null
  protein_g: number | null
  carbs_g: number | null
  fat_g: number | null
  fiber_g: number | null
}> {
  // Normaliza + filtra por país (BR=TACO; US=USDA quando populado, etc.)
  const { data, error } = await (supabase as unknown as {
    rpc: (n: string, p: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }>
  }).rpc('search_food_trgm', {
    search_term: name.toLowerCase(),
    min_similarity: 0.2,
    max_results: 1,
    p_country: country,
  })

  const empty = {
    id: null,
    name_pt: null,
    similarity: 0,
    kcal_per_100g: null,
    protein_g: null,
    carbs_g: null,
    fat_g: null,
    fiber_g: null,
  }

  type Row = {
    id: number | null
    name_pt: string | null
    similarity: number | null
    kcal_per_100g: number | string | null
    protein_g: number | string | null
    carbs_g: number | string | null
    fat_g: number | string | null
    fiber_g: number | string | null
  }
  const rows = (data ?? []) as Row[]
  if (error || rows.length === 0) return empty

  const top = rows[0]
  if (!top) return empty
  return {
    id: top.id ?? null,
    name_pt: top.name_pt ?? null,
    similarity: top.similarity ?? 0,
    kcal_per_100g: top.kcal_per_100g != null ? Number(top.kcal_per_100g) : null,
    protein_g: top.protein_g != null ? Number(top.protein_g) : null,
    carbs_g: top.carbs_g != null ? Number(top.carbs_g) : null,
    fat_g: top.fat_g != null ? Number(top.fat_g) : null,
    fiber_g: top.fiber_g != null ? Number(top.fiber_g) : null,
  }
}

/**
 * Calcula macros para uma lista de itens.
 * Cada item identificado vai para a food_db. Itens sem match recebem
 * estimativa zero e o warning é registrado.
 */
export async function calcMealMacros(
  supabase: ServiceClient,
  items: MealItemInput[],
  country: string = 'BR',
): Promise<MealCalcResult> {
  const matched: MealItemMatched[] = []
  const warnings: string[] = []
  const totals = { kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0, fiber_g: 0 }

  for (const it of items) {
    const m = await matchFood(supabase, it.food_name, country)
    const factor = it.quantity_g / 100

    if (m.id != null && m.kcal_per_100g != null && m.similarity >= 0.3) {
      const kcal = +(m.kcal_per_100g * factor).toFixed(1)
      const protein = +((m.protein_g ?? 0) * factor).toFixed(2)
      const carbs = +((m.carbs_g ?? 0) * factor).toFixed(2)
      const fat = +((m.fat_g ?? 0) * factor).toFixed(2)
      const fiber = +((m.fiber_g ?? 0) * factor).toFixed(2)

      matched.push({
        food_name: it.food_name,
        matched_taco_name: m.name_pt ?? '',
        matched_taco_id: m.id,
        quantity_g: it.quantity_g,
        kcal,
        protein_g: protein,
        carbs_g: carbs,
        fat_g: fat,
        fiber_g: fiber,
        similarity: m.similarity,
        source: 'taco',
      })

      totals.kcal += kcal
      totals.protein_g += protein
      totals.carbs_g += carbs
      totals.fat_g += fat
      totals.fiber_g += fiber

      if (m.similarity < 0.5) {
        warnings.push(
          `Match com baixa confiança: "${it.food_name}" → "${m.name_pt}" (sim=${m.similarity.toFixed(2)})`,
        )
      }
    } else {
      warnings.push(`Sem match TACO para: "${it.food_name}" — calorias zeradas`)
      matched.push({
        food_name: it.food_name,
        matched_taco_name: '',
        matched_taco_id: null,
        quantity_g: it.quantity_g,
        kcal: 0,
        protein_g: 0,
        carbs_g: 0,
        fat_g: 0,
        fiber_g: 0,
        similarity: 0,
        source: 'no_match',
      })
    }
  }

  return { items: matched, totals: roundTotals(totals), warnings }
}

function roundTotals(t: { kcal: number; protein_g: number; carbs_g: number; fat_g: number; fiber_g: number }) {
  return {
    kcal: +t.kcal.toFixed(1),
    protein_g: +t.protein_g.toFixed(1),
    carbs_g: +t.carbs_g.toFixed(1),
    fat_g: +t.fat_g.toFixed(1),
    fiber_g: +t.fiber_g.toFixed(1),
  }
}
