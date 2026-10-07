import { describe, expect, it } from 'vitest'
import { DEFAULT_CALC_CONFIG } from '../src/calc-config.js'
import { decideSignupEligibility } from '../src/protocol-eligibility.js'
import {
  gainBlockedAboveRangeMessage,
  gainUnavailableBodyFatReason,
  gainUnavailableTrainingReason,
  type ProtocolMessageLocale,
  protocolWelcomeMessage,
  signupAssignedNotice,
} from '../src/protocol-messages.js'
import type { Protocol } from '../src/types.js'

// The exact wording of every text is pinned, in both languages, in
// packages/agent/src/__golden__/audit-10-07-protocol-messages.test.ts. Here:
// the shape of what the functions return and where each variable part goes.

const PROTOCOLS: Protocol[] = ['recomposicao', 'ganho_massa', 'manutencao']
const LOCALES: ProtocolMessageLocale[] = ['pt-BR', 'en-US']

/** Lines of each paragraph: the same in both languages, by protocol. */
const WELCOME_SHAPE: Record<Protocol, number[]> = {
  recomposicao: [2, 3, 1, 2],
  ganho_massa: [1, 1, 4, 3, 1, 1, 2],
  manutencao: [1, 4, 1, 2],
}

describe('protocolWelcomeMessage', () => {
  it.each(
    PROTOCOLS.flatMap((protocol) => LOCALES.map((locale) => [protocol, locale] as const)),
  )('%s in %s: the paragraphs and their lines', (protocol, locale) => {
    const paragraphs = protocolWelcomeMessage(protocol, 'Marina', locale)
    expect(paragraphs.map((paragraph) => paragraph.split('\n').length)).toEqual(
      WELCOME_SHAPE[protocol],
    )
    for (const paragraph of paragraphs) {
      expect(paragraph).toBe(paragraph.trim())
      expect(paragraph).not.toMatch(/\n\n|\n | \n| {2}/)
      for (const line of paragraph.split('\n')) expect(line.length).toBeGreaterThan(0)
    }
  })

  it.each(
    PROTOCOLS.flatMap((protocol) => LOCALES.map((locale) => [protocol, locale] as const)),
  )('%s in %s: the name opens the first paragraph and is nowhere else', (protocol, locale) => {
    const paragraphs = protocolWelcomeMessage(protocol, 'Marina', locale)
    expect(paragraphs[0]?.startsWith('Marina, ')).toBe(true)
    expect(paragraphs.join('\n\n').split('Marina')).toHaveLength(2)
    // The sentence after the name starts in lower case, as the client wrote it.
    expect(paragraphs[0]?.charAt('Marina, '.length)).toMatch(/\p{Ll}/u)
  })

  it('a name is used as one line: trimmed, inner line breaks and runs of spaces as one space', () => {
    const [first] = protocolWelcomeMessage('recomposicao', '  Ana \n\n Clara\t Souza ', 'pt-BR')
    expect(first?.startsWith('Ana Clara Souza, a partir de agora')).toBe(true)
    expect(protocolWelcomeMessage('recomposicao', '  Ana \n\n Clara ', 'pt-BR')).toHaveLength(4)
  })

  it.each([
    ['absent', undefined],
    ['null', null],
    ['empty', ''],
    ['only white space', ' \n\t '],
  ])('name %s: no vocative, the sentence starts with a capital, the rest is the same', (_case, name) => {
    for (const protocol of PROTOCOLS) {
      for (const locale of LOCALES) {
        const named = protocolWelcomeMessage(protocol, 'Marina', locale)
        const unnamed = protocolWelcomeMessage(protocol, name, locale)
        const opening = (named[0] ?? '').slice('Marina, '.length)
        expect(unnamed[0]).toBe(opening.charAt(0).toUpperCase() + opening.slice(1))
        expect(unnamed.slice(1)).toEqual(named.slice(1))
      }
    }
  })

  it('is pure: the same arguments give equal, independent arrays', () => {
    const first = protocolWelcomeMessage('ganho_massa', 'Marina', 'en-US')
    first.push('changed by the caller')
    expect(protocolWelcomeMessage('ganho_massa', 'Marina', 'en-US')).toHaveLength(7)
  })
})

describe('what the sign-up says about its decision', () => {
  it('every text is one paragraph, in both languages', () => {
    for (const locale of LOCALES) {
      expect(signupAssignedNotice(locale)).toHaveLength(1)
      expect(gainBlockedAboveRangeMessage('BF', locale)).toHaveLength(1)
      expect(gainBlockedAboveRangeMessage('IMC', locale)).toHaveLength(1)
      expect(gainUnavailableBodyFatReason(19, locale)).toHaveLength(1)
      expect(gainUnavailableTrainingReason(3, 2, locale)).toHaveLength(1)
    }
  })

  it('the blocking phrase names what decided, and only that', () => {
    expect(gainBlockedAboveRangeMessage('BF', 'pt-BR')[0]).toContain(
      'seu percentual de gordura atual coloca você',
    )
    expect(gainBlockedAboveRangeMessage('BF', 'pt-BR')[0]).not.toContain('IMC')
    expect(gainBlockedAboveRangeMessage('IMC', 'pt-BR')[0]).toContain('seu IMC atual coloca você')
    expect(gainBlockedAboveRangeMessage('IMC', 'pt-BR')[0]).not.toContain('percentual')
    expect(gainBlockedAboveRangeMessage('BF', 'en-US')[0]).toContain(
      'your current body fat percentage places you',
    )
    expect(gainBlockedAboveRangeMessage('BF', 'en-US')[0]).not.toContain('BMI')
    expect(gainBlockedAboveRangeMessage('IMC', 'en-US')[0]).toContain('your current BMI places you')
    expect(gainBlockedAboveRangeMessage('IMC', 'en-US')[0]).not.toContain('percentage')
  })

  it('the body fat reason cites the cut it is given — the one of the decision', () => {
    const man = decideSignupEligibility({
      sex: 'masculino',
      heightCm: 180,
      weightKg: 80,
      bodyFatPercent: 19.5,
      trainingFrequency: 3,
    })
    const woman = decideSignupEligibility({
      sex: 'feminino',
      heightCm: 165,
      weightKg: 62,
      bodyFatPercent: 27.5,
      trainingFrequency: 3,
    })
    if (man.outcome === 'invalid_input' || woman.outcome === 'invalid_input') {
      throw new Error('entrada inválida')
    }
    expect(man.limits.bodyFatGain).toBe(DEFAULT_CALC_CONFIG.bf_limits.masculino.gain)
    expect(gainUnavailableBodyFatReason(man.limits.bodyFatGain, 'pt-BR')[0]).toContain(
      'de até 19%.',
    )
    expect(gainUnavailableBodyFatReason(woman.limits.bodyFatGain, 'pt-BR')[0]).toContain(
      'de até 27%.',
    )
    expect(gainUnavailableBodyFatReason(woman.limits.bodyFatGain, 'en-US')[0]).toContain(
      'of 27% or less.',
    )
    // Another config, another number in the text: nothing is hard-coded.
    expect(gainUnavailableBodyFatReason(18, 'pt-BR')[0]).toContain('de até 18%.')
    expect(gainUnavailableBodyFatReason(18, 'pt-BR')[0]).not.toMatch(/19|27/)
  })

  it('a cut with decimals is written as the language writes it, without trailing zeros', () => {
    expect(gainUnavailableBodyFatReason(18.5, 'pt-BR')[0]).toContain('de até 18,5%.')
    expect(gainUnavailableBodyFatReason(18.5, 'en-US')[0]).toContain('of 18.5% or less.')
    expect(gainUnavailableBodyFatReason(18.25, 'pt-BR')[0]).toContain('de até 18,25%.')
    expect(gainUnavailableBodyFatReason(18.0, 'pt-BR')[0]).toContain('de até 18%.')
  })

  it('the training reason carries the minimum it is given and the sessions the person informed', () => {
    expect(gainUnavailableTrainingReason(3, 2, 'pt-BR')[0]).toContain(
      'pelo menos 3 vezes por semana.',
    )
    expect(gainUnavailableTrainingReason(3, 2, 'pt-BR')[0]).toContain('Você informou 2 por semana.')
    expect(gainUnavailableTrainingReason(3, 0, 'en-US')[0]).toContain('at least 3 times a week.')
    expect(gainUnavailableTrainingReason(3, 0, 'en-US')[0]).toContain('You reported 0 a week.')
    expect(gainUnavailableTrainingReason(4, 3, 'pt-BR')[0]).toContain(
      'pelo menos 4 vezes por semana.',
    )
    expect(gainUnavailableTrainingReason(4, 3, 'pt-BR')[0]).not.toContain('pelo menos 3')
    expect(gainUnavailableTrainingReason(1, 0, 'pt-BR')[0]).toContain(
      'pelo menos 1 vez por semana.',
    )
    expect(gainUnavailableTrainingReason(1, 0, 'en-US')[0]).toContain('at least 1 time a week.')
  })
})
