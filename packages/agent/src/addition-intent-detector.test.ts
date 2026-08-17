import { describe, expect, it } from 'vitest'
import { detectAdditionInRecentMessages, detectAdditionIntent } from './addition-intent-detector.js'

describe('detectAdditionIntent', () => {
  describe('GATILHO POSITIVO (deve detectar)', () => {
    it('"Segunda fatia" — caso real Luciana 2026-06-10', () => {
      expect(detectAdditionIntent('Segunda fatia')).toBeTruthy()
    })

    it('"Favor acrescentar mais um pedaço de bolo de milho"', () => {
      expect(detectAdditionIntent('Favor acrescentar mais um pedaço de bolo de milho')).toBeTruthy()
    })

    it('"mais uma porção"', () => {
      expect(detectAdditionIntent('mais uma porção')).toBeTruthy()
    })

    it('"outro pedaço"', () => {
      expect(detectAdditionIntent('outro pedaço')).toBeTruthy()
    })

    it('"outra fatia"', () => {
      expect(detectAdditionIntent('outra fatia')).toBeTruthy()
    })

    it('"outro igual"', () => {
      expect(detectAdditionIntent('outro igual')).toBeTruthy()
    })

    it('"mais um copo"', () => {
      expect(detectAdditionIntent('mais um copo')).toBeTruthy()
    })

    it('"+ 1"', () => {
      expect(detectAdditionIntent('+ 1')).toBeTruthy()
    })

    it('"+1"', () => {
      expect(detectAdditionIntent('+1 banana')).toBeTruthy()
    })

    it('"comi mais"', () => {
      expect(detectAdditionIntent('comi mais 1 fatia depois')).toBeTruthy()
    })

    it('"tem mais um"', () => {
      expect(detectAdditionIntent('tem mais um pão no almoço')).toBeTruthy()
    })

    it('"acrescentar"', () => {
      expect(detectAdditionIntent('quero acrescentar mais um item')).toBeTruthy()
    })

    it('"Adicionei 30g de leite em pó ao iogurte" — caso real Roberto', () => {
      expect(detectAdditionIntent('Adicionei 30g de leite em pó ao iogurte')).toBeTruthy()
    })

    it('"dobrei a porção"', () => {
      expect(detectAdditionIntent('dobrei a porção')).toBeTruthy()
    })

    it('"repeti o prato"', () => {
      expect(detectAdditionIntent('repeti o prato')).toBeTruthy()
    })

    it('"também comi"', () => {
      expect(detectAdditionIntent('também comi uma banana')).toBeTruthy()
    })

    it('"agora comi outro"', () => {
      expect(detectAdditionIntent('agora comi outro pão')).toBeTruthy()
    })
  })

  describe('GATILHO NEGATIVO (não deve detectar)', () => {
    it('"era 100g não 200g" — correção, não adição', () => {
      expect(detectAdditionIntent('era 100g não 200g')).toBeFalsy()
    })

    it('"corrige o café, era leite com whey"', () => {
      expect(detectAdditionIntent('corrige o café, era leite com whey')).toBeFalsy()
    })

    it('"não é arroz, é mandioca"', () => {
      expect(detectAdditionIntent('não é arroz, é mandioca')).toBeFalsy()
    })

    it('"esqueci a salada"', () => {
      // borderline mas semanticamente é adição de novo item, não dup; nosso
      // detector é conservador e não pega isso (LLM resolve via "adicionei X")
      expect(detectAdditionIntent('esqueci a salada')).toBeFalsy()
    })

    it('texto vazio', () => {
      expect(detectAdditionIntent('')).toBeNull()
    })

    it('só whitespace', () => {
      expect(detectAdditionIntent('   ')).toBeNull()
    })
  })

  describe('detectAdditionInRecentMessages', () => {
    it('pega gatilho na última msg user', () => {
      const msgs = [
        { role: 'user' as const, content: 'comi um bolo de milho' },
        { role: 'assistant' as const, content: 'Lanche registrado ✅' },
        { role: 'user' as const, content: 'Segunda fatia' },
      ]
      expect(detectAdditionInRecentMessages(msgs)).toBeTruthy()
    })

    it('pega gatilho em msg user anterior dentro da janela', () => {
      const msgs = [
        { role: 'user' as const, content: 'comi outro pedaço' },
        { role: 'assistant' as const, content: 'É mesmo bolo ou outro?' },
        { role: 'user' as const, content: 'isso' },
      ]
      expect(detectAdditionInRecentMessages(msgs)).toBeTruthy()
    })

    it('ignora gatilho em msg do assistant', () => {
      const msgs = [
        { role: 'user' as const, content: 'café com whey' },
        { role: 'assistant' as const, content: 'Quer registrar outra fatia?' },
        { role: 'user' as const, content: 'sim' },
      ]
      expect(detectAdditionInRecentMessages(msgs)).toBeFalsy()
    })

    it('null quando não há msgs user', () => {
      expect(detectAdditionInRecentMessages([])).toBeNull()
    })

    it('respeita window count', () => {
      const msgs = [
        { role: 'user' as const, content: 'mais um pão' }, // 5 msgs atrás
        { role: 'assistant' as const, content: 'ok' },
        { role: 'user' as const, content: 'comi' },
        { role: 'assistant' as const, content: 'ok' },
        { role: 'user' as const, content: 'arroz' },
        { role: 'assistant' as const, content: 'ok' },
        { role: 'user' as const, content: 'feijão' },
      ]
      // janela 2 só vê últimas 2 do user (feijão, arroz) — não pega
      expect(detectAdditionInRecentMessages(msgs, 2)).toBeFalsy()
      // janela 4 alcança "mais um pão"
      expect(detectAdditionInRecentMessages(msgs, 4)).toBeTruthy()
    })
  })
})
