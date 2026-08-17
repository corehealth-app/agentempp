import { describe, expect, it } from 'vitest'
import { marcaRefeicaoPulada, registraMetricaDiaria } from './tools.js'

function makeSkipContext(insertError?: string) {
  const events: Array<Record<string, unknown>> = []
  return {
    events,
    context: {
      userId: 'user-1',
      userWpp: '15555550100',
      userTimezone: 'America/New_York',
      referenceTimestamp: new Date('2026-07-11T03:30:00.000Z'),
      providerMessageId: 'provider-1',
      supabase: {
        from(table: string) {
          if (table !== 'product_events') throw new Error(`unexpected table: ${table}`)
          return {
            insert: async (event: Record<string, unknown>) => {
              events.push(event)
              return { error: insertError ? { message: insertError } : null }
            },
          }
        },
      },
    },
  }
}

describe('marca_refeicao_pulada — persistência', () => {
  it('grava a data local da mensagem original', async () => {
    const { context, events } = makeSkipContext()

    const result = await marcaRefeicaoPulada.execute({ meal_type: 'ceia' }, context as never)

    expect(result).toMatchObject({ success: true, date: '2026-07-10' })
    expect(events[0]).toMatchObject({
      event: 'meal.user_skipped',
      properties: {
        meal_type: 'ceia',
        local_date: '2026-07-10',
        source_timestamp: '2026-07-11T03:30:00.000Z',
      },
    })
  })

  it('não retorna sucesso quando o Supabase rejeita o evento', async () => {
    const { context } = makeSkipContext('write failed')

    await expect(
      marcaRefeicaoPulada.execute({ meal_type: 'jantar' }, context as never),
    ).rejects.toThrow('write failed')
  })
})

function makeMetricContext(options: { upsertError?: string; eventError?: string } = {}) {
  const upserts: Array<Record<string, unknown>> = []
  const events: Array<Record<string, unknown>> = []
  return {
    upserts,
    events,
    context: {
      userId: 'user-1',
      userWpp: '15555550100',
      userTimezone: 'America/New_York',
      referenceTimestamp: new Date('2026-07-11T03:30:00.000Z'),
      supabase: {
        from(table: string) {
          if (table === 'daily_snapshots') {
            return {
              upsert: async (value: Record<string, unknown>) => {
                upserts.push(value)
                return { error: options.upsertError ? { message: options.upsertError } : null }
              },
            }
          }
          if (table === 'product_events') {
            return {
              insert: async (event: Record<string, unknown>) => {
                events.push(event)
                return { error: options.eventError ? { message: options.eventError } : null }
              },
            }
          }
          throw new Error(`unexpected table: ${table}`)
        },
      },
    },
  }
}

describe('registra_metrica_diaria — consistência', () => {
  it('usa a data local da mensagem e persiste somente após confirmar o upsert', async () => {
    const { context, upserts } = makeMetricContext()

    const result = await registraMetricaDiaria.execute(
      { water_ml: 2000, sleep_hours: 7.5, steps: 8000 },
      context as never,
    )

    expect(result).toMatchObject({ success: true, date: '2026-07-10' })
    expect(upserts[0]).toMatchObject({
      date: '2026-07-10',
      water_consumed_ml: 2000,
      sleep_hours: 7.5,
      steps: 8000,
    })
  })

  it('não retorna sucesso quando o snapshot rejeita a escrita', async () => {
    const { context } = makeMetricContext({ upsertError: 'snapshot write failed' })

    await expect(
      registraMetricaDiaria.execute({ water_ml: 1500 }, context as never),
    ).rejects.toThrow('snapshot write failed')
  })

  it('rejeita métricas negativas ou fisiologicamente inválidas no schema', () => {
    expect(registraMetricaDiaria.parameters.safeParse({ water_ml: -1 }).success).toBe(false)
    expect(registraMetricaDiaria.parameters.safeParse({ sleep_hours: 25 }).success).toBe(false)
    expect(registraMetricaDiaria.parameters.safeParse({ steps: -100 }).success).toBe(false)
  })
})
