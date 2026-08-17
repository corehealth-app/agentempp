import { describe, expect, it } from 'vitest'
import { applyUserBlocoCorrection, recomputeUserBloco } from './bloco-recompute.js'

type Options = {
  profileError?: string
  snapshotsError?: string
  logsError?: string
}

function makeClient(options: Options = {}) {
  return {
    from(table: string) {
      if (table === 'user_profiles') {
        return {
          select: () => ({
            eq: () => ({
              maybeSingle: async () => ({
                data: { current_protocol: 'recomposicao', deficit_level: 500 },
                error: options.profileError ? { message: options.profileError } : null,
              }),
            }),
          }),
        }
      }
      if (table === 'daily_snapshots') {
        const terminal = async () => ({
          data: [
            {
              id: 'snapshot-1',
              calories_consumed: 1500,
              calories_target: 1900,
              exercise_calories: 0,
              daily_balance: -400,
              day_status: 'complete',
              training_done: false,
            },
          ],
          error: options.snapshotsError ? { message: options.snapshotsError } : null,
        })
        const chain = {
          eq: () => chain,
          order: terminal,
        }
        return { select: () => chain }
      }
      if (table === 'meal_logs') {
        return {
          select: () => ({
            in: async () => ({
              data: [{ snapshot_id: 'snapshot-1' }],
              error: options.logsError ? { message: options.logsError } : null,
            }),
          }),
        }
      }
      throw new Error(`unexpected table: ${table}`)
    },
  }
}

describe('recomputeUserBloco', () => {
  it.each([
    ['perfil', { profileError: 'profile unavailable' }, 'profile unavailable'],
    ['snapshots', { snapshotsError: 'snapshots unavailable' }, 'snapshots unavailable'],
    ['meal logs', { logsError: 'logs unavailable' }, 'logs unavailable'],
  ])('falha fechado quando a leitura de %s falha', async (_label, options, message) => {
    await expect(recomputeUserBloco(makeClient(options) as never, 'user-1')).rejects.toThrow(
      message,
    )
  })

  it('recalcula somente quando todas as fontes foram lidas', async () => {
    await expect(recomputeUserBloco(makeClient() as never, 'user-1')).resolves.toMatchObject({
      userId: 'user-1',
      daysClosed: 1,
    })
  })
})

function makeUpdateClient(options: { error?: string; updated?: boolean } = {}) {
  const payloads: Array<Record<string, unknown>> = []
  return {
    payloads,
    client: {
      from(table: string) {
        expect(table).toBe('user_progress')
        return {
          update(payload: Record<string, unknown>) {
            payloads.push(payload)
            return {
              eq: () => ({
                select: () => ({
                  maybeSingle: async () => ({
                    data: options.updated === false ? null : { user_id: 'user-1' },
                    error: options.error ? { message: options.error } : null,
                  }),
                }),
              }),
            }
          },
        }
      },
    },
  }
}

describe('applyUserBlocoCorrection', () => {
  it('confirma a linha corrigida antes de reportar sucesso', async () => {
    const db = makeUpdateClient()

    await applyUserBlocoCorrection(db.client as never, 'user-1', 1234, 2)

    expect(db.payloads[0]).toMatchObject({ deficit_block: 1234, blocks_completed: 2 })
  })

  it('propaga erro de update', async () => {
    const db = makeUpdateClient({ error: 'update unavailable' })
    await expect(applyUserBlocoCorrection(db.client as never, 'user-1', 1234, 2)).rejects.toThrow(
      'update unavailable',
    )
  })

  it('falha quando nenhuma linha foi alterada', async () => {
    const db = makeUpdateClient({ updated: false })
    await expect(applyUserBlocoCorrection(db.client as never, 'user-1', 1234, 2)).rejects.toThrow(
      'bloco progress row not found',
    )
  })
})
