/**
 * Backfill do bloco 7700 com a NOVA fórmula (modelo líquido — superávit subtrai).
 * Roberto 2026-05-28. Usa a função oficial recomputeUserBloco. Reporta diff
 * antes/depois e atualiza user_progress.
 *
 * Rodar:
 *   set -a; . ./.env.local; set +a
 *   pnpm tsx scripts/backfill-bloco-liquido.ts
 */
import { createServiceClient } from '@mpp/db'
import { recomputeUserBloco } from '../packages/inngest-functions/src/lib/bloco-recompute.js'

async function main() {
  const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!url || !key) throw new Error('SUPABASE_URL/SERVICE_ROLE_KEY ausente em env')
  const supabase = createServiceClient({ url, serviceRoleKey: key })

  const { data: users } = await supabase
    .from('users')
    .select('id, name')
    .eq('status', 'active')
    .order('name')

  console.log(`\n── Backfill modelo líquido bloco 7700 ──\n`)
  for (const u of (users ?? []) as Array<{ id: string; name: string | null }>) {
    const { data: progBefore } = await supabase
      .from('user_progress')
      .select('deficit_block, blocks_completed')
      .eq('user_id', u.id)
      .maybeSingle()
    const before = progBefore as { deficit_block?: number; blocks_completed?: number } | null

    const result = await recomputeUserBloco(supabase, u.id)
    const after = { deficit_block: result.correctDeficitBlock, blocks_completed: result.correctBlocksCompleted }

    const diff = after.deficit_block - (before?.deficit_block ?? 0)
    const diffStr = diff === 0 ? '(sem mudança)' : diff > 0 ? `+${diff}` : `${diff}`
    console.log(
      `${(u.name ?? u.id.slice(0, 8)).padEnd(10)}  ` +
        `antes: ${(before?.deficit_block ?? 0).toString().padStart(5)}/7700 (${before?.blocks_completed ?? 0}b)  ` +
        `depois: ${after.deficit_block.toString().padStart(5)}/7700 (${after.blocks_completed}b)  ` +
        `Δ ${diffStr}  [${result.daysClosed} dias]`,
    )

    await supabase
      .from('user_progress')
      .update({
        deficit_block: after.deficit_block,
        blocks_completed: after.blocks_completed,
        updated_at: new Date().toISOString(),
      })
      .eq('user_id', u.id)
  }

  console.log(`\n✅ Backfill concluído.`)
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
