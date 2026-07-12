import { describe, expect, it } from 'vitest'
import { atualizaDataUser } from './tools.js'

function makeContext(options: { updatedUser?: { id: string } | null } = {}) {
  const updates: Array<Record<string, unknown>> = []
  const supabase = {
    from(table: string) {
      if (table !== 'users') throw new Error(`unexpected table: ${table}`)
      return {
        update(values: Record<string, unknown>) {
          updates.push(values)
          return {
            eq: () => ({
              select: () => ({
                maybeSingle: async () => ({
                  data: options.updatedUser === undefined ? { id: 'user-1' } : options.updatedUser,
                  error: null,
                }),
              }),
            }),
          }
        },
      }
    },
  }
  return { updates, ctx: { supabase, userId: 'user-1' } as never }
}

describe('atualiza_data_user', () => {
  it('rejeita timezone IANA inválido antes de gravar', async () => {
    const { ctx, updates } = makeContext()

    await expect(atualizaDataUser.execute({ timezone: 'America/Orland' }, ctx)).rejects.toThrow(
      'Timezone inválido',
    )
    expect(updates).toEqual([])
  })

  it('não confirma chamada sem nenhum campo', async () => {
    const { ctx, updates } = makeContext()

    await expect(atualizaDataUser.execute({}, ctx)).resolves.toMatchObject({
      success: false,
      error: 'no_updates',
    })
    expect(updates).toEqual([])
  })

  it('não confirma update que não encontrou o usuário', async () => {
    const { ctx } = makeContext({ updatedUser: null })

    await expect(atualizaDataUser.execute({ name: 'Nome' }, ctx)).rejects.toThrow('user not found')
  })
})
