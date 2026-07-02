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

  // Caso Roberto 03/06 12:49 BRT: variante "lista veio igual das duas vezes"
  it('pega "lista veio igual das duas vezes" (caso Roberto 03/06)', () => {
    expect(
      detectFalseDuplicationClaim(
        'Não entendi o que você quer mudar — parece que a lista veio igual das duas vezes.',
        'leite com whey 200ml, ovo frito, pao integral, geleia, queijo',
      ),
    ).toBe(true)
  })

  it('pega "mensagem veio igual"', () => {
    expect(
      detectFalseDuplicationClaim(
        'A mensagem veio igual à anterior — é uma porção só?',
        '90g arroz / 140g carne',
      ),
    ).toBe(true)
  })

  it('pega "as duas mensagens vieram iguais"', () => {
    expect(
      detectFalseDuplicationClaim(
        'As duas mensagens vieram iguais — registro só uma vez?',
        '90g arroz e 140g carne',
      ),
    ).toBe(true)
  })

  it('pega "Recebi as duas mensagens — foi uma sessão..." (Roberto 2026-07-01)', () => {
    expect(
      detectFalseDuplicationClaim(
        'Recebi as duas mensagens — foi uma sessão de 40 minutos ou duas sessões separadas?',
        '40 minutos de musculação',
      ),
    ).toBe(true)
  })

  it('pega "veio igual nas duas vezes"', () => {
    expect(
      detectFalseDuplicationClaim(
        'A lista veio igual nas duas vezes, posso considerar só uma?',
        'arroz feijao carne',
      ),
    ).toBe(true)
  })

  // Verifica que ainda NÃO flaga quando paciente realmente repetiu (variante igual)
  it('NÃO flaga "lista veio igual" quando paciente realmente repetiu (linha 2x)', () => {
    expect(
      detectFalseDuplicationClaim(
        'A lista veio igual nas duas vezes — só uma porção?',
        'arroz com feijao\narroz com feijao',
      ),
    ).toBe(false)
  })
})

describe('detectFalseDuplicationClaim — Amanda 2026-06-11 (sintoma 3)', () => {
  it('pega "Mandou duas vezes — registro uma taça..." sem "você" sem "mesmos itens"', () => {
    expect(
      detectFalseDuplicationClaim(
        'Mandou duas vezes — registro uma taça de 100 ml de suco de laranja no café, certo?',
        '100mL suco de laranja',
      ),
    ).toBe(true)
  })

  it('pega "mandou isso 2 vezes"', () => {
    expect(
      detectFalseDuplicationClaim(
        'Hmm, mandou isso 2 vezes — registro só uma vez, certo?',
        '50g de chocolate',
      ),
    ).toBe(true)
  })

  it('pega "mandou o mesmo item"', () => {
    expect(
      detectFalseDuplicationClaim(
        'Acho que mandou o mesmo item antes — registro só uma vez?',
        '1 maçã',
      ),
    ).toBe(true)
  })

  it('pega variante "percebi que você enviou duas vezes"', () => {
    expect(
      detectFalseDuplicationClaim(
        'Percebi que você enviou duas vezes — registro 1 vez só?',
        'banana',
      ),
    ).toBe(true)
  })

  it('NÃO flaga quando paciente REALMENTE mandou texto duplicado', () => {
    expect(
      detectFalseDuplicationClaim(
        'Mandou duas vezes — registro só uma?',
        'banana\nbanana',
      ),
    ).toBe(false)
  })
})
