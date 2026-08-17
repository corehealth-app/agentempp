/**
 * Recovery do jantar do Paulo 2026-05-31 22:24 BRT.
 *
 * Contexto: Paulo mandou "Jantar uma fatia de pão integral 10gr de requeijão
 * 20gr de queijo branco 200ml de leite semi desnatado". Pipeline deu 402
 * (OpenRouter sem saldo). Msg não foi processada → jantar não registrado.
 * Snapshot 31/05 ficou 842 kcal, day_status=incomplete_no_response.
 *
 * Autorizado por Eduardo 2026-06-01 (opção 1: reprocessar manualmente com os
 * itens explícitos da msg original).
 *
 * Rodar: set -a; . ./.env.local; set +a; npx tsx scripts/recover-paulo-jantar-2026-05-31.ts
 */
import { createServiceClient } from '@mpp/db'
import { calcMealMacros } from '../packages/agent/src/meal-pipeline.js'
import { recomputeUserBloco } from '../packages/inngest-functions/src/lib/bloco-recompute.js'

const PAULO = '0589e41e-254b-43d7-81b5-596e643d34ab'
const PMID_RECOVERY = 'recovery_paulo_jantar_2026-05-31_22:24brt'
const CONSUMED_AT = '2026-05-31T22:24:00-03:00'

async function main() {
  const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!url || !key) throw new Error('SUPABASE_URL/SERVICE_ROLE_KEY ausente')
  const supabase = createServiceClient({ url, serviceRoleKey: key })

  // Snapshot do Paulo em 31/05
  const { data: snap } = await supabase
    .from('daily_snapshots')
    .select('id, calories_consumed, protein_g, carbs_g, fat_g, day_status')
    .eq('user_id', PAULO)
    .eq('date', '2026-05-31')
    .maybeSingle()
  if (!snap) throw new Error('Snapshot Paulo 31/05 não encontrado')
  console.log('Snapshot ANTES:', snap)

  // 4 itens da msg explícita do Paulo (texto original):
  //   "Jantar uma fatia de pão integral 10gr de requeijão 20gr de queijo branco 200ml de leite semi desnatado"
  const items = [
    { food_name: 'pão integral', quantity_g: 25 }, // 1 fatia
    { food_name: 'requeijão cremoso', quantity_g: 10 },
    { food_name: 'queijo branco', quantity_g: 20 },
    { food_name: 'leite semi desnatado', quantity_g: 200 },
  ]

  // Resolve macros via TACO (mesma função que a tool usa)
  const resolved = await calcMealMacros(supabase, items, 'BR', PAULO)
  console.log('\nResolved itens:')
  for (const it of resolved.items) {
    console.log(`  ${it.food_name} (${it.quantity_g}g): ${it.kcal} kcal | ${it.protein_g}p | ${it.carbs_g}c | ${it.fat_g}g`)
  }
  console.log(`Total: ${resolved.totals.kcal} kcal | ${resolved.totals.protein_g}p | ${resolved.totals.carbs_g}c | ${resolved.totals.fat_g}g`)

  // Insere meal_logs
  console.log('\nInserindo meal_logs...')
  for (const it of resolved.items) {
    const { error } = await supabase.from('meal_logs').insert({
      user_id: PAULO,
      snapshot_id: snap.id,
      meal_type: 'jantar',
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

  // Atualiza snapshot: SUM(meal_logs) agora reflete tudo do dia incl. jantar
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

  // Recalcula bloco do Paulo (afeta o crédito de 31/05 — agora pode mudar
  // pq dailyBalance mudou + opção C continua valendo)
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
    `Bloco: ${blocoBefore?.deficit_block ?? 0}/7700 → ${result.correctDeficitBlock}/7700 (${result.correctBlocksCompleted}b)`,
  )

  // Audit event
  await supabase.from('product_events').insert({
    user_id: PAULO,
    event: 'admin.meal_log_recovery',
    properties: {
      date: '2026-05-31',
      meal_type: 'jantar',
      reason: 'msg original do paciente sofreu pipeline.error 402 (OpenRouter sem saldo) e nunca foi reprocessada',
      original_msg_ts: '2026-05-31T22:24:00-03:00',
      original_text: 'Jantar uma fatia de pão integral 10gr de requeijão 20gr de queijo branco 200ml de leite semi desnatado',
      items: resolved.items.map((i) => ({ name: i.food_name, qty_g: i.quantity_g, kcal: i.kcal })),
      total_kcal: Math.round(resolved.totals.kcal),
      by: 'Eduardo autorizou via Claude (opção 1 reprocessar manualmente)',
    },
  })
  console.log('\n✅ Recovery aplicado e audit event registrado.')
}

main().catch((e) => {
  console.error('❌', e)
  process.exit(1)
})
