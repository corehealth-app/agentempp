import { describe, it, expect } from 'vitest'
import {
  composePostRegistrationMessage,
  formatMealTable,
  isPureRegistrationTurn,
  type MealItem,
} from './post-registration-message.js'

const item = (over: Partial<MealItem>): MealItem => ({
  name: 'arroz branco cozido',
  quantity_g: 100,
  display_qty: 100,
  display_unit: 'g',
  kcal: 128,
  protein_g: 2,
  carbs_g: 28,
  fat_g: 0,
  ...over,
})

describe('formatMealTable', () => {
  it('monta tabela canônica (label + itens + total, 4 macros)', () => {
    const out = formatMealTable(
      'almoco',
      [
        item({ name: 'filé grelhado', display_qty: 150, display_unit: 'g', kcal: 270, protein_g: 39, carbs_g: 0, fat_g: 12 }),
        item({ name: 'ovo cozido', display_qty: 2, display_unit: 'unidades', quantity_g: 100, kcal: 146, protein_g: 13, carbs_g: 1, fat_g: 10 }),
      ],
      { kcal: 416, protein_g: 52, carbs_g: 1, fat_g: 22 },
    )
    expect(out).toContain('**Almoço:**')
    expect(out).toContain('• *filé grelhado (150g):* 270 kcal | 39g proteína | 0g carboidrato | 12g gordura')
    // unidade natural quando não é grama
    expect(out).toContain('• *ovo cozido (2 unidades):* 146 kcal | 13g proteína | 1g carboidrato | 10g gordura')
    expect(out).toContain('**Total: 416 kcal | 52g proteína | 1g carboidrato | 22g gordura**')
  })

  it('macro fracionado mostra 1 casa', () => {
    const out = formatMealTable('cafe', [item({ name: 'água de coco', kcal: 22, protein_g: 0.5, carbs_g: 5, fat_g: 0 })], {
      kcal: 22,
      protein_g: 0.5,
      carbs_g: 5,
      fat_g: 0,
    })
    expect(out).toContain('0.5g proteína')
  })
})

describe('isPureRegistrationTurn (gatilho do curto-circuito determinístico)', () => {
  const ok = { name: 'registra_refeicao', result: { success: true } }
  it('só registra_refeicao com sucesso, sem pergunta → true', () => {
    expect(isPureRegistrationTurn([ok], 'comi arroz com feijão')).toBe(true)
  })
  it('registra_treino com sucesso → true', () => {
    expect(isPureRegistrationTurn([{ name: 'registra_treino', result: { success: true } }], 'corri 5km')).toBe(true)
  })
  it('refeição + treino juntos → true', () => {
    expect(isPureRegistrationTurn([ok, { name: 'registra_treino', result: {} }], 'almocei e treinei')).toBe(true)
  })
  it('paciente fez pergunta ("?") → false (LLM responde)', () => {
    expect(isPureRegistrationTurn([ok], 'comi arroz, tá bom isso?')).toBe(false)
  })
  it('outra tool no turno (ex: define_protocolo) → false', () => {
    expect(isPureRegistrationTurn([ok, { name: 'define_protocolo', result: {} }], 'oi')).toBe(false)
  })
  it('tool de registro com erro → false', () => {
    expect(isPureRegistrationTurn([{ name: 'registra_refeicao', error: 'boom' }], 'comi x')).toBe(false)
  })
  it('nenhuma tool → false', () => {
    expect(isPureRegistrationTurn([], 'oi')).toBe(false)
  })
  it('texto nulo (foto/áudio sem texto) → true', () => {
    expect(isPureRegistrationTurn([ok], null)).toBe(true)
  })
})

describe('composePostRegistrationMessage', () => {
  it('refeição (recomp) → frase fixa + tabela + card com Bloco 7700', () => {
    const msg = composePostRegistrationMessage({
      registrations: [
        {
          tool: 'registra_refeicao',
          mealType: 'almoco',
          items: [item({ name: 'feijão preto cozido', display_qty: 80, display_unit: 'g', kcal: 92, protein_g: 6, carbs_g: 16, fat_g: 0 })],
          totals: { kcal: 92, protein_g: 6, carbs_g: 16, fat_g: 0 },
        },
      ],
      card: {
        caloriesConsumed: 1100,
        caloriesTarget: 1843,
        proteinG: 80,
        proteinTarget: 149,
        exerciseCalories: 0,
        deficitBlock: 1235,
        protocol: 'recomposicao',
      },
    })
    expect(msg.startsWith('Almoço registrado ✅')).toBe(true)
    expect(msg).toContain('**Almoço:**')
    expect(msg).toContain('🔥 Consumido: **1.100 / 1.843 kcal (60%)**')
    expect(msg).toContain('🎯 Restam: **743 kcal**')
    expect(msg).toContain('📊 Bloco 7700: **1.235 / 7.700 kcal (16%)**')
  })

  it('excedente → linha 🎯 Excedente', () => {
    const msg = composePostRegistrationMessage({
      registrations: [
        {
          tool: 'registra_refeicao',
          mealType: 'jantar',
          items: [item({ name: 'pizza', kcal: 900, protein_g: 30, carbs_g: 100, fat_g: 40 })],
          totals: { kcal: 900, protein_g: 30, carbs_g: 100, fat_g: 40 },
        },
      ],
      card: {
        caloriesConsumed: 2000,
        caloriesTarget: 1500,
        proteinG: 90,
        proteinTarget: 120,
        exerciseCalories: 0,
        deficitBlock: 500,
        protocol: 'recomposicao',
      },
    })
    expect(msg).toContain('🎯 Excedente: **500 kcal**')
  })

  it('treino → frase fixa + resumo + card', () => {
    const msg = composePostRegistrationMessage({
      registrations: [
        { tool: 'registra_treino', workoutType: 'corrida', durationMin: 30, kcalBurned: 250 },
      ],
      card: {
        caloriesConsumed: 800,
        caloriesTarget: 1159,
        proteinG: 50,
        proteinTarget: 94,
        exerciseCalories: 250,
        deficitBlock: 4879,
        protocol: 'recomposicao',
      },
    })
    expect(msg.startsWith('Treino registrado ✅')).toBe(true)
    expect(msg).toContain('🏋️ corrida (30 min) — 250 kcal')
    expect(msg).toContain('🏃🏻 Exercício: **250 kcal** _(acelera o bloco 7700)_')
  })

  it('treino deduped (alreadyLogged) → "já estava registrado", sem linha de kcal', () => {
    const msg = composePostRegistrationMessage({
      registrations: [{ tool: 'registra_treino', workoutType: 'caminhada', durationMin: 60, alreadyLogged: true }],
      card: {
        caloriesConsumed: 1000,
        caloriesTarget: 1041,
        proteinG: 72,
        proteinTarget: 87,
        exerciseCalories: 168,
        deficitBlock: 1846,
        protocol: 'recomposicao',
      },
    })
    expect(msg).toContain('Treino registrado ✅')
    expect(msg).toContain('_(já estava registrado)_')
    expect(msg).not.toContain('🏋️')
  })

  it('alreadyLogged (dedup) → sem tabela, só confirmação + card', () => {
    const msg = composePostRegistrationMessage({
      registrations: [{ tool: 'registra_refeicao', mealType: 'cafe', alreadyLogged: true }],
      card: {
        caloriesConsumed: 300,
        caloriesTarget: 1458,
        proteinG: 20,
        proteinTarget: 120,
        exerciseCalories: 0,
        deficitBlock: 0,
        protocol: 'recomposicao',
      },
    })
    expect(msg).toContain('Café registrado ✅')
    expect(msg).toContain('_(já estava registrado)_')
    expect(msg).not.toContain('**Café:**')
  })
})
