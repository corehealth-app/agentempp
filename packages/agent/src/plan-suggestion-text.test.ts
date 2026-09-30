import { describe, expect, it } from 'vitest'
import {
  ensureSuggestionShown,
  nutritionSuggestionText,
  PLAN_SUGGESTION_TEXT_MAX,
  PLAN_SUGGESTION_TRUNCATED,
  trainingSuggestionText,
} from './plan-suggestion-text.js'

const food = (food_name: string, quantity_g: number, extra: Record<string, unknown> = {}) => ({
  food_name,
  quantity_g,
  ...extra,
})

describe('texto da sugestão: o que nunca vai para o chat', () => {
  it('suplemento e medicamento ficam só na revisão, e o total some', () => {
    const text = nutritionSuggestionText({
      meta_kcal: 2000,
      meta_protein_g: 140,
      daily_meals: [
        {
          meal_type: 'cafe',
          items: [food('Ovo cozido', 100), food('Whey protein', 30), food('Metformina 500 mg', 1)],
          total_kcal: 400,
          total_protein_g: 40,
        },
      ],
    })
    expect(text).toContain('• Ovo cozido: 100 g')
    expect(text).not.toMatch(/Whey|Metformina|500 mg/)
    expect(text).toContain('2 itens precisam ser conferidos em "Revisar sugestão"')
    expect(text).not.toContain('Total do dia')
  })

  it('treino: um item de suplemento no lugar de exercício não aparece', () => {
    const text = trainingSuggestionText({
      weekly_schedule: [
        {
          day: 'Segunda',
          focus: 'A',
          exercises: [
            { name: 'Agachamento livre', sets: 3, reps_range: '12', rest_seconds: 90 },
            { name: 'Creatina 5 g', sets: 1, reps_range: '1', rest_seconds: 0 },
          ],
        },
      ],
    })
    expect(text).not.toMatch(/Creatina/)
    expect(text).toContain('1 item precisa ser conferido')
  })

  it('meta 0 (sem meta oficial) não aparece como meta', () => {
    const text = nutritionSuggestionText({
      meta_kcal: 0,
      meta_protein_g: 0,
      daily_meals: [
        { meal_type: 'almoco', items: [food('Arroz', 100)], total_kcal: 130, total_protein_g: 2.5 },
      ],
    })
    expect(text.split('\n').at(-1)).toBe('Total do dia: 130 kcal, 2,5 g de proteína')
  })
})

describe('texto da sugestão: fiel à revisão', () => {
  it('medida caseira com os gramas, sem arredondar 0,25', () => {
    const text = nutritionSuggestionText({
      daily_meals: [
        {
          meal_type: 'lanche_tarde',
          items: [food('Aveia', 30, { display_qty: 0.25, display_unit: 'xícara' })],
          total_kcal: 120.4,
          total_protein_g: 4.2,
        },
      ],
    })
    expect(text).toContain('• Aveia: 0,25 xícara (30 g)')
    expect(text).toContain('Lanche da tarde — 120,4 kcal, 4,2 g de proteína')
  })

  it('dia sem nome nem foco não deixa linha em branco', () => {
    const text = trainingSuggestionText({
      weekly_schedule: [
        { exercises: [{ name: 'Remada', sets: 3, reps_range: '10', rest_seconds: 60 }] },
      ],
    })
    expect(text).toBe('• Remada — 3×10, descanso 60 s')
  })

  it('o corte cai entre refeições, dentro do limite, e mantém o total', () => {
    const meal = (meal_type: string) => ({
      meal_type,
      items: Array.from({ length: 12 }, (_, i) =>
        food(`Alimento de nome bem comprido número ${i + 1}`, 100),
      ),
      total_kcal: 500,
      total_protein_g: 30,
    })
    const text = nutritionSuggestionText({
      meta_kcal: 3000,
      meta_protein_g: 180,
      daily_meals: ['cafe', 'lanche_manha', 'almoco', 'lanche_tarde', 'jantar', 'ceia'].map(meal),
    })
    expect(text.length).toBeLessThanOrEqual(PLAN_SUGGESTION_TEXT_MAX)
    expect(text).toContain(PLAN_SUGGESTION_TRUNCATED)
    expect(text.split('\n').at(-1)).toBe(
      'Total do dia: 3.000 kcal, 180 g de proteína (meta: 3.000 kcal, 180 g)',
    )
    // Nenhuma refeição fica com o cabeçalho e sem os itens.
    const beforeNotice = text.split(PLAN_SUGGESTION_TRUNCATED)[0]?.trim() ?? ''
    expect(beforeNotice.split('\n').at(-1)).toMatch(/^• /)
  })
})

describe('ensureSuggestionShown', () => {
  const calls = [
    {
      name: 'propoe_plano_treino',
      result: {
        success: true,
        status: 'ready_for_review',
        sugestao: 'Segunda — A\n• Remada — 3×10',
      },
    },
  ]

  it('resposta vazia vira a sugestão (nunca um 502 com rascunho criado)', () => {
    const shown = ensureSuggestionShown('', calls)
    expect(shown.replaced).toBe(true)
    expect(shown.text).toContain('• Remada — 3×10')
    expect(shown.text).toContain('"Revisar sugestão"')
  })

  it('espaços diferentes não contam como paráfrase', () => {
    const reply = 'Pronta!\n\nSegunda — A\n\n• Remada — 3×10\n\nToque em "Revisar sugestão".'
    expect(ensureSuggestionShown(reply, calls)).toEqual({ text: reply, replaced: false })
  })

  it('rascunho incompleto: o fecho diz que falta completar', () => {
    const shown = ensureSuggestionShown('Pronto.', [
      {
        name: 'propoe_plano_dieta',
        result: { success: true, status: 'needs_completion', sugestao: 'Almoço\n• Arroz: 100 g' },
      },
    ])
    expect(shown.text).toContain('Alguns campos ficaram para você completar na revisão.')
  })

  it('WhatsApp (gera_*) e falhas nunca são tocados', () => {
    for (const toolCalls of [
      [{ name: 'gera_treino', result: { success: true, sugestao: 'x' } }],
      [{ name: 'propoe_plano_treino', result: { success: false, sugestao: 'x' } }],
      [],
    ]) {
      expect(ensureSuggestionShown('Resposta.', toolCalls)).toEqual({
        text: 'Resposta.',
        replaced: false,
      })
    }
  })
})
