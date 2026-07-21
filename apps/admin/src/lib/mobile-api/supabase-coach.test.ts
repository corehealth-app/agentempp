import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { createSupabaseCoachDependencies } from './supabase-coach'

const userId = '00000000-0000-0000-0000-000000000911'

function queryWith(result: unknown) {
  const query = {
    select: vi.fn(),
    eq: vi.fn(),
    order: vi.fn(),
    maybeSingle: vi.fn().mockResolvedValue(result),
    // biome-ignore lint/suspicious/noThenProperty: Supabase query builders are intentionally PromiseLike.
    then: (resolve: (value: unknown) => unknown) => Promise.resolve(result).then(resolve),
  }
  query.select.mockReturnValue(query)
  query.eq.mockReturnValue(query)
  query.order.mockReturnValue(query)
  return query
}

describe('Supabase coach adapter', () => {
  it('builds a localized balanced state without exposing catalog tables to a patient client', async () => {
    const preferenceQuery = queryWith({ data: null, error: null })
    const personalitiesQuery = queryWith({
      data: [
        {
          code: 'focus',
          name_pt_br: 'Focus',
          description_pt_br: 'Objetivo e direto.',
          name_en_us: 'Focus',
          description_en_us: 'Direct and objective.',
        },
        {
          code: 'impulse',
          name_pt_br: 'Impulse',
          description_pt_br: 'Energético e positivo.',
          name_en_us: 'Impulse',
          description_en_us: 'Energetic and positive.',
        },
        {
          code: 'zen',
          name_pt_br: 'Zen',
          description_pt_br: 'Calmo e claro.',
          name_en_us: 'Zen',
          description_en_us: 'Calm and clear.',
        },
      ],
      error: null,
    })
    const mascotQuery = queryWith({ data: null, error: null })
    const from = vi.fn((table: string) => {
      if (table === 'user_coach_preferences') return preferenceQuery
      if (table === 'coach_personalities') return personalitiesQuery
      if (table === 'user_mascot_state') return mascotQuery
      throw new Error(`Unexpected table: ${table}`)
    })

    const state = await createSupabaseCoachDependencies({
      from,
    } as unknown as ServiceClient).repository.getPersonaState(userId, 'pt-BR')

    expect(state).toEqual({
      selected: null,
      effective: 'balanced',
      options: [
        { code: 'focus', name: 'Focus', description: 'Objetivo e direto.' },
        { code: 'impulse', name: 'Impulse', description: 'Energético e positivo.' },
        { code: 'zen', name: 'Zen', description: 'Calmo e claro.' },
      ],
      mascot: { state: 'inactive', changed_at: null },
      contract_version: 'bodyflow.coach-persona.v1',
    })
    expect(from).toHaveBeenCalledWith('coach_personalities')
  })

  it('persists persona selection through the service-only RPC', async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: { selected_personality: 'zen', effective_personality: 'zen' },
      error: null,
    })
    const deps = createSupabaseCoachDependencies({ rpc } as unknown as ServiceClient)

    await expect(deps.repository.setPersona(userId, 'zen')).resolves.toBeUndefined()
    expect(rpc).toHaveBeenCalledWith('set_user_coach_personality', {
      p_user_id: userId,
      p_personality: 'zen',
    })
  })

  it('parses selected claims and returns null for suppression', async () => {
    const selected = {
      usage_id: '00000000-0000-0000-0000-000000000912',
      pack_id: '00000000-0000-0000-0000-000000000913',
      template_version_id: '00000000-0000-0000-0000-000000000914',
      requested_personality: 'focus',
      effective_personality: 'balanced',
      outcome: 'selected',
      reason: 'balanced_fallback',
      title: null,
      subject: null,
      body: 'Registro atualizado.',
      allowed_variables: ['name'],
      required_variables: [],
    }
    const rpc = vi
      .fn()
      .mockResolvedValueOnce({ data: selected, error: null })
      .mockResolvedValueOnce({
        data: { outcome: 'suppressed', reason: 'daily_limit' },
        error: null,
      })
    const repository = createSupabaseCoachDependencies({
      rpc,
    } as unknown as ServiceClient).repository

    const input = {
      userId,
      context: 'progress' as const,
      channel: 'in_app' as const,
      locale: 'pt-BR' as const,
      eventKey: 'progress-event-911',
      availableVariables: ['name'],
      now: '2026-07-20T13:00:00.000Z',
    }

    await expect(repository.claimMessage(input)).resolves.toMatchObject({
      usageId: selected.usage_id,
      reason: 'balanced_fallback',
      body: 'Registro atualizado.',
    })
    await expect(
      repository.claimMessage({ ...input, eventKey: 'progress-event-912' }),
    ).resolves.toBeNull()
    expect(rpc).toHaveBeenNthCalledWith(1, 'claim_coach_message', {
      p_user_id: userId,
      p_context: 'progress',
      p_channel: 'in_app',
      p_locale: 'pt-BR',
      p_event_key: 'progress-event-911',
      p_available_variables: ['name'],
      p_now: '2026-07-20T13:00:00.000Z',
    })
  })

  it('records render failure telemetry without copy or patient data', async () => {
    const insert = vi.fn().mockResolvedValue({ error: null })
    const from = vi.fn().mockReturnValue({ insert })
    const usageId = '00000000-0000-0000-0000-000000000915'
    const repository = createSupabaseCoachDependencies({
      from,
    } as unknown as ServiceClient).repository

    await repository.markUsageFailed(usageId, 'render_failed')

    expect(from).toHaveBeenCalledWith('product_events')
    expect(insert).toHaveBeenCalledWith({
      user_id: null,
      event: 'coach.render_failed',
      properties: { usage_id: usageId, reason: 'render_failed' },
    })
    expect(JSON.stringify(insert.mock.calls)).not.toContain('body')
  })
})
