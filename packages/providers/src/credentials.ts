/**
 * Resolver de credenciais com cache.
 *
 * Estratégia (em ordem de preferência):
 *   1. Tabela service_credentials (editável via admin UI)
 *   2. process.env como fallback
 *
 * Cache em memória de 60s para não bater no Postgres a cada request.
 */
import type { SupabaseClient } from '@supabase/supabase-js'

interface CacheEntry {
  value: string
  fetchedAt: number
}

const TTL_MS = 60_000
const cache = new Map<string, CacheEntry>()

export interface CredentialResolverOpts {
  supabase: SupabaseClient
  envFallback?: NodeJS.ProcessEnv
}

export async function resolveCredential(
  service: string,
  keyName: string,
  envKey: string | undefined,
  opts: CredentialResolverOpts,
): Promise<string | null> {
  const cacheKey = `${service}:${keyName}`
  const hit = cache.get(cacheKey)
  if (hit && Date.now() - hit.fetchedAt < TTL_MS) return hit.value

  const { data } = await opts.supabase
    .from('service_credentials')
    .select('value')
    .eq('service', service)
    .eq('key_name', keyName)
    .eq('is_active', true)
    .maybeSingle()

  if (data?.value) {
    cache.set(cacheKey, { value: data.value, fetchedAt: Date.now() })
    return data.value
  }

  // Fallback env
  const env = opts.envFallback ?? process.env
  if (envKey && env[envKey]) {
    return env[envKey]!
  }

  return null
}

export function invalidateCredentialsCache(service?: string): void {
  if (!service) {
    cache.clear()
    return
  }
  for (const k of cache.keys()) {
    if (k.startsWith(`${service}:`)) cache.delete(k)
  }
}
