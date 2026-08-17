import { describe, expect, it } from 'vitest'
import { loadUserProcessingState } from './user-processing-state.js'

function makeClient(result: {
  data: { status: 'active' | 'blocked' | 'deleted'; metadata: Record<string, unknown> } | null
  error: { message: string } | null
}) {
  return {
    from: () => ({
      select: () => ({
        eq: () => ({ maybeSingle: async () => result }),
      }),
    }),
  }
}

describe('loadUserProcessingState', () => {
  it('bloqueia conta marcada para exclusão', async () => {
    const client = makeClient({ data: { status: 'deleted', metadata: {} }, error: null })

    await expect(loadUserProcessingState(client as never, 'user-1')).resolves.toEqual({
      kind: 'deleted',
    })
  })

  it('bloqueia conta suspensa', async () => {
    const client = makeClient({ data: { status: 'blocked', metadata: {} }, error: null })

    await expect(loadUserProcessingState(client as never, 'user-1')).resolves.toEqual({
      kind: 'blocked',
    })
  })

  it('respeita pausa ainda vigente', async () => {
    const client = makeClient({
      data: { status: 'active', metadata: { paused_until: '2026-07-12T13:00:00.000Z' } },
      error: null,
    })

    await expect(
      loadUserProcessingState(client as never, 'user-1', new Date('2026-07-12T12:00:00.000Z')),
    ).resolves.toEqual({ kind: 'paused', until: '2026-07-12T13:00:00.000Z' })
  })

  it('libera conta ativa com pausa expirada', async () => {
    const client = makeClient({
      data: { status: 'active', metadata: { paused_until: '2026-07-12T11:00:00.000Z' } },
      error: null,
    })

    await expect(
      loadUserProcessingState(client as never, 'user-1', new Date('2026-07-12T12:00:00.000Z')),
    ).resolves.toEqual({ kind: 'active' })
  })

  it('propaga erro da consulta em vez de liberar processamento', async () => {
    const client = makeClient({ data: null, error: { message: 'user state unavailable' } })

    await expect(loadUserProcessingState(client as never, 'user-1')).rejects.toThrow(
      'user state unavailable',
    )
  })
})
