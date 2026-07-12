import type { ServiceClient } from '@mpp/db'

let routerFlagCache: { value: boolean; expiresAt: number } | null = null
const ROUTER_FLAG_TTL_MS = 60_000

export async function loadRouterFlag(supabase: ServiceClient): Promise<boolean> {
  const now = Date.now()
  if (routerFlagCache && routerFlagCache.expiresAt > now) return routerFlagCache.value

  const { data, error } = await (
    supabase as unknown as {
      from: (table: string) => {
        select: (columns: string) => {
          eq: (
            column: string,
            value: string,
          ) => {
            maybeSingle: () => Promise<{ data: unknown; error: unknown }>
          }
        }
      }
    }
  )
    .from('global_config')
    .select('value')
    .eq('key', 'router.haiku_enabled')
    .maybeSingle()

  // Em indisponibilidade, usa o modelo principal e tenta consultar de novo no
  // próximo turno. Não cacheia a falha como se fosse configuração explícita.
  if (error) return false

  const value =
    data && (data as { value?: unknown }).value !== undefined
      ? (data as { value?: unknown }).value !== false &&
        (data as { value?: unknown }).value !== 'false'
      : true
  routerFlagCache = { value, expiresAt: now + ROUTER_FLAG_TTL_MS }
  return value
}

export function resetRouterFlagCacheForTests(): void {
  routerFlagCache = null
}
