import type { ServiceClient } from '@mpp/db'
import { beforeEach, describe, expect, it } from 'vitest'
import { loadRouterFlag, resetRouterFlagCacheForTests } from './router-flag.js'

function makeClient(result: { data: unknown; error: { message: string } | null }): ServiceClient {
  const chain = (): unknown => {
    const value: Record<string, unknown> = {
      select: () => chain(),
      eq: () => chain(),
      maybeSingle: () => Promise.resolve(result),
    }
    return value
  }
  return { from: () => chain() } as unknown as ServiceClient
}

describe('loadRouterFlag', () => {
  beforeEach(() => resetRouterFlagCacheForTests())

  it('desativa roteamento econômico quando a configuração não pode ser lida', async () => {
    const client = makeClient({ data: null, error: { message: 'router config unavailable' } })

    await expect(loadRouterFlag(client)).resolves.toBe(false)
  })

  it('mantém o default habilitado quando a consulta funciona e a chave não existe', async () => {
    const client = makeClient({ data: null, error: null })

    await expect(loadRouterFlag(client)).resolves.toBe(true)
  })

  it('respeita valor false explícito', async () => {
    const client = makeClient({ data: { value: false }, error: null })

    await expect(loadRouterFlag(client)).resolves.toBe(false)
  })
})
