import { DEFAULT_CALC_CONFIG } from '@mpp/core'
import { beforeEach, describe, expect, it } from 'vitest'
import { clearCalcConfigCache, loadCalcConfig } from './calc-config-loader.js'

function makeClient(result: {
  data: Array<{ key: string; value: unknown }> | null
  error: { message: string } | null
}) {
  return {
    from: () => ({
      select: () => ({
        like: async () => result,
      }),
    }),
  }
}

describe('loadCalcConfig', () => {
  beforeEach(() => clearCalcConfigCache())

  it('não cacheia defaults quando a leitura da configuração falha', async () => {
    const client = makeClient({ data: null, error: { message: 'calc config unavailable' } })

    await expect(loadCalcConfig(client)).rejects.toThrow('calc config unavailable')
  })

  it('usa defaults quando a consulta funciona e não existem overrides', async () => {
    const client = makeClient({ data: [], error: null })

    await expect(loadCalcConfig(client)).resolves.toEqual(DEFAULT_CALC_CONFIG)
  })

  it('mescla override válido sobre a configuração canônica', async () => {
    const client = makeClient({
      data: [{ key: 'calc.kcal_block', value: 8000 }],
      error: null,
    })

    const result = await loadCalcConfig(client)

    expect(result.kcal_block).toBe(8000)
  })
})
