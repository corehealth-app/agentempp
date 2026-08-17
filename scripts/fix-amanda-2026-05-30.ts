/**
 * Correção pontual Amanda 2026-05-30 (autorizado por Eduardo):
 *  1) re-insere meal_log da empanada do lanche da manhã (sumiu por
 *     cross-meal-type autocorrect com replace=true — bug fechado
 *     no commit 6eb11c4)
 *  2) recompute snapshot.calories_consumed/protein/carbs/fat = SUM(meal_logs)
 *     após o INSERT, eliminando o drift de +307 kcal fantasmas do
 *     insert duplicado bloqueado (UNIQUE pmid,food_name) — bug
 *     também fechado no mesmo commit.
 *
 * Rodar:
 *   set -a; . ./.env.local; set +a
 *   npx tsx scripts/fix-amanda-2026-05-30.ts
 */
const TOKEN = process.env.SUPABASE_ACCESS_TOKEN
const REF = 'xuxehkhdvjivitduarvb'
if (!TOKEN) {
  console.error('SUPABASE_ACCESS_TOKEN ausente em env')
  process.exit(1)
}

const AMANDA = '39b63819-9f48-4844-86d4-a857126ff84b'
const SNAPSHOT_ID = '3ebc689d-8706-4b5e-886d-d1a34d264535'
const PMID_LANCHE_EMPANADA = 'wamid.HBgMNTU4NDk5Mjk2MzYzFQIAEhgUM0EwRTVEQjYzMURBOTczQzlDMjYA'

async function q(sql: string): Promise<unknown> {
  const res = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  })
  const json = await res.json()
  if (!res.ok || (json as { message?: string }).message) {
    throw new Error(`SQL error: ${JSON.stringify(json)}`)
  }
  return json
}

async function main() {
  console.log('── Estado ANTES ──')
  const before = await q(
    `SELECT s.calories_consumed AS snap, ROUND(COALESCE(SUM(m.kcal),0)::numeric,0) AS sum_logs, COUNT(m.id) AS n FROM daily_snapshots s LEFT JOIN meal_logs m ON m.snapshot_id = s.id WHERE s.id = '${SNAPSHOT_ID}' GROUP BY s.id`,
  )
  console.log(before)

  console.log('\n── SQL #1: INSERT empanada do lanche ──')
  const ins = await q(
    `INSERT INTO meal_logs (user_id, snapshot_id, meal_type, food_name, quantity_g, kcal, protein_g, carbs_g, fat_g, consumed_at, raw_provider_message_id, source) VALUES ('${AMANDA}', '${SNAPSHOT_ID}', 'lanche', 'empanada de provolone com tomate seco', 100, 18, 0.9, 3.9, 0.2, '2026-05-30 09:44:49+00', '${PMID_LANCHE_EMPANADA}', 'admin_backfill') RETURNING id, food_name, kcal, meal_type`,
  )
  console.log(ins)

  console.log('\n── SQL #2: UPDATE snapshot pra SUM(meal_logs) ──')
  const upd = await q(
    `UPDATE daily_snapshots SET calories_consumed = (SELECT COALESCE(SUM(kcal),0)::int FROM meal_logs WHERE snapshot_id = '${SNAPSHOT_ID}'), protein_g = (SELECT ROUND(COALESCE(SUM(protein_g),0)::numeric, 2) FROM meal_logs WHERE snapshot_id = '${SNAPSHOT_ID}'), carbs_g = (SELECT ROUND(COALESCE(SUM(carbs_g),0)::numeric, 2) FROM meal_logs WHERE snapshot_id = '${SNAPSHOT_ID}'), fat_g = (SELECT ROUND(COALESCE(SUM(fat_g),0)::numeric, 2) FROM meal_logs WHERE snapshot_id = '${SNAPSHOT_ID}'), updated_at = now() WHERE id = '${SNAPSHOT_ID}' RETURNING calories_consumed, protein_g, carbs_g, fat_g, daily_balance`,
  )
  console.log(upd)

  console.log('\n── Estado DEPOIS (validação) ──')
  const after = await q(
    `SELECT s.calories_consumed AS snap, ROUND(COALESCE(SUM(m.kcal),0)::numeric,0) AS sum_logs, COUNT(m.id) AS n, s.calories_consumed - ROUND(COALESCE(SUM(m.kcal),0)::numeric,0) AS drift FROM daily_snapshots s LEFT JOIN meal_logs m ON m.snapshot_id = s.id WHERE s.id = '${SNAPSHOT_ID}' GROUP BY s.id`,
  )
  console.log(after)

  console.log('\n── Audit event ──')
  await q(
    `INSERT INTO product_events (user_id, event, properties) VALUES ('${AMANDA}', 'admin.snapshot_recompute', '{"date":"2026-05-30","reason":"drift +307 kcal por insert duplicado bloqueado + empanada lanche perdida por cross-meal autocorrect","by":"Eduardo via fix-amanda-2026-05-30.ts","commit_fixes":"6eb11c4"}'::jsonb)`,
  )
  console.log('✅ Correção aplicada')
}

main().catch((e) => {
  console.error('❌', e)
  process.exit(1)
})
