/**
 * Seed food_db com os top alimentos que apareciam em meal_logs sem entry
 * exata em food_db, caindo em fallback (llm_estimate, trigram fraco, ou
 * match catastrófico tipo moela→asa de frango 290 kcal/100g).
 *
 * Análise feita 2026-06-04: 17% dos meal_logs em 30d eram fallback. Os 22
 * itens abaixo cobrem ~200 logs/mês.
 *
 * Valores principais: TACO IV USP (Tabela Brasileira de Composição de
 * Alimentos). Quando TACO não tinha entry, fallback USDA SR Legacy.
 *
 * Idempotente: pula se name_pt já existe (sem UNIQUE constraint, então
 * check manual).
 *
 * Rodar: set -a; . ./.env.local; set +a; npx tsx scripts/seed-food-db-gaps-2026-06-04.ts
 */
import { createServiceClient } from '@mpp/db'

interface FoodEntry {
  name_pt: string
  category: string
  kcal_per_100g: number
  protein_g: number
  carbs_g: number
  fat_g: number
  fiber_g: number
  source: string
}

// Todos valores TACO IV USP (oficial brasileiro). Quando indicado [USDA],
// fallback USDA SR Legacy. Categoria segue convenção do food_db.
const ENTRIES: FoodEntry[] = [
  // Laticínios
  { name_pt: 'leite semi desnatado', category: 'laticínios', kcal_per_100g: 46, protein_g: 3.3, carbs_g: 4.9, fat_g: 1.6, fiber_g: 0, source: 'TACO_IV' },
  { name_pt: 'leite em pó desnatado', category: 'laticínios', kcal_per_100g: 360, protein_g: 35.0, carbs_g: 52.0, fat_g: 1.0, fiber_g: 0, source: 'TACO_IV' },
  { name_pt: 'leite em pó integral', category: 'laticínios', kcal_per_100g: 496, protein_g: 26.0, carbs_g: 38.0, fat_g: 27.0, fiber_g: 0, source: 'TACO_IV' },
  { name_pt: 'iogurte desnatado', category: 'laticínios', kcal_per_100g: 41, protein_g: 4.1, carbs_g: 4.0, fat_g: 0.1, fiber_g: 0, source: 'TACO_IV' },
  { name_pt: 'iogurte zero açúcar', category: 'laticínios', kcal_per_100g: 41, protein_g: 4.1, carbs_g: 4.0, fat_g: 0.1, fiber_g: 0, source: 'TACO_IV' }, // idem desnatado
  { name_pt: 'iogurte natural integral', category: 'laticínios', kcal_per_100g: 61, protein_g: 3.5, carbs_g: 4.7, fat_g: 3.3, fiber_g: 0, source: 'TACO_IV' },

  // Cereais / massas / acompanhamentos
  { name_pt: 'milho verde cozido', category: 'cereais', kcal_per_100g: 98, protein_g: 3.3, carbs_g: 21.1, fat_g: 1.2, fiber_g: 3.9, source: 'TACO_IV' },
  { name_pt: 'milho cozido', category: 'cereais', kcal_per_100g: 98, protein_g: 3.3, carbs_g: 21.1, fat_g: 1.2, fiber_g: 3.9, source: 'TACO_IV' }, // alias
  { name_pt: 'cuscuz de milho cozido sem sal', category: 'cereais', kcal_per_100g: 112, protein_g: 3.6, carbs_g: 23.5, fat_g: 0.6, fiber_g: 1.0, source: 'TACO_IV' },
  { name_pt: 'cuscuz cozido', category: 'cereais', kcal_per_100g: 112, protein_g: 3.6, carbs_g: 23.5, fat_g: 0.6, fiber_g: 1.0, source: 'TACO_IV' }, // alias
  { name_pt: 'arroz branco com ervilha', category: 'cereais', kcal_per_100g: 120, protein_g: 3.5, carbs_g: 23.0, fat_g: 1.0, fiber_g: 1.5, source: 'TACO_IV_calc' },
  { name_pt: 'feijão cozido', category: 'leguminosas', kcal_per_100g: 76, protein_g: 4.8, carbs_g: 13.6, fat_g: 0.5, fiber_g: 8.5, source: 'TACO_IV' }, // genérico ~carioca

  // Ovos
  { name_pt: 'ovo mexido', category: 'ovos', kcal_per_100g: 196, protein_g: 13.6, carbs_g: 1.6, fat_g: 15.4, fiber_g: 0, source: 'USDA_SR' },

  // Carnes
  { name_pt: 'carne assada', category: 'carnes', kcal_per_100g: 215, protein_g: 32.0, carbs_g: 0, fat_g: 9.0, fiber_g: 0, source: 'TACO_IV_avg' }, // média assada magra
  { name_pt: 'bife grelhado', category: 'carnes', kcal_per_100g: 220, protein_g: 32.0, carbs_g: 0, fat_g: 10.0, fiber_g: 0, source: 'TACO_IV_avg' },
  { name_pt: 'carne cozida em cubos', category: 'carnes', kcal_per_100g: 200, protein_g: 30.0, carbs_g: 0, fat_g: 8.0, fiber_g: 0, source: 'TACO_IV_avg' },
  { name_pt: 'carne de porco assada', category: 'carnes', kcal_per_100g: 250, protein_g: 28.0, carbs_g: 0, fat_g: 14.0, fiber_g: 0, source: 'TACO_IV' }, // lombo assado
  { name_pt: 'costelinha de porco assada', category: 'carnes', kcal_per_100g: 290, protein_g: 25.0, carbs_g: 0, fat_g: 21.0, fiber_g: 0, source: 'TACO_IV' },

  // Frutas
  { name_pt: 'banana', category: 'frutas', kcal_per_100g: 89, protein_g: 1.1, carbs_g: 22.8, fat_g: 0.3, fiber_g: 2.6, source: 'TACO_IV' }, // média nanica/prata
  { name_pt: 'mamão picado', category: 'frutas', kcal_per_100g: 45, protein_g: 0.5, carbs_g: 11.0, fat_g: 0.1, fiber_g: 1.8, source: 'TACO_IV' }, // alias mamão formosa

  // Vegetais / saladas
  { name_pt: 'alface', category: 'vegetais', kcal_per_100g: 11, protein_g: 1.3, carbs_g: 1.7, fat_g: 0.2, fiber_g: 1.7, source: 'TACO_IV' }, // genérico crespa/lisa
  { name_pt: 'salada de folhas verdes', category: 'vegetais', kcal_per_100g: 18, protein_g: 1.5, carbs_g: 3.0, fat_g: 0.3, fiber_g: 1.8, source: 'TACO_IV_avg' },
  { name_pt: 'quiabo refogado', category: 'vegetais', kcal_per_100g: 47, protein_g: 2.0, carbs_g: 8.0, fat_g: 1.5, fiber_g: 4.0, source: 'TACO_IV_calc' }, // cru 33 + óleo refog

  // Molhos
  { name_pt: 'molho de salada', category: 'molhos', kcal_per_100g: 100, protein_g: 0.5, carbs_g: 4.0, fat_g: 9.0, fiber_g: 0.5, source: 'USDA_SR_avg' }, // vinagrete genérico
]

async function main() {
  const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!url || !key) throw new Error('SUPABASE_URL/SERVICE_ROLE_KEY ausente')
  const supabase = createServiceClient({ url, serviceRoleKey: key })

  console.log(`Seed food_db: ${ENTRIES.length} entries candidatas\n`)

  // Pega quem já existe (case insensitive)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const sp = supabase as any
  const { data: existing } = await sp.from('food_db').select('name_pt').eq('country_code', 'BR')
  const existingSet = new Set(((existing ?? []) as Array<{ name_pt: string }>).map((r) => r.name_pt.toLowerCase()))

  const toInsert = ENTRIES.filter((e) => !existingSet.has(e.name_pt.toLowerCase()))
  console.log(`Pulando ${ENTRIES.length - toInsert.length} já existentes`)
  console.log(`Inserindo ${toInsert.length} novas\n`)

  let inserted = 0
  for (const e of toInsert) {
    const { error } = await sp.from('food_db').insert({
      name_pt: e.name_pt,
      category: e.category,
      kcal_per_100g: e.kcal_per_100g,
      protein_g: e.protein_g,
      carbs_g: e.carbs_g,
      fat_g: e.fat_g,
      fiber_g: e.fiber_g,
      source: e.source,
      country_code: 'BR',
    })
    if (error) {
      console.error(`  ❌ ${e.name_pt}: ${error.message}`)
      continue
    }
    console.log(`  ✅ ${e.name_pt} (${e.kcal_per_100g} kcal/100g, ${e.source})`)
    inserted++
  }

  console.log(`\n${inserted}/${toInsert.length} inseridos com sucesso.`)

  // Validação: rodar search_food_trgm pra cada nome inserido e confirmar sim=1.0
  console.log('\n── Validação trgm ──')
  let pass = 0
  for (const e of toInsert) {
    const { data } = await sp.rpc('search_food_trgm', {
      search_term: e.name_pt.toLowerCase(),
      min_similarity: 0.5,
      max_results: 1,
      p_country: 'BR',
    })
    const top = ((data ?? []) as Array<{ similarity: number; name_pt: string }>)[0]
    const sim = top?.similarity ?? 0
    const ok = sim >= 0.99
    if (ok) pass++
    console.log(`  ${ok ? '✅' : '⚠️'} "${e.name_pt}" → sim=${sim.toFixed(3)} (top=${top?.name_pt ?? 'NONE'})`)
  }
  console.log(`\nValidação: ${pass}/${toInsert.length} com match perfeito.`)
}

main().catch((e) => {
  console.error('❌', e)
  process.exit(1)
})
