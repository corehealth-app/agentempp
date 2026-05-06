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
  source:
    | 'taco'
    | 'llm_estimate'
    | 'no_match'
    /** Nome com "X com Y", "X e Y" — paciente passou prato composto. */
    | 'composite_rejected'
    /** Match com densidade calórica de gordura mas food_name não é gordura. */
    | 'category_mismatch'
    /** Alimento que deveria ter proteína (ovo/carne/whey) bateu sem proteína. */
    | 'protein_mismatch'
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
    // Sanity 1: nome composto ("ovo com azeite", "leite com whey", "arroz e feijão").
    // Antes: rejeitava direto e zerava. Agora: tenta auto-split, busca cada parte
    // separadamente, divide a quantidade proporcionalmente. Se TODAS as partes
    // matcham bem, agrega os macros. Senão rejeita com warning.
    const isComposite =
      / com | e | \+ |\bcom\s+|^com\s+/i.test(` ${it.food_name} `) &&
      it.food_name.split(/\s+/).length >= 3
    if (isComposite) {
      const parts = it.food_name
        .split(/ com | e | \+ /i)
        .map((s) => s.trim())
        .filter((s) => s.length >= 2)
      // Dividir qty igual entre as partes
      const partQty = it.quantity_g / parts.length
      const partMatches: Array<{ name: string; m: Awaited<ReturnType<typeof matchFood>> }> = []
      for (const p of parts) {
        const pm = await matchFood(supabase, p, country)
        partMatches.push({ name: p, m: pm })
      }
      const allGood = partMatches.every((pm) => pm.m.similarity >= 0.45 && pm.m.kcal_per_100g != null)
      if (allGood) {
        // Adiciona cada parte como item separado, com nome composto preservado em matched_taco_name
        let totalKcal = 0,
          totalProt = 0,
          totalCarbs = 0,
          totalFat = 0,
          totalFib = 0
        for (const pm of partMatches) {
          const f = partQty / 100
          const kcal = +((pm.m.kcal_per_100g ?? 0) * f).toFixed(1)
          const prot = +((pm.m.protein_g ?? 0) * f).toFixed(2)
          const carb = +((pm.m.carbs_g ?? 0) * f).toFixed(2)
          const fat = +((pm.m.fat_g ?? 0) * f).toFixed(2)
          const fib = +((pm.m.fiber_g ?? 0) * f).toFixed(2)
          totalKcal += kcal
          totalProt += prot
          totalCarbs += carb
          totalFat += fat
          totalFib += fib
        }
        matched.push({
          food_name: it.food_name,
          matched_taco_name: partMatches.map((pm) => pm.m.name_pt).join(' + '),
          matched_taco_id: null,
          quantity_g: it.quantity_g,
          kcal: +totalKcal.toFixed(1),
          protein_g: +totalProt.toFixed(2),
          carbs_g: +totalCarbs.toFixed(2),
          fat_g: +totalFat.toFixed(2),
          fiber_g: +totalFib.toFixed(2),
          similarity: Math.min(...partMatches.map((pm) => pm.m.similarity)),
          source: 'taco',
        })
        totals.kcal += totalKcal
        totals.protein_g += totalProt
        totals.carbs_g += totalCarbs
        totals.fat_g += totalFat
        totals.fiber_g += totalFib
        warnings.push(
          `"${it.food_name}" auto-dividido em ${partMatches.map((pm) => pm.m.name_pt).join(' + ')} (qty ${partQty.toFixed(0)}g cada). Quando souber quantidades exatas, separe os itens.`,
        )
        continue
      }
      // Algum part não matchou — mantém rejeição
      warnings.push(
        `Item composto rejeitado: "${it.food_name}" — não consegui separar em alimentos conhecidos. Peça pro paciente separar (ex: "leite 250ml" + "whey 30g"). Calorias zeradas.`,
      )
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
        source: 'composite_rejected',
      })
      continue
    }

    const m = await matchFood(supabase, it.food_name, country)
    const factor = it.quantity_g / 100

    // Threshold mais conservador: 0.45 (era 0.3). Matches abaixo disso são quase
    // sempre erros (ex: "ovo" pegando "azeite" sim=0.3).
    if (m.id != null && m.kcal_per_100g != null && m.similarity >= 0.45) {
      const kcal = +(m.kcal_per_100g * factor).toFixed(1)
      const protein = +((m.protein_g ?? 0) * factor).toFixed(2)
      const carbs = +((m.carbs_g ?? 0) * factor).toFixed(2)
      const fat = +((m.fat_g ?? 0) * factor).toFixed(2)
      const fiber = +((m.fiber_g ?? 0) * factor).toFixed(2)

      // Sanity 2: densidade calórica catastrófica. Alimento sólido com >5 kcal/g
      // só faz sentido pra gorduras puras (azeite=8.84, manteiga=7.2). Se food_name
      // não menciona gordura/óleo/manteiga, é sinal de match errado.
      const kcalPerG = (m.kcal_per_100g ?? 0) / 100
      const lowerName = it.food_name.toLowerCase()
      const isFatLike =
        /azeite|óleo|oleo|manteiga|margarina|maionese|gordura|óleos|nozes|castanha|amêndoa|amendoim|pasta de amendoim/.test(
          lowerName,
        )
      if (kcalPerG > 5 && !isFatLike) {
        warnings.push(
          `Match suspeito: "${it.food_name}" → "${m.name_pt}" (${m.kcal_per_100g} kcal/100g é densidade de gordura). Provavelmente match errado. Confirme com paciente. Calorias zeradas.`,
        )
        matched.push({
          food_name: it.food_name,
          matched_taco_name: m.name_pt ?? '',
          matched_taco_id: m.id,
          quantity_g: it.quantity_g,
          kcal: 0,
          protein_g: 0,
          carbs_g: 0,
          fat_g: 0,
          fiber_g: 0,
          similarity: m.similarity,
          source: 'category_mismatch',
        })
        continue
      }

      // Sanity 3: alimento c/ proteína esperada (carnes, peixes, ovos, embutidos,
      // laticínios proteicos) não pode ter protein_g=0. Match errado se sim.
      const expectsProtein =
        /\bovo|\bfrango|\bcarne|\bpeixe|\bwhey|\batum|\bfil[ée]|\bpicanha|\bbife|\bsalm[ãa]o|\btil[áa]pia|\bsalsicha|\blingu[ií]ça|\bbacon|\bpresunto|\bsalame|\bmortadela|\bperu|\bpernil|\bhamb[uú]rguer|\bnugget|\bisca|\bpat[ée]|\bmussarela|\bricota|\bcoalho|\bsardinha|\bcamar[ãa]o|\bcord[ãa]o\s+azul|\bcordeiro|\bcostela/.test(
          lowerName,
        )
      if (expectsProtein && (m.protein_g ?? 0) < 5) {
        warnings.push(
          `Match suspeito: "${it.food_name}" tem proteína esperada mas matchou "${m.name_pt}" (${m.protein_g}g/100g). Match errado. Confirme com paciente. Calorias zeradas.`,
        )
        matched.push({
          food_name: it.food_name,
          matched_taco_name: m.name_pt ?? '',
          matched_taco_id: m.id,
          quantity_g: it.quantity_g,
          kcal: 0,
          protein_g: 0,
          carbs_g: 0,
          fat_g: 0,
          fiber_g: 0,
          similarity: m.similarity,
          source: 'protein_mismatch',
        })
        continue
      }

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
