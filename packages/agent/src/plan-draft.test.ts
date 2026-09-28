import { describe, expect, it } from 'vitest'
import {
  assessPlanDraftPayload,
  confirmablePlanDraftPayload,
  mentionsMedication,
  planDraftValidUntil,
  sanitizeUnrecognizedSegments,
} from './plan-draft.js'

const exercise = {
  name: 'Agachamento livre',
  muscle_group: 'pernas',
  sets: 4,
  reps_range: '8-12',
  rest_seconds: 90,
}

const training = {
  plan_type: 'split',
  equipment_summary: 'halteres e barra',
  weekly_schedule: [
    { day: 'seg', focus: 'inferiores', duration_min: 60, exercises: [exercise] },
    { day: 'qua', focus: 'superiores', duration_min: 50, exercises: [exercise] },
  ],
  notes: 'progredir carga a cada 2 semanas',
}

const nutrition = {
  horizon: 'daily',
  daily_meals: [
    {
      meal_type: 'almoco',
      items: [
        { food_name: 'arroz integral', quantity_g: 120 },
        { food_name: 'frango grelhado', quantity_g: 150, kcal: 240, protein_g: 45 },
      ],
    },
  ],
}

describe('assessPlanDraftPayload — treino', () => {
  it('conteúdo completo passa como veio', () => {
    const result = assessPlanDraftPayload('training', training)
    expect(result.complete).toBe(true)
    expect(result.uncertain_fields).toEqual([])
    expect(result.payload).toEqual(training)
  })

  it('valor fora da faixa vira null e incerto, nunca é ajustado', () => {
    const result = assessPlanDraftPayload('training', {
      ...training,
      weekly_schedule: [
        {
          day: 'seg',
          focus: 'inferiores',
          duration_min: 600,
          exercises: [{ ...exercise, sets: 40, rest_seconds: -5 }],
        },
      ],
    })
    expect(result.complete).toBe(false)
    expect(result.uncertain_fields).toEqual(
      expect.arrayContaining([
        { pointer: '/weekly_schedule/0/duration_min', reason: 'out_of_range' },
        { pointer: '/weekly_schedule/0/exercises/0/sets', reason: 'out_of_range' },
        { pointer: '/weekly_schedule/0/exercises/0/rest_seconds', reason: 'out_of_range' },
      ]),
    )
    const day = (result.payload.weekly_schedule as Array<Record<string, unknown>>)[0]
    expect(day?.duration_min).toBeNull()
    const first = (day?.exercises as Array<Record<string, unknown>>)[0]
    expect(first?.sets).toBeNull()
    expect(first?.rest_seconds).toBeNull()
    // o que estava certo continua igual
    expect(first?.name).toBe('Agachamento livre')
    expect(first?.reps_range).toBe('8-12')
  })

  it('campo obrigatório ausente é "missing" e bloqueia a confirmação', () => {
    const result = assessPlanDraftPayload('training', {
      weekly_schedule: [{ day: 'seg', exercises: [{ name: 'Supino' }] }],
    })
    expect(result.complete).toBe(false)
    expect(result.uncertain_fields).toEqual(
      expect.arrayContaining([
        { pointer: '/weekly_schedule/0/focus', reason: 'missing' },
        { pointer: '/weekly_schedule/0/duration_min', reason: 'missing' },
        { pointer: '/weekly_schedule/0/exercises/0/sets', reason: 'missing' },
        { pointer: '/weekly_schedule/0/exercises/0/rest_seconds', reason: 'missing' },
      ]),
    )
    expect(confirmablePlanDraftPayload('training', result.payload)).toBeNull()
  })

  it('dia sem exercício e plano sem dia não são confirmáveis', () => {
    expect(
      assessPlanDraftPayload('training', {
        weekly_schedule: [{ day: 'seg', focus: 'a', duration_min: 30, exercises: [] }],
      }).uncertain_fields,
    ).toEqual([{ pointer: '/weekly_schedule/0/exercises', reason: 'missing' }])
    expect(assessPlanDraftPayload('training', { weekly_schedule: [] }).complete).toBe(false)
    expect(assessPlanDraftPayload('training', {}).uncertain_fields).toEqual([
      { pointer: '/weekly_schedule', reason: 'missing' },
    ])
  })

  it('número decimal onde só cabe inteiro é inválido, não arredondado', () => {
    const result = assessPlanDraftPayload('training', {
      ...training,
      weekly_schedule: [
        {
          day: 'seg',
          focus: 'a',
          duration_min: 45,
          exercises: [{ ...exercise, sets: 3.5 }],
        },
      ],
    })
    expect(result.uncertain_fields).toEqual([
      { pointer: '/weekly_schedule/0/exercises/0/sets', reason: 'invalid' },
    ])
    const day = (result.payload.weekly_schedule as Array<Record<string, unknown>>)[0]
    expect((day?.exercises as Array<Record<string, unknown>>)[0]?.sets).toBeNull()
  })

  it('chave desconhecida nunca entra no rascunho (dose, medicamento, instrução)', () => {
    const result = assessPlanDraftPayload('training', {
      ...training,
      medications: [{ name: 'X', dose: '10 mg' }],
      confirm: true,
      status: 'confirmed',
      user_id: 'outro',
      weekly_schedule: [
        {
          day: 'seg',
          focus: 'a',
          duration_min: 45,
          supplement: 'creatina 5 g',
          exercises: [{ ...exercise, dose: '2 comprimidos', __proto__: { x: 1 } }],
        },
      ],
    })
    const text = JSON.stringify(result.payload)
    expect(result.complete).toBe(true)
    for (const word of ['medications', 'dose', 'supplement', 'creatina', 'confirm', 'user_id', 'status']) {
      expect(text).not.toContain(word)
    }
  })

  it('recusa o que não é objeto', () => {
    for (const value of [null, 'texto', 3, [training]]) {
      expect(() => assessPlanDraftPayload('training', value)).toThrow(TypeError)
    }
  })

  it('reavaliar o conteúdo já limpo dá o mesmo resultado', () => {
    const first = assessPlanDraftPayload('training', {
      weekly_schedule: [{ day: 'seg', duration_min: 999, exercises: [{ name: 'Supino', sets: 99 }] }],
    })
    const second = assessPlanDraftPayload('training', first.payload)
    expect(second.payload).toEqual(first.payload)
    expect(second.complete).toBe(false)
    expect(second.uncertain_fields.map((field) => field.pointer).sort()).toEqual(
      first.uncertain_fields.map((field) => field.pointer).sort(),
    )
  })
})

describe('assessPlanDraftPayload — dieta', () => {
  it('plano importado sem calorias é completo e continua sem calorias', () => {
    const result = assessPlanDraftPayload('nutrition', nutrition)
    expect(result.complete).toBe(true)
    const meal = (result.payload.daily_meals as Array<Record<string, unknown>>)[0]
    const items = meal?.items as Array<Record<string, unknown>>
    expect(items[0]).toEqual({ food_name: 'arroz integral', quantity_g: 120 })
    expect(items[0]).not.toHaveProperty('kcal')
    expect(meal).not.toHaveProperty('total_kcal')
    expect(result.payload).not.toHaveProperty('meta_kcal')
    expect(items[1]?.kcal).toBe(240)
  })

  it('alimento sem quantidade bloqueia; quantidade zero ou absurda vira null', () => {
    const result = assessPlanDraftPayload('nutrition', {
      daily_meals: [
        {
          meal_type: 'almoco',
          items: [
            { food_name: 'arroz' },
            { food_name: 'feijão', quantity_g: 0 },
            { food_name: 'frango', quantity_g: 50_000 },
            { quantity_g: 100 },
          ],
        },
      ],
    })
    expect(result.complete).toBe(false)
    expect(result.uncertain_fields).toEqual(
      expect.arrayContaining([
        { pointer: '/daily_meals/0/items/0/quantity_g', reason: 'missing' },
        { pointer: '/daily_meals/0/items/1/quantity_g', reason: 'out_of_range' },
        { pointer: '/daily_meals/0/items/2/quantity_g', reason: 'out_of_range' },
        { pointer: '/daily_meals/0/items/3/food_name', reason: 'missing' },
      ]),
    )
    const items = (result.payload.daily_meals as Array<Record<string, unknown>>)[0]
      ?.items as Array<Record<string, unknown>>
    expect(items.map((item) => item.quantity_g)).toEqual([undefined, null, null, 100])
  })

  it('tipo de refeição desconhecido é inválido, não trocado por outro', () => {
    const result = assessPlanDraftPayload('nutrition', {
      daily_meals: [{ meal_type: 'brunch', items: [{ food_name: 'pão', quantity_g: 50 }] }],
    })
    expect(result.uncertain_fields).toEqual([
      { pointer: '/daily_meals/0/meal_type', reason: 'invalid' },
    ])
    expect((result.payload.daily_meals as Array<Record<string, unknown>>)[0]?.meal_type).toBeNull()
  })

  it('caloria negativa ou absurda informada no documento não é aceita', () => {
    const result = assessPlanDraftPayload('nutrition', {
      daily_meals: [
        {
          meal_type: 'jantar',
          items: [{ food_name: 'sopa', quantity_g: 300, kcal: -10, protein_g: 9000 }],
        },
      ],
    })
    expect(result.complete).toBe(false)
    expect(result.uncertain_fields.map((field) => field.pointer).sort()).toEqual([
      '/daily_meals/0/items/0/kcal',
      '/daily_meals/0/items/0/protein_g',
    ])
  })
})

describe('apoios', () => {
  it('trechos não reconhecidos ficam como vieram, com limites', () => {
    expect(
      sanitizeUnrecognizedSegments([
        '  Tomar 1   comprimido de X  ',
        '',
        42,
        null,
        'a'.repeat(900),
      ]),
    ).toEqual(['Tomar 1 comprimido de X', 'a'.repeat(500)])
    expect(sanitizeUnrecognizedSegments('texto')).toEqual([])
    expect(sanitizeUnrecognizedSegments(Array.from({ length: 80 }, (_, i) => `t${i}`))).toHaveLength(40)
  })

  it('reconhece menção a medicamento, suplemento ou dose', () => {
    for (const text of [
      'Tomar 1 comprimido de X',
      'Creatina 5 g ao dia',
      'Vitamina D 2000 UI',
      'Remédio para pressão',
      'Losartana 50 mg',
    ]) {
      expect(mentionsMedication(text), text).toBe(true)
    }
    for (const text of ['Beber 2 litros de água', 'Treinar em jejum', 'Observação do treinador']) {
      expect(mentionsMedication(text), text).toBe(false)
    }
  })

  it('validade: gerados seguem a regra dos geradores; importados não ganham validade', () => {
    const now = new Date('2026-09-28T12:00:00.000Z')
    expect(planDraftValidUntil('training', 'flow_generated', training, now)).toBe(
      '2026-11-09T12:00:00.000Z',
    )
    expect(planDraftValidUntil('nutrition', 'flow_generated', { horizon: 'daily' }, now)).toBe(
      '2026-09-29T12:00:00.000Z',
    )
    expect(planDraftValidUntil('nutrition', 'flow_generated', { horizon: 'weekly' }, now)).toBe(
      '2026-10-05T12:00:00.000Z',
    )
    expect(planDraftValidUntil('training', 'imported_pdf', training, now)).toBeNull()
    expect(planDraftValidUntil('nutrition', 'imported_photo', nutrition, now)).toBeNull()
  })
})
