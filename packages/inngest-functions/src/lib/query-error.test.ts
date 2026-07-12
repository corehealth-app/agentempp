import { describe, expect, it } from 'vitest'
import { throwIfQueryFailed } from './query-error.js'

describe('throwIfQueryFailed', () => {
  it('mantém a mensagem do banco para diagnóstico e retry', () => {
    expect(() => throwIfQueryFailed({ message: 'buffer lookup failed' }, 'fallback')).toThrow(
      'buffer lookup failed',
    )
  })

  it('usa fallback para erros sem mensagem', () => {
    expect(() => throwIfQueryFailed({ code: 'XX000' }, 'fallback')).toThrow('fallback')
  })

  it('não lança sem erro', () => {
    expect(() => throwIfQueryFailed(null, 'fallback')).not.toThrow()
  })
})
