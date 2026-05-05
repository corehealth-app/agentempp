/**
 * Validador de saída: parseia números numa resposta do LLM e compara
 * com valores reais do contexto. Nao BLOQUEIA — apenas audita em
 * product_events ('llm.numeric_mismatch').
 *
 * Defensa em camadas: mesmo com (a) dados pre-injetados, (b) regra
 * inviolavel e (c) tool consulta_metricas, ainda pode haver alucinacao
 * em edge cases. Este validador detecta e loga pra investigacao.
 *
 * Nao corrige automaticamente — autoregeneracao e arriscada (loop) e a
 * correcao ideal depende do contexto (re-prompt? truncar? marcar?).
 *
 * Criterio de divergencia: |claimed - real| / max(|real|, 1) > 0.10
 * (10% de erro relativo) OU diferenca absoluta > 30 pra valores baixos.
 */

import type { Json, ServiceClient } from '@mpp/db'

// Config cache (60s) — controla threshold + on/off via /settings/global
interface ValidatorConfig {
  enabled: boolean
  threshold_pct: number
}
const DEFAULT_CONFIG: ValidatorConfig = { enabled: true, threshold_pct: 0.1 }
let cachedConfig: { config: ValidatorConfig; expiresAt: number } | null = null
const TTL_MS = 60_000

async function loadValidatorConfig(supabase: ServiceClient): Promise<ValidatorConfig> {
  const now = Date.now()
  if (cachedConfig && cachedConfig.expiresAt > now) return cachedConfig.config
  const { data } = (await supabase
    .from('global_config')
    .select('key, value')
    .like('key', 'numeric_validator.%')) as {
    data: Array<{ key: string; value: unknown }> | null
  }
  const merged: ValidatorConfig = { ...DEFAULT_CONFIG }
  for (const row of data ?? []) {
    if (row.key === 'numeric_validator.enabled' && typeof row.value === 'boolean') {
      merged.enabled = row.value
    } else if (row.key === 'numeric_validator.threshold_pct') {
      const n = Number(row.value)
      if (Number.isFinite(n) && n >= 0 && n <= 1) merged.threshold_pct = n
    }
  }
  cachedConfig = { config: merged, expiresAt: now + TTL_MS }
  return merged
}

interface NumericContext {
  calories_target?: number | null
  protein_target?: number | null
  imc?: number | null
  bmr?: number | null
  tdee?: number | null
  age?: number | null
  current_streak?: number | null
  level?: number | null
  calories_consumed_today?: number | null
}

interface MismatchFinding {
  field: string
  claimed: number
  real: number
  diff_abs: number
  diff_pct: number
  excerpt: string
}

const PATTERNS: Array<{
  field: keyof NumericContext
  re: RegExp
  /** Index do grupo de captura que tem o numero. */
  group: number
}> = [
  // "2.500 kcal", "2500 kcal", "meta de 2,500 kcal"
  { field: 'calories_target', re: /(?:meta|alvo|target|goal)\s*(?:hoje|de|é)?\s*(?:é\s*)?\*{0,2}\s*([\d]{3,5}(?:[.,][\d]{3})?)\s*\*{0,2}\s*kcal/gi, group: 1 },
  // "180g proteina", "180 g de proteina"
  { field: 'protein_target', re: /\*{0,2}\s*([\d]{2,4}(?:[.,]\d)?)\s*\*{0,2}\s*g\s*(?:de\s*)?prote[íi]na/gi, group: 1 },
  // "IMC 25", "IMC de 25.3", "IMC: 25,3"
  { field: 'imc', re: /imc\s*[:=]?\s*(?:de\s*)?(\d{1,2}(?:[.,]\d)?)/gi, group: 1 },
  // "BMR 1973", "BMR de 1.973"
  { field: 'bmr', re: /bmr\s*[:=]?\s*(?:de\s*)?(\d{3,4}(?:[.,]\d{3})?)/gi, group: 1 },
  // "TDEE 3059", "TDEE de 3.059"
  { field: 'tdee', re: /tdee\s*[:=]?\s*(?:de\s*)?(\d{3,4}(?:[.,]\d{3})?)/gi, group: 1 },
  // "46 anos", "tem 46 anos"
  { field: 'age', re: /(\d{2})\s*anos\b/gi, group: 1 },
  // "streak de 5 dias", "5 dias seguidos"
  { field: 'current_streak', re: /streak\s*(?:de|atual)?\s*[:=]?\s*(\d{1,3})/gi, group: 1 },
]

function parseNum(s: string): number {
  // "2.500" → 2500 (PT-BR), "2,500" → 2500
  const cleaned = s.replace(/\./g, '').replace(',', '.')
  return Number(cleaned)
}

export function validateNumericClaims(
  text: string,
  ctx: NumericContext,
  thresholdPct = 0.1,
): MismatchFinding[] {
  const findings: MismatchFinding[] = []
  for (const { field, re, group } of PATTERNS) {
    const real = ctx[field]
    if (real == null) continue
    re.lastIndex = 0
    let match: RegExpExecArray | null
    while ((match = re.exec(text)) !== null) {
      const claimedRaw = match[group]
      if (!claimedRaw) continue
      const claimed = parseNum(claimedRaw)
      if (!Number.isFinite(claimed)) continue
      const diff = Math.abs(claimed - real)
      const diffPct = diff / Math.max(Math.abs(real), 1)

      const tolerance =
        field === 'age'
          ? 1
          : field === 'current_streak' || field === 'level'
            ? 2
            : Math.max(real * thresholdPct, 30)
      if (diff <= tolerance) continue

      const excerptStart = Math.max(0, match.index - 40)
      const excerptEnd = Math.min(text.length, match.index + match[0].length + 40)
      findings.push({
        field,
        claimed,
        real,
        diff_abs: +diff.toFixed(2),
        diff_pct: +diffPct.toFixed(3),
        excerpt: text.slice(excerptStart, excerptEnd).trim(),
      })
    }
  }
  return findings
}

/**
 * Loga divergencias em product_events. Nao bloqueia. Nao retorna nada.
 */
export async function auditNumericClaims(
  supabase: ServiceClient,
  userId: string,
  text: string,
  ctx: NumericContext,
  metadata: Record<string, Json> = {},
): Promise<void> {
  if (!text) return
  const config = await loadValidatorConfig(supabase)
  if (!config.enabled) return
  const findings = validateNumericClaims(text, ctx, config.threshold_pct)
  if (findings.length === 0) return

  await supabase.from('product_events').insert({
    user_id: userId,
    event: 'llm.numeric_mismatch',
    properties: {
      findings: findings as unknown as Json,
      threshold_pct: config.threshold_pct,
      ...metadata,
    },
  })
}
