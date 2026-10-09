import { buildDailyState, type DailyStateInput, type Protocol } from '@mpp/core'
import { describe, expect, it } from 'vitest'
import { renderFlowDayStatus } from './flow-day-status-message.js'

function day(protocol: Protocol | null, patch: Partial<DailyStateInput> = {}) {
  return buildDailyState({
    localDate: '2026-10-08',
    generatedAt: '2026-10-08T18:00:00.000Z',
    protocol,
    calculatedTargets: { calories_target: 2400, protein_target: 150 },
    programmedDeficitKcal: protocol === 'recomposicao' ? 500 : 0,
    gainSurplusMultiplier: 1.05,
    snapshot: {
      caloriesConsumed: 1785,
      caloriesTarget: 2400,
      proteinG: 126,
      proteinTarget: 150,
      carbsG: 180,
      fatG: 45,
      exerciseCalories: 0,
      waterConsumedMl: 1000,
      protocol,
      dayClosed: false,
      dayStatus: null,
      updatedAt: '2026-10-08T17:00:00.000Z',
    },
    meals: [],
    workouts: [],
    pendingRegistrations: [],
    hydrationTarget: null,
    routineItems: [],
    mealGap: {
      expected: [],
      registered: [],
      skipped: [],
      open: [],
      reliable: false,
      activeDays: 0,
    },
    progress: { deficitBlock: 3120, blocksCompleted: 2, updatedAt: null },
    ...patch,
  })
}

const OPEN_PT =
  'Antes de atualizar seu status: teve alguma refeição, belisco ou atividade física que você fez e não registrou? Sem cobrança — é só pra manter tudo preciso. Use Registrar para incluir o que faltou.'
const OPEN_EN =
  'Before updating your status: did you have a meal, snack or physical activity that you have not recorded? No pressure — this helps keep everything accurate. Use Register to add anything missing.'
const DAILY_PT =
  'Status do dia: 2026-10-08\nConsumido: 1.785 / 2.400 kcal (74%).\nRestam: 615 kcal para comida.\nExercício registrado: 0 kcal. Esse gasto não aumenta o que resta para comida.\nProteína: 126 / 150 g (84%). Faltam 24 g.'

describe('C7 official Today presentation, with no calculation or model', () => {
  it.each([
    {
      protocol: 'recomposicao' as const,
      balance: 'Déficit de 1.115',
      phase:
        'Bloco 7.700: 3.120 / 7.700 kcal (41%). Referência teórica de déficit acumulado.\nBlocos concluídos: 2.',
      close: 'Nesta fase, o foco é repetir dias bem executados até fechar o bloco.',
    },
    {
      protocol: 'ganho_massa' as const,
      balance: 'Déficit de 501',
      phase: 'O Bloco 7.700 é exibido apenas na recomposição corporal.',
      close: 'Aqui, o progresso vem da repetição consistente do estímulo — não da balança.',
    },
    {
      protocol: 'manutencao' as const,
      balance: 'Déficit de 615',
      phase: 'O Bloco 7.700 é exibido apenas na recomposição corporal.',
      close: 'Na manutenção, o corpo responde à média — não a um dia isolado.',
    },
  ])('renders the full 1785/2400 and 126/150 golden for $protocol', ({
    protocol,
    balance,
    phase,
    close,
  }) => {
    expect(renderFlowDayStatus(day(protocol), 'pt-BR')).toBe(
      `${OPEN_PT}\n\n${DAILY_PT}\nBalanço do dia (parcial): ${balance} kcal.\n${phase}\n\n${close}`,
    )
  })

  it('renders the English recomposition golden using the same official numbers', () => {
    expect(renderFlowDayStatus(day('recomposicao'), 'en')).toBe(
      `${OPEN_EN}\n\nDay status: 2026-10-08\nConsumed: 1,785 / 2,400 kcal (74%).\nRemaining: 615 kcal for food.\nRecorded exercise: 0 kcal. This expenditure does not increase the food remaining.\nProtein: 126 / 150 g (84%). Remaining: 24 g.\nDay balance (partial): Deficit of 1,115 kcal.\nBlock 7,700: 3,120 / 7,700 kcal (41%). Theoretical reference for accumulated deficit.\nCompleted blocks: 2.\n\nIn this phase, the focus is on repeating well-executed days until the block is complete.`,
    )
  })

  it.each([
    'recomposicao',
    'ganho_massa',
    'manutencao',
  ] as const)('renders an observed empty day with targets and unavailable progress for %s', (protocol) => {
    const text = renderFlowDayStatus(day(protocol, { snapshot: null, progress: null }), 'pt-BR')
    expect(text).toContain('Ainda não há refeição ou treino confirmado neste dia.')
    expect(text).toContain('Consumido: 0 / 2.400 kcal (0%).')
    expect(text).toContain('Restam: 2.400 kcal para comida.')
    expect(text).toContain('Proteína: 0 / 150 g (0%). Faltam 150 g.')
    expect(text).not.toMatch(/jeju|não comeu|não treinou|perdeu|Proteína batida|14 dias|DAM/iu)
    if (protocol === 'recomposicao') expect(text).toContain('Bloco 7.700: dados indisponíveis.')
    else expect(text).not.toContain('Blocos concluídos:')
  })

  it('does not confuse a confirmed zero-energy record with no record', () => {
    const text = renderFlowDayStatus(
      day('manutencao', {
        snapshot: null,
        meals: [
          {
            id: 'zero-meal',
            meal_type: 'lanche',
            food_name: 'Água',
            quantity_g: 200,
            kcal: 0,
            protein_g: 0,
            carbs_g: 0,
            fat_g: 0,
            consumed_at: '2026-10-08T15:00:00Z',
          },
        ],
        workouts: [
          {
            id: 'zero-workout',
            workout_type: 'outro',
            duration_min: 1,
            estimated_kcal: 0,
            intensity: null,
            performed_at: '2026-10-08T15:10:00Z',
          },
        ],
      }),
      'pt-BR',
    )
    expect(text).toContain('Consumido: 0 / 2.400 kcal (0%).')
    expect(text).not.toContain('Ainda não há refeição ou treino confirmado')
  })

  it('keeps pending proposals out of confirmed totals and makes review visible', () => {
    const text = renderFlowDayStatus(
      day('manutencao', {
        snapshot: null,
        pendingRegistrations: [
          {
            id: 'pending-a',
            kind: 'meal',
            meal_type: 'almoco',
            created_at: '2026-10-08T17:00:00Z',
            expires_at: '2026-10-09T17:00:00Z',
          },
        ],
      }),
      'pt-BR',
    )
    expect(text).toContain('Há 1 registro pendente de revisão; ele ainda não entra nos totais.')
    expect(text).toContain('Consumido: 0 / 2.400 kcal (0%).')
    expect(text).toContain('Ainda não há refeição ou treino confirmado')
  })

  it('does not call an existing positive total empty just because embedded logs are absent', () => {
    const text = renderFlowDayStatus(day('manutencao'), 'pt-BR')
    expect(text).toContain('Consumido: 1.785 / 2.400 kcal (74%).')
    expect(text).not.toContain('Ainda não há refeição ou treino confirmado')
  })

  it('keeps missing targets and unknown protocol unavailable without fictitious percentages or phase', () => {
    const text = renderFlowDayStatus(
      day(null, {
        snapshot: null,
        calculatedTargets: { calories_target: null, protein_target: null },
        progress: null,
      }),
      'pt-BR',
    )
    expect(text).toContain('Consumido: 0 kcal. Meta indisponível.')
    expect(text).toContain('Proteína: 0 g. Meta indisponível.')
    expect(text).toContain('Balanço do dia: indisponível.')
    expect(text).toContain('Confira os dados do seu objetivo em Perfil.')
    expect(text).not.toMatch(/\d+%|Bloco|fase|manutenção|estímulo|14 dias|DAM/iu)
  })

  it('keeps exercise separate from food remaining and uses the official balance', () => {
    const original = day('recomposicao')
    const text = renderFlowDayStatus(
      { ...original, exercise_kcal: 322, daily_balance_kcal: -1437 },
      'pt-BR',
    )
    expect(text).toContain('Restam: 615 kcal para comida.')
    expect(text).toContain('Exercício registrado: 322 kcal.')
    expect(text).toContain('Balanço do dia (parcial): Déficit de 1.437 kcal.')
    expect(text).toContain('Bloco 7.700: 3.120 / 7.700 kcal (41%).')
  })

  it('uses the current profile for presentation while preserving historical day energy', () => {
    const original = day('recomposicao')
    const text = renderFlowDayStatus(
      {
        ...original,
        current_protocol: 'ganho_massa',
        block_7700: { ...original.block_7700, enabled: false },
      },
      'pt-BR',
    )
    expect(text).toContain('Balanço do dia (parcial): Déficit de 1.115 kcal.')
    expect(text).toContain('O Bloco 7.700 é exibido apenas na recomposição corporal.')
    expect(text).not.toContain('3.120')
    expect(text).toContain(
      'Aqui, o progresso vem da repetição consistente do estímulo — não da balança.',
    )
  })

  it('shows excess and reached protein instead of inventing a negative remaining amount', () => {
    const original = day('manutencao')
    const text = renderFlowDayStatus(
      {
        ...original,
        consumed: { ...original.consumed, calories_kcal: 2500, protein_g: 160 },
        remaining_food_kcal: 0,
        food_excess_kcal: 100,
        protein_status: {
          consumed_g: 160,
          target_g: 150,
          remaining_g: 0,
          percentage: 107,
          status: 'target_reached',
        },
        daily_balance_kcal: 100,
      },
      'pt-BR',
    )
    expect(text).toContain('Consumido: 2.500 / 2.400 kcal (104%).')
    expect(text).toContain('Excedente: 100 kcal de comida.')
    expect(text).toContain('Proteína: 160 / 150 g (107%). Meta atingida.')
    expect(text).toContain('Balanço do dia (parcial): Superávit de 100 kcal.')
    expect(text).not.toContain('Faltam -')
  })

  it.each([
    { status: 'final' as const, expected: 'Balanço do dia (final): Déficit de 615 kcal.' },
    { status: 'insufficient_data' as const, expected: 'Balanço do dia: dados insuficientes.' },
  ])('does not relabel official $status balance as partial', ({ status, expected }) => {
    const original = day('manutencao')
    expect(renderFlowDayStatus({ ...original, daily_balance_status: status }, 'pt-BR')).toContain(
      expected,
    )
  })

  it('shows exact zero balance without assigning a deficit or surplus', () => {
    expect(renderFlowDayStatus({ ...day('manutencao'), daily_balance_kcal: 0 }, 'pt-BR')).toContain(
      'Balanço do dia (parcial): 0 kcal.',
    )
  })

  it('does not mutate Today state when rendering A to B to A', () => {
    const a = day('recomposicao')
    const before = JSON.stringify(a)
    const first = renderFlowDayStatus(a, 'pt-BR')
    renderFlowDayStatus(day('manutencao'), 'en')
    expect(renderFlowDayStatus(a, 'pt-BR')).toBe(first)
    expect(first).toContain('1.785 / 2.400')
    expect(JSON.stringify(a)).toBe(before)
  })

  it('preserves optional official sequence, level and XP without inventing missing progress', () => {
    const official = { currentStreak: 3, level: 4, xpTotal: 500 }
    expect(renderFlowDayStatus(day('manutencao'), 'pt-BR', official)).toContain(
      'Sequência: 3 dias · Nível: 4 · XP: 500.',
    )
    expect(renderFlowDayStatus(day('manutencao'), 'en', official)).toContain(
      'Streak: 3 days · Level: 4 · XP: 500.',
    )
    expect(renderFlowDayStatus(day('manutencao'), 'pt-BR')).not.toMatch(/Sequência|XP/u)
  })

  it.each([
    {
      calories: null,
      protein: 150,
      missing: 'Consumido: 0 kcal. Meta indisponível.',
      known: 'Proteína: 0 / 150 g (0%). Faltam 150 g.',
    },
    {
      calories: 2400,
      protein: null,
      missing: 'Proteína: 0 g. Meta indisponível.',
      known: 'Consumido: 0 / 2.400 kcal (0%).',
    },
  ])('keeps independently missing targets unavailable: %j', ({
    calories,
    protein,
    missing,
    known,
  }) => {
    const text = renderFlowDayStatus(
      day('manutencao', {
        snapshot: null,
        calculatedTargets: { calories_target: calories, protein_target: protein },
      }),
      'pt-BR',
    )
    expect(text).toContain(missing)
    expect(text).toContain(known)
    expect(text).toContain('Confira os dados do seu objetivo em Perfil.')
    expect(text).not.toMatch(/NaN|Infinity|undefined/u)
  })

  it('shows exact reached food and protein targets without an excess or deficit claim', () => {
    const original = day('manutencao')
    const text = renderFlowDayStatus(
      {
        ...original,
        consumed: { ...original.consumed, calories_kcal: 2400, protein_g: 150 },
        remaining_food_kcal: 0,
        food_excess_kcal: 0,
        daily_balance_kcal: 0,
        protein_status: {
          consumed_g: 150,
          target_g: 150,
          remaining_g: 0,
          percentage: 100,
          status: 'target_reached',
        },
      },
      'pt-BR',
    )
    expect(text).toContain('Consumido: 2.400 / 2.400 kcal (100%).')
    expect(text).toContain('Restam: 0 kcal para comida.')
    expect(text).toContain('Proteína: 150 / 150 g (100%). Meta atingida.')
    expect(text).toContain('Balanço do dia (parcial): 0 kcal.')
    expect(text).not.toMatch(/Excedente:|Déficit de|Superávit de/u)
  })

  it('distinguishes an official zero block from an unavailable block', () => {
    const text = renderFlowDayStatus(
      day('recomposicao', {
        progress: { deficitBlock: 0, blocksCompleted: 0, updatedAt: null },
      }),
      'pt-BR',
    )
    expect(text).toContain(
      'Bloco 7.700: 0 / 7.700 kcal (0%). Referência teórica de déficit acumulado.',
    )
    expect(text).toContain('Blocos concluídos: 0.')
    expect(text).not.toContain('dados indisponíveis')
  })

  it('describes only meal and workout absence when the day contains water', () => {
    const text = renderFlowDayStatus(
      day('manutencao', {
        snapshot: {
          caloriesConsumed: 0,
          caloriesTarget: 2400,
          proteinG: 0,
          proteinTarget: 150,
          carbsG: 0,
          fatG: 0,
          exerciseCalories: 0,
          waterConsumedMl: 1000,
          protocol: 'manutencao',
          dayClosed: false,
          dayStatus: null,
          updatedAt: '2026-10-08T17:00:00Z',
        },
      }),
      'pt-BR',
    )
    expect(text).toContain('Ainda não há refeição ou treino confirmado neste dia.')
    expect(text).not.toMatch(/nenhum registro|nada registrado|não bebeu/iu)
  })
})
