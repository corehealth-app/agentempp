import { describe, it, expect } from 'vitest'
import { detectCorrectionIntent } from './correction-detector.js'

describe('detectCorrectionIntent', () => {
  describe('PT — detecta correção legítima', () => {
    it('"corrige o café"', () => {
      expect(detectCorrectionIntent(['corrige o café da manhã'])).toMatch(/corrig/i)
    })
    it('"errei, na verdade era leite"', () => {
      expect(detectCorrectionIntent(['errei, na verdade era leite com whey'])).toBeTruthy()
    })
    it('"troca o achocolatado"', () => {
      expect(detectCorrectionIntent(['troca o achocolatado por whey'])).toMatch(/troca/i)
    })
    it('"não é achocolatado, é leite com whey"', () => {
      expect(
        detectCorrectionIntent(['Não é achocolatado quente, é leite com whey']),
      ).toBeTruthy()
    })
    it('"era 200g não 150g"', () => {
      expect(detectCorrectionIntent(['na verdade era 200g não 150g'])).toBeTruthy()
    })
    it('"esqueci de mandar o ovo"', () => {
      expect(detectCorrectionIntent(['esqueci de mandar o ovo'])).toMatch(/esqueci/i)
    })
  })

  describe('EN — detecta correção', () => {
    it('"actually it was 2 eggs"', () => {
      expect(detectCorrectionIntent(['actually it was 2 eggs'])).toBeTruthy()
    })
    it('"sorry, I meant 100g"', () => {
      expect(detectCorrectionIntent(['sorry, I meant 100g'])).toBeTruthy()
    })
    it('"fix the breakfast"', () => {
      expect(detectCorrectionIntent(['fix the breakfast please'])).toMatch(/fix/i)
    })
  })

  describe('ES — detecta corrección', () => {
    it('"en realidad era leche"', () => {
      expect(detectCorrectionIntent(['en realidad era leche con whey'])).toBeTruthy()
    })
    it('"me equivoqué"', () => {
      expect(detectCorrectionIntent(['perdón, me equivoqué'])).toBeTruthy()
    })
  })

  describe('NÃO detecta em mensagens sem correção (críticos)', () => {
    it('foto enviada (sem texto)', () => {
      expect(detectCorrectionIntent([''])).toBe(null)
    })
    it('paciente cumprimenta', () => {
      expect(detectCorrectionIntent(['oi tudo bem?'])).toBe(null)
    })
    it('paciente pergunta sobre meta', () => {
      expect(
        detectCorrectionIntent(['quantos pães posso comer pra bater minha meta?']),
      ).toBe(null)
    })
    it('paciente fala do café como NOVO registro', () => {
      // Roberto enviando café da manhã sem nenhuma palavra de correção
      expect(detectCorrectionIntent(['café da manhã: pão, ovo, leite'])).toBe(null)
    })
    it('descrição de padrão alimentar', () => {
      expect(
        detectCorrectionIntent(['costumo comer pão de queijo no café']),
      ).toBe(null)
    })
  })

  describe('Múltiplas mensagens — basta uma ter palavra', () => {
    it('correção na 2a msg', () => {
      expect(
        detectCorrectionIntent(['oi', 'na verdade comi 2 ovos, não 1']),
      ).toBeTruthy()
    })
  })
})
