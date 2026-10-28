import { describe, expect, it } from 'vitest'
import { type FlowClinicalPolicy, flowClinicalPolicyNotice } from './flow-current-clinical.js'
import { projectFlowMetricAnswer, projectStoredFlowMetricAnswer } from './flow-public-metrics.js'

const policy: FlowClinicalPolicy = {
  version: 1,
  observed_at: '2026-10-27T12:00:00Z',
  assessment: 'complete',
  recording_allowed: true,
  pause_weight_loss_guidance: true,
  professional_assessment_recommended: true,
  phase_selection_pending: false,
  target_source: 'unavailable',
  hide: { objective: true, calories: true, protein: true, balance: true, block: true },
}
const objective = { currentProtocol: null, clinicalPolicy: policy }
const prescriptions = [
  ['pt-BR', 'Para emagrecer, faça um déficit de 500 kcal por dia.'],
  ['pt-BR', 'Você deve consumir 900 kcal por dia.'],
  ['pt-BR', 'Adote um déficit energético de 500 kcal.'],
  ['pt-BR', 'Para perder peso, limite sua ingestão a 1200 kcal diárias.'],
  ['pt-BR', 'Procure ficar abaixo da meta para secar.'],
  ['pt-BR', 'Diminua a comida e acelere a perda de gordura.'],
  ['pt-BR', 'Jejue para perder gordura.'],
  ['en', 'To slim down, aim for a daily deficit of 500 kcal.'],
  ['en', 'You should eat 900 calories a day.'],
  ['en', 'Consume no more than 1200 kcal daily to reduce body fat.'],
  ['en', 'Aim for a calorie shortfall of 400 kcal.'],
  ['en', 'Eat less than your target to get leaner.'],
  ['en', 'Skipping meals will help you burn fat.'],
] as const
describe('current clinical copies of stored Flow replies', () => {
  it.each(
    prescriptions,
  )('withholds equivalent prescriptions in live and stored replies (%s): %s', (locale, text) => {
    const held = {
      currentProtocol: 'recomposicao' as const,
      clinicalPolicy: {
        ...policy,
        hide: { objective: false, calories: false, protein: false, balance: false, block: false },
      },
    }
    for (const guarded of [objective, held]) {
      const current = projectFlowMetricAnswer(text, null, locale, false, undefined, guarded)
      const historical = projectStoredFlowMetricAnswer(text, locale, false, guarded)
      for (const presented of [current, historical]) {
        expect(presented).not.toContain(text)
        expect(presented).toMatch(/profissional|professional/)
      }
    }
  })
  it.each([
    ['Meta calórica: 1800 kcal. Consumido: 1000 kcal.', 'Consumido: 1000 kcal.', '1800'],
    ['Sua meta é 1800 kcal; proteína consumida: 50 g.', 'proteína consumida: 50 g.', '1800'],
    ['Meta de proteína: 140 g. Registrou 50 g de proteína.', 'Registrou 50 g de proteína.', '140'],
    [
      'Balanço do dia: déficit de 849 kcal. Exercício registrado: 504 kcal.',
      'Exercício registrado: 504 kcal.',
      '849',
    ],
    ['Protocolo atual: recomposição. XP: 150.', 'XP: 150.', 'recomposição'],
    [
      'Reduza as calorias para emagrecer. Seu registro foi preservado.',
      'Seu registro foi preservado.',
      'Reduza',
    ],
    ['Your calorie target: 1800 kcal. Consumed: 1000 kcal.', 'Consumed: 1000 kcal.', '1800'],
    [
      'Maintain a calorie deficit to lose weight. Recorded exercise: 504 kcal.',
      'Recorded exercise: 504 kcal.',
      'Maintain',
    ],
  ])('withholds suspended guidance while retaining observed facts: %s', (text, kept, removed) => {
    const result = projectStoredFlowMetricAnswer(text, 'pt-BR', false, objective)
    expect(result).toContain(kept)
    expect(result).not.toContain(removed)
    expect(result).toContain(
      flowClinicalPolicyNotice(policy, text.startsWith('Your ') ? 'en' : 'pt-BR'),
    )
  })
  it('keeps ordinary food calories, consumed protein, allergies and XP', () => {
    const text =
      'O leite forneceu 132 kcal. Consumiu 30 g de proteína. Alergia a amendoim. XP: 150.'
    expect(projectStoredFlowMetricAnswer(text, 'pt-BR', false, objective)).toBe(text)
  })
  it('keeps preserved targets and factual day balance under a hold without no-plan hides', () => {
    const held = {
      ...policy,
      hide: { objective: false, calories: false, protein: false, balance: false, block: false },
    }
    const text = 'Meta calórica: 1800 kcal. Balanço do dia: déficit de 300 kcal.'
    expect(
      projectStoredFlowMetricAnswer(text, 'pt-BR', false, {
        currentProtocol: 'recomposicao',
        clinicalPolicy: held,
      }),
    ).toBe(text)
  })
  it.each([
    ['pt-BR', 'O leite forneceu 132 kcal. Consumiu 30 g de proteína. Alergia a amendoim. XP: 150.'],
    ['en', 'Milk provided 132 kcal. You consumed 30 g of protein. Peanut allergy. XP: 150.'],
    ['en', 'Your calorie target is 1800 kcal. Daily balance: deficit of 300 kcal.'],
  ])('preserves factual copies in both live and stored held replies: %s', (locale, text) => {
    const held = {
      currentProtocol: 'recomposicao' as const,
      clinicalPolicy: {
        ...policy,
        hide: { objective: false, calories: false, protein: false, balance: false, block: false },
      },
    }
    expect(projectFlowMetricAnswer(text, null, locale, false, undefined, held)).toBe(text)
    expect(projectStoredFlowMetricAnswer(text, locale, false, held)).toBe(text)
  })
  it.each(prescriptions)('keeps allowed healthy replies unchanged (%s): %s', (locale, text) => {
    const healthy = {
      currentProtocol: 'recomposicao' as const,
      clinicalPolicy: {
        ...policy,
        pause_weight_loss_guidance: false,
        professional_assessment_recommended: false,
        hide: { objective: false, calories: false, protein: false, balance: false, block: false },
      },
    }
    expect(projectFlowMetricAnswer(text, null, locale, false, undefined, healthy)).toBe(text)
    expect(projectStoredFlowMetricAnswer(text, locale, false, healthy)).toBe(text)
  })
  it('does not promote an invalid policy to the legacy projection', () => {
    expect(() =>
      projectStoredFlowMetricAnswer('Meta calórica: 1800 kcal.', 'pt-BR', false, {
        currentProtocol: null,
        clinicalPolicy: { ...policy, version: 2 } as unknown as FlowClinicalPolicy,
      }),
    ).toThrow()
  })
})

it('does not report healthy targets as unavailable when removing an unrelated private formula', () => {
  const healthy = {
    ...policy,
    pause_weight_loss_guidance: false,
    professional_assessment_recommended: false,
    hide: { objective: false, calories: false, protein: false, balance: false, block: false },
  }
  const value = projectStoredFlowMetricAnswer(
    'BMR: 1800 kcal. Consumido: 1000 kcal.',
    'pt-BR',
    false,
    { currentProtocol: 'recomposicao', clinicalPolicy: healthy },
  )
  expect(value).toContain('1000')
  expect(value).not.toContain('1800')
  expect(value).not.toContain('indisponíveis')
})
