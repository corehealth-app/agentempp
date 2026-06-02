import { describe, expect, it } from 'vitest'
import {
  detectFalseDuplicationClaim,
  isLiterallyDuplicated,
} from './false-duplication-detector.js'

describe('isLiterallyDuplicated', () => {
  it('falso pra msg curta normal', () => {
    expect(isLiterallyDuplicated('fiz musculação')).toBe(false)
  })

  it('falso pra lista com múltiplos itens distintos (caso Roberto 02/06)', () => {
    expect(
      isLiterallyDuplicated('fiz 45 min de musculação e 19 min de bicicleta'),
    ).toBe(false)
  })

  it('falso pra texto cortado (não é dup)', () => {
    expect(
      isLiterallyDuplicated('Uma colher de sopa rasa de semente de abóbora crua e descasca'),
    ).toBe(false)
  })

  it('falso pra texto longo com 4 itens diferentes (caso Luciana 30/05)', () => {
    const txt = `200 gramas de carne de churrasco
30 gramas de batata chips
1 bola de sorvete de doce de leite
2 taças pequenas de bebida ( mimosa )`
    expect(isLiterallyDuplicated(txt)).toBe(false)
  })

  it('true quando msg é literal repetida ("foo foo")', () => {
    expect(isLiterallyDuplicated('comi um pao integral comi um pao integral')).toBe(true)
  })

  it('true quando uma linha aparece 2x', () => {
    expect(isLiterallyDuplicated('arroz com feijao\narroz com feijao')).toBe(true)
  })
})

describe('detectFalseDuplicationClaim', () => {
  it('flaga quando LLM acusa "veio duplicado" + paciente mandou msg distinta', () => {
    expect(
      detectFalseDuplicationClaim(
        'Veio duplicado — registro 1 vez cada, certo?',
        'fiz 45 min de musculação e 19 min de bicicleta',
      ),
    ).toBe(true)
  })

  it('flaga "parece que a lista veio duplicada"', () => {
    expect(
      detectFalseDuplicationClaim(
        'Parece que a lista veio duplicada — confirma?',
        '200g carne / 30g batata / 1 sorvete',
      ),
    ).toBe(true)
  })

  it('NÃO flaga quando paciente realmente duplicou (msg repetida)', () => {
    expect(
      detectFalseDuplicationClaim(
        'Veio duplicada — uma vez só?',
        'arroz com feijao\narroz com feijao',
      ),
    ).toBe(false)
  })

  it('NÃO flaga quando LLM não acusa duplicação', () => {
    expect(
      detectFalseDuplicationClaim(
        'Beleza, vou registrar.',
        'fiz musculação e bicicleta',
      ),
    ).toBe(false)
  })
})
