import { describe, expect, it } from 'vitest'
import { cadastraDadosIniciais, deleteUser } from './tools.js'

function makeProfileContext(options: { nameUpdateError?: string } = {}) {
  const supabase = {
    from(table: string) {
      if (table === 'user_profiles') {
        return {
          upsert: async () => ({ error: null }),
          select: () => ({
            eq: () => ({
              maybeSingle: async () => ({ data: null, error: null }),
            }),
          }),
        }
      }
      if (table === 'users') {
        return {
          update: () => ({
            eq: async () => ({
              error: options.nameUpdateError ? { message: options.nameUpdateError } : null,
            }),
          }),
        }
      }
      if (table === 'v_user_metrics') {
        return {
          select: () => ({
            eq: () => ({
              maybeSingle: async () => ({ data: null, error: null }),
            }),
          }),
        }
      }
      if (table === 'global_config') {
        return {
          select: () => ({
            like: async () => ({ data: [], error: null }),
          }),
        }
      }
      throw new Error(`unexpected table: ${table}`)
    },
  }
  return {
    supabase,
    context: {
      supabase,
      userId: 'user-1',
      userWpp: '15555550100',
      referenceTimestamp: new Date('2026-07-11T12:00:00.000Z'),
    },
  }
}

describe('profile write safety', () => {
  it('cadastra_dados_iniciais não confirma nome que falhou ao gravar', async () => {
    const { context } = makeProfileContext({ nameUpdateError: 'name write failed' })

    await expect(
      cadastraDadosIniciais.execute({ name: 'Nome Teste' }, context as never),
    ).rejects.toThrow('name write failed')
  })

  it('delete_user não confirma exclusão quando status não foi persistido', async () => {
    const events: Array<Record<string, unknown>> = []
    const context = {
      userId: 'user-1',
      userWpp: '15555550100',
      supabase: {
        from(table: string) {
          if (table === 'users') {
            return {
              update: () => ({
                eq: async () => ({ error: { message: 'delete status write failed' } }),
              }),
            }
          }
          if (table === 'product_events') {
            return {
              insert: async (event: Record<string, unknown>) => {
                events.push(event)
                return { error: null }
              },
            }
          }
          throw new Error(`unexpected table: ${table}`)
        },
      },
    }

    await expect(deleteUser.execute({ confirmacao: 'confirmo' }, context as never)).rejects.toThrow(
      'delete status write failed',
    )
    expect(events).toHaveLength(0)
  })

  it('delete_user registra quando a janela segura para purge começou', async () => {
    const userUpdates: Array<Record<string, unknown>> = []
    const context = {
      userId: 'user-1',
      userWpp: '15555550100',
      supabase: {
        from(table: string) {
          if (table === 'users') {
            return {
              update: (values: Record<string, unknown>) => {
                userUpdates.push(values)
                return { eq: async () => ({ error: null }) }
              },
            }
          }
          if (table === 'product_events') {
            return { insert: async () => ({ error: null }) }
          }
          throw new Error(`unexpected table: ${table}`)
        },
      },
    }

    await expect(
      deleteUser.execute({ confirmacao: 'confirmo' }, context as never),
    ).resolves.toMatchObject({ success: true })
    const userUpdate = userUpdates[0]
    expect(userUpdate).toMatchObject({ status: 'deleted' })
    expect(new Date(String(userUpdate?.updated_at)).toISOString()).toBe(userUpdate?.updated_at)
  })
})
