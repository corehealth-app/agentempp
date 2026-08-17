import { describe, expect, it } from 'vitest'
import { purgeDeletedUsers } from './user-deletion-purger.js'

function makeClient(result: {
  data: Array<{ id: string }> | null
  error: { message: string } | null
}) {
  const calls: Array<[string, unknown]> = []
  const client = {
    from: (table: string) => {
      calls.push(['from', table])
      return {
        delete: () => {
          calls.push(['delete', null])
          return {
            eq: (column: string, value: unknown) => {
              calls.push(['eq', [column, value]])
              return {
                lte: (dateColumn: string, cutoff: unknown) => {
                  calls.push(['lte', [dateColumn, cutoff]])
                  return {
                    select: async (selection: string) => {
                      calls.push(['select', selection])
                      return result
                    },
                  }
                },
              }
            },
          }
        },
      }
    },
  }
  return { client, calls }
}

describe('purgeDeletedUsers', () => {
  it('remove somente contas deleted fora da janela de entrega', async () => {
    const { client, calls } = makeClient({ data: [{ id: 'user-1' }], error: null })

    await expect(
      purgeDeletedUsers(client as never, new Date('2026-07-12T12:00:00.000Z')),
    ).resolves.toEqual({ purged: 1 })
    expect(calls).toContainEqual(['eq', ['status', 'deleted']])
    expect(calls).toContainEqual(['lte', ['updated_at', '2026-07-12T11:00:00.000Z']])
  })

  it('propaga erro de banco para o Inngest tentar novamente', async () => {
    const { client } = makeClient({ data: null, error: { message: 'purge unavailable' } })

    await expect(purgeDeletedUsers(client as never)).rejects.toThrow('purge unavailable')
  })
})
