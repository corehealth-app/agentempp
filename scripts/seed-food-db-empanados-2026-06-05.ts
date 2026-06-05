/**
 * Seed food_db com preparos brasileiros calóricos sem entry (Roberto 05/06).
 *
 * Contexto: Roberto reportou "frango à milanesa" sendo registrado com 165 kcal/100g
 * (igual a frango cozido), quando o real é ~280 kcal/100g. Causa: food_db não
 * tem entries pra preparos empanados/fritos. Trigram cai em "asa de frango"
 * (sim=0.39, < threshold 0.45) → fallback pega "frango cozido" → kcal errado.
 *
 * Esta migration cobre os preparos calóricos mais comuns no padrão BR:
 *
 * Valores: TACO IV USP onde disponível, USDA SR Legacy como fallback.
 *
 * Também CORRIGE "frango à parmegiana" id=298 (215 → 265 kcal/100g — subestimado).
 *
 * Idempotente: pula se name_pt já existe case-insensitive.
 *
 * Rodar: set -a; . ./.env.local; set +a; npx tsx scripts/seed-food-db-empanados-2026-06-05.ts
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

const ENTRIES: FoodEntry[] = [
  // Frango empanado / milanesa — TACO: filé empanado frito ~277 kcal/100g
  { name_pt: 'frango à milanesa', category: 'pratos', kcal_per_100g: 280, protein_g: 23.0, carbs_g: 11.0, fat_g: 16.0, fiber_g: 0.5, source: 'TACO_IV' },
  { name_pt: 'frango empanado', category: 'pratos', kcal_per_100g: 280, protein_g: 23.0, carbs_g: 11.0, fat_g: 16.0, fiber_g: 0.5, source: 'TACO_IV' },
  { name_pt: 'filé de frango empanado', category: 'pratos', kcal_per_100g: 280, protein_g: 23.0, carbs_g: 11.0, fat_g: 16.0, fiber_g: 0.5, source: 'TACO_IV' },
  { name_pt: 'peito de frango empanado', category: 'pratos', kcal_per_100g: 280, protein_g: 23.0, carbs_g: 11.0, fat_g: 16.0, fiber_g: 0.5, source: 'TACO_IV' },
  // Frango à passarinho (frito inteiro com pele) — mais gordura
  { name_pt: 'frango à passarinho', category: 'pratos', kcal_per_100g: 290, protein_g: 24.0, carbs_g: 3.0, fat_g: 21.0, fiber_g: 0, source: 'USDA_SR' },
  // Nuggets — bem processado
  { name_pt: 'nuggets de frango', category: 'pratos', kcal_per_100g: 295, protein_g: 14.0, carbs_g: 18.0, fat_g: 18.0, fiber_g: 0.5, source: 'USDA_SR' },

  // Bife empanado / à milanesa — carne tem mais gordura
  { name_pt: 'bife à milanesa', category: 'pratos', kcal_per_100g: 300, protein_g: 22.0, carbs_g: 12.0, fat_g: 17.0, fiber_g: 0.5, source: 'TACO_IV_avg' },
  { name_pt: 'bife empanado', category: 'pratos', kcal_per_100g: 300, protein_g: 22.0, carbs_g: 12.0, fat_g: 17.0, fiber_g: 0.5, source: 'TACO_IV_avg' },
  // Bife à parmegiana — empanado + queijo derretido + molho de tomate
  { name_pt: 'bife à parmegiana', category: 'pratos', kcal_per_100g: 290, protein_g: 20.0, carbs_g: 13.0, fat_g: 17.0, fiber_g: 1.0, source: 'TACO_IV_avg' },
  // Escalope (genérico empanado)
  { name_pt: 'escalope à milanesa', category: 'pratos', kcal_per_100g: 280, protein_g: 22.0, carbs_g: 11.0, fat_g: 16.0, fiber_g: 0.5, source: 'TACO_IV_avg' },

  // Peixe empanado — TACO: filé de peixe empanado ~220 kcal/100g
  { name_pt: 'peixe à milanesa', category: 'pratos', kcal_per_100g: 220, protein_g: 18.0, carbs_g: 13.0, fat_g: 11.0, fiber_g: 0.5, source: 'TACO_IV' },
  { name_pt: 'filé de peixe empanado', category: 'pratos', kcal_per_100g: 220, protein_g: 18.0, carbs_g: 13.0, fat_g: 11.0, fiber_g: 0.5, source: 'TACO_IV' },
]

async function main() {
  const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!url || !key) throw new Error('SUPABASE_URL/SERVICE_ROLE_KEY ausente')
  const supabase = createServiceClient({ url, serviceRoleKey: key })

  console.log(`Seed food_db empanados: ${ENTRIES.length} entries candidatas\n`)

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const sp = supabase as any
  const { data: existing } = await sp.from('food_db').select('name_pt').eq('country_code', 'BR')
  const existingSet = new Set(
    ((existing ?? []) as Array<{ name_pt: string }>).map((r) => r.name_pt.toLowerCase()),
  )

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
    console.log(`  ✅ ${e.name_pt} (${e.kcal_per_100g} kcal/100g)`)
    inserted++
  }

  // Corrigir frango à parmegiana subestimado (215 → 265)
  console.log('\n── Corrigindo "frango à parmegiana" 215 → 265 ──')
  const { data: parmRows, error: parmErr } = await sp
    .from('food_db')
    .update({ kcal_per_100g: 265, protein_g: 22.0, carbs_g: 13.0, fat_g: 14.0 })
    .eq('id', 298)
    .select('name_pt, kcal_per_100g, protein_g, fat_g')
  if (parmErr) console.error(`  ❌ ${parmErr.message}`)
  else console.log(`  ✅ ${JSON.stringify(parmRows?.[0])}`)

  console.log(`\n${inserted}/${toInsert.length} entries inseridas.`)

  // Validação
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
  console.log(`\n${pass}/${toInsert.length} com match perfeito.`)
}

main().catch((e) => {
  console.error('❌', e)
  process.exit(1)
})
