import { describe, expect, it } from 'vitest'
import { ensureUser } from './pipeline.js'

describe('ensureUser', () => {
  it('inicializa usuário, perfil e progresso por uma única RPC atômica', async () => {
    const calls: Array<{ name: string; params: Record<string, unknown> }> = []
    const supabase = {
      rpc: async (name: string, params: Record<string, unknown>) => {
        calls.push({ name, params })
        return { data: 'user-1', error: null }
      },
      from: () => {
        throw new Error('ensureUser must not issue separate table writes')
      },
    }

    await expect(ensureUser(supabase as never, '15551234567')).resolves.toBe('user-1')
    expect(calls).toEqual([
      {
        name: 'ensure_user_initialized',
        params: { p_wpp: '15551234567' },
      },
    ])
  })

  it('propaga falha da inicialização para o worker poder tentar novamente', async () => {
    const supabase = {
      rpc: async () => ({ data: null, error: { message: 'database unavailable' } }),
    }

    await expect(ensureUser(supabase as never, '15551234567')).rejects.toThrow(
      'database unavailable',
    )
  })

  it('rejeita resposta sem id mesmo quando a RPC não informa erro', async () => {
    const supabase = {
      rpc: async () => ({ data: null, error: null }),
    }

    await expect(ensureUser(supabase as never, '15551234567')).rejects.toThrow(
      'ensure_user_initialized returned no user id',
    )
  })
})
