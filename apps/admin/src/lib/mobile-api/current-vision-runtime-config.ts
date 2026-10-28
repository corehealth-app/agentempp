/** BFF leaf: configured Vision behavior without importing worker runtime/jobs.
 * Last-known-good is scoped to a normalized Supabase origin, never global. */
import type { ServiceClient } from '@mpp/db'
import type { VisionPromptOverrides } from '@mpp/providers/vision'

interface VisionRuntimeConfig {
  readonly model: string
  readonly nutrition_label_model: string
  readonly meal_confidence_threshold: number
  readonly prompts: Readonly<VisionPromptOverrides>
}
const promptKeys = new Set([
  'meal',
  'body',
  'scale',
  'nutrition_label',
  'equipment',
  'other',
  'classifier',
])
function originKey(value: string) {
  const url = new URL(value)
  if (
    url.protocol !== 'https:' ||
    !/^[a-z0-9]{20}\.supabase\.co$/.test(url.hostname) ||
    url.username ||
    url.password ||
    url.search ||
    url.hash ||
    url.port ||
    (url.pathname !== '/' && url.pathname !== '')
  )
    throw new Error('Invalid Vision configuration origin')
  return url.origin
}
export function createCurrentVisionConfigLoader(now: () => number = Date.now) {
  const cache = new Map<string, { config: VisionRuntimeConfig; expiresAt: number }>()
  return async (client: ServiceClient, storageOrigin: string): Promise<VisionRuntimeConfig> => {
    const key = originKey(storageOrigin),
      started = now(),
      previous = cache.get(key)
    if (previous && previous.expiresAt > started) return previous.config
    try {
      const globals = await client
        .from('global_config')
        .select('key, value')
        .like('key', 'vision.%')
      if (globals.error) throw new Error('Vision configuration unavailable')
      let model = 'google/gemini-2.5-flash',
        nutritionLabel = 'anthropic/claude-sonnet-4.6',
        threshold = 0.6
      for (const row of globals.data ?? []) {
        if (row.key === 'vision.model' && typeof row.value === 'string') model = row.value
        else if (row.key === 'vision.nutrition_label_model' && typeof row.value === 'string')
          nutritionLabel = row.value
        else if (row.key === 'vision.meal.confidence_threshold') {
          const value = Number(row.value)
          if (Number.isFinite(value) && value >= 0 && value <= 1) threshold = value
        }
      }
      const rules = await client
        .from('agent_rules')
        .select('slug, content')
        .like('slug', 'vision-%')
        .eq('status', 'active')
      if (rules.error) throw new Error('Vision prompts unavailable')
      const prompts: VisionPromptOverrides = {}
      for (const row of rules.data ?? []) {
        const prompt = row.slug.replace(/^vision-/, '')
        if (promptKeys.has(prompt) && typeof row.content === 'string' && row.content)
          prompts[prompt as keyof VisionPromptOverrides] = row.content
      }
      const config = Object.freeze({
        model,
        nutrition_label_model: nutritionLabel,
        meal_confidence_threshold: threshold,
        prompts: Object.freeze(prompts),
      })
      cache.set(key, { config, expiresAt: started + 60000 })
      return config
    } catch (error) {
      if (previous) return previous.config
      throw error
    }
  }
}
