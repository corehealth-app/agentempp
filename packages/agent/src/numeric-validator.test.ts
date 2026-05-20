import { describe, it, expect } from 'vitest'
import { validateNumericClaims, reconcileBalanceProse } from './numeric-validator.js'

const ctx = { protein_target: 178.2, calories_target: 1843 }

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
