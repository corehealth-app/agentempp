import { describe, it, expect } from 'vitest'
import { detectFakeWrite } from './fake-write-detector.js'

const CARD = `🔥 Consumido: 1.433 / 1.843 kcal\n🎯 Restam: 410 kcal\n📊 Bloco 7700: 5.757 / 7.700`

describe('detectFakeWrite', () => {
  it('flags fake REGISTRATION: claims registro + card + no tool', () => {
    const r = detectFakeWrite({
      content: `Almoço registrado.\n\n${CARD}`,
      registrationToolCalled: false,
    })
    expect(r.isFake).toBe(true)
    expect(r.kind).toBe('registration')
  })

  it('flags fake CORRECTION: "Corrigido" + card + no tool (caso Roberto 21/05)', () => {
    const r = detectFakeWrite({
      content: `Corrigido.\n\n**Almoço:**\n• Feijão carioca (180 g): 137 kcal\n${CARD}`,
      registrationToolCalled: false,
    })
    expect(r.isFake).toBe(true)
    expect(r.kind).toBe('correction')
  })

  it('flags fake REGISTRATION via "salvo" (Paulo 21/05 jantar perdido)', () => {
    const r = detectFakeWrite({
      content: `Jantar salvo, Paulo.\n• Banana (2 un): 178 kcal\n${CARD}`,
      registrationToolCalled: false,
    })
    expect(r.isFake).toBe(true)
    expect(r.kind).toBe('registration')
  })

  it('flags fake CORRECTION via "substituí"', () => {
    const r = detectFakeWrite({
      content: `Substituí o item, Roberto.\n${CARD}`,
      registrationToolCalled: false,
    })
    expect(r.isFake).toBe(true)
    expect(r.kind).toBe('correction')
  })

  it('flags card de refeição SEM palavra-chave (Roberto 22/05 14:02: "**Almoço:** ... Total refeição: 543")', () => {
    const r = detectFakeWrite({
      content:
        '**Almoço:**\n• Feijão carioca (200 g): 152 kcal | 10g P\n• Arroz (100 g): 128 kcal\n\n**Total refeição: 543 kcal | 55g P | 55g C | 11g G.**',
      registrationToolCalled: false,
    })
    expect(r.isFake).toBe(true)
    expect(r.kind).toBe('registration')
  })

  it('NÃO flaga card de refeição quando a tool FOI chamada', () => {
    const r = detectFakeWrite({
      content: '**Almoço:**\n• Arroz: 128 kcal\n**Total refeição: 543 kcal.**',
      registrationToolCalled: true,
    })
    expect(r.isFake).toBe(false)
  })

  it('does NOT flag when a registration tool WAS called this turn', () => {
    const r = detectFakeWrite({
      content: `Corrigido.\n${CARD}`,
      registrationToolCalled: true,
    })
    expect(r.isFake).toBe(false)
    expect(r.kind).toBe(null)
  })

  it('does NOT flag correction-word WITHOUT food signature (ex: "Sono corrigido")', () => {
    const r = detectFakeWrite({
      content: 'Sono corrigido para 22:30 às 7:30, anotado.',
      registrationToolCalled: false,
    })
    expect(r.isFake).toBe(false)
  })

  it('does NOT flag normal prose without registration/correction claim', () => {
    const r = detectFakeWrite({
      content: `Bom dia! Você está mandando bem. ${CARD}`,
      registrationToolCalled: false,
    })
    expect(r.isFake).toBe(false)
  })

  it('detects card by emoji even without the word "kcal"', () => {
    const r = detectFakeWrite({
      content: 'Corrigido. 💪 Proteína: 114 / 149',
      registrationToolCalled: false,
    })
    expect(r.isFake).toBe(true)
    expect(r.kind).toBe('correction')
  })
})
