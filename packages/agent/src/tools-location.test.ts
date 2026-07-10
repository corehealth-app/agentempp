import { describe, expect, it } from 'vitest'
import { confirmaPaisResidencia } from './tools.js'

function makeContext() {
  const updates: Array<Record<string, unknown>> = []
  const events: Array<Record<string, unknown>> = []
  const existing = {
    country: null,
    country_confirmed: false,
    timezone: 'America/Sao_Paulo',
    metadata: { buttons_enabled: true },
    locale: 'pt-BR',
  }
  const supabase = {
    from: (table: string) => {
      if (table === 'users') {
        return {
          select: () => ({
            eq: () => ({
              maybeSingle: () => Promise.resolve({ data: existing, error: null }),
            }),
          }),
          update: (value: Record<string, unknown>) => ({
            eq: () => {
              updates.push(value)
              return Promise.resolve({ error: null })
            },
          }),
        }
      }
      return {
        insert: (value: Record<string, unknown>) => {
          events.push(value)
          return Promise.resolve({ error: null })
        },
      }
    },
  }
  return {
    updates,
    events,
    ctx: { supabase, userId: 'user-1', userWpp: 'masked' } as never,
  }
}

describe('confirma_pais_residencia', () => {
  it('preserva metadata existente e confirma Orlando/New York', async () => {
    const { ctx, updates } = makeContext()
    const result = await confirmaPaisResidencia.execute(
      {
        country: 'US',
        language: 'pt-BR',
        unit_system: 'metric',
        city: 'Orlando',
        region: 'FL',
        timezone: 'America/New_York',
      },
      ctx,
    )

    expect(result).toMatchObject({ success: true, timezone: 'America/New_York' })
    expect(updates[0]?.metadata).toMatchObject({
      buttons_enabled: true,
      unit_system: 'metric',
      residence_city: 'Orlando',
      residence_region: 'FL',
      timezone_confirmed: true,
    })
  })

  it('nao grava nova residencia US sem cidade/estado', async () => {
    const { ctx, updates } = makeContext()
    const result = await confirmaPaisResidencia.execute(
      { country: 'US', language: 'pt-BR', unit_system: 'metric' },
      ctx,
    )
    expect(result).toMatchObject({ success: false, error: 'location_required' })
    expect(updates).toEqual([])
  })
})
