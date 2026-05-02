/**
 * Carrega CalcConfig do global_config (Supabase) com cache em memória.
 *
 * Uso:
 *   const config = await loadCalcConfig(supabaseClient)
 *   const metrics = computeMetrics(profile, new Date(), config)
 *
 * O cache vive 60s. Mudanças via /settings/calc no admin demoram até esse
 * tempo pra propagar (ou reinicia o worker).
 */
import { DEFAULT_CALC_CONFIG, type CalcConfig } from '@mpp/core'

interface ConfigRow {
  key: string
  value: unknown
}

const TTL_MS = 60_000
let cached: { config: CalcConfig; expiresAt: number } | null = null

interface SupabaseLike {
  from: (table: string) => {
    select: (cols: string) => {
      like: (col: string, pat: string) => Promise<{ data: ConfigRow[] | null; error: unknown }>
    }
  }
}

export async function loadCalcConfig(svc: SupabaseLike): Promise<CalcConfig> {
  const now = Date.now()
  if (cached && cached.expiresAt > now) return cached.config

  const { data, error } = await svc.from('global_config').select('key, value').like('key', 'calc.%')
  if (error || !data || data.length === 0) {
    // Fallback seguro: usa defaults se DB falhar
    cached = { config: DEFAULT_CALC_CONFIG, expiresAt: now + TTL_MS }
    return DEFAULT_CALC_CONFIG
  }

  const merged: CalcConfig = JSON.parse(JSON.stringify(DEFAULT_CALC_CONFIG))
  for (const row of data) {
    const subKey = row.key.replace(/^calc\./, '') as keyof CalcConfig
    if (subKey in merged) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      ;(merged as any)[subKey] = row.value
    }
  }

  cached = { config: merged, expiresAt: now + TTL_MS }
  return merged
}

export function clearCalcConfigCache(): void {
  cached = null
}
