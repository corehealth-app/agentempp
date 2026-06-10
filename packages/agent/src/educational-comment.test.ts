import { describe, it, expect } from 'vitest'
import { hasPhantomFoodMention } from './educational-comment.js'

describe('hasPhantomFoodMention', () => {
  const cafe = [
    { food_name: 'leite com whey' },
    { food_name: 'ovo frito' },
    { food_name: 'pao frances' },
    { food_name: 'geleia de morango' },
    { food_name: 'queijo mussarela' },
  ]

  it('flag quando comentário sugere reduzir MANTEIGA inexistente (caso Roberto 2026-06-09)', () => {
    const comment = 'Café com 39g de proteína — começo forte. A gordura ficou elevada (19.6g) — da próxima, se reduzir um pouco da manteiga ou do óleo que tempera os itens, você mantém a saciedade.'
    expect(hasPhantomFoodMention(comment, cafe)).toBe(true)
  })

  it('flag quando sugere reduzir AÇÚCAR inexistente', () => {
    const comment = 'Bom café. Da próxima, reduz o açúcar pra equilibrar mais.'
    expect(hasPhantomFoodMention(comment, cafe)).toBe(true)
  })

  it('NÃO flaga quando sugere reduzir item que ESTÁ na lista', () => {
    const comment = 'Café sólido. O pão francês puxou carboidrato — na próxima reduz pela metade.'
    expect(hasPhantomFoodMention(comment, cafe)).toBe(false)
  })

  it('NÃO flaga menção genérica sem verbo de orientação (manteiga em contexto abstrato)', () => {
    const comment = 'Manteiga e óleo costumam disparar a gordura — você manteve baixo nesse café, parabéns.'
    expect(hasPhantomFoodMention(comment, cafe)).toBe(false)
  })

  it('NÃO flaga quando item está na lista mesmo com variação', () => {
    const itemsComMussarela = [{ food_name: 'queijo mussarela' }]
    const comment = 'O queijo mussarela puxou a gordura — reduz pela metade na próxima.'
    expect(hasPhantomFoodMention(comment, itemsComMussarela)).toBe(false)
  })

  it('flaga BACON quando não está na lista', () => {
    const comment = 'Boa proteína. Da próxima, tira o bacon pra reduzir gordura.'
    expect(hasPhantomFoodMention(comment, cafe)).toBe(true)
  })

  it('NÃO flaga BACON quando está na lista', () => {
    const itemsComBacon = [{ food_name: 'bacon' }, { food_name: 'ovo frito' }]
    const comment = 'Da próxima, reduz o bacon — fica menos gorduroso.'
    expect(hasPhantomFoodMention(comment, itemsComBacon)).toBe(false)
  })

  it('flaga normalmente mesmo lista vazia (caller filtra antes)', () => {
    // Garantia documental: a função em si não defende contra lista vazia.
    // O caller (generateEducationalComment) só chama se items.length > 0.
    const comment = 'reduz a manteiga'
    expect(hasPhantomFoodMention(comment, [])).toBe(true)
  })
})
