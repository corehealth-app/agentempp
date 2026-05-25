import { describe, it, expect } from 'vitest'
import {
  hasBalanceCard,
  injectCanonicalCard,
  renderBalanceCard,
  replaceLooseBlockMentions,
  stripBalanceCard,
} from './balance-card.js'

describe('renderBalanceCard — formato canônico', () => {
  it('REGRA MPP (Roberto 2026-05-21): Restam = meta − consumido, exercício NÃO entra', () => {
    // consumed 1301, target 1843, exercise 565.
    // Restam (comida) = 1843 - 1301 = 542. O exercício NÃO soma no Restam —
    // vai pro bloco e aparece anotado na linha 🏃🏻.
    const card = renderBalanceCard({
      caloriesConsumed: 1301,
      caloriesTarget: 1843,
      proteinG: 98,
      proteinTarget: 148,
      exerciseCalories: 565,
      deficitBlock: 5254,
      protocol: 'recomposicao',
    })
    expect(card).toContain('🔥 Consumido: **1.301 / 1.843 kcal (71%)**')
    expect(card).toContain('🎯 Restam: **542 kcal**')
    expect(card).toContain('💪 Proteína: **98 / 148g (66%)**')
    expect(card).toContain('🏃🏻 Exercício: **565 kcal** _(acelera o bloco 7700)_')
    expect(card).toContain('📊 Bloco 7700: **5.254 / 7.700 kcal (68%)**')
  })

  it('Roberto 2026-05-20: comeu 1407 (meta 1843) + 467 exercício → Restam 436, NÃO 903', () => {
    // O exercício (467) NÃO infla o "Restam". Restam = 1843 - 1407 = 436.
    const card = renderBalanceCard({
      caloriesConsumed: 1407,
      caloriesTarget: 1843,
      proteinG: 102.4,
      proteinTarget: 149,
      exerciseCalories: 467,
      deficitBlock: 4967,
      protocol: 'recomposicao',
    })
    expect(card).toContain('🎯 Restam: **436 kcal**')
    expect(card).not.toContain('903')
    expect(card).toContain('🏃🏻 Exercício: **467 kcal** _(acelera o bloco 7700)_')
  })

  it('comeu acima da meta → Excedente = consumido − meta (exercício à parte)', () => {
    // consumed 2076, target 1843 → Excedente comida = 233. O exercício (565)
    // vai pro bloco, mas o "Excedente de comida" continua 233 (regra MPP nova).
    const card = renderBalanceCard({
      caloriesConsumed: 2076,
      caloriesTarget: 1843,
      proteinG: 182.1,
      proteinTarget: 149,
      exerciseCalories: 565,
      deficitBlock: 5254,
      protocol: 'recomposicao',
    })
    expect(card).toContain('🎯 Excedente: **233 kcal**')
    expect(card).not.toContain('Restam')
  })

  it('recomp em excedente real sem exercício — mostra Excedente', () => {
    const card = renderBalanceCard({
      caloriesConsumed: 1935,
      caloriesTarget: 1843,
      proteinG: 81,
      proteinTarget: 148,
      exerciseCalories: 0,
      deficitBlock: 3794,
      protocol: 'recomposicao',
    })
    expect(card).toContain('🎯 Excedente: **92 kcal**')
    expect(card).toContain('🔥 Consumido: **1.935 / 1.843 kcal (105%)**')
  })

  it('Bloco 7700 = 0 → mostra 0%', () => {
    const card = renderBalanceCard({
      caloriesConsumed: 500,
      caloriesTarget: 1500,
      proteinG: 20,
      proteinTarget: 100,
      exerciseCalories: 0,
      deficitBlock: 0,
      protocol: 'recomposicao',
    })
    expect(card).toContain('📊 Bloco 7700: **0 / 7.700 kcal (0%)**')
  })

  it('manutenção — orçamento 14d em vez de bloco', () => {
    const card = renderBalanceCard({
      caloriesConsumed: 1500,
      caloriesTarget: 1800,
      proteinG: 90,
      proteinTarget: 120,
      exerciseCalories: 200,
      deficitBlock: 0,
      protocol: 'manutencao',
      last14d: { consumed_total: 21000, target_total: 25200, dam: 1500, days_with_data: 14 },
    })
    expect(card).toContain('📊 Orçamento 14d: **21.000 / 25.200 kcal (83%)** · DAM: 1500/14')
    expect(card).not.toContain('Bloco 7700')
  })
})

describe('hasBalanceCard / stripBalanceCard / injectCanonicalCard', () => {
  const sampleCard =
    '🔥 Consumido: **1.301 / 1.843 kcal (71%)**\n🎯 Restam: **542 kcal**\n💪 Proteína: **98 / 148g (66%)**'

  it('detecta presença de card via emoji + Consumido', () => {
    expect(hasBalanceCard('Almoço ok. ' + sampleCard)).toBe(true)
    expect(hasBalanceCard('Texto sem card')).toBe(false)
  })

  it('strip remove TODAS as linhas do card mas preserva preâmbulo e comentário', () => {
    const text =
      'Almoço registrado.\n\n' +
      '• Arroz (100g): 128 kcal\n\n' +
      sampleCard +
      '\n🏃🏻 Exercício: **0 kcal**\n\n' +
      'Bom progresso, manda mais.'
    const stripped = stripBalanceCard(text)
    expect(stripped).toContain('Almoço registrado.')
    expect(stripped).toContain('Arroz (100g): 128 kcal')
    expect(stripped).toContain('Bom progresso, manda mais.')
    expect(stripped).not.toContain('🔥 Consumido')
    expect(stripped).not.toContain('🎯 Restam')
    expect(stripped).not.toContain('🏃🏻 Exercício')
  })

  it('inject SUBSTITUI o card alucinado pelo canônico', () => {
    const llmText =
      'Almoço ok.\n\n' +
      '🔥 Consumido: **1.935 / 1.843 kcal (105%)**\n' +
      '🎯 Excedente: **92 kcal**\n' +
      '💪 Proteína: **81 / 148g (55%)**\n\n' +
      'Bom dia.'
    const canonical = renderBalanceCard({
      caloriesConsumed: 1448,
      caloriesTarget: 1843,
      proteinG: 81,
      proteinTarget: 148,
      exerciseCalories: 565,
      deficitBlock: 5254,
      protocol: 'recomposicao',
    })
    const out = injectCanonicalCard(llmText, canonical)
    expect(out).toContain('🔥 Consumido: **1.448 / 1.843 kcal (79%)**')
    // Restam (comida) = 1843 - 1448 = 395 (exercício NÃO entra — regra MPP)
    expect(out).toContain('🎯 Restam: **395 kcal**')
    expect(out).not.toContain('1.935')
    expect(out).not.toContain('Excedente: **92 kcal**')
    expect(out).toContain('Bom dia.')
  })

  it('inject ANEXA card quando texto não tinha card', () => {
    const llmText = 'Almoço registrado. Tabela de itens aqui.'
    const canonical = '🔥 Consumido: **500 / 1500 kcal (33%)**'
    const out = injectCanonicalCard(llmText, canonical)
    expect(out).toContain('Almoço registrado.')
    expect(out).toContain('🔥 Consumido')
  })
})

describe('replaceLooseBlockMentions — menções soltas de Bloco 7700', () => {
  it('substitui "Bloco 7700: **3.000 / 7.700 kcal (39%)**" pelo real', () => {
    const t = 'Comentário motivacional. 📊 Bloco 7700: **3.000 / 7.700 kcal** (39%) — bom ritmo.'
    const out = replaceLooseBlockMentions(t, 3794)
    expect(out.replacements).toBe(1)
    expect(out.text).toContain('Bloco 7700: **3.794 / 7.700 kcal** (49%)')
    expect(out.text).not.toContain('3.000')
  })

  it('substitui menção solta "X / 7.700" sem prefixo Bloco', () => {
    const t = 'Você está em 3000 / 7700 kcal acumulados — quase metade.'
    const out = replaceLooseBlockMentions(t, 3794)
    expect(out.replacements).toBe(1)
    expect(out.text).toContain('3.794 / 7.700')
  })

  it('NÃO substitui se diferença pequena (<100 kcal e <5%)', () => {
    const t = '📊 Bloco 7700: **3.790 / 7.700 kcal** (49%)'
    const out = replaceLooseBlockMentions(t, 3794) // diff 4 kcal
    expect(out.replacements).toBe(0)
    expect(out.text).toContain('3.790')
  })

  it('NÃO toca quando texto não tem menção a Bloco/7700', () => {
    const t = 'Comeu bem hoje, parabéns.'
    const out = replaceLooseBlockMentions(t, 3794)
    expect(out.replacements).toBe(0)
    expect(out.text).toBe(t)
  })

  it('substitui múltiplas ocorrências no mesmo texto', () => {
    const t = 'Você está em 3.000 / 7.700 agora. Faltam pouco pro Bloco 7700: 3.000 kcal de 7.700.'
    const out = replaceLooseBlockMentions(t, 3794)
    expect(out.replacements).toBeGreaterThanOrEqual(2)
    expect(out.text).not.toContain('3.000')
  })

  // Bug Roberto 2026-05-25: engagement "bom dia" disse "2.958 de 7.700 (38%)" quando
  // o real era 1.235 (16%). O guard NÃO pegou porque a frase tinha palavras entre
  // "bloco 7700" e o número ("agora em") e usava "de" no lugar de "/".
  it('Roberto 2026-05-25: "bloco 7700 agora em 2.958 kcal de 7.700 (38%)" → corrige p/ real', () => {
    const t =
      'Ontem você fechou com **479 kcal de déficit** — saldo no bloco 7700 agora em **2.958 kcal de 7.700** (38%).'
    const out = replaceLooseBlockMentions(t, 1235)
    expect(out.replacements).toBeGreaterThanOrEqual(1)
    expect(out.text).not.toContain('2.958')
    expect(out.text).toContain('1.235')
    expect(out.text).not.toContain('38%')
    expect(out.text).toContain('16%')
  })
})
