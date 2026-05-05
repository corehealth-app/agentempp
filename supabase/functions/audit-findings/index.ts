// Edge function: audit-findings
//
// Agrega bugs detectaveis nas ultimas 8h. Chamado por routine remota
// /schedule 3x/dia. Auth via shared secret no header (AUDIT_SECRET).
//
// Retorna JSON com:
//   - numeric_mismatches: alucinacoes detectadas pelo validador de saida
//   - meal_warnings: matches TACO suspeitos
//   - tools_failed: tools que retornaram error
//   - foods_no_match: alimentos consistentemente sem match (alvos pra alias)
//   - summary: contagens + nivel de severidade

import { createClient } from 'jsr:@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const AUDIT_SECRET = Deno.env.get('AUDIT_SECRET') ?? ''

interface NoMatchAggregate {
  food_name: string
  count: number
  last_seen: string
  example_users: string[]
}

Deno.serve(async (req: Request) => {
  // Auth
  const authHeader = req.headers.get('x-audit-secret') ?? ''
  if (!AUDIT_SECRET || authHeader !== AUDIT_SECRET) {
    return new Response('forbidden', { status: 403 })
  }
  if (req.method !== 'GET') {
    return new Response('method', { status: 405 })
  }

  const url = new URL(req.url)
  const hours = Number(url.searchParams.get('hours') ?? '8')
  const lookbackDays = Number(url.searchParams.get('lookback_days') ?? '7')
  const since = new Date(Date.now() - hours * 3600 * 1000).toISOString()
  const sinceLookback = new Date(Date.now() - lookbackDays * 24 * 3600 * 1000).toISOString()

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  // 1. Numeric mismatches recentes
  const { data: numericMismatches } = await supabase
    .from('product_events')
    .select('user_id, occurred_at, properties')
    .eq('event', 'llm.numeric_mismatch')
    .gte('occurred_at', since)
    .order('occurred_at', { ascending: false })
    .limit(50)

  // 2. Meal match warnings
  const { data: mealWarnings } = await supabase
    .from('product_events')
    .select('user_id, occurred_at, properties')
    .eq('event', 'meal.match_warning')
    .gte('occurred_at', since)
    .order('occurred_at', { ascending: false })
    .limit(50)

  // 3. Tools que falharam
  const { data: toolsFailed } = await supabase
    .from('tools_audit')
    .select('user_id, tool_name, error, created_at, arguments')
    .eq('success', false)
    .gte('created_at', since)
    .order('created_at', { ascending: false })
    .limit(30)

  // 4. Foods consistentemente sem match nos ultimos 7 dias (alvos pra alias)
  const { data: noMatchLogs } = await supabase
    .from('meal_logs')
    .select('user_id, food_name, created_at')
    .eq('source', 'no_match')
    .gte('created_at', sinceLookback)
    .order('created_at', { ascending: false })
    .limit(500)

  // Aggregate por nome normalizado
  const noMatchCounts = new Map<string, NoMatchAggregate>()
  for (const log of noMatchLogs ?? []) {
    const key = (log.food_name as string).toLowerCase().trim()
    if (!noMatchCounts.has(key)) {
      noMatchCounts.set(key, {
        food_name: log.food_name as string,
        count: 0,
        last_seen: log.created_at as string,
        example_users: [],
      })
    }
    const agg = noMatchCounts.get(key)!
    agg.count++
    if (agg.example_users.length < 3 && !agg.example_users.includes(log.user_id as string)) {
      agg.example_users.push(log.user_id as string)
    }
  }
  // Filtra alvos: ≥3 ocorrencias, ≥2 users distintos (evita um user spammando)
  const foodsNoMatchTargets = Array.from(noMatchCounts.values())
    .filter((a) => a.count >= 3 && a.example_users.length >= 2)
    .sort((a, b) => b.count - a.count)
    .slice(0, 20)

  // 5. Summary com severidade
  const numericCount = (numericMismatches ?? []).length
  const mealWarningCount = (mealWarnings ?? []).length
  const toolsFailedCount = (toolsFailed ?? []).length
  const noMatchTargetCount = foodsNoMatchTargets.length

  let severity: 'ok' | 'warning' | 'critical' = 'ok'
  if (numericCount > 10 || toolsFailedCount > 5) severity = 'critical'
  else if (numericCount > 0 || mealWarningCount > 5 || noMatchTargetCount > 0) severity = 'warning'

  return Response.json({
    window_hours: hours,
    since,
    severity,
    counts: {
      numeric_mismatches: numericCount,
      meal_warnings: mealWarningCount,
      tools_failed: toolsFailedCount,
      foods_no_match_targets: noMatchTargetCount,
    },
    numeric_mismatches: numericMismatches ?? [],
    meal_warnings: mealWarnings ?? [],
    tools_failed: toolsFailed ?? [],
    foods_no_match_targets: foodsNoMatchTargets,
  })
})
