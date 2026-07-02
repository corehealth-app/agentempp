import { describe, expect, it } from 'vitest'
import {
  aggregateBodyBfEstimate,
  type BodyPhotoSignal,
  bodyPhotoSignalFromEventProperties,
  composeReevalBodyPhotoWaitMessage,
  deriveBodyPhotoState,
  formatBodyPhotoDigest,
  shouldWaitForBodyPhotosBeforeReeval,
} from './reevaluation-body-photos.js'

const signal = (overrides: Partial<BodyPhotoSignal>): BodyPhotoSignal => ({
  view: 'unknown',
  bfPercentEstimate: null,
  confidence: null,
  occurredAt: null,
  providerMessageId: null,
  photoCount: null,
  compositionNotes: null,
  postureNotes: null,
  ...overrides,
})

describe('reevaluation body photos', () => {
  it('detecta angulos recebidos e pede somente os faltantes', () => {
    const state = deriveBodyPhotoState([signal({ view: 'front' }), signal({ view: 'side' })])

    expect(state.receivedViews).toEqual(['front', 'side'])
    expect(state.missingViews).toEqual(['back'])
    expect(state.isComplete).toBe(false)
    expect(shouldWaitForBodyPhotosBeforeReeval(state, true)).toBe(true)
    expect(composeReevalBodyPhotoWaitMessage(state)).toContain('ainda falta costas')
    expect(composeReevalBodyPhotoWaitMessage(state)).not.toContain('frente, lado')
  })

  it('nao trava a reavaliacao quando o paciente autoriza seguir sem fotos', () => {
    expect(deriveBodyPhotoState([], ['Pode seguir sem fotos hoje']).optedOut).toBe(true)
    const state = deriveBodyPhotoState([], ['Pode seguir com essa so hoje'])

    expect(state.optedOut).toBe(true)
    expect(state.isComplete).toBe(false)
    expect(shouldWaitForBodyPhotosBeforeReeval(state, true)).toBe(false)
  })

  it('considera frente, lado e costas como completo', () => {
    const state = deriveBodyPhotoState([
      signal({ view: 'front' }),
      signal({ view: 'side' }),
      signal({ view: 'back' }),
    ])

    expect(state.missingViews).toEqual([])
    expect(state.isComplete).toBe(true)
    expect(shouldWaitForBodyPhotosBeforeReeval(state, true)).toBe(false)
  })

  it('gera digest de foto corporal para entrar no historico natural', () => {
    const digest = formatBodyPhotoDigest([
      signal({
        view: 'back',
        bfPercentEstimate: 21.24,
        confidence: 0.82,
        compositionNotes: 'boa definicao de costas',
      }),
    ])

    expect(digest).toContain('[vision-body]')
    expect(digest).toContain('costas')
    expect(digest).toContain('BF ~21.2%')
  })

  it('agrega BF usando a ultima foto de cada angulo, nao a ultima foto isolada', () => {
    const agg = aggregateBodyBfEstimate([
      signal({
        view: 'front',
        bfPercentEstimate: 20,
        confidence: 0.8,
        occurredAt: '2026-07-02T12:00:00.000Z',
      }),
      signal({
        view: 'side',
        bfPercentEstimate: 24,
        confidence: 0.6,
        occurredAt: '2026-07-02T12:01:00.000Z',
      }),
      signal({
        view: 'back',
        bfPercentEstimate: 22,
        confidence: 0.7,
        occurredAt: '2026-07-02T12:02:00.000Z',
      }),
      signal({
        view: 'front',
        bfPercentEstimate: 21,
        confidence: 0.9,
        occurredAt: '2026-07-02T12:03:00.000Z',
      }),
    ])

    expect(agg).toEqual({
      estimate: 22.1,
      confidence: 0.73,
      views: ['front', 'side', 'back'],
    })
  })

  it('normaliza metadados de product_events de body vision', () => {
    expect(
      bodyPhotoSignalFromEventProperties(
        {
          type: 'body',
          view: 'frente',
          bf_percent_estimate: '19.5',
          confidence: 0.77,
          provider_message_id: 'wamid-1',
          photo_count: 3,
        },
        '2026-07-02T12:00:00.000Z',
      ),
    ).toMatchObject({
      view: 'front',
      bfPercentEstimate: 19.5,
      confidence: 0.77,
      occurredAt: '2026-07-02T12:00:00.000Z',
      providerMessageId: 'wamid-1',
      photoCount: 3,
    })
  })
})
