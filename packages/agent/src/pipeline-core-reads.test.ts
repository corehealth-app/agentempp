import { afterEach, describe, expect, it } from 'vitest'
import { checkSubscription, hasOpenPending, loadContext } from './pipeline.js'

function terminalQuery(result: { data: unknown; error: unknown }) {
  const chain = {
    select: () => chain,
    eq: () => chain,
    order: () => chain,
    limit: () => chain,
    single: async () => result,
    maybeSingle: async () => result,
  }
  return chain
}

const originalNodeEnv = process.env.NODE_ENV
const originalSubscriptionGate = process.env.SUBSCRIPTION_GATE

afterEach(() => {
  process.env.NODE_ENV = originalNodeEnv
  if (originalSubscriptionGate === undefined) delete process.env.SUBSCRIPTION_GATE
  else process.env.SUBSCRIPTION_GATE = originalSubscriptionGate
})

describe('leituras essenciais do pipeline', () => {
  it('não libera assinatura quando a consulta falha', async () => {
    process.env.NODE_ENV = 'production'
    delete process.env.SUBSCRIPTION_GATE
    const supabase = {
      from: (table: string) => {
        expect(table).toBe('subscriptions')
        return terminalQuery({ data: null, error: { message: 'subscription lookup failed' } })
      },
    }

    await expect(checkSubscription(supabase as never, 'user-1')).rejects.toThrow(
      'subscription lookup failed',
    )
  })

  it('interrompe o turno quando o usuário não pode ser carregado', async () => {
    const supabase = {
      from: (table: string) => {
        if (table !== 'users') throw new Error(`unexpected table ${table}`)
        return terminalQuery({ data: null, error: { message: 'user context lookup failed' } })
      },
    }

    await expect(
      loadContext(
        supabase as never,
        'user-1',
        null,
        null,
        new Date('2026-07-12T12:00:00.000Z'),
      ),
    ).rejects.toThrow('user context lookup failed')
  })

  it('não assume ausência de pending quando a consulta falha', async () => {
    const result = { data: null, error: { message: 'pending lookup failed' } }
    const chain = {
      select: () => chain,
      eq: () => chain,
      limit: async () => result,
    }
    const supabase = { from: () => chain }

    await expect(hasOpenPending(supabase as never, 'user-1')).rejects.toThrow(
      'pending lookup failed',
    )
  })
})
