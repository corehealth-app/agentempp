/**
 * Recovery do café da manhã do Roberto 2026-05-31.
 *
 * Contexto: Roberto mandou foto às 22:31 BRT (= 21:31 NY) depois do gap
 * reminder. OpenRouter estava sem saldo → 402, foto não foi processada.
 * Eduardo abriu a foto comigo aqui agora 2026-06-01 e confirmou os itens:
 *   1. leite com whey (200 ml)
 *   2. pão francês (50g, 1 pão)
 *   3. geleia de morango (20g)
 *   4. ovo frito (50g, 1 unidade)
 *   5. pão integral tostado (25g)
 *
 * Refeição identificada pelo Eduardo como café da manhã (mandada tarde
 * pelo Roberto). consumed_at = manhã NY (timezone do Roberto).
 *
 * Rodar: set -a; . ./.env.local; set +a; npx tsx scripts/recover-roberto-cafe-2026-05-31.ts
 */
import { createServiceClient } from '@mpp/db'
import { calcMealMacros } from '../packages/agent/src/meal-pipeline.js'
import { recomputeUserBloco } from '../packages/inngest-functions/src/lib/bloco-recompute.js'

const ROBERTO = '118587e3-e752-4a23-b304-57231d7ef40f'
const PMID_RECOVERY = 'recovery_roberto_cafe_2026-05-31_foto_perdida_402'
// Roberto = America/New_York. Foto chegou 21:31 NY 31/05. Café da manhã
// típico ~8-9h NY → uso 09:00 NY como consumed_at (dentro do dia 31/05 NY).
const CONSUMED_AT = '2026-05-31T09:00:00-04:00'

async function main() {
  const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!url || !key) throw new Error('SUPABASE_URL/SERVICE_ROLE_KEY ausente')
  const supabase = createServiceClient({ url, serviceRoleKey: key })

  const { data: snap } = await supabase
    .from('daily_snapshots')
    .select('id, calories_consumed, protein_g, carbs_g, fat_g, day_status')
    .eq('user_id', ROBERTO)
    .eq('date', '2026-05-31')
    .maybeSingle()
  if (!snap) throw new Error('Snapshot Roberto 31/05 não encontrado')
  console.log('Snapshot ANTES:', snap)

  const items = [
    { food_name: 'leite com whey', quantity_g: 200 },
    { food_name: 'pão francês', quantity_g: 50 },
    { food_name: 'geleia de morango', quantity_g: 20 },
    { food_name: 'ovo frito', quantity_g: 50 },
    { food_name: 'pão integral tostado', quantity_g: 25 },
  ]
  const resolved = await calcMealMacros(supabase, items, 'US', ROBERTO)
  console.log('\nResolved:')
  for (const it of resolved.items) {
    console.log(`  ${it.food_name} (${it.quantity_g}g): ${it.kcal} kcal | ${it.protein_g}p | ${it.carbs_g}c | ${it.fat_g}g`)
  }
  console.log(`Total: ${resolved.totals.kcal} kcal | ${resolved.totals.protein_g}p | ${resolved.totals.carbs_g}c | ${resolved.totals.fat_g}g`)

  console.log('\nInserindo meal_logs...')
  for (const it of resolved.items) {
    const { error } = await supabase.from('meal_logs').insert({
      user_id: ROBERTO,
      snapshot_id: snap.id,
      meal_type: 'cafe',
      food_name: it.food_name,
      quantity_g: it.quantity_g,
      kcal: it.kcal,
      protein_g: it.protein_g,
      carbs_g: it.carbs_g,
      fat_g: it.fat_g,
      source: 'admin_backfill',
      confidence: it.similarity ?? 0.5,
      consumed_at: CONSUMED_AT,
      raw_provider_message_id: PMID_RECOVERY,
    })
    if (error) throw new Error(`insert ${it.food_name}: ${error.message}`)
  }

  const newConsumed = (snap.calories_consumed ?? 0) + Math.round(resolved.totals.kcal)
  const newProtein = Number((Number(snap.protein_g ?? 0) + resolved.totals.protein_g).toFixed(2))
  const newCarbs = Number((Number(snap.carbs_g ?? 0) + resolved.totals.carbs_g).toFixed(2))
  const newFat = Number((Number(snap.fat_g ?? 0) + resolved.totals.fat_g).toFixed(2))
  const { data: snapAfter, error: updErr } = await supabase
    .from('daily_snapshots')
    .update({
      calories_consumed: newConsumed,
      protein_g: newProtein,
      carbs_g: newCarbs,
      fat_g: newFat,
      updated_at: new Date().toISOString(),
    })
    .eq('id', snap.id)
    .select('calories_consumed, protein_g, carbs_g, fat_g, daily_balance, day_status')
    .single()
  if (updErr) throw new Error(`update snapshot: ${updErr.message}`)
  console.log('\nSnapshot DEPOIS:', snapAfter)

  console.log('\nRecomputando bloco Roberto...')
  const blocoBefore = (
    await supabase.from('user_progress').select('deficit_block, blocks_completed').eq('user_id', ROBERTO).maybeSingle()
  ).data as { deficit_block?: number; blocks_completed?: number } | null
  const result = await recomputeUserBloco(supabase, ROBERTO)
  await supabase
    .from('user_progress')
    .update({
      deficit_block: result.correctDeficitBlock,
      blocks_completed: result.correctBlocksCompleted,
      updated_at: new Date().toISOString(),
    })
    .eq('user_id', ROBERTO)
  console.log(
    `Bloco: ${blocoBefore?.deficit_block ?? 0}/7700 (${blocoBefore?.blocks_completed ?? 0}b) → ${result.correctDeficitBlock}/7700 (${result.correctBlocksCompleted}b)`,
  )

  await supabase.from('product_events').insert({
    user_id: ROBERTO,
    event: 'admin.meal_log_recovery',
    properties: {
      date: '2026-05-31',
      meal_type: 'cafe',
      reason: 'foto sofreu pipeline.error 402 (OpenRouter sem saldo) — Eduardo identificou itens da foto comigo aqui em 2026-06-01',
      original_msg_ts: '2026-05-31T22:31:41-03:00',
      items: resolved.items.map((i) => ({ name: i.food_name, qty_g: i.quantity_g, kcal: i.kcal })),
      total_kcal: Math.round(resolved.totals.kcal),
      by: 'Eduardo autorizou via Claude (opção 1 reprocessar manualmente, foto analisada multimodal)',
    },
  })
  console.log('\n✅ Recovery aplicado e audit event registrado.')
}

main().catch((e) => {
  console.error('❌', e)
  process.exit(1)
})
