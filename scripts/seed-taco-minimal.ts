/**
 * Seed inicial de food_db com ~80 alimentos brasileiros mais comuns.
 * Valores nutricionais baseados na TACO 4ª edição (UNICAMP/NEPA).
 *
 * Para o seed COMPLETO da TACO (~600 itens), o cliente deve baixar o arquivo
 * oficial e usar `seed-taco-from-file.ts` (TODO).
 *
 * Uso:
 *   pnpm --filter @mpp/scripts seed:taco-minimal
 */
import { createClient } from '@supabase/supabase-js'
import type { Database } from '@mpp/db'

interface FoodItem {
  name_pt: string
  category: string
  kcal_per_100g: number
  protein_g: number
  carbs_g: number
  fat_g: number
  fiber_g?: number
}

// Fonte: TACO 4ª edição - valores por 100g de parte comestível
const FOODS: FoodItem[] = [
  // ========== Cereais e derivados ==========
  { name_pt: 'arroz branco cozido', category: 'cereais', kcal_per_100g: 128, protein_g: 2.5, carbs_g: 28.1, fat_g: 0.2, fiber_g: 1.6 },
  { name_pt: 'arroz integral cozido', category: 'cereais', kcal_per_100g: 124, protein_g: 2.6, carbs_g: 25.8, fat_g: 1.0, fiber_g: 2.7 },
  { name_pt: 'arroz parboilizado cozido', category: 'cereais', kcal_per_100g: 130, protein_g: 2.5, carbs_g: 28.6, fat_g: 0.4, fiber_g: 1.0 },
  { name_pt: 'pão francês', category: 'cereais', kcal_per_100g: 300, protein_g: 8.0, carbs_g: 58.6, fat_g: 3.1, fiber_g: 2.3 },
  { name_pt: 'pão integral', category: 'cereais', kcal_per_100g: 253, protein_g: 9.4, carbs_g: 49.9, fat_g: 3.0, fiber_g: 6.9 },
  { name_pt: 'pão de forma', category: 'cereais', kcal_per_100g: 287, protein_g: 9.4, carbs_g: 49.4, fat_g: 5.9, fiber_g: 2.3 },
  { name_pt: 'macarrão cozido', category: 'cereais', kcal_per_100g: 102, protein_g: 3.4, carbs_g: 19.9, fat_g: 0.9, fiber_g: 1.6 },
  { name_pt: 'aveia em flocos crua', category: 'cereais', kcal_per_100g: 394, protein_g: 13.9, carbs_g: 66.6, fat_g: 8.5, fiber_g: 9.1 },
  { name_pt: 'tapioca pronta', category: 'cereais', kcal_per_100g: 240, protein_g: 0.5, carbs_g: 59.0, fat_g: 0.3, fiber_g: 0.8 },
  { name_pt: 'cuscuz de milho cozido', category: 'cereais', kcal_per_100g: 113, protein_g: 2.2, carbs_g: 25.0, fat_g: 0.3, fiber_g: 0.9 },
  { name_pt: 'farinha de mandioca', category: 'cereais', kcal_per_100g: 361, protein_g: 1.2, carbs_g: 87.9, fat_g: 0.3, fiber_g: 6.4 },
  { name_pt: 'granola tradicional', category: 'cereais', kcal_per_100g: 471, protein_g: 11.5, carbs_g: 61.2, fat_g: 19.6, fiber_g: 7.9 },

  // ========== Leguminosas ==========
  { name_pt: 'feijão carioca cozido', category: 'leguminosas', kcal_per_100g: 76, protein_g: 4.8, carbs_g: 13.6, fat_g: 0.5, fiber_g: 8.5 },
  { name_pt: 'feijão preto cozido', category: 'leguminosas', kcal_per_100g: 77, protein_g: 4.5, carbs_g: 14.0, fat_g: 0.5, fiber_g: 8.4 },
  { name_pt: 'lentilha cozida', category: 'leguminosas', kcal_per_100g: 93, protein_g: 6.3, carbs_g: 16.3, fat_g: 0.5, fiber_g: 7.9 },
  { name_pt: 'grão de bico cozido', category: 'leguminosas', kcal_per_100g: 121, protein_g: 8.4, carbs_g: 21.2, fat_g: 1.4, fiber_g: 7.4 },
  { name_pt: 'soja cozida', category: 'leguminosas', kcal_per_100g: 131, protein_g: 12.5, carbs_g: 9.9, fat_g: 6.0, fiber_g: 6.2 },
  { name_pt: 'ervilha cozida', category: 'leguminosas', kcal_per_100g: 63, protein_g: 5.0, carbs_g: 9.2, fat_g: 0.4, fiber_g: 7.2 },

  // ========== Carnes ==========
  { name_pt: 'frango peito grelhado', category: 'carnes', kcal_per_100g: 159, protein_g: 32.0, carbs_g: 0, fat_g: 2.5, fiber_g: 0 },
  { name_pt: 'frango sobrecoxa cozida', category: 'carnes', kcal_per_100g: 215, protein_g: 27.3, carbs_g: 0, fat_g: 11.0, fiber_g: 0 },
  { name_pt: 'frango coxa cozida sem pele', category: 'carnes', kcal_per_100g: 216, protein_g: 28.6, carbs_g: 0, fat_g: 10.9, fiber_g: 0 },
  { name_pt: 'patinho bovino grelhado', category: 'carnes', kcal_per_100g: 219, protein_g: 35.9, carbs_g: 0, fat_g: 7.3, fiber_g: 0 },
  { name_pt: 'alcatra grelhada', category: 'carnes', kcal_per_100g: 217, protein_g: 32.4, carbs_g: 0, fat_g: 8.8, fiber_g: 0 },
  { name_pt: 'contra-filé grelhado', category: 'carnes', kcal_per_100g: 222, protein_g: 32.6, carbs_g: 0, fat_g: 9.2, fiber_g: 0 },
  { name_pt: 'carne moída cozida', category: 'carnes', kcal_per_100g: 212, protein_g: 27.4, carbs_g: 0, fat_g: 10.5, fiber_g: 0 },
  { name_pt: 'lombo de porco assado', category: 'carnes', kcal_per_100g: 210, protein_g: 31.2, carbs_g: 0, fat_g: 8.6, fiber_g: 0 },
  { name_pt: 'tilápia grelhada', category: 'peixes', kcal_per_100g: 129, protein_g: 26.8, carbs_g: 0, fat_g: 1.7, fiber_g: 0 },
  { name_pt: 'salmão grelhado', category: 'peixes', kcal_per_100g: 208, protein_g: 25.4, carbs_g: 0, fat_g: 11.4, fiber_g: 0 },
  { name_pt: 'atum em água lata', category: 'peixes', kcal_per_100g: 116, protein_g: 25.5, carbs_g: 0, fat_g: 0.8, fiber_g: 0 },
  { name_pt: 'sardinha em molho de tomate', category: 'peixes', kcal_per_100g: 200, protein_g: 18.0, carbs_g: 1.5, fat_g: 13.5, fiber_g: 0 },

  // ========== Ovos e laticínios ==========
  { name_pt: 'ovo de galinha inteiro cozido', category: 'ovos', kcal_per_100g: 146, protein_g: 13.3, carbs_g: 0.6, fat_g: 9.5, fiber_g: 0 },
  { name_pt: 'ovo de galinha mexido', category: 'ovos', kcal_per_100g: 156, protein_g: 11.4, carbs_g: 0.6, fat_g: 11.7, fiber_g: 0 },
  { name_pt: 'clara de ovo crua', category: 'ovos', kcal_per_100g: 43, protein_g: 10.0, carbs_g: 0.5, fat_g: 0, fiber_g: 0 },
  { name_pt: 'leite integral', category: 'laticinios', kcal_per_100g: 61, protein_g: 2.9, carbs_g: 4.3, fat_g: 3.3, fiber_g: 0 },
  { name_pt: 'leite desnatado', category: 'laticinios', kcal_per_100g: 35, protein_g: 3.4, carbs_g: 4.9, fat_g: 0.2, fiber_g: 0 },
  { name_pt: 'iogurte natural integral', category: 'laticinios', kcal_per_100g: 51, protein_g: 4.1, carbs_g: 1.9, fat_g: 3.0, fiber_g: 0 },
  { name_pt: 'iogurte natural desnatado', category: 'laticinios', kcal_per_100g: 41, protein_g: 4.2, carbs_g: 5.5, fat_g: 0.2, fiber_g: 0 },
  { name_pt: 'iogurte grego natural', category: 'laticinios', kcal_per_100g: 97, protein_g: 9.0, carbs_g: 4.0, fat_g: 5.0, fiber_g: 0 },
  { name_pt: 'queijo minas frescal', category: 'laticinios', kcal_per_100g: 264, protein_g: 17.4, carbs_g: 3.2, fat_g: 20.2, fiber_g: 0 },
  { name_pt: 'queijo mussarela', category: 'laticinios', kcal_per_100g: 280, protein_g: 22.6, carbs_g: 3.0, fat_g: 22.0, fiber_g: 0 },
  { name_pt: 'queijo prato', category: 'laticinios', kcal_per_100g: 360, protein_g: 22.7, carbs_g: 1.9, fat_g: 29.1, fiber_g: 0 },
  { name_pt: 'requeijão cremoso', category: 'laticinios', kcal_per_100g: 257, protein_g: 9.7, carbs_g: 3.0, fat_g: 23.0, fiber_g: 0 },
  { name_pt: 'whey protein concentrado', category: 'suplementos', kcal_per_100g: 380, protein_g: 75.0, carbs_g: 10.0, fat_g: 5.0, fiber_g: 0 },

  // ========== Verduras e legumes ==========
  { name_pt: 'alface crespa', category: 'verduras', kcal_per_100g: 11, protein_g: 1.3, carbs_g: 1.7, fat_g: 0.2, fiber_g: 1.8 },
  { name_pt: 'tomate cru', category: 'verduras', kcal_per_100g: 15, protein_g: 1.1, carbs_g: 3.1, fat_g: 0.2, fiber_g: 1.2 },
  { name_pt: 'cenoura crua', category: 'verduras', kcal_per_100g: 34, protein_g: 1.3, carbs_g: 7.7, fat_g: 0.2, fiber_g: 3.2 },
  { name_pt: 'cenoura cozida', category: 'verduras', kcal_per_100g: 30, protein_g: 0.8, carbs_g: 6.7, fat_g: 0.2, fiber_g: 2.6 },
  { name_pt: 'beterraba cozida', category: 'verduras', kcal_per_100g: 32, protein_g: 1.3, carbs_g: 7.2, fat_g: 0.1, fiber_g: 1.9 },
  { name_pt: 'brócolis cozido', category: 'verduras', kcal_per_100g: 25, protein_g: 2.1, carbs_g: 4.4, fat_g: 0.4, fiber_g: 3.4 },
  { name_pt: 'couve manteiga refogada', category: 'verduras', kcal_per_100g: 90, protein_g: 3.6, carbs_g: 5.0, fat_g: 6.4, fiber_g: 4.0 },
  { name_pt: 'espinafre refogado', category: 'verduras', kcal_per_100g: 39, protein_g: 2.7, carbs_g: 1.8, fat_g: 2.6, fiber_g: 2.5 },
  { name_pt: 'abobrinha cozida', category: 'verduras', kcal_per_100g: 15, protein_g: 1.0, carbs_g: 3.1, fat_g: 0.2, fiber_g: 1.6 },
  { name_pt: 'pepino cru', category: 'verduras', kcal_per_100g: 10, protein_g: 0.9, carbs_g: 2.0, fat_g: 0.1, fiber_g: 0.9 },
  { name_pt: 'pimentão verde cru', category: 'verduras', kcal_per_100g: 21, protein_g: 1.1, carbs_g: 4.9, fat_g: 0.2, fiber_g: 2.6 },
  { name_pt: 'cebola crua', category: 'verduras', kcal_per_100g: 39, protein_g: 1.7, carbs_g: 8.9, fat_g: 0.4, fiber_g: 2.2 },

  // ========== Tubérculos e raízes ==========
  { name_pt: 'batata inglesa cozida', category: 'tuberculos', kcal_per_100g: 52, protein_g: 1.2, carbs_g: 11.9, fat_g: 0, fiber_g: 1.3 },
  { name_pt: 'batata doce cozida', category: 'tuberculos', kcal_per_100g: 77, protein_g: 0.6, carbs_g: 18.4, fat_g: 0.1, fiber_g: 2.2 },
  { name_pt: 'batata baroa cozida', category: 'tuberculos', kcal_per_100g: 80, protein_g: 1.3, carbs_g: 18.7, fat_g: 0.1, fiber_g: 2.7 },
  { name_pt: 'mandioca cozida', category: 'tuberculos', kcal_per_100g: 125, protein_g: 0.6, carbs_g: 30.1, fat_g: 0.3, fiber_g: 1.6 },
  { name_pt: 'inhame cozido', category: 'tuberculos', kcal_per_100g: 97, protein_g: 2.1, carbs_g: 22.5, fat_g: 0.2, fiber_g: 2.0 },

  // ========== Frutas ==========
  { name_pt: 'banana prata', category: 'frutas', kcal_per_100g: 98, protein_g: 1.3, carbs_g: 26.0, fat_g: 0.1, fiber_g: 2.0 },
  { name_pt: 'banana nanica', category: 'frutas', kcal_per_100g: 92, protein_g: 1.4, carbs_g: 23.8, fat_g: 0.1, fiber_g: 1.9 },
  { name_pt: 'maçã com casca', category: 'frutas', kcal_per_100g: 56, protein_g: 0.3, carbs_g: 15.2, fat_g: 0, fiber_g: 1.3 },
  { name_pt: 'laranja pera', category: 'frutas', kcal_per_100g: 37, protein_g: 1.0, carbs_g: 8.9, fat_g: 0.1, fiber_g: 4.0 },
  { name_pt: 'mamão formosa', category: 'frutas', kcal_per_100g: 45, protein_g: 0.8, carbs_g: 11.6, fat_g: 0.1, fiber_g: 1.8 },
  { name_pt: 'manga palmer', category: 'frutas', kcal_per_100g: 64, protein_g: 0.4, carbs_g: 16.7, fat_g: 0.2, fiber_g: 2.1 },
  { name_pt: 'abacaxi', category: 'frutas', kcal_per_100g: 48, protein_g: 0.9, carbs_g: 12.3, fat_g: 0.1, fiber_g: 1.0 },
  { name_pt: 'morango', category: 'frutas', kcal_per_100g: 30, protein_g: 0.9, carbs_g: 6.8, fat_g: 0.3, fiber_g: 1.7 },
  { name_pt: 'uva itália', category: 'frutas', kcal_per_100g: 53, protein_g: 0.7, carbs_g: 13.6, fat_g: 0.2, fiber_g: 0.9 },
  { name_pt: 'melancia', category: 'frutas', kcal_per_100g: 33, protein_g: 0.9, carbs_g: 8.1, fat_g: 0.2, fiber_g: 0.1 },
  { name_pt: 'abacate', category: 'frutas', kcal_per_100g: 96, protein_g: 1.2, carbs_g: 6.0, fat_g: 8.4, fiber_g: 6.3 },
  { name_pt: 'pera', category: 'frutas', kcal_per_100g: 53, protein_g: 0.5, carbs_g: 14.0, fat_g: 0.1, fiber_g: 3.1 },

  // ========== Gorduras e óleos ==========
  { name_pt: 'azeite de oliva extra virgem', category: 'gorduras', kcal_per_100g: 884, protein_g: 0, carbs_g: 0, fat_g: 100, fiber_g: 0 },
  { name_pt: 'óleo de soja', category: 'gorduras', kcal_per_100g: 884, protein_g: 0, carbs_g: 0, fat_g: 100, fiber_g: 0 },
  { name_pt: 'manteiga sem sal', category: 'gorduras', kcal_per_100g: 726, protein_g: 0.5, carbs_g: 0.1, fat_g: 82.0, fiber_g: 0 },
  { name_pt: 'margarina cremosa', category: 'gorduras', kcal_per_100g: 596, protein_g: 0.7, carbs_g: 0.4, fat_g: 65.0, fiber_g: 0 },

  // ========== Açúcares e doces ==========
  { name_pt: 'açúcar refinado', category: 'acucares', kcal_per_100g: 387, protein_g: 0, carbs_g: 99.5, fat_g: 0, fiber_g: 0 },
  { name_pt: 'mel de abelha', category: 'acucares', kcal_per_100g: 309, protein_g: 0.4, carbs_g: 84.0, fat_g: 0, fiber_g: 0.4 },
  { name_pt: 'chocolate ao leite barra', category: 'doces', kcal_per_100g: 540, protein_g: 6.4, carbs_g: 60.0, fat_g: 30.5, fiber_g: 1.7 },
  { name_pt: 'chocolate amargo 70%', category: 'doces', kcal_per_100g: 559, protein_g: 7.8, carbs_g: 45.9, fat_g: 39.8, fiber_g: 11.0 },

  // ========== Castanhas e oleaginosas ==========
  { name_pt: 'castanha do pará', category: 'oleaginosas', kcal_per_100g: 643, protein_g: 14.5, carbs_g: 15.1, fat_g: 63.5, fiber_g: 7.9 },
  { name_pt: 'castanha de caju torrada', category: 'oleaginosas', kcal_per_100g: 570, protein_g: 18.5, carbs_g: 29.1, fat_g: 46.3, fiber_g: 3.7 },
  { name_pt: 'amendoim torrado', category: 'oleaginosas', kcal_per_100g: 544, protein_g: 22.5, carbs_g: 20.3, fat_g: 43.9, fiber_g: 8.0 },
  { name_pt: 'pasta de amendoim', category: 'oleaginosas', kcal_per_100g: 605, protein_g: 25.0, carbs_g: 19.4, fat_g: 50.2, fiber_g: 6.0 },
  { name_pt: 'amêndoa torrada', category: 'oleaginosas', kcal_per_100g: 581, protein_g: 21.6, carbs_g: 19.5, fat_g: 47.3, fiber_g: 11.6 },

  // ========== Bebidas ==========
  { name_pt: 'café preparado sem açúcar', category: 'bebidas', kcal_per_100g: 4, protein_g: 0.3, carbs_g: 0.7, fat_g: 0, fiber_g: 0 },
  { name_pt: 'suco de laranja natural', category: 'bebidas', kcal_per_100g: 37, protein_g: 0.7, carbs_g: 8.7, fat_g: 0.1, fiber_g: 0.4 },
  { name_pt: 'água de coco', category: 'bebidas', kcal_per_100g: 22, protein_g: 0.5, carbs_g: 5.3, fat_g: 0.1, fiber_g: 1.2 },
]

function env(key: string): string {
  const v = process.env[key]
  if (!v) throw new Error(`Missing env: ${key}`)
  return v
}

async function main() {
  const supabase = createClient<Database>(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  console.log(`━━━ Seed inicial food_db: ${FOODS.length} alimentos ━━━\n`)

  // Limpa antes (idempotência)
  await supabase.from('food_db').delete().neq('id', -1)

  // Insere em chunks
  const rows = FOODS.map((f) => ({
    name_pt: f.name_pt,
    category: f.category,
    kcal_per_100g: f.kcal_per_100g,
    protein_g: f.protein_g,
    carbs_g: f.carbs_g,
    fat_g: f.fat_g,
    fiber_g: f.fiber_g ?? null,
    source: 'TACO_4_seed_minimal',
  }))

  for (let i = 0; i < rows.length; i += 50) {
    const chunk = rows.slice(i, i + 50)
    const { error } = await supabase.from('food_db').insert(chunk)
    if (error) throw error
    console.log(`✓ ${Math.min(i + 50, rows.length)}/${rows.length}`)
  }

  // Verifica
  const { count } = await supabase
    .from('food_db')
    .select('*', { count: 'exact', head: true })
  console.log(`\nTotal em food_db: ${count}`)

  const { data: byCategory } = await supabase.from('food_db').select('category')
  const stats = (byCategory ?? []).reduce<Record<string, number>>((acc, r) => {
    const c = r.category ?? '?'
    acc[c] = (acc[c] ?? 0) + 1
    return acc
  }, {})
  for (const [cat, n] of Object.entries(stats).sort((a, b) => b[1] - a[1])) {
    console.log(`  ${cat.padEnd(15)} ${n}`)
  }

  console.log('\n✅ Seed minimal concluído.')
  console.log('ℹ️  TODO: importar TACO completa (~600 itens) via seed-taco-from-file.ts')
}

main().catch((e) => {
  console.error('💥', e)
  process.exit(1)
})
