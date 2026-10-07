import { protocolWelcomeMessage } from '@mpp/core'
import { describe, expect, it } from 'vitest'
import { protocolReadModel } from './protocol-service'

// The words of each entry message are pinned, in both languages, in
// packages/agent/src/__golden__/audit-10-07-protocol-messages.test.ts.

const TARGETS = { calories_kcal: 1564, protein_g: 121.5 }

describe('protocol read model', () => {
  it.each([
    'recomposicao',
    'ganho_massa',
    'manutencao',
  ] as const)('reports the protocol of the profile, the targets it was handed and its entry message: %s', (protocol) => {
    expect(
      protocolReadModel({
        profile: { current_protocol: protocol, weight_kg: 81 },
        todayTargets: TARGETS,
        name: 'Synthetic User',
        locale: 'pt-BR',
      }),
    ).toEqual({
      current_protocol: protocol,
      targets: { calories: 1564, protein_g: 121.5 },
      welcome: {
        protocol,
        paragraphs: protocolWelcomeMessage(protocol, 'Synthetic User', 'pt-BR'),
      },
    })
  })

  it('writes the entry message in the language it is asked for', () => {
    const result = protocolReadModel({
      profile: { current_protocol: 'ganho_massa' },
      todayTargets: TARGETS,
      name: 'Synthetic User',
      locale: 'en-US',
    })

    expect(result.welcome?.paragraphs).toEqual(
      protocolWelcomeMessage('ganho_massa', 'Synthetic User', 'en-US'),
    )
    expect(result.welcome?.paragraphs[0]).toMatch(
      /^Synthetic User, you are now entering the muscle gain phase\./,
    )
  })

  it('an account with no registered name gets the message without the vocative', () => {
    const result = protocolReadModel({
      profile: { current_protocol: 'manutencao' },
      todayTargets: TARGETS,
      name: null,
      locale: 'pt-BR',
    })

    expect(result.welcome?.paragraphs[0]).toMatch(/^Agora você entra na fase de manutenção /)
  })

  it.each([
    ['no profile row', null],
    ['a profile without a protocol', { current_protocol: null, onboarding_completed: false }],
    ['a profile row without the column', {}],
    ['a value that is not one of the three protocols', { current_protocol: 'bulking' }],
    ['a value that is not text', { current_protocol: 1 }],
  ])('%s: no protocol and no entry message; the targets are still the ones handed over', (_case, profile) => {
    expect(
      protocolReadModel({
        profile,
        todayTargets: TARGETS,
        name: 'Synthetic User',
        locale: 'pt-BR',
      }),
    ).toEqual({
      current_protocol: null,
      targets: { calories: 1564, protein_g: 121.5 },
      welcome: null,
    })
  })

  it('passes absent targets on as null: nothing is calculated here', () => {
    expect(
      protocolReadModel({
        profile: { current_protocol: 'recomposicao' },
        todayTargets: { calories_kcal: null, protein_g: null },
        name: 'Synthetic User',
        locale: 'pt-BR',
      }).targets,
    ).toEqual({ calories: null, protein_g: null })
  })

  it('says nothing about changing the objective', () => {
    const result = protocolReadModel({
      profile: { current_protocol: 'manutencao' },
      todayTargets: TARGETS,
      name: 'Synthetic User',
      locale: 'pt-BR',
    })

    expect(Object.keys(result).sort()).toEqual(['current_protocol', 'targets', 'welcome'])
  })
})
