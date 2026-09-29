/**
 * Golden test — spoken lead-in kept as part of the food name, staging
 * simulator gate 2026-09-29 13:58 local (QA account A, backend 26f96a9).
 *
 * Exact scenario: imported audio transcribed by the worker (Groq) as
 *   " No almoço eu comi 150 gramas de arroz branco cozido e 120 gramas de frango grelhado."
 * and the review showed the food "No almoço eu comi de arroz branco cozido".
 * An introduction made only of meal/time words and an eating verb is dropped;
 * a food word before the verb is never dropped.
 */
import { describe, expect, it } from 'vitest'
import { draftFromStatedText, parseStatedGrams } from '../meal-draft.js'

describe('audit 2026-09-29 — spoken lead-in before a stated quantity', () => {
  it('the exact transcript gives the two foods with their grams', () => {
    const { raw, rest } = draftFromStatedText(
      ' No almoço eu comi 150 gramas de arroz branco cozido e 120 gramas de frango grelhado.',
    )
    expect(raw).toEqual([
      { name: 'arroz branco cozido', grams_stated: 150 },
      { name: 'frango grelhado', grams_stated: 120 },
    ])
    expect(rest).toEqual([])
  })

  it('other introductions made of meal and time words are dropped', () => {
    for (const [text, name] of [
      ['Hoje no café da manhã eu comi 30 g de aveia', 'aveia'],
      ['No jantar comi 100 g de batata doce', 'batata doce'],
      ['Ontem à noite eu jantei 180 g de carne moída', 'carne moída'],
      ['comi 90 g de pão', 'pão'],
    ] as const) {
      expect(parseStatedGrams(text)?.name, text).toBe(name)
    }
  })

  it('a food word before the verb is kept (nothing is guessed away)', () => {
    expect(parseStatedGrams('frango que eu comi 150 g')?.name).toBe('frango que eu comi')
    expect(parseStatedGrams('Feijão carioca 86,5 g')).toEqual({ name: 'Feijão carioca', grams_stated: 86.5 })
  })
})
