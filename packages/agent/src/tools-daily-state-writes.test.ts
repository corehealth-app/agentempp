import { describe, expect, it } from 'vitest'
import { marcaRefeicaoPulada } from './tools.js'

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
