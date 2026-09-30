/**
 * Audit 2026-09-30 (Eduardo, iPhone, Flow do app):
 *   "Monte uma proposta de treino de 3 dias por semana, academia, nivel iniciante."
 *   → "Pode ser equilibrado no geral."
 * O Flow respondeu só "Segunda — Full Body A (6 exercícios) ...": genérico. O
 * pedido: mostrar no chat a sugestão de treino e de dieta com exercício, séries,
 * repetições, alimentos e quantidades, e chamar de "sugestão", não "proposta".
 *
 * Fixtures: os rascunhos reais gravados em staging para a conta QA A
 * (treino 956b82be…, 2026-09-30 15:57Z; cardápio 7cafaf19…, 2026-09-29), só com
 * os campos que o texto usa (notas, passos e erros comuns ficam na revisão).
 */
import { describe, expect, it } from 'vitest'
import {
  nutritionSuggestionText,
  PLAN_SUGGESTION_TEXT_MAX,
  trainingSuggestionText,
} from '../plan-suggestion-text.js'

const ex = (name: string, muscle_group: string, sets: number, rest_seconds: number) => ({
  name,
  muscle_group,
  sets,
  reps_range: '12-15',
  rpe_target: '7-8',
  rest_seconds,
})

const TRAINING_DRAFT = {
  plan_type: 'full_body',
  equipment_summary: 'equipamentos completos de academia',
  weekly_schedule: [
    {
      day: 'Segunda-feira',
      focus: 'Full Body A',
      duration_min: 60,
      exercises: [
        ex('Agachamento livre', 'quadríceps/glúteos', 3, 90),
        ex('Supino reto com barra', 'peitoral', 3, 90),
        ex('Puxada frontal', 'dorsal', 3, 90),
        ex('Desenvolvimento com halteres', 'ombros', 3, 90),
        ex('Rosca direta com barra', 'bíceps', 2, 60),
        ex('Tríceps na polia (corda)', 'tríceps', 2, 60),
      ],
    },
    {
      day: 'Quarta-feira',
      focus: 'Full Body B',
      duration_min: 60,
      exercises: [
        ex('Leg press 45°', 'quadríceps/glúteos', 3, 90),
        ex('Supino inclinado com halteres', 'peitoral superior', 3, 90),
        ex('Remada curvada com barra', 'dorsal', 3, 90),
        ex('Elevação lateral com halteres', 'ombros (deltoides laterais)', 3, 90),
        ex('Rosca martelo alternada', 'bíceps/antebraço', 2, 60),
        ex('Tríceps testa com barra', 'tríceps', 2, 60),
      ],
    },
    {
      day: 'Sexta-feira',
      focus: 'Full Body C',
      duration_min: 60,
      exercises: [
        ex('Stiff (levantamento romeno)', 'posteriores de coxa/glúteos', 3, 90),
        ex('Crucifixo inclinado com halteres', 'peitoral', 3, 90),
        ex('Pulldown com corda (ou pullover)', 'dorsal', 3, 90),
        ex('Remada alta com barra', 'ombros/trapézio', 3, 90),
        ex('Rosca concentrada', 'bíceps', 2, 60),
        ex('Tríceps francês com haltere', 'tríceps', 2, 60),
      ],
    },
  ],
  progression_rule:
    'Período de aclimatação: 15 dias mantendo mesmo peso para aprender técnica. Depois, progressão em escada por 4-6 meses: 1ª semana 12-15 reps, 2ª semana 10-12 reps, 3ª semana 8-10 reps, 4ª semana 6-8 reps. Sempre mantendo técnica perfeita. Quando completar ciclo, aumenta carga e reinicia.',
}

const item = (food_name: string, quantity_g: number, kcal: number, protein_g: number) => ({
  food_name,
  quantity_g,
  kcal,
  protein_g,
})

const NUTRITION_DRAFT = {
  mode: 'referencia',
  horizon: 'daily',
  meta_kcal: 3361,
  meta_protein_g: 186.1,
  daily_meals: [
    {
      meal_type: 'cafe',
      time_suggestion: '07:00',
      items: [
        item('Pão francês', 100, 300, 9),
        item('Ovo cozido', 100, 155, 13),
        item('Queijo minas frescal', 50, 132, 8.8),
        item('Café sem açúcar', 200, 4, 0.2),
        item('Banana', 100, 98, 1.3),
      ],
      total_kcal: 689,
      total_protein_g: 32.3,
    },
    {
      meal_type: 'almoco',
      time_suggestion: '12:30',
      items: [
        item('Frango grelhado', 200, 330, 58),
        item('Arroz branco cozido', 200, 260, 5),
        item('Feijão carioca cozido', 150, 114, 8.4),
        item('Brócolis cozido', 100, 25, 2.5),
        item('Azeite de oliva', 10, 90, 0),
        item('Salada de alface e tomate', 80, 16, 0.8),
      ],
      total_kcal: 835,
      total_protein_g: 74.7,
    },
    {
      meal_type: 'lanche_tarde',
      time_suggestion: '16:00',
      items: [
        item('Batata doce cozida', 200, 172, 1.2),
        item('Peito de frango desfiado', 100, 165, 29),
        item('Amendoim torrado', 30, 179, 7.8),
        item('Maçã', 130, 68, 0.3),
      ],
      total_kcal: 584,
      total_protein_g: 38.3,
    },
    {
      meal_type: 'jantar',
      time_suggestion: '20:00',
      items: [
        item('Frango grelhado', 180, 297, 52.2),
        item('Arroz branco cozido', 180, 234, 4.5),
        item('Feijão carioca cozido', 120, 91, 6.7),
        item('Abóbora cozida', 100, 40, 1.4),
        item('Couve refogada', 50, 18, 1.2),
        item('Azeite de oliva', 8, 72, 0),
        item('Laranja', 150, 71, 1.3),
      ],
      total_kcal: 823,
      total_protein_g: 67.3,
    },
  ],
}

describe('audit 09-30: a sugestão do Flow mostra o plano, não um resumo', () => {
  it('treino: cada dia com exercício, séries×repetições e descanso', () => {
    const text = trainingSuggestionText(TRAINING_DRAFT)
    expect(text.split('\n').slice(0, 8)).toEqual([
      'Segunda-feira — Full Body A (60 min)',
      '• Agachamento livre — 3×12-15, descanso 90 s',
      '• Supino reto com barra — 3×12-15, descanso 90 s',
      '• Puxada frontal — 3×12-15, descanso 90 s',
      '• Desenvolvimento com halteres — 3×12-15, descanso 90 s',
      '• Rosca direta com barra — 2×12-15, descanso 60 s',
      '• Tríceps na polia (corda) — 2×12-15, descanso 60 s',
      '',
    ])
    // Os 18 exercícios, todos, sem o resumo genérico "(6 exercícios)".
    expect(text.match(/^• /gm)).toHaveLength(18)
    expect(text).toContain('Sexta-feira — Full Body C (60 min)')
    expect(text).toContain('• Tríceps francês com haltere — 2×12-15, descanso 60 s')
    expect(text).not.toMatch(/\d+ exercícios/)
    expect(text.endsWith(`Progressão: ${TRAINING_DRAFT.progression_rule}`)).toBe(true)
  })

  it('dieta: cada refeição com alimentos e quantidades, e o total contra a meta', () => {
    const text = nutritionSuggestionText(NUTRITION_DRAFT)
    expect(text.split('\n').slice(0, 7)).toEqual([
      'Café da manhã (07:00) — 689 kcal, 32,3 g de proteína',
      '• Pão francês: 100 g',
      '• Ovo cozido: 100 g',
      '• Queijo minas frescal: 50 g',
      '• Café sem açúcar: 200 g',
      '• Banana: 100 g',
      '',
    ])
    expect(text).toContain('Lanche da tarde (16:00) — 584 kcal, 38,3 g de proteína')
    expect(text).toContain('• Azeite de oliva: 8 g')
    expect(text.match(/^• /gm)).toHaveLength(22)
    // A soma é a das refeições gravadas; a meta aparece ao lado, sem ajuste.
    expect(text.split('\n').at(-1)).toBe(
      'Total do dia: 2.931 kcal, 212,6 g de proteína (meta: 3.361 kcal, 186,1 g)',
    )
    expect(text).not.toMatch(/cafe|lanche_tarde|almoco|jantar/)
  })

  it('os planos reais cabem inteiros, sem corte', () => {
    for (const text of [
      trainingSuggestionText(TRAINING_DRAFT),
      nutritionSuggestionText(NUTRITION_DRAFT),
    ]) {
      expect(text.length).toBeLessThanOrEqual(PLAN_SUGGESTION_TEXT_MAX)
      expect(text).not.toContain('O restante está em')
    }
  })

  it('um plano maior que o limite é cortado numa linha inteira e aponta para a revisão', () => {
    const long = {
      weekly_schedule: Array.from({ length: 7 }, (_, day) => ({
        day: `Dia ${day + 1}`,
        focus: 'Full Body',
        exercises: TRAINING_DRAFT.weekly_schedule[0]?.exercises.concat(
          TRAINING_DRAFT.weekly_schedule[1]?.exercises ?? [],
        ),
      })),
    }
    const text = trainingSuggestionText(long)
    expect(text.length).toBeLessThanOrEqual(PLAN_SUGGESTION_TEXT_MAX + 60)
    expect(text.split('\n').at(-1)).toBe('(O restante está em "Revisar sugestão".)')
  })
})
