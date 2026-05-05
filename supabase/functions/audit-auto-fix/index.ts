// Edge function: audit-auto-fix
//
// Aceita POST com lista de fixes triviais que a routine remota detectou
// e aplica no DB. Auth via shared secret. Cada fix loga em audit_log
// e product_events pra rastreabilidade.
//
// Suporta APENAS fixes seguros (dado, nao codigo):
//   - food_alias: adiciona entrada em food_db com macros estimados
//
// Cada fix tem confidence ('high'/'medium'/'low') e fonte ('llm_estimate').
// Source='alias_auto' permite filtrar/auditar/reverter facilmente em /settings/foods.

import { createClient } from 'jsr:@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const AUDIT_SECRET = Deno.env.get('AUDIT_SECRET') ?? ''

interface FoodAliasFix {
  type: 'food_alias'
  food_name: string
  category: string
  kcal_per_100g: number
  protein_g: number
  carbs_g: number
  fat_g: number
  fiber_g: number
  country_code?: string
  confidence: 'high' | 'medium' | 'low'
  reasoning: string
}

type Fix = FoodAliasFix

interface FixResult {
  ok: boolean
  type: string
  food_name?: string
  reason?: string
  inserted_id?: number
}

Deno.serve(async (req: Request) => {
  const authHeader = req.headers.get('x-audit-secret') ?? ''
  if (!AUDIT_SECRET || authHeader !== AUDIT_SECRET) {
    return new Response('forbidden', { status: 403 })
  }
  if (req.method !== 'POST') return new Response('method', { status: 405 })

  let body: { fixes: Fix[]; run_id?: string }
  try {
    body = await req.json()
  } catch {
    return new Response('bad json', { status: 400 })
  }

  if (!Array.isArray(body.fixes)) {
    return Response.json({ ok: false, error: 'fixes must be array' }, { status: 400 })
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const results: FixResult[] = []
  let applied = 0
  let skipped = 0

  for (const fix of body.fixes) {
    if (fix.type !== 'food_alias') {
      results.push({ ok: false, type: fix.type, reason: 'unsupported fix type' })
      skipped++
      continue
    }

    // Sanity: rejeita auto-fix com confidence baixa
    if (fix.confidence === 'low') {
      results.push({
        ok: false,
        type: fix.type,
        food_name: fix.food_name,
        reason: 'confidence low — needs manual review',
      })
      skipped++
      continue
    }

    // Sanity: macros plausíveis
    const validMacros =
      fix.kcal_per_100g >= 0 &&
      fix.kcal_per_100g <= 1000 &&
      fix.protein_g >= 0 &&
      fix.protein_g <= 100 &&
      fix.carbs_g >= 0 &&
      fix.carbs_g <= 100 &&
      fix.fat_g >= 0 &&
      fix.fat_g <= 100
    if (!validMacros) {
      results.push({
        ok: false,
        type: fix.type,
        food_name: fix.food_name,
        reason: 'macros fora de limite plausível',
      })
      skipped++
      continue
    }

    // Sanity: kcal coerente com macros (1 prot=4, 1 carb=4, 1 fat=9 kcal)
    const computedKcal = fix.protein_g * 4 + fix.carbs_g * 4 + fix.fat_g * 9
    if (Math.abs(computedKcal - fix.kcal_per_100g) > 60) {
      results.push({
        ok: false,
        type: fix.type,
        food_name: fix.food_name,
        reason: `kcal incoerente com macros (computado=${computedKcal.toFixed(0)}, fornecido=${fix.kcal_per_100g})`,
      })
      skipped++
      continue
    }

    const country = fix.country_code ?? 'BR'

    // Skip se ja existe
    const { data: existing } = await supabase
      .from('food_db')
      .select('id')
      .eq('name_pt', fix.food_name)
      .eq('country_code', country)
      .maybeSingle()
    if (existing) {
      results.push({
        ok: false,
        type: fix.type,
        food_name: fix.food_name,
        reason: 'ja existe',
      })
      skipped++
      continue
    }

    const { data: inserted, error } = await supabase
      .from('food_db')
      .insert({
        name_pt: fix.food_name,
        category: fix.category,
        kcal_per_100g: fix.kcal_per_100g,
        protein_g: fix.protein_g,
        carbs_g: fix.carbs_g,
        fat_g: fix.fat_g,
        fiber_g: fix.fiber_g,
        country_code: country,
        source: 'alias_auto',
      })
      .select('id')
      .single()

    if (error) {
      results.push({
        ok: false,
        type: fix.type,
        food_name: fix.food_name,
        reason: error.message,
      })
      skipped++
      continue
    }

    // Loga audit_log + product_events
    await supabase.from('audit_log').insert({
      action: 'audit.auto_fix.food_alias_added',
      entity: 'food_db',
      entity_id: String((inserted as { id: number }).id),
      details: {
        food_name: fix.food_name,
        macros: {
          kcal: fix.kcal_per_100g,
          prot: fix.protein_g,
          carb: fix.carbs_g,
          fat: fix.fat_g,
        },
        confidence: fix.confidence,
        reasoning: fix.reasoning,
        run_id: body.run_id ?? null,
      },
    })
    await supabase.from('product_events').insert({
      user_id: null,
      event: 'audit.auto_fix.applied',
      properties: {
        type: 'food_alias',
        food_name: fix.food_name,
        food_id: (inserted as { id: number }).id,
        confidence: fix.confidence,
        run_id: body.run_id ?? null,
      },
    })

    results.push({
      ok: true,
      type: 'food_alias',
      food_name: fix.food_name,
      inserted_id: (inserted as { id: number }).id,
    })
    applied++
  }

  return Response.json({
    ok: true,
    applied,
    skipped,
    results,
  })
})
