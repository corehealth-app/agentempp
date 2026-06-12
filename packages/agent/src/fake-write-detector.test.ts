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

  // Bug Paulo 2026-05-28: "Registrei as duas caminhadas de 60 minutos cada"
  // sem chamar registra_treino → guard antigo passava (zero kcal/emoji); fix:
  // adiciona assinatura de TREINO (duração + tipo).
  it('detects WORKOUT fake write (duração + tipo, sem kcal) — caso Paulo 2026-05-28', () => {
    const r = detectFakeWrite({
      content:
        'Registrei as duas caminhadas de 60 minutos cada. Mas quero confirmar — foram duas sessões separadas hoje (120 minutos no total) ou foi uma única de 60 minutos?',
      registrationToolCalled: false,
    })
    expect(r.isFake).toBe(true)
    expect(r.kind).toBe('registration')
  })

  it('detects workout fake (musculação 40 min, sem kcal)', () => {
    const r = detectFakeWrite({
      content: 'Anotado: musculação de 40 minutos.',
      registrationToolCalled: false,
    })
    expect(r.isFake).toBe(true)
  })

  it('NÃO confunde com prosa que só fala de treino sem afirmar registro', () => {
    const r = detectFakeWrite({
      content: 'Posso te ajudar com sua musculação de 30 minutos hoje?',
      registrationToolCalled: false,
    })
    expect(r.isFake).toBe(false)
  })

  it('detecta proposta-fake genérica: bullets+kcal+Confirma? sem verbo de claim (caso Roberto 2026-05-30 "Entendido! Então incluo também...")', () => {
    const r = detectFakeWrite({
      content:
        'Entendido! Então incluo também o ovo frito e a geleia, completando o café de sempre:\n\n• leite com whey (200 ml): 190 kcal\n• ovo frito (1 unidade): 94 kcal\n• pao frances (1 pão): 150 kcal\n\nTotal: 434 kcal\n\nConfirma?',
      registrationToolCalled: false,
    })
    expect(r.isFake).toBe(true)
    expect(r.kind).toBe('registration')
  })

  it('NÃO flaga pergunta solta com kcal mas sem bullets (ex: "tem 200 kcal? Confirma?")', () => {
    const r = detectFakeWrite({
      content: 'O pão francês tem cerca de 150 kcal. Confirma?',
      registrationToolCalled: false,
    })
    expect(r.isFake).toBe(false)
  })

  it('detecta proposta-fake SEM kcal: bullets com quantidade em (g) + Confirma? (caso Roberto 2026-05-30 14:24 "fica assim: • risoto (200g)...")', () => {
    const r = detectFakeWrite({
      content:
        'Entendido! Então o almoço fica assim:\n\n**Prato principal:**\n• risoto (200g)\n• queijo ralado (30g)\n• fraldinha assada (120g)\n\n**Salada:**\n• alface mista (60g)\n• tomate cereja (50g)\n\nConfirma?',
      registrationToolCalled: false,
    })
    expect(r.isFake).toBe(true)
    expect(r.kind).toBe('registration')
  })

  it('NÃO flaga lista sem quantidades em unidade conhecida (ex: lembrete "Confirma?")', () => {
    const r = detectFakeWrite({
      content:
        'Vou te lembrar de:\n• beber água\n• fazer 30 min de caminhada\n\nConfirma?',
      registrationToolCalled: false,
    })
    expect(r.isFake).toBe(false)
  })

  // Bug Roberto 2026-06-03 15:41: LLM mandou rascunho com kcal inventada +
  // pergunta legítima no fim ("tem proteína?") — escapou de PROPOSAL_QUESTION
  // porque não termina com "Confirma?". Resultado: kcal inventada exibida,
  // depois quando a tool roda no segundo turno as kcal são diferentes e
  // parece bug de consistência. Detector novo: ≥2 bullets "• <nome> (<qty>) — X kcal"
  // + nenhuma tool → fake.
  it('detecta rascunho com kcal inventada + pergunta legítima no fim (Roberto 2026-06-03 15:41)', () => {
    const r = detectFakeWrite({
      content:
        'Entendi isso pro seu almoço:\n\n• alface crespa (40g) — 6 kcal\n• alface roxa (20g) — 3 kcal\n• tomate cereja (60g) — 11 kcal\n• milho em conserva (40g) — 34 kcal\n• molho para salada (15g) — 57 kcal\n\n**Total: 111 kcal | 2.8g proteína | 18.2g carboidrato | 5.8g gordura**\n\nTem proteína nessa refeição? Frango, ovo, atum — algo assim?',
      registrationToolCalled: false,
    })
    expect(r.isFake).toBe(true)
    expect(r.kind).toBe('registration')
  })

  it('NÃO flaga kcal bullet quando a tool FOI chamada (cenário normal)', () => {
    const r = detectFakeWrite({
      content:
        '**Almoço:**\n• alface crespa (40g) — 4 kcal\n• milho (40g) — 14 kcal\n\nTotal: 18 kcal',
      registrationToolCalled: true,
    })
    expect(r.isFake).toBe(false)
  })

  it('NÃO flaga prosa com kcal solta sem padrão bullet+qty+kcal', () => {
    const r = detectFakeWrite({
      content:
        'No geral, o almoço de hoje deve ter entre 400 e 600 kcal. Banana tem cerca de 90 kcal. Como está o seu apetite?',
      registrationToolCalled: false,
    })
    expect(r.isFake).toBe(false)
  })

  // --- Novos detectores: prescrição-fantasma (Sprint 4.1 review 2026-06-12)

  it('flags DIET_FAKE: 2+ headers de refeição + lista de compras + sem gera_dieta', () => {
    const r = detectFakeWrite({
      content: `Café da manhã: ovo mexido (2un), pão integral, café
Almoço: arroz, frango grelhado, salada
Jantar: tilápia, batata-doce

Lista de compras:
- 12 ovos
- 1kg de frango
- pão integral`,
      registrationToolCalled: false,
      prescriptionToolCalled: false,
    })
    expect(r.isFake).toBe(true)
    expect(r.kind).toBe('diet_fake')
  })

  it('flags DIET_FAKE: 2+ refeições + total diário + sem gera_dieta', () => {
    const r = detectFakeWrite({
      content: `Almoço: arroz 100g, frango 150g
Jantar: tilápia 200g, batata-doce 150g
Total diário: 1850 kcal`,
      registrationToolCalled: false,
      prescriptionToolCalled: false,
    })
    expect(r.isFake).toBe(true)
    expect(r.kind).toBe('diet_fake')
  })

  it('NÃO flaga DIET_FAKE quando gera_dieta foi chamada', () => {
    const r = detectFakeWrite({
      content: `Café da manhã: ovo, pão
Almoço: arroz, frango
Lista de compras: ovos, pão, arroz`,
      registrationToolCalled: false,
      prescriptionToolCalled: true,
    })
    expect(r.isFake).toBe(false)
  })

  it('NÃO flaga DIET_FAKE com 1 header só (explicação simples)', () => {
    const r = detectFakeWrite({
      content: 'Almoço: o ideal é ter proteína + carbo + vegetais. Lista de compras curta amanhã.',
      registrationToolCalled: false,
      prescriptionToolCalled: false,
    })
    expect(r.isFake).toBe(false)
  })

  it('flags TRAINING_FAKE: treino A com ≥3 exercícios + sem gera_treino', () => {
    const r = detectFakeWrite({
      content: `Treino A:
- Agachamento 4x10
- Leg press 3x12
- Cadeira extensora 3x15
Treino B: peito e tríceps`,
      registrationToolCalled: false,
      prescriptionToolCalled: false,
    })
    expect(r.isFake).toBe(true)
    expect(r.kind).toBe('training_fake')
  })

  it('flags TRAINING_FAKE: dias da semana + ≥3 exercícios', () => {
    const r = detectFakeWrite({
      content: `Segunda: inferiores
- Agachamento 4x8
- Stiff 3x10
- Cadeira extensora 3x12`,
      registrationToolCalled: false,
      prescriptionToolCalled: false,
    })
    expect(r.isFake).toBe(true)
    expect(r.kind).toBe('training_fake')
  })

  it('NÃO flaga TRAINING_FAKE quando gera_treino foi chamada', () => {
    const r = detectFakeWrite({
      content: `Treino A:
- Agachamento 4x10
- Leg press 3x12
- Cadeira extensora 3x15`,
      registrationToolCalled: false,
      prescriptionToolCalled: true,
    })
    expect(r.isFake).toBe(false)
  })

  it('NÃO flaga TRAINING_FAKE em prosa solta sem ≥3 exercícios', () => {
    const r = detectFakeWrite({
      content:
        'Treino A pode ser pernas, segunda costuma ser o melhor dia. Agachamento 4x10 é base boa.',
      registrationToolCalled: false,
      prescriptionToolCalled: false,
    })
    expect(r.isFake).toBe(false)
  })
})
