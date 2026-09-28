import { describe, expect, it } from 'vitest'
import {
  assessPlanDraftPayload,
  classifyHealthProduct,
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

describe('medicamento, suplemento e dose: nunca orientação, nunca nome apagado', () => {
  it('texto livre que fala de dose sai do campo e volta como veio', () => {
    const result = assessPlanDraftPayload('training', {
      ...training,
      notes: 'Tomar 2 comprimidos de X antes do treino',
      weekly_schedule: [
        {
          day: 'seg',
          focus: 'inferiores',
          duration_min: 60,
          exercises: [
            {
              ...exercise,
              notes: 'creatina 5 g',
              execution_steps: ['descer devagar', 'tomar suplemento antes'],
            },
          ],
        },
      ],
    })

    expect(JSON.stringify(result.payload)).not.toMatch(/comprimido|creatina|suplemento/i)
    expect([...result.removed_segments].sort()).toEqual([
      'Tomar 2 comprimidos de X antes do treino',
      'creatina 5 g',
      'tomar suplemento antes',
    ])
    const exercises = (result.payload.weekly_schedule as Array<Record<string, unknown>>)[0]
      ?.exercises as Array<Record<string, unknown>>
    expect(exercises[0]?.execution_steps).toEqual(['descer devagar'])
    expect(exercises[0]).not.toHaveProperty('notes')
    // Only free text was touched: the plan itself is complete.
    expect(result.complete).toBe(true)
  })

  it('medicamento como item fica com o nome, identificado, e impede a confirmação', () => {
    const result = assessPlanDraftPayload(
      'nutrition',
      {
        daily_meals: [
          {
            meal_type: 'cafe',
            items: [
              { food_name: 'Pão integral', quantity_g: 50 },
              { food_name: 'Losartana 50 mg', quantity_g: 1 },
            ],
          },
        ],
      },
      'document',
    )
    const items = (result.payload.daily_meals as Array<Record<string, unknown>>)[0]
      ?.items as Array<Record<string, unknown>>
    expect(items[1]?.food_name).toBe('Losartana 50 mg')
    expect(result.uncertain_fields).toEqual([
      { pointer: '/daily_meals/0/items/1', reason: 'outside_domain' },
    ])
    expect(result.complete).toBe(false)
    expect(confirmablePlanDraftPayload('nutrition', result.payload, 'document')).toBeNull()
  })

  it('suplemento num documento importado fica como veio, com aviso, e pode ser confirmado', () => {
    const payload = {
      daily_meals: [
        {
          meal_type: 'lanche_tarde',
          items: [
            { food_name: 'Banana', quantity_g: 100 },
            { food_name: 'Whey protein', quantity_g: 30 },
          ],
        },
      ],
    }
    const result = assessPlanDraftPayload('nutrition', payload, 'document')
    const items = (result.payload.daily_meals as Array<Record<string, unknown>>)[0]
      ?.items as Array<Record<string, unknown>>
    expect(items[1]).toEqual({ food_name: 'Whey protein', quantity_g: 30 })
    expect(result.uncertain_fields).toEqual([
      { pointer: '/daily_meals/0/items/1', reason: 'supplement' },
    ])
    expect(result.complete).toBe(true)
    expect(confirmablePlanDraftPayload('nutrition', payload, 'document')).not.toBeNull()
  })

  it('suplemento proposto pelo Flow fica visível e impede a confirmação (o Flow não sugere dose)', () => {
    const payload = {
      daily_meals: [
        { meal_type: 'lanche_tarde', items: [{ food_name: 'Creatina', quantity_g: 5 }] },
      ],
    }
    const result = assessPlanDraftPayload('nutrition', payload, 'flow')
    const items = (result.payload.daily_meals as Array<Record<string, unknown>>)[0]
      ?.items as Array<Record<string, unknown>>
    expect(items[0]).toEqual({ food_name: 'Creatina', quantity_g: 5 })
    expect(result.uncertain_fields).toEqual([
      { pointer: '/daily_meals/0/items/0', reason: 'supplement' },
    ])
    expect(result.complete).toBe(false)
    expect(confirmablePlanDraftPayload('nutrition', payload, 'flow')).toBeNull()
  })

  it('vitamina de fruta é bebida, não suplemento', () => {
    const payload = {
      daily_meals: [
        {
          meal_type: 'cafe',
          items: [
            { food_name: 'Vitamina de banana', quantity_g: 300 },
            { food_name: 'Vitamina com leite e aveia', quantity_g: 250 },
          ],
        },
      ],
    }
    for (const author of ['flow', 'document'] as const) {
      const result = assessPlanDraftPayload('nutrition', payload, author)
      expect(result.uncertain_fields).toEqual([])
      expect(result.complete).toBe(true)
    }
  })

  it('texto opcional retirado não impede a confirmação do resto', () => {
    const result = assessPlanDraftPayload('nutrition', {
      ...nutrition,
      notes: 'Vitamina D 2000 UI',
    })
    expect(result.complete).toBe(true)
    expect(result.payload).not.toHaveProperty('notes')
    expect(result.removed_segments).toEqual(['Vitamina D 2000 UI'])
  })

  it('opcional vazio ou null é o mesmo que ausente, e nada é acrescentado', () => {
    const result = assessPlanDraftPayload('nutrition', {
      horizon: null,
      notes: '  ',
      meta_kcal: null,
      daily_meals: [
        {
          meal_type: 'almoco',
          day_of_week: null,
          time_suggestion: null,
          notes: null,
          items: [{ food_name: 'arroz', quantity_g: 120, kcal: null, display_unit: null }],
        },
      ],
    })
    expect(result.complete).toBe(true)
    expect(result.uncertain_fields).toEqual([])
    // No default is written into the plan: what is stored is what was written.
    expect(result.payload).not.toHaveProperty('horizon')
    expect(result.payload).not.toHaveProperty('shopping_list')
    const trainingResult = assessPlanDraftPayload('training', {
      weekly_schedule: training.weekly_schedule,
    })
    expect(trainingResult.payload).not.toHaveProperty('plan_type')
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

  it('classifica pelo contexto, não por uma palavra isolada', () => {
    const cases: Array<[string, 'medication' | 'supplement' | null]> = [
      ['Tomar 1 comprimido de X', 'medication'],
      ['Losartana 50 mg', 'medication'],
      ['Vitamina D 2000 UI', 'medication'],
      ['Remédio para pressão', 'medication'],
      ['Injeção semanal', 'medication'],
      ['Creatina 5 g ao dia', 'supplement'],
      ['Whey protein', 'supplement'],
      ['Vitamina D', 'supplement'],
      ['vitamina B12', 'supplement'],
      ['Ômega 3', 'supplement'],
      ['Pré-treino', 'supplement'],
      ['Vitamina de banana', null],
      ['Vitamina com leite', null],
      ['Uma vitamina no lanche', null],
      ['Beber 2 litros de água', null],
      ['Treinar em jejum', null],
      ['Frango grelhado 150 g', null],
      ['Observação do treinador', null],
    ]
    for (const [text, kind] of cases) {
      expect(classifyHealthProduct(text), text).toBe(kind)
      expect(mentionsMedication(text), text).toBe(kind !== null)
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
