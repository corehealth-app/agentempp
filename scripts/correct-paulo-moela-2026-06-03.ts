/**
 * Correção do almoço Paulo 03/06 — moela de frango gravada com kcal errada.
 *
 * Contexto: na hora do registro (16:25 BRT 03/06), food_db NÃO tinha entrada
 * pra "moela de frango". Trigram match casou com "asa de frango" (290 kcal/100g)
 * por trigram sim>=0.45 — resultado: 150g registrados como 435 kcal (real
 * moela ~94 kcal/100g, devia ser 141 kcal). Erro de 294 kcal.
 *
 * Fix: 2026-06-04 adicionei "moela de frango" id=450 (94 kcal/100g, 17.7g
 * prot, 2.1g fat) na food_db. Eduardo autorizou backfill do log do Paulo
 * agora pra refletir valor correto.
 *
 * Operação: UPDATE direto no meal_log + UPDATE no snapshot + recompute do
 * bloco (paciente recomposicao, dia já fechado).
 *
 * Rodar: set -a; . ./.env.local; set +a; npx tsx scripts/correct-paulo-moela-2026-06-03.ts
 */
import { createServiceClient } from '@mpp/db'
import { recomputeUserBloco } from '../packages/inngest-functions/src/lib/bloco-recompute.js'

const PAULO = '0589e41e-254b-43d7-81b5-596e643d34ab'
const MOELA_LOG_ID = '9d116754-8129-4f5f-be14-e691f5420e60'
const SNAPSHOT_ID = '9d86a96a-6eac-44b2-aa9b-8848bc99391d'

// Valores antigos (asa de frango trigram match — wrong)
const OLD = { kcal: 435.0, protein_g: 39.0, carbs_g: 0.0, fat_g: 28.5 }
// Valores corretos (moela de frango id=450, 150g)
const NEW = { kcal: 141.0, protein_g: 26.55, carbs_g: 0.0, fat_g: 3.15 }

async function main() {
  const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!url || !key) throw new Error('SUPABASE_URL/SERVICE_ROLE_KEY ausente')
  const supabase = createServiceClient({ url, serviceRoleKey: key })

  const { data: snapBefore } = await supabase
    .from('daily_snapshots')
    .select('id, calories_consumed, protein_g, carbs_g, fat_g, daily_balance, day_status, exercise_calories, calories_target')
    .eq('id', SNAPSHOT_ID)
    .maybeSingle()
  if (!snapBefore) throw new Error('Snapshot Paulo 03/06 não encontrado')
  console.log('Snapshot ANTES:', snapBefore)

  const { data: logBefore } = await supabase
    .from('meal_logs')
    .select('id, food_name, quantity_g, kcal, protein_g, carbs_g, fat_g')
    .eq('id', MOELA_LOG_ID)
    .maybeSingle()
  console.log('\nmeal_log ANTES:', logBefore)

  const deltaKcal = NEW.kcal - OLD.kcal
  const deltaProtein = NEW.protein_g - OLD.protein_g
  const deltaCarbs = NEW.carbs_g - OLD.carbs_g
  const deltaFat = NEW.fat_g - OLD.fat_g
  console.log(`\nDeltas: kcal=${deltaKcal} prot=${deltaProtein} carbs=${deltaCarbs} fat=${deltaFat}`)

  // 1) UPDATE meal_log
  const { error: updLogErr } = await supabase
    .from('meal_logs')
    .update({
      kcal: NEW.kcal,
      protein_g: NEW.protein_g,
      carbs_g: NEW.carbs_g,
      fat_g: NEW.fat_g,
    })
    .eq('id', MOELA_LOG_ID)
  if (updLogErr) throw new Error(`update meal_log: ${updLogErr.message}`)
  console.log('\nmeal_log atualizado.')

  // 2) UPDATE snapshot (aplica delta)
  const newConsumed = (snapBefore.calories_consumed ?? 0) + Math.round(deltaKcal)
  const newProtein = Number((Number(snapBefore.protein_g ?? 0) + deltaProtein).toFixed(2))
  const newCarbs = Number((Number(snapBefore.carbs_g ?? 0) + deltaCarbs).toFixed(2))
  const newFat = Number((Number(snapBefore.fat_g ?? 0) + deltaFat).toFixed(2))
  // daily_balance é generated column (= calories_consumed - calories_target - exercise_calories)
  // Recalcula automaticamente quando atualizamos calories_consumed.
  const { data: snapAfter, error: updSnapErr } = await supabase
    .from('daily_snapshots')
    .update({
      calories_consumed: newConsumed,
      protein_g: newProtein,
      carbs_g: newCarbs,
      fat_g: newFat,
      updated_at: new Date().toISOString(),
    })
    .eq('id', SNAPSHOT_ID)
    .select('calories_consumed, protein_g, carbs_g, fat_g, daily_balance, day_status')
    .single()
  if (updSnapErr) throw new Error(`update snapshot: ${updSnapErr.message}`)
  console.log('\nSnapshot DEPOIS:', snapAfter)

  // 3) Recompute bloco
  console.log('\nRecomputando bloco Paulo...')
  const blocoBefore = (
    await supabase.from('user_progress').select('deficit_block, blocks_completed').eq('user_id', PAULO).maybeSingle()
  ).data as { deficit_block?: number; blocks_completed?: number } | null
  const result = await recomputeUserBloco(supabase, PAULO)
  await supabase
    .from('user_progress')
    .update({
      deficit_block: result.correctDeficitBlock,
      blocks_completed: result.correctBlocksCompleted,
      updated_at: new Date().toISOString(),
    })
    .eq('user_id', PAULO)
  console.log(
    `Bloco: ${blocoBefore?.deficit_block ?? 0}/7700 (${blocoBefore?.blocks_completed ?? 0}b) → ${result.correctDeficitBlock}/7700 (${result.correctBlocksCompleted}b)`,
  )

  // 4) Audit event
  await supabase.from('product_events').insert({
    user_id: PAULO,
    event: 'admin.meal_log_correction',
    properties: {
      date: '2026-06-03',
      meal_type: 'almoco',
      log_id: MOELA_LOG_ID,
      food_name: 'moela de frango',
      reason: 'food_db não tinha moela; trigram match casou com "asa de frango" 290 kcal/100g. Corrigido após inserir moela de frango id=450 (94 kcal/100g) em food_db.',
      delta: { kcal: deltaKcal, protein_g: deltaProtein, carbs_g: deltaCarbs, fat_g: deltaFat },
      old_values: OLD,
      new_values: NEW,
      by: 'Eduardo autorizou via Claude 2026-06-04',
    },
  })
  console.log('\n✅ Correção aplicada e audit event registrado.')
}

main().catch((e) => {
  console.error('❌', e)
  process.exit(1)
})
