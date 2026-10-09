import { protocolPhaseExplanation } from '@mpp/core'
import { describe, expect, it } from 'vitest'
import { flowLanguageCards } from './flow-language-policy.js'

const PHASES = [
  ['recomposicao', 'recomposição corporal.'],
  ['ganho_massa', 'ganho de massa.'],
  ['manutencao', 'manutenção.'],
] as const

function phaseSegment(stable: string): string {
  const marker = '### Fase atual do Flow\n'
  const position = stable.indexOf(marker)
  return position < 0 ? '' : stable.slice(position)
}

describe('C6 canonical phase cards in the stable Flow context', () => {
  it.each(PHASES)('%s includes its source facts once, within its own budget', (protocol, label) => {
    const cards = flowLanguageCards(protocol, true)
    const phase = phaseSegment(cards.stable)
    expect(phase).toContain(`Objetivo registrado: ${label}`)
    expect(phase.match(/### Fase atual do Flow/g)).toHaveLength(1)
    expect(phase.match(/Objetivo registrado:/g)).toHaveLength(1)
    for (const fact of protocolPhaseExplanation(protocol)) expect(phase).toContain(fact)
    expect(phase.length).toBeLessThanOrEqual(1800)
    expect(cards.stable.slice(0, cards.stable.indexOf(phase)).trimEnd().length).toBeLessThanOrEqual(
      2700,
    )
    expect(cards.situation.length).toBeLessThanOrEqual(200)
    for (const [other, otherLabel] of PHASES) {
      if (other !== protocol) expect(phase).not.toContain(`Objetivo registrado: ${otherLabel}`)
    }
    expect(phase).not.toMatch(/MPP|BodyFlow|Roberto|14 dias|15 dias|DAM|orçamento/)
  })

  it.each(PHASES)('%s has the same stable facts with and without assistant history', (protocol) => {
    const empty = flowLanguageCards(protocol, false)
    const loaded = flowLanguageCards(protocol, true)
    expect(empty.stable).toBe(loaded.stable)
    expect(empty.situation).toBe('')
    expect(loaded.situation.length).toBeGreaterThan(0)
  })

  it.each([
    null,
    undefined,
    'gain',
    'maintenance',
    'RECOMPOSICAO',
    {},
    0,
  ])('keeps the language policy without assigning a phase for %j', (protocol) => {
    const cards = flowLanguageCards(protocol, false)
    expect(cards.stable).toContain('### Linguagem do Flow')
    expect(phaseSegment(cards.stable)).toBe('')
    expect(cards.stable).not.toContain('7.700')
  })

  it('A → B → A is stateless and does not keep the prior card', () => {
    const a = flowLanguageCards('recomposicao', false)
    const b = flowLanguageCards('ganho_massa', true)
    expect(b.stable).not.toContain('7.700')
    expect(flowLanguageCards('recomposicao', true).stable).toBe(a.stable)
  })
})
