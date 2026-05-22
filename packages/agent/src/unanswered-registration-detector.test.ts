import { describe, it, expect } from 'vitest'
import { looksLikeRegistrationRequest } from './unanswered-registration-detector.js'

describe('looksLikeRegistrationRequest', () => {
  it('flags explicit "Registre meu Almoço" (caso Erika 17/05)', () => {
    expect(
      looksLikeRegistrationRequest({
        content: 'Registre meu Almoço :\n\n300g\nCamarão refogado, purê de batata, feijão e farofa.',
        contentType: 'text',
      }),
    ).toBe(true)
  })

  it('flags meal label with colon ("Almoço :")', () => {
    expect(looksLikeRegistrationRequest({ content: 'Almoço :', contentType: 'text' })).toBe(true)
  })

  it('flags meal label "Café da manhã:" with food', () => {
    expect(
      looksLikeRegistrationRequest({ content: 'Café da manhã: 2 ovos e pão', contentType: 'text' }),
    ).toBe(true)
  })

  it('flags "anota aí" / "adiciona ao café"', () => {
    expect(looksLikeRegistrationRequest({ content: 'anota aí 2 bananas', contentType: 'text' })).toBe(
      true,
    )
    expect(
      looksLikeRegistrationRequest({ content: 'adiciona ao café um pão', contentType: 'text' }),
    ).toBe(true)
  })

  it('flags eating verb ("comi", "jantei")', () => {
    expect(looksLikeRegistrationRequest({ content: 'comi um prato de arroz', contentType: 'text' })).toBe(
      true,
    )
    expect(looksLikeRegistrationRequest({ content: 'jantei frango grelhado', contentType: 'text' })).toBe(
      true,
    )
  })

  it('flags image (food photo) regardless of content', () => {
    expect(looksLikeRegistrationRequest({ content: null, contentType: 'image' })).toBe(true)
  })

  it('flags audio (voice note describing food)', () => {
    expect(looksLikeRegistrationRequest({ content: null, contentType: 'audio' })).toBe(true)
  })

  it('flags EN ("log my lunch") and ES ("registra mi almuerzo")', () => {
    expect(looksLikeRegistrationRequest({ content: 'log my lunch please', contentType: 'text' })).toBe(
      true,
    )
    expect(
      looksLikeRegistrationRequest({ content: 'registra mi almuerzo', contentType: 'text' }),
    ).toBe(true)
  })

  it('does NOT flag a plain question', () => {
    expect(
      looksLikeRegistrationRequest({ content: 'Qual meu balanço de hoje?', contentType: 'text' }),
    ).toBe(false)
  })

  it('does NOT flag a bare food name without verb/label/colon', () => {
    expect(looksLikeRegistrationRequest({ content: 'banana', contentType: 'text' })).toBe(false)
  })

  it('does NOT flag chit-chat that mentions a meal without colon', () => {
    expect(
      looksLikeRegistrationRequest({ content: 'o almoço de ontem estava ótimo', contentType: 'text' }),
    ).toBe(false)
  })

  it('does NOT flag "até" (sem acento) como verbo de comer', () => {
    expect(looksLikeRegistrationRequest({ content: 'ok, ate amanha entao', contentType: 'text' })).toBe(
      false,
    )
  })

  it('does NOT flag empty text message', () => {
    expect(looksLikeRegistrationRequest({ content: '', contentType: 'text' })).toBe(false)
    expect(looksLikeRegistrationRequest({ content: null, contentType: 'text' })).toBe(false)
  })
})
