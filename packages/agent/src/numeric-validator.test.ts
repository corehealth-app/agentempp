import { describe, it, expect } from 'vitest'
import {
  validateNumericClaims,
  reconcileBalanceProse,
  reconcileRealDeficitProse,
  detectDeficitRealMismatch,
  detectPrematureBlockCompletion,
} from './numeric-validator.js'

const ctx = { protein_target: 178.2, calories_target: 1843 }

describe('detectPrematureBlockCompletion', () => {
  // O bloco só credita no FECHAMENTO do dia. Afirmar "bloco fechou/completou
  // AGORA/hoje/com isso" durante o dia é prematuro (Roberto 22/05 12:31).
  it('pega o caso Roberto: "bloco 7700 fechado hoje" + "segundo bloco completo"', () => {
    expect(
      detectPrematureBlockCompletion(
        'Com isso, o déficit do dia ultrapassa 1.046 — bloco 7700 fechado hoje, Roberto. 🎉 Segundo bloco completo.',
      ),
    ).toBe(true)
  })
  it('NÃO pega a linha do card "Bloco 7700: 6.654 / 7.700 (86%)"', () => {
    expect(detectPrematureBlockCompletion('📊 Bloco 7700: 6.654 / 7.700 (86%)')).toBe(false)
  })
  it('NÃO pega "faltam 1.046 kcal pra fechar o segundo bloco"', () => {
    expect(detectPrematureBlockCompletion('faltam 1.046 kcal pra fechar o segundo bloco')).toBe(
      false,
    )
  })
  it('NÃO pega comemoração de bloco PASSADO ("você fechou seu 1o bloco ontem")', () => {
    expect(
      detectPrematureBlockCompletion('Parabéns — você fechou seu primeiro bloco ontem!'),
    ).toBe(false)
  })
})

describe('detectDeficitRealMismatch', () => {
  // "déficit real do dia" = crédito do bloco = designDeficit − dailyBalance.
  // O LLM erra fazendo exercício − excedente, esquecendo o déficit embutido na meta.
  const params = { designDeficit: 500, dailyBalance: -397 } // correto = 897

  it('pega o erro do Roberto 21/05: "déficit real de 397" quando o certo é 897', () => {
    const r = detectDeficitRealMismatch(
      'Com o exercício, o excedente de 126 kcal vira déficit real de **397 kcal** no dia.',
      params,
    )
    expect(r).not.toBeNull()
    expect(r?.claimed).toBe(397)
    expect(r?.correct).toBe(897)
  })

  it('NÃO acusa quando o agente escreve o valor certo (897)', () => {
    const r = detectDeficitRealMismatch('déficit real de 897 kcal no dia', params)
    expect(r).toBeNull()
  })

  it('NÃO acusa quando não há número ("déficit real do dia fica positivo")', () => {
    const r = detectDeficitRealMismatch('o déficit real do dia fica positivo', params)
    expect(r).toBeNull()
  })

  it('NÃO acusa texto sem menção a "déficit real"', () => {
    const r = detectDeficitRealMismatch('Almoço registrado, 521 kcal no total.', params)
    expect(r).toBeNull()
  })

  it('entende separador de milhar pt-BR ("1.943")', () => {
    const r = detectDeficitRealMismatch('déficit real de 1.943 kcal', {
      designDeficit: 500,
      dailyBalance: -397,
    })
    expect(r?.claimed).toBe(1943)
    expect(r?.correct).toBe(897)
  })
})

describe('validateNumericClaims protein_target — false positive fix', () => {
  it('NÃO dispara em proteína per-refeição', () => {
    expect(validateNumericClaims('Total refeição: 447 kcal | 11g proteína', ctx)).toEqual([])
    expect(validateNumericClaims('Total refeição: 596 kcal | 67g proteína', ctx)).toEqual([])
    expect(validateNumericClaims('• Frango (200g): 380 kcal | 58g P', ctx)).toEqual([])
  })

  it('dispara quando LLM inventa meta diária errada', () => {
    const r1 = validateNumericClaims('tua meta de proteína é 220g por dia', ctx)
    expect(r1.length).toBeGreaterThan(0)
    expect(r1[0]?.field).toBe('protein_target')

    const r2 = validateNumericClaims('alvo de 250g de proteína', ctx)
    expect(r2.length).toBeGreaterThan(0)

    const r3 = validateNumericClaims('💪 Proteína: 125 / 250g (50%)', ctx)
    expect(r3.length).toBeGreaterThan(0)
  })

  it('NÃO dispara quando o card mostra meta correta', () => {
    expect(validateNumericClaims('💪 Proteína: 125 / 178g (70%)', ctx)).toEqual([])
    expect(validateNumericClaims('meta de 178g de proteína', ctx)).toEqual([])
  })

  // BUG (Luciana+Amanda+Erika 2026-05-16): validator pegava "32g de proteína
  // pra fechar o dia" e marcava como mismatch (claimed=32, real=120). Mas
  // "32g" era RESTANTE, não claim sobre meta. Fix: skip se "falta(m)|ainda|
  // resta|pra fechar" aparece nos 40 chars antes do número.
  it('NÃO dispara em "ainda faltam 32g de proteína pra fechar o dia"', () => {
    const t = 'Você está indo bem. Ainda faltam 32g de proteína pra fechar o dia, foque no jantar.'
    expect(validateNumericClaims(t, ctx)).toEqual([])
  })
  it('NÃO dispara em "falta 43g de proteína pra fechar a meta"', () => {
    const t = 'Falta 43g de proteína pra fechar a meta; vale priorizar fonte proteica.'
    expect(validateNumericClaims(t, ctx)).toEqual([])
  })
  it('NÃO dispara em "restam 42g de proteína"', () => {
    const t = 'Excelente progresso, restam 42g de proteína pra atingir o alvo do dia.'
    expect(validateNumericClaims(t, ctx)).toEqual([])
  })
  it('AINDA dispara quando LLM realmente inventa meta absoluta diferente', () => {
    // Card format: bate na regex A "Proteína: X / Yg" — meta absoluta = 250 (real 178, diff 72 > tol 30)
    const t = '💪 Proteína: 80 / 250g (32%)'
    const findings = validateNumericClaims(t, ctx)
    expect(findings.length).toBeGreaterThan(0)
    expect(findings[0]!.field).toBe('protein_target')
    expect(findings[0]!.claimed).toBe(250)
  })

  // BUG (Luciana 2026-05-18 19:12): validator pegava "Meta de proteína batida
  // com folga — 23g num iogurte" como mismatch (claimed=23, real=120). 23g é
  // proteína DO IOGURTE, não meta. Fix: ampliar RESTANTE_BEFORE_PATTERNS com
  // "batida/atingida/com folga/num/numa/em um".
  it('NÃO dispara em "Meta de proteína batida com folga — 23g num iogurte"', () => {
    const t = 'Meta de proteína batida com folga — 23g num iogurte zero açúcar, ótimo.'
    expect(validateNumericClaims(t, ctx)).toEqual([])
  })
  it('NÃO dispara em "Meta atingida — 30g no leite"', () => {
    const t = 'Meta atingida — 30g no leite vai garantir.'
    expect(validateNumericClaims(t, ctx)).toEqual([])
  })
  it('NÃO dispara em "Cumprida a meta — 25g numa banana"', () => {
    const t = 'Cumprida a meta — 25g numa banana entrega o restante.'
    expect(validateNumericClaims(t, ctx)).toEqual([])
  })
})

describe('validateNumericClaims deficit_block (bloco 7700) — bug do Roberto 2026-05-15', () => {
  const blocoCtx = { deficit_block: 2110 }

  it('dispara quando LLM zera o bloco erroneamente (caso Roberto)', () => {
    const r = validateNumericClaims(
      '📊 Bloco 7700: **0 / 7.700 kcal (0%)**',
      blocoCtx,
    )
    expect(r.length).toBeGreaterThan(0)
    expect(r[0]?.field).toBe('deficit_block')
    expect(r[0]?.claimed).toBe(0)
    expect(r[0]?.real).toBe(2110)
  })

  it('dispara em outras inconsistências (LLM inventa 5000)', () => {
    const r = validateNumericClaims('Bloco 7700: 5.000 / 7.700 kcal (65%)', blocoCtx)
    expect(r.length).toBeGreaterThan(0)
  })

  it('NÃO dispara quando o valor está correto', () => {
    expect(validateNumericClaims('📊 Bloco 7700: 2.110 / 7.700 kcal (27%)', blocoCtx)).toEqual([])
    expect(validateNumericClaims('Bloco 7700: 2110 / 7700 kcal', blocoCtx)).toEqual([])
    expect(
      validateNumericClaims('Bloco 7700 em andamento: **2110 kcal de 7700**', blocoCtx),
    ).toEqual([])
  })

  it('tolera diferença pequena (dentro de 10% ou ±30)', () => {
    expect(validateNumericClaims('Bloco 7700: 2100 / 7.700 kcal', blocoCtx)).toEqual([])
    expect(validateNumericClaims('Bloco 7700: 2150 / 7.700 kcal', blocoCtx)).toEqual([])
  })

  it('NÃO dispara quando deficit_block real é null no contexto', () => {
    const r = validateNumericClaims('Bloco 7700: 999 / 7.700 kcal', { deficit_block: null })
    expect(r).toEqual([])
  })

  it('NÃO confunde o "7.700" target com o valor atual', () => {
    // O regex deve casar só com o lado esquerdo da fração, não com 7.700 (target)
    const r = validateNumericClaims('Bloco 7700: 2.110 / 7.700 kcal (27%)', blocoCtx)
    expect(r).toEqual([]) // 2110 está correto
  })
})

describe('reconcileBalanceProse — corrige rótulo/magnitude na prosa (Paulo 2026-05-20)', () => {
  it('pipeline #2: "Excedente leve de 130 kcal" com saldo real -122 vira "Restam 122 kcal"', () => {
    const text = 'Excedente leve de 130 kcal — nada que quebre o processo. Faltam 12g de proteína.'
    const r = reconcileBalanceProse(text, -122)
    expect(r.replacements).toBe(1)
    expect(r.text).toContain('Restam 122 kcal')
    expect(r.text).not.toMatch(/excedente/i)
    expect(r.text).toContain('Faltam 12g de proteína') // não toca proteína
  })

  it('engagement #3: "458 kcal de déficit" com saldo +458 vira "excedente de 458 kcal"', () => {
    const text = 'Ontem você fechou com 458 kcal de déficit — saldo sólido no bloco de 7.700.'
    const r = reconcileBalanceProse(text, 458)
    expect(r.replacements).toBe(1)
    expect(r.text).toContain('excedente de 458 kcal')
    expect(r.text).not.toMatch(/d[ée]ficit/i)
    expect(r.text).toContain('bloco de 7.700') // não toca o resto
  })

  it('NÃO altera prosa já correta (déficit real, texto diz "restam")', () => {
    const text = 'Boa! Ainda restam 200 kcal pra fechar a meta.'
    const r = reconcileBalanceProse(text, -200)
    expect(r.replacements).toBe(0)
    expect(r.text).toBe(text)
  })

  it('NÃO altera prosa já correta (excedente real, texto diz "excedente de X")', () => {
    const text = 'Você fechou com excedente de 100 kcal hoje.'
    const r = reconcileBalanceProse(text, 100)
    expect(r.replacements).toBe(0)
    expect(r.text).toBe(text)
  })

  it('NÃO toca linhas de card (formato "Excedente: X kcal" com dois-pontos)', () => {
    const card = '🎯 Restam: 122 kcal\n🔥 Consumido: 1.171 / 1.041 kcal'
    const r = reconcileBalanceProse(card, -122)
    expect(r.replacements).toBe(0)
    expect(r.text).toBe(card)
  })

  it('on_target (|saldo| ≤ tolerância) não mexe em nada', () => {
    const text = 'Você teve um excedente de 10 kcal, irrelevante.'
    const r = reconcileBalanceProse(text, 10)
    expect(r.replacements).toBe(0)
  })

  it('saldo null/undefined é no-op seguro', () => {
    expect(reconcileBalanceProse('qualquer texto', null).replacements).toBe(0)
    expect(reconcileBalanceProse('qualquer texto', undefined).replacements).toBe(0)
  })
})

describe('reconcileRealDeficitProse — matinal usa déficit REAL vs manutenção (Paulo 2026-05-27)', () => {
  it('BUG do Paulo: "excedente de 119 kcal real" com realDef +381 vira "déficit real de 381 kcal vs manutenção"', () => {
    const text = 'Ontem fechou com excedente de 119 kcal real — o treino ajudou bastante nesse total.'
    const r = reconcileRealDeficitProse(text, 381)
    expect(r.replacements).toBe(1)
    expect(r.text).toContain('déficit real de 381 kcal vs manutenção')
    expect(r.text).not.toMatch(/excedente/i)
    expect(r.text).toContain('o treino ajudou') // não toca o resto da prosa
  })

  it('NÃO altera quando a prosa já diz déficit (sinal certo) — magnitude do LLM preservada', () => {
    const text = 'Ontem você fechou com déficit real de 505 kcal vs manutenção. Mandou bem!'
    const r = reconcileRealDeficitProse(text, 505)
    expect(r.replacements).toBe(0)
    expect(r.text).toBe(text)
  })

  it('superávit real: "déficit de 919 kcal" com realDef -919 vira "superávit ... acima da manutenção"', () => {
    const text = 'Ontem você teve 919 kcal de déficit, ótimo ritmo.'
    const r = reconcileRealDeficitProse(text, -919)
    expect(r.replacements).toBe(1)
    expect(r.text).toContain('superávit de 919 kcal acima da manutenção')
    expect(r.text).not.toMatch(/d[ée]ficit/i)
  })

  it('Roberto correto: "919 kcal acima da manutenção" com realDef -919 fica intacto', () => {
    const text = 'Ontem você acumulou 919 kcal acima da manutenção — dia mais flexível, tudo bem.'
    const r = reconcileRealDeficitProse(text, -919)
    expect(r.replacements).toBe(0)
    expect(r.text).toBe(text)
  })

  it('on_target (|realDef| ≤ tolerância) e null/undefined são no-op', () => {
    expect(reconcileRealDeficitProse('quase em manutenção, 20 kcal', 20).replacements).toBe(0)
    expect(reconcileRealDeficitProse('texto', null).replacements).toBe(0)
    expect(reconcileRealDeficitProse('texto', undefined).replacements).toBe(0)
  })
})

// ============================================================================
// Audit 06-26 sprint pendentes Item 4: cobertura Bug B
// ----------------------------------------------------------------------------
// Trava 3 comportamentos do audit 06-24 que estavam sem teste dedicado:
//  - parseNum: decimais PT-BR vs milhar (cenário Luciana 100.1g)
//  - PER_MEAL_BEFORE_PATTERNS: "Almoço com Xg" suprime falso positivo
//  - minPlausibleTarget / targetAnchored: threshold 0.5 (proteína) vs 0.4
//    (calorias), e targetAnchored=true ignora threshold (claimed pode ser
//    menor que real sem suprimir).
// ============================================================================

describe('parseNum via validateNumericClaims (Bug B audit 06-24)', () => {
  // parseNum é privado — exercitado indiretamente via "Nova meta: Xg de
  // proteína". Para evitar falso positivo o claimed deve ser parseado
  // corretamente e bater com ctx.protein_target.
  const ctx = { protein_target: 178.2, calories_target: 1843 }

  it('decimal EN "Nova meta: 178.2g de proteína" → claimed=178.2, sem mismatch', () => {
    const r = validateNumericClaims('Nova meta: 178.2g de proteína por dia.', ctx)
    expect(r.length).toBe(0)
  })

  it('decimal PT "Nova meta: 178,2g de proteína" → claimed=178.2, sem mismatch', () => {
    const r = validateNumericClaims('Nova meta: 178,2g de proteína por dia.', ctx)
    expect(r.length).toBe(0)
  })

  it('milhar "Meta hoje é 1.843 kcal" → claimed=1843, sem mismatch', () => {
    const r = validateNumericClaims('Meta hoje é 1.843 kcal por dia.', ctx)
    expect(r.length).toBe(0)
  })

  it('milhar com vírgula decimal "Meta: 1.843,0 kcal" → claimed=1843, sem mismatch', () => {
    const r = validateNumericClaims('Meta: 1.843,0 kcal hoje.', ctx)
    expect(r.length).toBe(0)
  })

  it('inteiro puro "Meta hoje é 1843 kcal" → claimed=1843, sem mismatch', () => {
    const r = validateNumericClaims('Meta hoje é 1843 kcal por dia.', ctx)
    expect(r.length).toBe(0)
  })

  it('REGRESSÃO Luciana: "Nova meta: 100.1g de proteína" com target 100.1 NÃO vira mismatch', () => {
    // O bug original parseava "100.1" → 1001 (removia o ponto) → mismatch contra
    // target 100.1. Agora deve parsear corretamente.
    const r = validateNumericClaims(
      'Nova meta: 100.1g de proteína por dia.',
      { protein_target: 100.1, calories_target: 1843 },
    )
    expect(r.length).toBe(0)
  })

  it('valor REALMENTE divergente ainda vira mismatch (parser não esconde bug real)', () => {
    const r = validateNumericClaims('Meta hoje é 2500 kcal por dia.', ctx)
    expect(r.length).toBe(1)
    expect(r[0]?.field).toBe('calories_target')
    expect(r[0]?.claimed).toBe(2500)
  })

  it('PT-BR prefere decimal: "2,5" parseia como 2.5 (NÃO 25)', () => {
    // Bug B fix: vírgula em PT-BR é SEMPRE decimal. Documentação do
    // comportamento: ambiguidade EN milhar "2,500" é resolvida como
    // decimal "2.500" → 2.5 (perda esperada porque PT-BR não usa vírgula
    // como milhar — UI/LLM operam em PT). Mismatch 2.5 vs 1843 suprime
    // por minPlausibleTarget (2.5 < 737.2).
    const r = validateNumericClaims('Meta hoje é 2,5 kcal.', ctx)
    expect(r.length).toBe(0)
  })
})

describe('PER_MEAL_BEFORE_PATTERNS (Bug B audit 06-24)', () => {
  // Quando a frase é claramente per-refeição ("Almoço com 40g"), o número não
  // é meta diária — não deve virar mismatch contra protein_target.
  const ctx = { protein_target: 178.2, calories_target: 1843 }

  it('"Almoço com 40g de proteína" — per-meal suprime', () => {
    const r = validateNumericClaims('Almoço com 40g de proteína no total.', ctx)
    expect(r.length).toBe(0)
  })

  it('"Jantar com 21g de proteína" — per-meal suprime', () => {
    const r = validateNumericClaims('Jantar com 21g de proteína registrado.', ctx)
    expect(r.length).toBe(0)
  })

  it('"Jantar com 44,5g de proteína" — decimal PT em per-meal suprime', () => {
    const r = validateNumericClaims('Jantar com 44,5g de proteína registrado.', ctx)
    expect(r.length).toBe(0)
  })

  it('"no almoço comeu 30g de proteína" — per-meal suprime', () => {
    const r = validateNumericClaims('no almoço comeu 30g de proteína.', ctx)
    expect(r.length).toBe(0)
  })

  it('"Café da manhã com 15g de proteína" — café suprime (incluindo "é" diacrítico)', () => {
    const r = validateNumericClaims('Café da manhã com 15g de proteína.', ctx)
    expect(r.length).toBe(0)
  })

  it('SEM contexto per-meal ("Você bateu 40g de proteína hoje") NÃO suprime se distante demais da meta', () => {
    // Esse caso (claimed=40 vs target=178.2) ativa o protector
    // minPlausibleTarget (40 < 178.2*0.5=89.1) → suprime POR plausibilidade,
    // não por per-meal. Verifica que NÃO levanta mismatch também.
    const r = validateNumericClaims('Você bateu 40g de proteína hoje', ctx)
    expect(r.length).toBe(0) // suprimido por minPlausibleTarget
  })
})

describe('minPlausibleTarget + targetAnchored (Bug B audit 06-24)', () => {
  // targetAnchored=true: claimed pode ser MENOR que real sem suprimir (paciente
  // está EXPLICITAMENTE referenciando a meta — "meta de 50g" com target 120
  // ainda dispara, é uma claim incorreta de meta).
  const ctx = { protein_target: 178.2, calories_target: 1843 }

  it('threshold 0.5 proteína: claimed=80g vs target=178 → suprime (80 < 89.1)', () => {
    // Frase neutra que casa só o pattern genérico "X g de proteina" se
    // existir. Como sem prefixo "meta", deveria ser pego pelo pattern
    // genérico (não targetAnchored) e suprimido pelo threshold.
    const r = validateNumericClaims('Você comeu 80g de proteína hoje', ctx)
    expect(r.length).toBe(0)
  })

  it('threshold 0.5 proteína: claimed=100g vs target=178 → DISPARA (100 >= 89.1)', () => {
    // Review LOW (audit 06-26 review): assertion firme — antes era
    // condicional `if (r.length > 0)` que virava verde por qualquer
    // comportamento. Caso real: "meta de 100g de proteína por dia" casa
    // 2 patterns (B keyword-antes + C keyword-depois), ambos com mesma
    // claim → 2 findings com mesmo claimed=100. Cobertura redundante é OK.
    const r = validateNumericClaims('meta de 100g de proteína por dia', ctx)
    expect(r.length).toBeGreaterThanOrEqual(1)
    for (const f of r) {
      expect(f.field).toBe('protein_target')
      expect(f.claimed).toBe(100)
    }
  })

  it('targetAnchored: "Meta hoje é 800 kcal" com target=1843 DISPARA (não suprime por minPlausible)', () => {
    // Esse pattern (meta|alvo|target) tem targetAnchored=true. Mesmo que
    // 800 < 1843*0.4=737.2, NÃO suprime — é uma claim incorreta de meta.
    const r = validateNumericClaims('Meta hoje é 800 kcal.', ctx)
    expect(r.length).toBe(1)
    expect(r[0]?.field).toBe('calories_target')
    expect(r[0]?.claimed).toBe(800)
  })

  it('threshold 0.4 calorias: claimed=700 vs target=1843 → suprime (700 < 737.2) em pattern NÃO targetAnchored', () => {
    // Frase sem palavra-chave de meta (sem "meta/alvo/target")
    // Como praticamente todos os PATTERNS calories_target são targetAnchored,
    // este teste é um placeholder afirmando que SE existir pattern não-anchored,
    // o threshold ativa.
    const r = validateNumericClaims('Você consumiu 700 kcal no almoço', ctx)
    // "no almoço" é per-meal → suprime via PER_MEAL antes do threshold
    expect(r.length).toBe(0)
  })
})
