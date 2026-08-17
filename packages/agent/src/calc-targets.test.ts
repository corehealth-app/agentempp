import { DEFAULT_CALC_CONFIG } from '@mpp/core'
import { describe, expect, it } from 'vitest'
import { loadDailyTargets } from './calc-targets.js'

function makeClient(result: { data: Record<string, unknown> | null; error: unknown }) {
  const terminal = {
    maybeSingle: async () => result,
  }
  return {
    from: () => ({
      select: () => ({
        eq: () => terminal,
      }),
    }),
  }
}

describe('loadDailyTargets', () => {
  it('propaga erro de perfil em vez de calcular metas com perfil vazio', async () => {
    const client = makeClient({ data: null, error: { message: 'profile lookup failed' } })

    await expect(loadDailyTargets(client, 'user-1', DEFAULT_CALC_CONFIG)).rejects.toThrow(
      'profile lookup failed',
    )
  })

  it('mantém fallback funcional quando a consulta é válida e o perfil ainda não existe', async () => {
    const client = makeClient({ data: null, error: null })

    await expect(loadDailyTargets(client, 'user-1', DEFAULT_CALC_CONFIG)).resolves.toEqual(
      expect.objectContaining({ calories_target: null, protein_target: null }),
    )
  })
})
