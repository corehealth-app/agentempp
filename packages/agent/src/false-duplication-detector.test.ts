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

  // Casos novos 2026-06-02 — LLM aprende sinônimos
  it('pega "repetiu os mesmos itens duas vezes" (caso Luciana 02/06 13:31 BRT)', () => {
    expect(
      detectFalseDuplicationClaim(
        'Anotado! Só confirma — você repetiu os mesmos itens duas vezes. Foi uma porção só?',
        '90 gramas de arroz\n140 de carne moída',
      ),
    ).toBe(true)
  })

  it('pega "veio em duas mensagens"', () => {
    expect(
      detectFalseDuplicationClaim(
        'Parece que veio em duas mensagens — registro só uma vez?',
        '90g arroz\n140g carne',
      ),
    ).toBe(true)
  })

  it('pega "você mandou os mesmos itens duas vezes"', () => {
    expect(
      detectFalseDuplicationClaim(
        'Você mandou os mesmos itens duas vezes — confirma só uma porção?',
        'arroz\ncarne moída',
      ),
    ).toBe(true)
  })
})
