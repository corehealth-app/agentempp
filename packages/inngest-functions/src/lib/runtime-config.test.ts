import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  loadVisionConfig,
  parseBooleanRuntimeValue,
  resetRuntimeConfigCaches,
} from './runtime-config.js'

type QueryResult = { data: unknown; error: { message: string } | null }

function thenableQuery(result: () => QueryResult) {
  const query = {
    select: () => query,
    like: () => query,
    eq: () => query,
    // biome-ignore lint/suspicious/noThenProperty: Supabase query builders are intentionally thenable.
    then: <TResult1 = QueryResult, TResult2 = never>(
      onfulfilled?: ((value: QueryResult) => TResult1 | PromiseLike<TResult1>) | null,
      onrejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
    ) => Promise.resolve(result()).then(onfulfilled, onrejected),
  }
  return query
}

afterEach(() => {
  resetRuntimeConfigCaches()
  vi.useRealTimers()
})

describe('parseBooleanRuntimeValue', () => {
  it('aceita boolean, number e strings comuns', () => {
    expect(parseBooleanRuntimeValue(true, false)).toBe(true)
    expect(parseBooleanRuntimeValue(false, true)).toBe(false)
    expect(parseBooleanRuntimeValue(1, false)).toBe(true)
    expect(parseBooleanRuntimeValue(0, true)).toBe(false)
    expect(parseBooleanRuntimeValue('enabled', false)).toBe(true)
    expect(parseBooleanRuntimeValue('off', true)).toBe(false)
  })

  it('preserva fallback para valores ambíguos', () => {
    expect(parseBooleanRuntimeValue('talvez', false)).toBe(false)
    expect(parseBooleanRuntimeValue('talvez', true)).toBe(true)
    expect(parseBooleanRuntimeValue(null, true)).toBe(true)
  })
})

describe('loadVisionConfig', () => {
  it('não interpreta imagens com defaults quando a configuração não pode ser lida', async () => {
    const svc = {
      from: vi.fn(() =>
        thenableQuery(() => ({ data: null, error: { message: 'vision config unavailable' } })),
      ),
    }

    await expect(loadVisionConfig(svc)).rejects.toThrow('vision config unavailable')
    expect(svc.from).toHaveBeenCalledTimes(1)
  })

  it('não ignora falha ao carregar prompts ativos de vision', async () => {
    const svc = {
      from: vi.fn((table: string) =>
        thenableQuery(() =>
          table === 'global_config'
            ? { data: [], error: null }
            : { data: null, error: { message: 'vision rules unavailable' } },
        ),
      ),
    }

    await expect(loadVisionConfig(svc)).rejects.toThrow('vision rules unavailable')
  })

  it('reutiliza o último config válido se a atualização do cache falhar', async () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-07-12T12:00:00.000Z'))
    let databaseAvailable = true
    const svc = {
      from: vi.fn((table: string) =>
        thenableQuery(() => {
          if (!databaseAvailable) {
            return { data: null, error: { message: 'database unavailable' } }
          }
          return table === 'global_config'
            ? { data: [{ key: 'vision.model', value: 'custom/vision-model' }], error: null }
            : {
                data: [{ slug: 'vision-meal', content: 'Regra validada de refeição' }],
                error: null,
              }
        }),
      ),
    }

    await expect(loadVisionConfig(svc)).resolves.toMatchObject({
      model: 'custom/vision-model',
      prompts: { meal: 'Regra validada de refeição' },
    })

    databaseAvailable = false
    vi.advanceTimersByTime(60_001)

    await expect(loadVisionConfig(svc)).resolves.toMatchObject({
      model: 'custom/vision-model',
      prompts: { meal: 'Regra validada de refeição' },
    })
  })
})
