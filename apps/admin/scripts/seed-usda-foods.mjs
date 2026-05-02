/**
 * Seed de alimentos americanos comuns. Pega macros via LLM (OpenRouter,
 * Grok 4.1 Fast — barato e fluente em USDA values).
 *
 * Não é um import do FoodData Central completo (1M+ itens). É um seed
 * curado dos ~150 mais comuns que aparecem em diários alimentares (rice,
 * chicken, eggs, salads, etc.). Suficiente pra agente trabalhar com US users.
 *
 * Idempotente: skip se já tem item com esse name_pt + country_code.
 */
import OpenAI from 'openai'
import { createClient } from '@supabase/supabase-js'

const svc = createClient(
  process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY,
  { auth: { persistSession: false } },
)

const { data: cred } = await svc
  .from('service_credentials')
  .select('value')
  .eq('service', 'openrouter')
  .eq('key_name', 'api_key')
  .eq('is_active', true)
  .maybeSingle()
if (!cred?.value) {
  console.error('openrouter.api_key ausente')
  process.exit(1)
}

const llm = new OpenAI({
  apiKey: cred.value,
  baseURL: 'https://openrouter.ai/api/v1',
  defaultHeaders: { 'HTTP-Referer': 'https://github.com/corehealth-app/agentempp', 'X-Title': 'Agente MPP USDA seed' },
})

const PROMPT = `Você é um nutricionista americano. Gere uma tabela de **150 alimentos comuns nos Estados Unidos** com macros por 100g, baseado em valores médios da USDA FoodData Central.

Cubra estas categorias proporcionalmente:
- Cereais e grãos (rice, oats, quinoa, pasta, breads — ~20 itens)
- Proteínas (chicken breast, beef cuts, eggs, fish, turkey — ~25 itens)
- Vegetais (broccoli, spinach, carrots, peppers — ~25 itens)
- Frutas (apple, banana, berries — ~15 itens)
- Lácteos (milk, cheese, yogurt — ~15 itens)
- Gorduras e óleos (olive oil, butter, nuts — ~15 itens)
- Snacks e fast foods comuns (peanut butter, pretzels, granola bars — ~15 itens)
- Bebidas e açúcares (sodas, juices, sugar — ~10 itens)
- Embalados/processados (cereal boxes, frozen meals — ~10 itens)

Para cada item:
- Nome em **inglês simples** (ex: "white rice cooked", "chicken breast grilled skinless", "whole milk")
- Categoria curta em inglês
- kcal_per_100g (número, 0-700 range)
- protein_g, carbs_g, fat_g, fiber_g por 100g (números com 1 casa decimal)

Retorne APENAS um JSON com estrutura {"items": [...]}, exemplo:

{
  "items": [
    {"name": "white rice cooked", "category": "grains", "kcal_per_100g": 130, "protein_g": 2.7, "carbs_g": 28.2, "fat_g": 0.3, "fiber_g": 0.4},
    {"name": "chicken breast grilled skinless", "category": "protein", "kcal_per_100g": 165, "protein_g": 31, "carbs_g": 0, "fat_g": 3.6, "fiber_g": 0}
  ]
}

Garanta exatamente 150 itens dentro de items[], sem repetições, todos preparados/cozidos quando aplicável (não cru), valores realistas USDA.`

console.log('Gerando seed via Grok-4.1-fast...')
const start = Date.now()
const completion = await llm.chat.completions.create({
  model: 'x-ai/grok-4.1-fast',
  temperature: 0.3,
  max_tokens: 16000,
  response_format: { type: 'json_object' },
  messages: [
    { role: 'system', content: 'Você gera JSON puro, nada além.' },
    { role: 'user', content: PROMPT },
  ],
})
console.log(`LLM: ${Date.now() - start}ms`)

const raw = completion.choices[0]?.message?.content ?? ''
let items
try {
  const parsed = JSON.parse(raw)
  // Pode vir como {items: [...]} ou direto como array
  items = Array.isArray(parsed) ? parsed : parsed.items ?? parsed.foods ?? Object.values(parsed)[0]
  if (!Array.isArray(items)) throw new Error('JSON não é array')
} catch (e) {
  console.error('Parse falhou:', e.message)
  console.log(raw.slice(0, 500))
  process.exit(1)
}

console.log(`✓ ${items.length} itens gerados`)

// Insere em batch (skip duplicados por name_pt + country_code)
let inserted = 0
let skipped = 0
let failed = 0

for (const it of items) {
  if (!it.name || it.kcal_per_100g == null) {
    failed++
    continue
  }
  // Check duplicata
  const { data: dup } = await svc
    .from('food_db')
    .select('id')
    .eq('name_pt', it.name)
    .eq('country_code', 'US')
    .maybeSingle()
  if (dup) {
    skipped++
    continue
  }
  const { error } = await svc.from('food_db').insert({
    name_pt: it.name,
    category: it.category ?? null,
    kcal_per_100g: Number(it.kcal_per_100g),
    protein_g: it.protein_g != null ? Number(it.protein_g) : null,
    carbs_g: it.carbs_g != null ? Number(it.carbs_g) : null,
    fat_g: it.fat_g != null ? Number(it.fat_g) : null,
    fiber_g: it.fiber_g != null ? Number(it.fiber_g) : null,
    source: 'USDA_seed_llm',
    country_code: 'US',
  })
  if (error) {
    console.error(`  ✗ ${it.name}: ${error.message}`)
    failed++
  } else {
    inserted++
  }
}

console.log(`\nResultado: inseridos=${inserted} skipped=${skipped} failed=${failed}`)
