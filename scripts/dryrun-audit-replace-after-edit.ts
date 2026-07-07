/**
 * DRY-RUN: lista casos históricos em que replace foi ratificado/inferido por
 * contexto de pending editado. Não altera dados e não tem modo de escrita.
 *
 * Rodar:
 *   set -a; . ./.env.local; set +a
 *   pnpm --dir scripts exec tsx dryrun-audit-replace-after-edit.ts --days=30 --limit=100
 */
import { createServiceClient } from '@mpp/db'

const WATCH_EVENTS = [
  'tool.replace_ratified_by_proposal_context',
  'tap.replace_inferred_after_edit',
] as const

type EventRow = {
  id: string
  user_id: string | null
  event: string
  occurred_at: string
  properties: unknown
}

type AuditRow = {
  id: string
  created_at: string
  arguments: unknown
  result: unknown
}

function argNumber(name: string, fallback: number): number {
  const raw = process.argv.find((a) => a.startsWith(`--${name}=`))?.split('=')[1]
  const n = Number(raw)
  return Number.isFinite(n) && n > 0 ? n : fallback
}

function maskId(id: string | null | undefined): string | null {
  if (!id) return null
  if (id.length <= 12) return `${id.slice(0, 4)}...`
  return `${id.slice(0, 8)}...${id.slice(-4)}`
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {}
}

function auditKcal(audit: AuditRow | null): {
  audit_id: string | null
  kcal_removed: number | null
  kcal_added: number | null
  proposed_delta_if_preserved: number | null
} {
  if (!audit) {
    return {
      audit_id: null,
      kcal_removed: null,
      kcal_added: null,
      proposed_delta_if_preserved: null,
    }
  }
  const result = asRecord(audit.result)
  const replaced = asRecord(result.replaced)
  const meal = asRecord(result.meal)
  const totals = asRecord(meal.totals)
  const removed = Number(replaced.kcal_removed)
  const added = Number(totals.kcal)
  return {
    audit_id: maskId(audit.id),
    kcal_removed: Number.isFinite(removed) ? removed : null,
    kcal_added: Number.isFinite(added) ? Math.round(added) : null,
    proposed_delta_if_preserved: Number.isFinite(removed) ? removed : null,
  }
}

async function main() {
  if (process.argv.includes('--apply')) {
    throw new Error('Este script é dry-run only. --apply não é suportado.')
  }

  const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!url || !key) throw new Error('SUPABASE_URL/SERVICE_ROLE_KEY ausente em env')
  const supabase = createServiceClient({ url, serviceRoleKey: key })

  const days = argNumber('days', 30)
  const limit = argNumber('limit', 100)
  const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString()

  const { data: events, error } = await supabase
    .from('product_events')
    .select('id, user_id, event, occurred_at, properties')
    .in('event', [...WATCH_EVENTS])
    .gte('occurred_at', since)
    .order('occurred_at', { ascending: false })
    .limit(limit)
  if (error) throw new Error(error.message)

  console.log('\nDRY-RUN: replace após pending editado')
  console.log(`janela=${days}d limit=${limit} eventos=${events?.length ?? 0}`)
  console.log('Nenhuma escrita será feita.\n')

  for (const row of (events ?? []) as EventRow[]) {
    const props = asRecord(row.properties)
    const userId = row.user_id
    let nearestAudit: AuditRow | null = null
    if (userId) {
      const from = new Date(new Date(row.occurred_at).getTime() - 10 * 60 * 1000).toISOString()
      const to = new Date(new Date(row.occurred_at).getTime() + 10 * 60 * 1000).toISOString()
      const { data: audits } = await supabase
        .from('tools_audit')
        .select('id, created_at, arguments, result')
        .eq('user_id', userId)
        .eq('tool_name', 'registra_refeicao')
        .gte('created_at', from)
        .lte('created_at', to)
        .order('created_at', { ascending: false })
        .limit(1)
      nearestAudit = ((audits ?? []) as AuditRow[])[0] ?? null
    }

    const args = asRecord(nearestAudit?.arguments)
    const kcal = auditKcal(nearestAudit)
    const mealType = props.meal_type ?? props.corrected_meal_type ?? args.meal_type ?? 'unknown'
    const pendingId = props.edited_pending_id ?? props.pendingId ?? null
    const output = {
      event_id: maskId(row.id),
      event: row.event,
      occurred_at: row.occurred_at,
      user_id: maskId(userId),
      meal_type: mealType,
      pending_id: maskId(typeof pendingId === 'string' ? pendingId : null),
      audit_id: kcal.audit_id,
      kcal_removed_by_replace: kcal.kcal_removed,
      kcal_added_by_new_registration: kcal.kcal_added,
      proposed_delta_if_historical_fix_preserved_removed_meal: kcal.proposed_delta_if_preserved,
      justification:
        kcal.kcal_removed == null
          ? 'caso suspeito; kcal antes/depois não calculável pelo tools_audit disponível'
          : 'caso suspeito; correção histórica exigiria revisão manual antes de qualquer UPDATE',
    }
    console.log(JSON.stringify(output))
  }

  console.log(
    '\nFim do dry-run. Para corrigir dados históricos, criar script separado e pedir aprovação explícita.\n',
  )
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
