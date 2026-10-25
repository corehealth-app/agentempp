import { describe, expect, it } from 'vitest'
import {
  getKnownReevaluationAnswers,
  getReevaluationFormDescriptor,
  parseReevaluationFormDraft,
} from './reevaluation-form-contracts.js'

const context = {
  phase: 'recomposicao' as const,
  kind: 'REGULAR' as const,
  sex: 'feminino' as const,
  currentActivityLevel: 'moderado' as const,
  holdActive: false,
  activityPurpose: 'normal' as const,
  confirmedMealDays: 0,
}
const base = {
  version: 1,
  phase: 'recomposicao',
  kind: 'REGULAR',
  activityPurpose: 'normal',
  answers: {},
}
const common = ['weightKg', 'strengthSessions', 'adherence', 'hunger', 'energy']

describe('n1/n3 adaptive pure descriptor', () => {
  it('recomposition is exactly five common questions then health, with preference separate', () => {
    const form = getReevaluationFormDescriptor(context)
    expect(form.questions.map((question) => question.key)).toEqual([...common, 'healthCheck'])
    expect(form.questions.map((question) => question.label)).toEqual([
      'Qual é o seu peso hoje?',
      'Quantos treinos de musculação por semana você fez nestes 14 dias?',
      'Nos últimos 14 dias, como foi sua alimentação em relação ao plano?',
      'Como esteve a sua fome, na média?',
      'E a sua energia no dia a dia?',
      'Alguma destas situações vale para você agora? Marque todas que valerem.',
    ])
    expect(form.preferenceQuestion?.label).toBe('Você tem uma meta em mente? (opcional)')
    expect(form.preferenceQuestion?.optional).toBe(true)
    expect(form.supportText).toBe('Você registrou refeições em 0 dos últimos 14 dias.')
    expect(form.decisionPriority).toEqual([
      'safety_exit',
      'phase_or_schedule',
      'activity_level',
      'phase_calories',
    ])
    expect(form.photoRequirement).toEqual({
      required: true,
      newOnly: true,
      poses: ['front', 'side', 'back'],
    })
  })

  it.each([
    'ganho_massa',
    'manutencao',
  ] as const)('phase %s adds its fields and activity once', (phase) => {
    const form = getReevaluationFormDescriptor({ ...context, phase })
    const keys = form.questions.map((question) => question.key)
    expect(keys.slice(0, 5)).toEqual(common)
    expect(keys.filter((key) => key === 'strengthSessions')).toHaveLength(1)
    expect(keys.at(-1)).toBe('healthCheck')
    expect(keys.includes('strengthProgression')).toBe(phase === 'ganho_massa')
    expect(keys.includes('fatPerception')).toBe(phase === 'ganho_massa')
    expect(keys.includes('difficultToMaintain')).toBe(phase === 'manutencao')
    const level = form.questions.find((question) => question.key === 'activity.activityLevel')
    expect(level).toMatchObject({ preselected: 'moderado', initiallyConfirmed: false })
    expect(form.questions.some((question) => question.key === 'activity.sessionMinutes')).toBe(true)
  })

  it.each([
    'consider_maintenance',
    'end_deficit',
  ] as const)('recomposition activity is contextual for %s', (activityPurpose) => {
    const form = getReevaluationFormDescriptor({ ...context, activityPurpose })
    expect(form.questions.some((question) => question.key === 'activity.activityLevel')).toBe(true)
  })

  it('pins all phase labels and explicit unknown choices', () => {
    const gain = getReevaluationFormDescriptor({ ...context, phase: 'ganho_massa' })
    expect(gain.questions.find((q) => q.key === 'adherence')?.options?.map((o) => o.label)).toEqual(
      ['Bem consistente', 'Mais ou menos', 'Pouco consistente'],
    )
    expect(gain.questions.find((q) => q.key === 'strengthProgression')).toMatchObject({
      label: 'Em relação aos 14 dias anteriores, seu treino de força…',
      options: [
        { value: 'melhorou', label: 'Melhorou' },
        { value: 'ficou_parecido', label: 'Ficou parecido' },
        { value: 'piorou_ou_travou', label: 'Piorou ou travou' },
        { value: 'nao_sei_avaliar', label: 'Não sei avaliar' },
      ],
    })
    expect(gain.questions.every((q) => q.optOutLabel === 'Prefiro não responder')).toBe(true)
  })

  it.each([
    'EARLY_FULL',
    'ROUTINE_REVIEW',
    'SAFETY',
  ] as const)('does not impose regular photos on %s', (kind) => {
    const form = getReevaluationFormDescriptor({ ...context, kind, holdActive: true })
    expect(form.photoRequirement.required).toBe(false)
    if (kind === 'EARLY_FULL') {
      expect(form.questions.slice(-2).map((q) => q.key)).toEqual([
        'healthCheck',
        'professionalConversationConfirmed',
      ])
    } else {
      expect(form.questions[0]?.key).toBe('strengthSessions')
      expect(form.questions.some((q) => q.key === 'healthCheck')).toBe(false)
      expect(form.preferenceQuestion).toBeNull()
    }
  })

  it('sex affects presentation only; missing sex does not hide a possibly relevant declaration', () => {
    for (const sex of ['feminino', null] as const) {
      expect(
        getReevaluationFormDescriptor({ ...context, sex }).questions.at(-1)?.options,
      ).toHaveLength(9)
    }
    expect(
      getReevaluationFormDescriptor({ ...context, sex: 'masculino' }).questions.at(-1)?.options,
    ).toHaveLength(7)
    expect(() =>
      parseReevaluationFormDraft({
        ...base,
        answers: { healthCheck: { kind: 'risks', items: ['pregnant_or_breastfeeding'] } },
      }),
    ).not.toThrow()
  })

  it.each([
    -1,
    15,
    1.5,
    NaN,
    Infinity,
  ])('rejects invalid support counts %s', (confirmedMealDays) => {
    expect(() => getReevaluationFormDescriptor({ ...context, confirmedMealDays })).toThrow()
  })
})

describe('nullable drafts never write, infer defaults or calculate', () => {
  it('boolean context choices use the same wire values as the draft parser', () => {
    const form = getReevaluationFormDescriptor({ ...context, phase: 'manutencao' })
    const choices = form.questions.find((q) => q.key === 'activity.mostlySitting')?.options
    expect(choices?.map((choice) => choice.value)).toEqual([true, false])
    for (const choice of choices ?? []) {
      expect(() =>
        parseReevaluationFormDraft({
          ...base,
          phase: 'manutencao',
          answers: { activity: { mostlySitting: choice.value } },
        }),
      ).not.toThrow()
    }
  })
  it('normalizes missing/blank/opt-out to null while preserving explicit zero', () => {
    const draft = parseReevaluationFormDraft({
      ...base,
      answers: {
        weightKg: ' ',
        strengthSessions: 0,
        adherence: 'prefiro_nao_responder',
        hunger: '',
        energy: null,
      },
    })
    expect(draft.answers).toEqual({
      weightKg: null,
      strengthSessions: 0,
      adherence: null,
      hunger: null,
      energy: null,
      strengthProgression: null,
      fatPerception: null,
      difficultToMaintain: null,
      activity: null,
      healthCheck: null,
      professionalConversationConfirmed: null,
    })
    expect(draft.preference).toBeNull()
    expect(parseReevaluationFormDraft(JSON.parse(JSON.stringify(draft)))).toEqual(draft)
    expect(getKnownReevaluationAnswers(draft, ['strengthSessions'])).toEqual({
      status: 'known',
      values: { strengthSessions: 0 },
    })
    expect(getKnownReevaluationAnswers(draft, ['hunger'])).toEqual({
      status: 'missing',
      missing: [
        {
          key: 'hunger',
          label: 'Como esteve a sua fome, na média?',
          message:
            'Faltou responder Como esteve a sua fome, na média?. Sem essa resposta o app não muda a sua meta nesta reavaliação.',
        },
      ],
    })
  })

  it('keeps Não sei avaliar explicit but unavailable to rule readers', () => {
    const draft = parseReevaluationFormDraft({
      ...base,
      phase: 'ganho_massa',
      answers: { strengthProgression: 'nao_sei_avaliar' },
    })
    expect(draft.answers.strengthProgression).toBe('nao_sei_avaliar')
    expect(getKnownReevaluationAnswers(draft, ['strengthProgression']).status).toBe('missing')
  })

  it('requires explicit activity confirmation and never derives a level from sessions', () => {
    const draft = parseReevaluationFormDraft({
      ...base,
      phase: 'ganho_massa',
      answers: { strengthSessions: 7, activity: { activityLevel: 'moderado' } },
    })
    expect(draft.answers.activity?.activityLevelConfirmed).toBe(false)
    expect(getKnownReevaluationAnswers(draft, ['activity']).status).toBe('missing')
    const confirmed = parseReevaluationFormDraft({
      ...draft,
      answers: {
        ...draft.answers,
        activity: { ...draft.answers.activity, activityLevelConfirmed: true },
      },
    })
    expect(getKnownReevaluationAnswers(confirmed, ['activity']).status).toBe('known')
    expect(JSON.stringify(confirmed)).not.toMatch(/calories|kcal|target/)
  })

  it('keeps optional preference outside numeric answers; support zero cannot veto adherence', () => {
    const draft = parseReevaluationFormDraft({
      ...base,
      answers: { adherence: 'bem_consistente' },
      preference: { action: 'change', value: { kind: 'body_fat', percent: 3 } },
    })
    expect(draft.preference).toEqual({ action: 'change', value: { kind: 'body_fat', percent: 3 } })
    expect(getKnownReevaluationAnswers(draft, ['adherence'])).toEqual({
      status: 'known',
      values: { adherence: 'bem_consistente' },
    })
    expect(draft.answers).not.toHaveProperty('preference')
    // Validating a preference draft is not clinical permission to activate it.
    expect(draft).not.toHaveProperty('goalType')
    expect(draft).not.toHaveProperty('approved')
  })

  it.each([
    { weightKg: 29.99 },
    { weightKg: 300.01 },
    { weightKg: '80' },
    { weightKg: Infinity },
    { strengthSessions: -1 },
    { strengthSessions: 8 },
    { strengthSessions: 1.5 },
    { adherence: 'consistent' },
    { hunger: 'moderado' },
    { energy: NaN },
    { strengthProgression: 'melhorou' },
    { difficultToMaintain: 'sim' },
    { activity: { activityLevel: 'alto' } },
    { unrequested: 1 },
  ])('rejects invalid or nonapplicable recomposition data %#', (answers) => {
    expect(() => parseReevaluationFormDraft({ ...base, answers })).toThrow()
  })

  it('rejects hidden full answers in a short review and unknown fields', () => {
    expect(() =>
      parseReevaluationFormDraft({ ...base, kind: 'ROUTINE_REVIEW', answers: { hunger: 'pouca' } }),
    ).toThrow()
    expect(() => parseReevaluationFormDraft({ ...base, target: 2000 })).toThrow()
    expect(() => getKnownReevaluationAnswers(base, ['preference' as 'hunger'])).toThrow()
  })

  it('accepts explicit source boundaries and context without an invented clinical minutes cap', () => {
    for (const weightKg of [30, 300]) {
      expect(parseReevaluationFormDraft({ ...base, answers: { weightKg } }).answers.weightKg).toBe(
        weightKg,
      )
    }
    const draft = parseReevaluationFormDraft({
      ...base,
      phase: 'manutencao',
      answers: {
        activity: {
          otherExerciseType: '  caminhada  ',
          otherExerciseDays: 7,
          sessionMinutes: 1000,
          mostlySitting: false,
        },
      },
    })
    expect(draft.answers.activity).toMatchObject({
      otherExerciseType: 'caminhada',
      otherExerciseDays: 7,
      sessionMinutes: 1000,
      mostlySitting: false,
      activityLevel: null,
      activityLevelConfirmed: false,
    })
    expect(() =>
      parseReevaluationFormDraft({
        ...base,
        phase: 'manutencao',
        answers: { activity: { sessionMinutes: 0 } },
      }),
    ).toThrow()
  })
})
