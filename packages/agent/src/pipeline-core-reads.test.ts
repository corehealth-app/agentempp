import { afterEach, describe, expect, it, vi } from 'vitest'
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
  vi.restoreAllMocks()
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
      loadContext(supabase as never, 'user-1', null, null, new Date('2026-07-12T12:00:00.000Z')),
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

  it('não inicia a preferência opcional Flow antes de carregar um usuário válido', async () => {
    const tables: string[] = []
    const supabase = {
      from: (table: string) => {
        tables.push(table)
        return terminalQuery({ data: null, error: null })
      },
    }
    await expect(
      loadContext(
        supabase as never,
        'user-a',
        null,
        null,
        new Date('2026-10-08T12:00:00Z'),
        'mobile_flow',
      ),
    ).rejects.toThrow('user context missing')
    expect(tables).toEqual(['users'])
  })

  it('mantém a falha essencial do perfil e consome a rejeição tardia da preferência em paralelo', async () => {
    const tables: string[] = []
    let rejectStyle!: (reason: Error) => void
    const style = new Promise<{ data: unknown; error: unknown }>((_resolve, reject) => {
      rejectStyle = reject
    })
    let consumed!: () => void
    const optionalConsumed = new Promise<void>((resolve) => {
      consumed = resolve
    })
    const warning = vi.spyOn(console, 'warn').mockImplementation((message, detail) => {
      if (message === '[mobile-flow] coach_style_unapplied' && detail.reason === 'query_rejected')
        consumed()
    })
    const supabase = {
      from: (table: string) => {
        tables.push(table)
        if (table === 'users') return terminalQuery({ data: { id: 'user-a' }, error: null })
        if (table === 'user_profiles')
          return terminalQuery({ data: null, error: { message: 'synthetic profile failure' } })
        if (table === 'user_coach_preferences')
          return {
            ...terminalQuery({ data: null, error: null }),
            select() {
              return this
            },
            eq() {
              return this
            },
            maybeSingle: () => style,
          }
        throw new Error('core failure must stop other context reads')
      },
    }
    await expect(
      loadContext(
        supabase as never,
        'user-a',
        null,
        null,
        new Date('2026-10-08T12:00:00Z'),
        'mobile_flow',
      ),
    ).rejects.toThrow('synthetic profile failure')
    expect(tables).toEqual(['users', 'user_profiles', 'user_coach_preferences'])
    rejectStyle(new Error('synthetic style transport failure'))
    await optionalConsumed
    expect(warning).toHaveBeenCalledWith('[mobile-flow] coach_style_unapplied', {
      reason: 'query_rejected',
    })
  })
})
