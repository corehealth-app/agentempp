/**
 * Loaders de runtime config compartilhados entre Inngest functions.
 * Cache 60s — mudanças via /settings/global propagam em ≤1min.
 *
 * Pra adicionar nova chave: adicione em DEFAULT_*, ajuste a função
 * loader pra ler do global_config (chave começando com prefix).
 */

export interface HumanizerConfig {
  min_delay_ms: number
  max_delay_ms: number
  /** delay max em respostas (process-message). engagement usa max_delay_ms. */
  response_max_delay_ms: number
  chars_per_second: number
}

const DEFAULT_HUMANIZER_CONFIG: HumanizerConfig = {
  min_delay_ms: 800,
  max_delay_ms: 3000,
  response_max_delay_ms: 3500,
  chars_per_second: 55,
}

let cached: { config: HumanizerConfig; expiresAt: number } | null = null
const TTL_MS = 60_000

export async function loadHumanizerConfig(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  svc: any,
): Promise<HumanizerConfig> {
  const now = Date.now()
  if (cached && cached.expiresAt > now) return cached.config

  const { data, error } = (await svc
    .from('global_config')
    .select('key, value')
    .like('key', 'humanizer.%')) as {
    data: Array<{ key: string; value: unknown }> | null
    error: unknown
  }

  if (error || !data || data.length === 0) {
    cached = { config: DEFAULT_HUMANIZER_CONFIG, expiresAt: now + TTL_MS }
    return DEFAULT_HUMANIZER_CONFIG
  }

  const merged: HumanizerConfig = { ...DEFAULT_HUMANIZER_CONFIG }
  for (const row of data) {
    const subKey = row.key.replace(/^humanizer\./, '') as keyof HumanizerConfig
    const num = Number(row.value)
    if (Number.isFinite(num) && subKey in merged) {
      merged[subKey] = num
    }
  }

  cached = { config: merged, expiresAt: now + TTL_MS }
  return merged
}

// ============================================================================
// Vision config — modelo, threshold de confidence, prompts (do agent_rules).
// Cache 60s. Mudanças via /settings/global e /prompts propagam em ≤1min.
// ============================================================================

export interface VisionRuntimeConfig {
  model: string
  meal_confidence_threshold: number
  prompts: {
    meal?: string
    body?: string
    scale?: string
    other?: string
    classifier?: string
  }
}

const DEFAULT_VISION_CONFIG = {
  model: 'google/gemini-2.5-flash',
  meal_confidence_threshold: 0.6,
}

let visionCached: { config: VisionRuntimeConfig; expiresAt: number } | null = null

export async function loadVisionConfig(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  svc: any,
): Promise<VisionRuntimeConfig> {
  const now = Date.now()
  if (visionCached && visionCached.expiresAt > now) return visionCached.config

  const merged: VisionRuntimeConfig = {
    model: DEFAULT_VISION_CONFIG.model,
    meal_confidence_threshold: DEFAULT_VISION_CONFIG.meal_confidence_threshold,
    prompts: {},
  }

  const { data: gcRows } = (await svc
    .from('global_config')
    .select('key, value')
    .like('key', 'vision.%')) as { data: Array<{ key: string; value: unknown }> | null }
  for (const row of gcRows ?? []) {
    if (row.key === 'vision.model' && typeof row.value === 'string') {
      merged.model = row.value
    } else if (row.key === 'vision.meal.confidence_threshold') {
      const n = Number(row.value)
      if (Number.isFinite(n) && n >= 0 && n <= 1) {
        merged.meal_confidence_threshold = n
      }
    }
  }

  const { data: ruleRows } = (await svc
    .from('agent_rules')
    .select('slug, content')
    .like('slug', 'vision-%')
    .eq('status', 'active')) as {
    data: Array<{ slug: string; content: string }> | null
  }
  for (const row of ruleRows ?? []) {
    const key = row.slug.replace(/^vision-/, '') as keyof VisionRuntimeConfig['prompts']
    if (['meal', 'body', 'scale', 'other', 'classifier'].includes(key) && row.content) {
      merged.prompts[key] = row.content
    }
  }

  visionCached = { config: merged, expiresAt: now + TTL_MS }
  return merged
}
