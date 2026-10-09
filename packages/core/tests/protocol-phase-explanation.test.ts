import { describe, expect, it } from 'vitest'
import { protocolPhaseExplanation, protocolWelcomeMessage } from '../src/protocol-messages.js'
import type { Protocol } from '../src/types.js'

const PHASES = [
  ['recomposicao', 'recomposição corporal.'],
  ['ganho_massa', 'ganho de massa.'],
  ['manutencao', 'manutenção.'],
] as const

describe('canonical phase explanations for Flow', () => {
  it.each(PHASES)('%s has a complete card within 1800 characters', (protocol, label) => {
    const facts = protocolPhaseExplanation(protocol)
    expect(facts.length).toBeGreaterThanOrEqual(3)
    const card = `### Fase atual do Flow\nObjetivo registrado: ${label}\n\n${facts.join('\n\n')}`
    expect(card.length).toBeLessThanOrEqual(1800)
    for (const fact of facts) {
      expect(fact).toBe(fact.trim())
      expect(fact.length).toBeGreaterThan(0)
    }
    expect(card).not.toMatch(
      /MPP|BodyFlow|Roberto|14 dias|15 dias|\bDAM\b|orçamento|\b\d+[,.]?\d*%|kcal\/kg|BMR|TDEE|agora você entra|a partir de agora/i,
    )
    expect(card).not.toMatch(/eu cuido|garantir|vou (?:ajustar|reduzir|aumentar)|automaticamente/i)
  })

  it('recomposition retains its welcome definition and qualifies the energy reference', () => {
    const facts = protocolPhaseExplanation('recomposicao')
    const definition = protocolWelcomeMessage('recomposicao', null, 'pt-BR')[0]?.split('\n')[1]
    expect(facts).toContain(definition)
    const card = facts.join('\n\n')
    expect(card).toContain('sem extremos e sem improviso')
    expect(card).toContain('7.700 kcal')
    expect(card).toContain('teórica e aproximada')
    expect(card).toContain('não mede a perda individual de gordura')
    expect(card).toContain('não altera a meta de calorias')
    expect(card).toContain('referência de planejamento')
    expect(card).toContain('calibração natural do processo')
  })

  it('gain uses shared training, protein and progress facts before diet changes', () => {
    const facts = protocolPhaseExplanation('ganho_massa')
    const welcome = protocolWelcomeMessage('ganho_massa', null, 'pt-BR')
    expect(facts).toContain(welcome[2]?.split('\n')[0])
    expect(facts).toContain(welcome[1])
    expect(facts).toContain(welcome[4])
    expect(facts).toContain(welcome[5])
    expect(facts.join('\n\n')).toContain('primeiro se audita o treino — depois a dieta')
    expect(facts.join('\n\n')).not.toMatch(/7[.,]700|mini.?cut|bloco|recomposição|manutenção|\d/)
  })

  it('maintenance shares the welcome target and consistency without promising adjustments', () => {
    const facts = protocolPhaseExplanation('manutencao')
    const welcome = protocolWelcomeMessage('manutencao', null, 'pt-BR')
    const targetLines = welcome[1]?.split('\n')
    expect(facts).toContain(targetLines?.[0])
    expect(facts).toContain(targetLines?.[3])
    expect(facts.join('\n\n')).toContain('manutenção não é pausa')
    expect(facts.join('\n\n')).not.toMatch(/7[.,]700|bloco|recomposição|ganho de massa|\d/)
  })

  it.each([
    null,
    undefined,
    '',
    'gain',
    'maintenance',
    'recomp',
    'GANHO_MASSA',
    {},
    0,
  ])('does not assign a phase to %j', (protocol) => {
    expect(protocolPhaseExplanation(protocol)).toEqual([])
  })

  it.each(PHASES)('%s returns independent arrays, without mutable shared selection', (protocol) => {
    const first = protocolPhaseExplanation(protocol)
    const second = protocolPhaseExplanation(protocol)
    expect(first).toEqual(second)
    expect(first).not.toBe(second)
    const mutable = [...first]
    mutable.pop()
    mutable.push('foreign fact')
    expect(protocolPhaseExplanation(protocol)).toEqual(second)
  })

  it('stateless A → B → A never carries another phase', () => {
    const first = protocolPhaseExplanation('recomposicao')
    protocolPhaseExplanation('ganho_massa')
    protocolPhaseExplanation('manutencao')
    expect(protocolPhaseExplanation('recomposicao')).toEqual(first)
  })

  it('the forbidden DAM metric is a word, not a substring of source wording', () => {
    expect('DAM: 6 de 4').toMatch(/\bDAM\b/i)
    expect('dam').toMatch(/\bDAM\b/i)
    expect('indiscriminadamente').not.toMatch(/\bDAM\b/i)
  })

  it('every phase keeps its existing full PT/EN welcome separate from recurring facts', () => {
    for (const [protocol] of PHASES) {
      for (const locale of ['pt-BR', 'en-US'] as const) {
        const before = protocolWelcomeMessage(protocol as Protocol, 'Ana\nClara', locale)
        protocolPhaseExplanation(protocol)
        expect(protocolWelcomeMessage(protocol as Protocol, 'Ana\nClara', locale)).toEqual(before)
      }
    }
  })
})
