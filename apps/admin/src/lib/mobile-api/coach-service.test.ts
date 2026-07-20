import { describe, expect, it, vi } from 'vitest'
import {
  type ClaimedCoachMessageRecord,
  type CoachDependencies,
  type CoachPersonaState,
  claimAndRenderCoachMessage,
  getCoachPersonaState,
  setCoachPersona,
} from './coach-service'

const userId = '00000000-0000-0000-0000-000000000901'

const state: CoachPersonaState = {
  selected: null,
  effective: 'balanced',
  options: [
    { code: 'focus', name: 'Focus', description: 'Objetivo e direto.' },
    { code: 'impulse', name: 'Impulse', description: 'Energético e positivo.' },
    { code: 'zen', name: 'Zen', description: 'Calmo e claro.' },
  ],
  mascot: { state: 'inactive', changed_at: null },
  contract_version: 'bodyflow.coach-persona.v1',
}

function createDependencies(
  overrides: Partial<CoachDependencies['repository']> = {},
): CoachDependencies {
  return {
    repository: {
      getPersonaState: vi.fn(async () => state),
      setPersona: vi.fn(async () => undefined),
      claimMessage: vi.fn(async () => null),
      markUsageFailed: vi.fn(async () => undefined),
      ...overrides,
    },
  }
}

describe('BodyFlow coach mobile service', () => {
  it('returns the localized persona state from the trusted repository', async () => {
    const deps = createDependencies()

    await expect(getCoachPersonaState(deps, userId, 'pt-BR')).resolves.toEqual(state)
    expect(deps.repository.getPersonaState).toHaveBeenCalledWith(userId, 'pt-BR')
  })

  it('persists only selectable personas and returns the refreshed state', async () => {
    const selectedState: CoachPersonaState = { ...state, selected: 'focus', effective: 'focus' }
    const deps = createDependencies({ getPersonaState: vi.fn(async () => selectedState) })

    await expect(setCoachPersona(deps, userId, 'focus', 'pt-BR')).resolves.toEqual(selectedState)
    expect(deps.repository.setPersona).toHaveBeenCalledWith(userId, 'focus')
    expect(deps.repository.getPersonaState).toHaveBeenCalledWith(userId, 'pt-BR')
  })

  it('claims and renders a safe same-locale catalog message', async () => {
    const deps = createDependencies({
      claimMessage: vi.fn(
        async () =>
          ({
            usageId: '00000000-0000-0000-0000-000000000902',
            templateVersionId: '00000000-0000-0000-0000-000000000903',
            packId: '00000000-0000-0000-0000-000000000904',
            requestedPersonality: 'focus',
            effectivePersonality: 'focus',
            reason: 'exact',
            title: 'Hora de hidratar',
            subject: null,
            body: 'Agora: faltam {{water_remaining_ml}} ml de água.',
            allowedVariables: ['name', 'water_remaining_ml'],
            requiredVariables: ['water_remaining_ml'],
          }) satisfies ClaimedCoachMessageRecord,
      ),
    })

    const result = await claimAndRenderCoachMessage(deps, {
      userId,
      context: 'hydration',
      channel: 'push',
      locale: 'pt-BR',
      eventKey: 'hydration-event-901',
      variables: { water_remaining_ml: 750 },
      now: '2026-07-20T13:00:00.000Z',
    })

    expect(deps.repository.claimMessage).toHaveBeenCalledWith({
      userId,
      context: 'hydration',
      channel: 'push',
      locale: 'pt-BR',
      eventKey: 'hydration-event-901',
      availableVariables: ['water_remaining_ml'],
      now: '2026-07-20T13:00:00.000Z',
    })
    expect(result).toMatchObject({
      reason: 'exact',
      rendered: {
        title: 'Hora de hidratar',
        subject: null,
        body: 'Agora: faltam 750 ml de água.',
      },
    })
  })

  it('returns null when frequency policy suppresses the claim', async () => {
    const deps = createDependencies()

    await expect(
      claimAndRenderCoachMessage(deps, {
        userId,
        context: 'progress',
        channel: 'in_app',
        locale: 'en-US',
        eventKey: 'progress-event-901',
        variables: {},
      }),
    ).resolves.toBeNull()
  })

  it('fails closed and records only the usage id when rendering is invalid', async () => {
    const usageId = '00000000-0000-0000-0000-000000000905'
    const deps = createDependencies({
      claimMessage: vi.fn(
        async () =>
          ({
            usageId,
            templateVersionId: '00000000-0000-0000-0000-000000000906',
            packId: '00000000-0000-0000-0000-000000000907',
            requestedPersonality: 'zen',
            effectivePersonality: 'balanced',
            reason: 'balanced_fallback',
            title: null,
            subject: null,
            body: 'Valor não permitido: {{unknown_value}}.',
            allowedVariables: [],
            requiredVariables: [],
          }) satisfies ClaimedCoachMessageRecord,
      ),
    })

    await expect(
      claimAndRenderCoachMessage(deps, {
        userId,
        context: 'progress',
        channel: 'in_app',
        locale: 'pt-BR',
        eventKey: 'progress-event-invalid',
        variables: {},
      }),
    ).resolves.toBeNull()
    expect(deps.repository.markUsageFailed).toHaveBeenCalledWith(usageId, 'render_failed')
  })
})
