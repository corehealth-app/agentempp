import { describe, expect, it } from 'vitest'
import { detectPhantomItems } from './phantom-item-detector.js'

describe('detectPhantomItems', () => {
  it('CASO REAL Amanda 2026-06-11: vinho fantasma após denial banana', () => {
    const r = detectPhantomItems({
      proposedItems: [{ food_name: 'vinho branco' }],
      recentUserMessages: ['Não faz parte'],
      recentAgentTexts: ['Tem uma banana ali no canto — ela faz parte da refeição ou era de outra coisa?'],
    })
    expect(r.phantomItems).toEqual(['vinho branco'])
    expect(r.denialDetected).toBe(true)
    expect(r.shouldBlock).toBe(true)
  })

  it('item legítimo (paciente mencionou) — não phantom', () => {
    const r = detectPhantomItems({
      proposedItems: [{ food_name: 'pão integral' }, { food_name: 'queijo mussarela' }],
      recentUserMessages: ['1 pão integral com queijo mussarela'],
      recentAgentTexts: [],
    })
    expect(r.phantomItems).toEqual([])
    expect(r.shouldBlock).toBe(false)
  })

  it('item identificado via vision (no card do agente, paciente confirmou)', () => {
    const r = detectPhantomItems({
      proposedItems: [{ food_name: 'cuscuz cozido' }],
      recentUserMessages: ['sim'],
      recentAgentTexts: ['Vi isso na sua foto: cuscuz cozido (40g), ovo mexido (2 un)'],
    })
    expect(r.phantomItems).toEqual([])
    expect(r.shouldBlock).toBe(false)
  })

  it('phantom MAS sem negação recente — NÃO bloqueia', () => {
    const r = detectPhantomItems({
      proposedItems: [{ food_name: 'vinho branco' }],
      recentUserMessages: ['ok'],
      recentAgentTexts: [],
    })
    expect(r.phantomItems).toEqual(['vinho branco'])
    expect(r.denialDetected).toBe(false)
    expect(r.shouldBlock).toBe(false) // Só warning, não bloqueia
  })

  it('"esquece esse vinho" como denial — bloqueia próximo phantom (cerveja)', () => {
    // Cenário: paciente disse "esquece esse vinho". Se agente teimar e propor
    // outra bebida não mencionada (cerveja), shouldBlock dispara.
    const r = detectPhantomItems({
      proposedItems: [{ food_name: 'cerveja' }],
      recentUserMessages: ['Esqueça esse vinho e foque no café da manhã'],
      recentAgentTexts: [],
    })
    expect(r.denialDetected).toBe(true)
    expect(r.phantomItems).toEqual(['cerveja'])
    expect(r.shouldBlock).toBe(true)
  })

  it('"não é isso" como denial', () => {
    const r = detectPhantomItems({
      proposedItems: [{ food_name: 'sorvete' }],
      recentUserMessages: ['não é isso, é pudim'],
      recentAgentTexts: [],
    })
    expect(r.denialDetected).toBe(true)
  })

  it('"não" isolado como denial', () => {
    const r = detectPhantomItems({
      proposedItems: [{ food_name: 'banana' }],
      recentUserMessages: ['Não'],
      recentAgentTexts: [],
    })
    expect(r.denialDetected).toBe(true)
  })

  it('match fuzzy: "pão de forma" no input, "pão de forma tostado" na proposta', () => {
    const r = detectPhantomItems({
      proposedItems: [{ food_name: 'pão de forma tostado' }],
      recentUserMessages: ['comi pão de forma com geleia'],
      recentAgentTexts: [],
    })
    expect(r.phantomItems).toEqual([])
  })

  it('items com palavras < 4 chars (ovo, uva) — pelo menos uma palavra ≥ 4 deve aparecer', () => {
    // "ovo cozido" → palavras >=4: "cozido". Paciente disse "ovo".
    // "cozido" não aparece em "ovo" → phantom. Conservador OK.
    const r = detectPhantomItems({
      proposedItems: [{ food_name: 'ovo cozido' }],
      recentUserMessages: ['ovo'],
      recentAgentTexts: [],
    })
    expect(r.phantomItems).toEqual(['ovo cozido'])
  })

  it('múltiplos items: alguns phantom, outros legítimos', () => {
    const r = detectPhantomItems({
      proposedItems: [
        { food_name: 'pão integral' },
        { food_name: 'vinho branco' },
        { food_name: 'queijo mussarela' },
      ],
      recentUserMessages: ['pão integral e queijo'],
      recentAgentTexts: [],
    })
    expect(r.phantomItems).toEqual(['vinho branco'])
  })
})
