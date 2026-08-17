/**
 * DRY-RUN do recompute do bloco com a nova regra (opção C) — só REPORTA o
 * delta esperado por paciente, NÃO aplica nada no banco. Roberto autorizou
 * via Eduardo 2026-05-31; backfill real depende de aprovação adicional.
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
    .not('name', 'is', null)
    .order('name')

  console.log('\n── DRY-RUN: bloco 7700 com OPÇÃO C ──\n')
  console.log('paciente   antes        depois       Δ')
  console.log('-'.repeat(60))

  for (const u of (users ?? []) as Array<{ id: string; name: string | null }>) {
    const { data: progBefore } = await supabase
      .from('user_progress')
      .select('deficit_block, blocks_completed')
      .eq('user_id', u.id)
      .maybeSingle()
    const before = progBefore as { deficit_block?: number; blocks_completed?: number } | null
    const beforeBlock = before?.deficit_block ?? 0
    const beforeCompleted = before?.blocks_completed ?? 0

    const result = await recomputeUserBloco(supabase, u.id)
    const after = result.correctDeficitBlock
    const afterCompleted = result.correctBlocksCompleted

    const delta = after + afterCompleted * 7700 - (beforeBlock + beforeCompleted * 7700)
    const arrow = delta === 0 ? '   =' : delta > 0 ? `  +${delta}` : `  ${delta}`
    console.log(
      `${(u.name ?? '?').padEnd(10)} ${beforeBlock}/7700 (${beforeCompleted}b)  →  ${after}/7700 (${afterCompleted}b)${arrow}`,
    )
  }
  console.log('\n(NADA foi escrito no banco. Pra aplicar de verdade, rode o backfill script.)\n')
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
