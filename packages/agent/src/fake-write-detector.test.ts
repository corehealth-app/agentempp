import { describe, it, expect } from 'vitest'
import {
  ADVERSARIAL_ANSWERS,
  AGREEMENT_ANSWERS,
  GOAL_ONLY_ANSWERS,
  OPEN_LIST_ANSWERS,
  OTHER_RULE_ANSWERS,
  P_GOAL_AND_MEAL,
  PHANTOM_ANSWERS,
} from './__golden__/fixtures/audit-10-04-guard-answers.js'
import { classifyBfGoal } from './bf-goal-classifier.js'
import { detectFakeWrite, inferMealFromSkipText } from './fake-write-detector.js'
import { classifyWeightGoal } from './weight-goal-classifier.js'

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

describe('detectFakeWrite — SKIP claim (bug Roberto 2026-06-15)', () => {
  // Caso REAL: Roberto: "Pulei" → Haiku "Anotado: jantar pulado hoje. Amanhã
  // a gente continua." sem chamar marca_refeicao_pulada. Detector deve
  // flagrar kind='skip' (não 'registration').
  it('flag SKIP quando "Pulei" + LLM diz "Anotado" sem chamar marca_refeicao_pulada', () => {
    const r = detectFakeWrite({
      content: 'Anotado: jantar pulado hoje. Amanhã a gente continua.',
      patientText: 'Pulei',
      registrationToolCalled: false,
      skipToolCalled: false,
      mealTypeHint: 'jantar',
    })
    expect(r.isFake).toBe(true)
    expect(r.kind).toBe('skip')
    expect(r.inferredMealType).toBe('jantar')
  })

  it('flag SKIP quando "Pulei o almoço" — infere meal_type sem hint', () => {
    const r = detectFakeWrite({
      content: 'Anotado: almoço pulado.',
      patientText: 'Pulei o almoço',
      registrationToolCalled: false,
      skipToolCalled: false,
    })
    expect(r.isFake).toBe(true)
    expect(r.kind).toBe('skip')
    expect(r.inferredMealType).toBe('almoco')
  })

  it('NÃO flaga SKIP quando marca_refeicao_pulada foi chamada (happy path)', () => {
    const r = detectFakeWrite({
      content: 'Pulou. Beleza, conta na próxima.',
      patientText: 'Pulei o almoço',
      registrationToolCalled: false,
      skipToolCalled: true,
    })
    expect(r.isFake).toBe(false)
  })

  it('NÃO flaga SKIP em ABANDONMENT "não comi nada hoje" (caso clínico)', () => {
    const r = detectFakeWrite({
      content: 'Entendi, sem dúvida. Vamos focar amanhã.',
      patientText: 'Não comi nada hoje',
      registrationToolCalled: false,
      skipToolCalled: false,
    })
    expect(r.isFake).toBe(false)
  })

  // Review CRITICAL SKIP-FP-NO-CONTENT-GUARD — sem assinatura de skip-ack
  // no content do LLM, NÃO flagrar. Cobre "passei direto pra cama".
  it('NÃO flaga SKIP quando LLM responde coisa conversational ("Boa noite!")', () => {
    const r = detectFakeWrite({
      content: 'Boa noite! Descansa bem.',
      patientText: 'passei direto pra cama',
      registrationToolCalled: false,
      skipToolCalled: false,
    })
    expect(r.isFake).toBe(false)
  })

  it('NÃO flaga SKIP em SKIP_NEGATIVE_CONTEXT "passei direto pra cama"', () => {
    // Mesmo se LLM dissesse "anotado", o NEGATIVE_CONTEXT já bloqueia
    // antes do guard do content. (Defesa em camadas.)
    const r = detectFakeWrite({
      content: 'Anotado.',
      patientText: 'passei direto pra cama',
      registrationToolCalled: false,
      skipToolCalled: false,
    })
    expect(r.isFake).toBe(false)
  })

  it('NÃO flaga SKIP em "jejum intermitente" (cenário clínico real)', () => {
    const r = detectFakeWrite({
      content: 'Tudo bem. Te vejo no almoço então.',
      patientText: 'Estou em jejum intermitente até 12h',
      registrationToolCalled: false,
      skipToolCalled: false,
    })
    expect(r.isFake).toBe(false)
  })

  it('NÃO flaga SKIP em negação de ITEM "não comi banana" — LLM responde social', () => {
    // Sem skip-ack no LLM, não dispara. Mesmo o "não comi" cita item
    // específico, não refeição inteira.
    const r = detectFakeWrite({
      content: 'Beleza, anota o que comeu então.',
      patientText: 'Não comi banana hoje',
      registrationToolCalled: false,
      skipToolCalled: false,
    })
    expect(r.isFake).toBe(false)
  })

  it('inferMealFromSkipText — happy paths', () => {
    expect(inferMealFromSkipText('Pulei o almoço')).toBe('almoco')
    expect(inferMealFromSkipText('Não jantei hoje')).toBe('jantar')
    expect(inferMealFromSkipText('Café da manhã pulado')).toBe('cafe')
    expect(inferMealFromSkipText('Pulei')).toBe(null)
    expect(inferMealFromSkipText('Pulei', 'jantar')).toBe('jantar')
  })
})

// Review 2026-10-04 (WhatsApp reassessment, goal refused by define_protocolo):
// the model answers from the tool result — "Protocolo registrado … a meta não
// foi registrada … 1.746 kcal" — and the generic rule (claim verb + kcal/emoji)
// read it as a meal registered without the tool, forcing a third model call
// that told it to call registra_refeicao. `goalToolCalled` = define_protocolo
// or define_meta_peso wrote, or refused the goal by its floor, in the turn
// (set by pipeline.ts).
//
// Follow-up of the same day: the exemption covers the SENTENCES about the goal
// or the protocol, not the whole answer (second describe below).
describe('detectFakeWrite — turno em que define_protocolo/define_meta_peso gravou', () => {
  // The reviewer's reproduction, verbatim (man 80 kg, 12% body fat, goal 7%).
  const REFUSED_GOAL_WITH_KCAL =
    'Sua nova meta é 1.746 kcal e 118,5 g de proteína por dia. A meta de 7% de gordura corporal não foi registrada: fica abaixo de 10%, que é o limite inferior seguro do método. Posso registrar uma meta a partir de 10%. Qual você prefere?'
  const REFUSED_GOAL_WITH_EMOJI =
    'Protocolo registrado. A meta de 7% de gordura corporal não foi registrada: fica abaixo de 10%. Posso registrar uma meta a partir de 10%. Qual você prefere? 💪'
  // "Before": HEAD already tripped on an accepted goal after define_meta_peso.
  const ACCEPTED_GOAL = 'Meta registrada: 12% de gordura corporal. Vamos focar! 💪'

  const UPDATED_PROTOCOL = 'Protocolo atualizado: recomposição, 1.746 kcal por dia.'
  const CASES = [
    { label: 'recusa com kcal', content: REFUSED_GOAL_WITH_KCAL, kind: 'registration' },
    { label: 'recusa sem kcal terminando em 💪', content: REFUSED_GOAL_WITH_EMOJI, kind: 'registration' },
    { label: 'meta aceita com 💪', content: ACCEPTED_GOAL, kind: 'registration' },
    { label: 'protocolo atualizado com kcal', content: UPDATED_PROTOCOL, kind: 'correction' },
  ] as const

  it.each(CASES)('$label: não é escrita fantasma de refeição quando a tool de protocolo/meta rodou', ({
    content,
  }) => {
    expect(
      detectFakeWrite({ content, registrationToolCalled: false, goalToolCalled: true }),
    ).toEqual({ isFake: false, kind: null })
  })

  it.each(CASES)('$label: sem a tool (ou com a flag ausente) o guard dispara como antes', ({
    content,
    kind,
  }) => {
    expect(detectFakeWrite({ content, registrationToolCalled: false })).toEqual({
      isFake: true,
      kind,
    })
    expect(
      detectFakeWrite({ content, registrationToolCalled: false, goalToolCalled: false }),
    ).toEqual({ isFake: true, kind })
  })

  it('o card de refeição ("Total refeição") continua sendo afirmação de registro, mesmo com a tool de protocolo', () => {
    const content =
      'Protocolo registrado. **Almoço:**\n• arroz (150g)\n• frango (120g)\n**Total refeição: 521 kcal**'
    expect(
      detectFakeWrite({ content, registrationToolCalled: false, goalToolCalled: true }),
    ).toEqual({ isFake: true, kind: 'registration' })
  })

  it('as regras estruturais não mudam com a tool de protocolo: proposta imitada, bullets com kcal e "pulei"', () => {
    expect(
      detectFakeWrite({
        content: 'Vi isso na sua foto (Almoço):\n• arroz (150g)\n• frango (120g)\nConfirma?',
        registrationToolCalled: false,
        goalToolCalled: true,
      }),
    ).toEqual({ isFake: true, kind: 'registration' })
    expect(
      detectFakeWrite({
        content:
          'Entendi isso pro seu almoço:\n• alface crespa (40g) — 6 kcal\n• alface roxa (20g) — 3 kcal\nTem proteína nessa refeição?',
        registrationToolCalled: false,
        goalToolCalled: true,
      }),
    ).toEqual({ isFake: true, kind: 'registration' })
    expect(
      detectFakeWrite({
        content: 'Anotado: jantar pulado.',
        patientText: 'Pulei o jantar',
        registrationToolCalled: false,
        skipToolCalled: false,
        goalToolCalled: true,
      }),
    ).toMatchObject({ isFake: true, kind: 'skip', inferredMealType: 'jantar' })
  })
})

// Independent check of 2026-10-04 on commit 9bc012b, MEDIUM: with the goal
// tool in the turn the generic rule was off for the WHOLE answer, so the texts
// of the incidents that created this guard passed with no retry and no audit
// event. The exemption became per sentence. Second check of the same day,
// HIGH: a sentence was set aside just for naming the goal, and 16 of 45
// phantom answers still passed (second describe below). The rule now, in
// `outsideGoalSentences`: a sentence is set aside only when it has a goal word
// (protocolo, meta, objetivo, IMC, gordura corporal / % de gordura,
// recomposição, ganho de massa, manutenção), no meal-or-workout word, no
// workout signature, every registration/correction verb in it bound to the
// goal noun, and no other word from outside the closed list. Any such verb
// left in the remaining sentences fires.
//
// Texts H1–H3, A1, A2, A7, A8, B1 and B3 are the first checker's probes,
// verbatim (scratchpad review6/probe-head.ts; no patient print exists for a
// goal turn). H1–H3 are the historic texts of the first describe of this file.
//
// > RC R4 — cenário refeição ou treino mostrados SEM verbo de registro próprio na resposta em que o único verbo é o da meta ("Frango com arroz — 430 kcal. Meta registrada 💪", "Meta registrada. Arroz com frango também. 430 kcal 💪", "Arroz com frango: meta registrada — 430 kcal", "Registrei a meta e 430 kcal 💪", "Registrei a meta do dia: 520 kcal de arroz, feijão e frango.") NÃO coberto nesta PR (pendência da audit 2026-10-04).
//   O verbo é explicado pela tool de meta e nenhum outro sobra: quando o texto do paciente no turno não tem palavra de refeição ou treino ("Minha meta agora é 75 kg"), o guard não dispara (no commit pai 279ba09 disparava, pelo verbo da meta). Com a palavra ("Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.") dispara. Os dois lados estão em fake-write-detector.test.ts e no golden. Sem relato de paciente.
// > RC R4 — cenário resposta fiel cujo verbo de registro/correção está numa frase SEM palavra de meta ("Atualizado! Agora são 1.746 kcal por dia 💪", "Registrado! Sua meta agora é 1.746 kcal por dia."), incluída a recusa parafraseada ("Não registrei: 7% fica abaixo de 10%, o limite seguro. Você continua com 1.746 kcal por dia 💪", "Anotado o pedido, mas o percentual de 7% não foi registrado: está abaixo do mínimo de 10% para homens. Você segue com 1.746 kcal por dia 💪") NÃO coberto nesta PR (pendência da audit 2026-10-04).
//   O guard dispara como no commit pai 279ba09: 3ª chamada ao modelo com "chame registra_refeicao" num turno sem refeição. A isenção não foi alargada para esses textos. As duas recusas estão no golden (3 chamadas, 2 eventos); as outras em fake-write-detector.test.ts.
// > RC R4 — cenário resposta fiel cuja frase do verbo cita a meta mas tem verbo não ligado ao nome da meta ("Registrei 75 kg como sua nova meta 💪"), particípio que não concorda com o nome da meta ("Meta registrado: 75 kg. 1.746 kcal por dia 💪"), palavra fora da lista fechada ("Meta registrada, Roberto! 1.746 kcal por dia 💪"), palavra de refeição/treino ("Protocolo registrado com 4 treinos por semana: 1.746 kcal por dia 💪") ou coordenação antes dos dois-pontos ("Protocolo registrado e também: 1.746 kcal por dia 💪") NÃO coberto nesta PR (pendência da audit 2026-10-04).
//   O guard dispara como no commit pai 279ba09 (3ª chamada ao modelo). Na dúvida a frase não é isenta. Caracterizado em fake-write-detector.test.ts.
describe('detectFakeWrite — a isenção da tool de meta vale por frase, não pelo texto inteiro', () => {
  const withGoalTool = (content: string) =>
    detectFakeWrite({ content, registrationToolCalled: false, goalToolCalled: true })

  it.each([
    {
      label: 'H1 "Almoço registrado." + card (Luciana 20/05)',
      content: `Almoço registrado.\n\n${CARD}`,
      kind: 'registration',
    },
    {
      label: 'H2 "Corrigido." + item + card (Roberto 21/05)',
      content: `Corrigido.\n\n**Almoço:**\n• Feijão carioca (180 g): 137 kcal\n${CARD}`,
      kind: 'correction',
    },
    {
      label: 'H3 "Jantar salvo, Paulo." + item + card (Paulo 21/05)',
      content: `Jantar salvo, Paulo.\n• Banana (2 un): 178 kcal\n${CARD}`,
      kind: 'registration',
    },
    {
      label: 'A1 meta registrada + refeição em prosa',
      content:
        'Meta registrada: 75 kg. Almoço registrado: arroz, feijão e frango grelhado — 520 kcal. 💪',
      kind: 'registration',
    },
    {
      label: 'A2 protocolo registrado + "Almoço registrado." + card de balanço',
      content:
        'Protocolo registrado: recomposição.\n\nAlmoço registrado. ✅\n🔥 Consumido: 521 / 1.746 kcal\n💪 Proteína: 38 / 120 g',
      kind: 'registration',
    },
    {
      label: 'A7 meta registrada + treino em prosa, sem kcal (Paulo 28/05)',
      content: 'Meta registrada: 75 kg. Registrei as duas caminhadas de 60 minutos cada.',
      kind: 'registration',
    },
    {
      label: 'A8 meta registrada + correção em prosa',
      content: 'Meta registrada: 75 kg. Corrigido. Feijão 180g — almoço agora com 610 kcal.',
      kind: 'correction',
    },
    {
      label: 'B1 recusa da meta + refeição em prosa',
      content:
        'Não registrei essa meta: 7% fica abaixo de 10%. Almoço registrado: arroz, feijão e frango grelhado — 520 kcal.',
      kind: 'registration',
    },
    {
      label: 'B3 pedido do dado que falta + refeição em prosa',
      content:
        'Preciso do seu percentual de gordura atual antes da meta. Almoço registrado: arroz e frango — 430 kcal.',
      kind: 'registration',
    },
    {
      label: 'meta e refeição na MESMA frase',
      content: 'Meta registrada e almoço registrado — 520 kcal.',
      kind: 'registration',
    },
    {
      label: 'a única kcal está na frase da meta, mas a afirmação cita a refeição',
      content: 'Almoço registrado. Você está em 520 kcal da meta de 1.746.',
      kind: 'registration',
    },
    {
      label: 'verbo solto + duração de treino em outra frase, sem kcal',
      content: 'Meta registrada: 75 kg. Anotado! Foram 60 minutos de caminhada.',
      kind: 'registration',
    },
    {
      label: '"gordura" como macro da refeição não é frase de meta',
      content: 'Registrei: picanha grelhada — 520 kcal, 20 g de gordura.',
      kind: 'registration',
    },
  ] as const)('$label: dispara mesmo com a tool de meta no turno', ({ content, kind }) => {
    expect(withGoalTool(content)).toEqual({ isFake: true, kind })
    // And the tool changes nothing about these texts: same verdict without it.
    expect(detectFakeWrite({ content, registrationToolCalled: false })).toEqual({
      isFake: true,
      kind,
    })
  })

  it('o tipo do retry vem do que sobra, não do verbo da frase de protocolo', () => {
    // "atualizado" belongs to the protocol sentence, which the tool explains:
    // the retry must ask for a registration, not for a replace.
    const content =
      'Protocolo atualizado: recomposição. Almoço registrado: arroz e frango — 430 kcal.'
    expect(withGoalTool(content)).toEqual({ isFake: true, kind: 'registration' })
    expect(detectFakeWrite({ content, registrationToolCalled: false })).toEqual({
      isFake: true,
      kind: 'correction',
    })
  })

  it.each([
    ['meta de peso aceita, com 💪 fora da frase', 'Meta registrada: 75 kg. Vamos focar! 💪'],
    [
      'meta de gordura aceita + a meta diária em kcal',
      'Meta registrada: 15% de gordura corporal. Sua meta diária segue em 1.746 kcal 💪',
    ],
    [
      'recusa com as palavras da tool define_meta_peso',
      'Não registrei essa meta: 7% fica abaixo de 10% de gordura corporal, que é o limite inferior seguro do método. O método não reduz a gordura corporal abaixo de 10%. Nada mudou no seu cadastro. Posso registrar uma meta a partir de 10%. Qual você prefere? 💪',
    ],
    ['objetivo e IMC', 'Objetivo registrado: IMC 23. Seguimos! 💪'],
    [
      'ganho de massa',
      'Protocolo atualizado: ganho de massa. Mantenha os treinos! 3.100 kcal por dia 💪',
    ],
    ['manutenção', 'Registrei a manutenção como seu protocolo. 2.300 kcal por dia.'],
  ])('resposta fiel (%s): a frase de meta/protocolo continua isenta', (_label, content) => {
    expect(withGoalTool(content)).toEqual({ isFake: false, kind: null })
    // Without the tool the same text is a claim with nothing behind it.
    expect(detectFakeWrite({ content, registrationToolCalled: false }).isFake).toBe(true)
  })

  it.each([
    [
      'verbo numa frase sem palavra de meta',
      'Atualizado! Agora são 1.746 kcal por dia 💪',
      'correction',
    ],
    [
      'verbo solto, a meta só na frase seguinte',
      'Registrado! Sua meta agora é 1.746 kcal por dia.',
      'registration',
    ],
    [
      'recusa parafraseada sem "meta" na frase do verbo',
      'Não registrei: 7% fica abaixo de 10%, o limite seguro. Você continua com 1.746 kcal por dia 💪',
      'registration',
    ],
    [
      'recusa que diz "percentual de 7%" em vez de "meta"',
      'Anotado o pedido, mas o percentual de 7% não foi registrado: está abaixo do mínimo de 10% para homens. Você segue com 1.746 kcal por dia 💪',
      'registration',
    ],
    ['verbo não ligado ao nome da meta', 'Registrei 75 kg como sua nova meta 💪', 'registration'],
    [
      'palavra fora da lista fechada (vocativo)',
      'Meta registrada, Roberto! 1.746 kcal por dia 💪',
      'registration',
    ],
    [
      'frase de meta que cita treino',
      'Protocolo registrado com 4 treinos por semana: 1.746 kcal por dia 💪',
      'registration',
    ],
  ] as const)('caracterização (pendência RC R4), resposta fiel — %s: dispara, como no commit pai', (_label, content, kind) => {
    expect(withGoalTool(content)).toEqual({ isFake: true, kind })
    expect(detectFakeWrite({ content, registrationToolCalled: false })).toEqual({
      isFake: true,
      kind,
    })
  })

  it.each([
    'Frango com arroz — 430 kcal. Meta registrada 💪',
    'Meta registrada. Arroz com frango também. 430 kcal 💪',
    'Arroz com frango: meta registrada — 430 kcal',
    'Registrei a meta e 430 kcal 💪',
  ])('caracterização (pendência RC R4), o que ainda passa — %s: a comida não tem verbo próprio', (content) => {
    expect(withGoalTool(content)).toEqual({ isFake: false, kind: null })
    // The parent read the whole text and fired on the goal's verb.
    expect(detectFakeWrite({ content, registrationToolCalled: false })).toEqual({
      isFake: true,
      kind: 'registration',
    })
  })
})

// Second independent check of 2026-10-04 (lens B), HIGH: with the per-sentence
// exemption, 16 of the checker's 45 phantom answers still passed in silence in
// a turn with define_protocolo or define_meta_peso (the parent 279ba09 fired on
// all of them). Every answer below is the checker's, verbatim (scratchpad
// reviewC/lensB/corpus.ts; no patient print exists). The same 16 run through
// processMessage in __golden__/audit-10-04-goal-ladder-floors.test.ts.
describe('detectFakeWrite — segunda checagem: afirmação que não é sobre a meta dispara, mesmo numa frase que cita a meta', () => {
  const withGoalTool = (content: string) =>
    detectFakeWrite({ content, registrationToolCalled: false, goalToolCalled: true })

  it.each([
    // Not declared in the previous round: the verb's sentence names the foods,
    // the sport or the duration, and the only kcal/emoji sits in a goal sentence.
    [
      'M08',
      'Meta registrada: 75 kg. Registrei arroz, feijão e frango grelhado. Você está em 520 kcal da meta de 1.746.',
      'registration',
    ],
    [
      'M09',
      'Protocolo registrado: recomposição. Registrei: arroz (150 g), feijão (100 g) e frango (120 g) — 520 kcal, dentro da sua meta.',
      'registration',
    ],
    [
      'M12',
      'Anotei os 2 ovos e o pão integral. Com isso você soma 780 kcal da meta de 1.746 kcal 💪',
      'registration',
    ],
    [
      'M22',
      'Adicionei ao seu diário: 2 fatias de pizza. Isso dá 560 kcal, e você passa da meta em 120 kcal.',
      'registration',
    ],
    [
      'M27',
      'Anotado: arroz, feijão e frango. Seu objetivo de hoje é 1.746 kcal e você já está em 520 kcal 💪',
      'registration',
    ],
    [
      'M28',
      'Protocolo de manutenção registrado. Também registrei o que você comeu: 520 kcal de 2.500 da manutenção.',
      'registration',
    ],
    ['C05', 'Corrigido: feijão 180 g. Total do dia: 1.433 kcal de 1.843 da meta.', 'correction'],
    ['W09', 'Anotei os 40 minutos de futsal. Meta do dia mantida em 1.746 kcal.', 'registration'],
    // "força" and "peso" are not in the meal-or-workout word list; the
    // duration next to them is the workout signature.
    [
      'W10',
      'Meta registrada: 75 kg. Registrei 40 minutos de força, bom para a meta.',
      'registration',
    ],
    ['W11', 'Registrei 1 hora de peso livre para a sua meta de 75 kg.', 'registration'],
    // Declared as pending in the previous round (bare verb; single sentence).
    ['M11', 'Registrado! Faltam 410 kcal para a meta.', 'registration'],
    [
      'C04',
      'Correção feita. O total de hoje fica em 1.433 kcal, dentro da meta de 1.843.',
      'correction',
    ],
    ['M10', 'Meta registrada e arroz com frango anotado — 430 kcal.', 'registration'],
    ['M18', 'Registrei o frango e o arroz na sua meta de hoje: 430 kcal 💪', 'registration'],
    [
      'M19',
      'Sua meta foi registrada e o frango com arroz do meio-dia também foi anotado. Hoje você está com 430 kcal de 1.746 kcal da meta.',
      'registration',
    ],
    [
      'M20',
      'Meta de 75 kg registrada, e já deixei anotado o pão com ovo de hoje cedo (310 kcal).',
      'registration',
    ],
    // docs/CALCULO-MPP.md said this one fired when it did not (LOW finding).
    [
      'doc',
      'Registrei arroz, feijão e frango grelhado. Você está em 520 kcal da meta de 1.746.',
      'registration',
    ],
  ] as const)('%s: dispara com a tool de meta no turno, com o mesmo tipo de retry de sem ela', (_id, content, kind) => {
    expect(withGoalTool(content)).toEqual({ isFake: true, kind })
    expect(detectFakeWrite({ content, registrationToolCalled: false })).toEqual({
      isFake: true,
      kind,
    })
  })

  it.each([
    ['o objeto do verbo é a comida, a meta vem depois', 'Anotei tudo na meta: 430 kcal 💪'],
    [
      'a comida coordenada com a meta sob o mesmo verbo',
      'Registrei a meta e o frango com arroz: 430 kcal 💪',
    ],
    ['idem, sem artigo', 'Registrei a meta e frango com arroz: 430 kcal 💪'],
    ['idem, em lista com vírgula', 'Registrei sua meta, o arroz e o frango — 430 kcal.'],
    [
      'particípio depois da meta, mas o sujeito é a comida',
      'Salada dentro da meta registrada — 120 kcal 💪',
    ],
    [
      'particípio no plural cobrindo comida e meta',
      'Frango com arroz e meta registrados — 430 kcal.',
    ],
    ['"massa" fora de "ganho de massa" é comida', 'Registrei a meta e a massa: 430 kcal 💪'],
    ['segundo particípio, não ligado à meta', 'Objetivo salvo e pizza salva: 560 kcal.'],
    [
      'treino sem palavra da lista, na frase da meta',
      'Protocolo registrado, 40 minutos de peso livre também.',
    ],
    ['uma linha por afirmação', 'Meta registrada\nFrango anotado\n430 kcal'],
  ])('frase que cita a meta — %s: dispara', (_label, content) => {
    expect(withGoalTool(content).isFake).toBe(true)
  })

  it.each([
    [
      'dois verbos, os dois ligados à meta (frases separadas pelo ":")',
      'Meta registrada: 75 kg e protocolo atualizado para recomposição. 1.746 kcal por dia 💪',
    ],
    [
      'dois verbos ligados à meta na mesma frase',
      'Meta de 75 kg registrada e protocolo atualizado para recomposição 💪',
    ],
    ['particípio no plural sobre dois nomes de meta', 'Meta e protocolo registrados 💪'],
    [
      'auxiliar entre o nome e o particípio',
      'O protocolo já está registrado e a meta foi atualizada para 75 kg 💪',
    ],
    ['verbo finito + a meta como objeto', 'Registrei sua meta de 75 kg. Vamos focar! 💪'],
    [
      'verbo finito + o protocolo como objeto',
      'Atualizei o protocolo para manutenção: 2.300 kcal por dia.',
    ],
    [
      'recusa com o verbo ligado à meta',
      'Não registrei a meta de 7%: fica abaixo de 10%. Sua meta diária segue em 1.746 kcal 💪',
    ],
    [
      'a frase da recusa de peso de define_meta_peso',
      'Por segurança, não registrei essa meta e nada mudou no seu cadastro. Sua meta diária segue em 1.746 kcal 💪',
    ],
    [
      'a recusa de IMC de define_protocolo',
      'Protocolo registrado. A meta de IMC 18 não foi registrada: fica abaixo do saudável (mínimo OMS é 18.5). Posso registrar uma meta de IMC a partir de 18.5. Qual você prefere? 💪',
    ],
    [
      'a mensagem "Meta de N% registrada." de define_meta_peso',
      'Meta de 7% registrada. 1.746 kcal por dia 💪',
    ],
    [
      'palavras da lista fechada ao redor da afirmação',
      'Pronto, meta registrada com sucesso! 1.746 kcal por dia 💪',
    ],
    [
      'valor da meta entre o nome e o particípio, em linhas',
      'Meta de 75 kg registrada ✅\n\nSeu plano continua igual:\n🔥 1.746 kcal por dia\n💪 120 g de proteína',
    ],
    [
      '"Objetivo salvo:" e a kcal numa frase sem verbo',
      'Feito! Objetivo salvo: chegar a 75 kg. Mantendo 1.746 kcal por dia você chega lá em cerca de 10 semanas 💪',
    ],
  ])('resposta fiel (%s): continua isenta', (_label, content) => {
    expect(withGoalTool(content)).toEqual({ isFake: false, kind: null })
    // Without the tool the same text is a claim with nothing behind it.
    expect(detectFakeWrite({ content, registrationToolCalled: false }).isFake).toBe(true)
  })

  it('varredura: nenhuma resposta fiel montada com as mensagens das próprias tools dispara', () => {
    // Every message classifyBfGoal / classifyWeightGoal can hand to the model
    // in these ranges, plus the two goal_message shapes of define_protocolo
    // (tools.ts, goalBelowFloorReason — locked verbatim in the golden).
    const messages = new Set<string>()
    for (const sex of ['masculino', 'feminino'] as const)
      for (let current = 8; current <= 40; current += 2)
        for (let target = 4; target <= 35; target += 1)
          messages.add(
            classifyBfGoal({ currentBfPercent: current, targetBfPercent: target, sex }).message,
          )
    for (const heightCm of [150, 160, 170, 180, 190])
      for (let current = 40; current <= 130; current += 6)
        for (let target = 38; target <= 120; target += 3)
          messages.add(
            classifyWeightGoal({ currentWeightKg: current, targetWeightKg: target, heightCm })
              .message,
          )
    for (const value of [7, 8, 9])
      messages.add(
        `Protocolo registrado. A meta de ${value}% de gordura corporal não foi registrada: fica abaixo de 10%, que é o limite inferior seguro do método. Posso registrar uma meta a partir de 10%. Qual você prefere?`,
      )
    for (const value of [16, 17, 18])
      messages.add(
        `Protocolo registrado. A meta de IMC ${value} não foi registrada: fica abaixo do saudável (mínimo OMS é 18.5). Posso registrar uma meta de IMC a partir de 18.5. Qual você prefere?`,
      )
    const frames: Array<(message: string) => string> = [
      (m) => `Meta registrada. ${m} 💪`,
      (m) => `Protocolo registrado. Sua nova meta é 1.746 kcal por dia. ${m}`,
      (m) => `Meta atualizada: ${m} Sua meta diária segue em 1.746 kcal 💪`,
      (m) => `${m}\n\nMeta registrada ✅ 1.746 kcal por dia 💪`,
      (m) => `${m} Sua meta diária segue em 1.746 kcal 💪`,
      (m) => `${m}\n\n🔥 Meta diária: 1.746 kcal\n💪 Proteína: 120 g`,
    ]
    const fired: string[] = []
    let firedWithoutTheTool = 0
    for (const message of messages)
      for (const frame of frames) {
        const content = frame(message)
        if (withGoalTool(content).isFake) fired.push(content)
        if (detectFakeWrite({ content, registrationToolCalled: false }).isFake)
          firedWithoutTheTool += 1
      }
    expect(messages.size).toBe(1610)
    expect(fired).toEqual([])
    // The sweep is not vacuous: without the goal tool most of these texts fire.
    expect(firedWithoutTheTool).toBe(6536)
  })
})

// Third independent check of 2026-10-04 (lens B). Every answer is the
// checker's, verbatim (fixtures/audit-10-04-guard-answers.ts; no patient print
// exists). The same answers run through processMessage in
// __golden__/audit-10-04-goal-ladder-floors.test.ts.
//
// HIGH — shape (A) bound to the goal ANY participle that came after the goal
// noun: "520 kcal da meta já registradas" was read as a claim about the goal,
// although the feminine plural agrees with the kcal eaten. 11 answers passed
// in silence; the parent 279ba09 fired on all of them.
// MEDIUM — the sentence break at ": " cut the verb from the list it governs:
// "Registrei a meta e também: arroz, feijão e frango — 520 kcal 💪".
// STRUCTURAL — in every probe that passed, the PATIENT had reported a meal or
// a workout in the same turn. With a meal-or-workout word in the patient's
// text of the turn (`patientTurnText`) the exemption is off.
// LOW — the bound-claim regex backtracked exponentially on numbers two spaces
// apart.
//
// > RC R4 — cenário particípio que concorda com o nome da meta numa frase sobre a refeição ("520 kcal da meta registrada 💪"), e particípio no plural depois de dois nomes de meta ligados por "e" ("520 kcal do protocolo e meta registradas 💪") NÃO coberto nesta PR (pendência da audit 2026-10-04).
//   A concordância com o nome da meta é o único sinal lido: quando o texto do paciente no turno não tem palavra de refeição ou treino ("Minha meta agora é 75 kg"), o guard não dispara (no commit pai 279ba09 disparava). Com a palavra ("Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.") dispara. Os dois lados estão em fake-write-detector.test.ts e no golden. Sem relato de paciente.
// > RC R4 — cenário paciente que relata a refeição ou o treino SEM palavra da lista ("Minha meta agora é 75 kg. Comi 2 fatias de pizza.", "Minha meta agora é 75 kg. Joguei 40 minutos de futsal.", "My goal is now 75 kg. I had rice, beans and chicken."), ou que relatou num turno anterior NÃO coberto nesta PR (pendência da audit 2026-10-04).
//   A isenção continua valendo nesse turno: a resposta é lida por frase, com as pendências desta lista (refeição mostrada sem verbo próprio; particípio que concorda com o nome da meta). A lista é a mesma usada na resposta (café, almoço/almocei, lanche, janta/jantar/jantei, ceia, refeição, treino, caminhada, corrida, musculação, bike, bicicleta, natação, alongamento, yoga, pilates, exercício, cross…): "comi", "tomei", nome de comida e nome de esporte não estão nela. Caracterizado em fake-write-detector.test.ts e no golden.
// > RC R4 — cenário resposta fiel (só meta ou protocolo) num turno em que o texto do paciente tem palavra de refeição ou treino SEM relatar refeição nem treino ("Peso 79 kg, treino 4 vezes por semana, fome moderada, não vou mandar fotos. Minha meta agora é 7% de gordura") NÃO coberto nesta PR (pendência da audit 2026-10-04).
//   A isenção não vale nesse turno e o guard dispara como no commit pai 279ba09 (3ª chamada ao modelo com "chame registra_refeicao"): a condição lê palavra, não sentido. É o caso de quem informa a frequência de treino junto com o peso e a fome na reavaliação. Travado no golden (3 chamadas, 2 eventos) e em fake-write-detector.test.ts. A frase do paciente é sintética: não há relato.
describe('detectFakeWrite — terceira checagem: concordância do particípio, lista depois dos dois-pontos e o texto do paciente', () => {
  const withGoalTool = (content: string, patientTurnText?: string) =>
    detectFakeWrite({
      content,
      registrationToolCalled: false,
      goalToolCalled: true,
      ...(patientTurnText === undefined ? {} : { patientTurnText }),
    })
  /** The parent 279ba09 had no goal exemption: it read the answer as a turn
   * without a goal tool is read today. */
  const asInTheParent = (content: string) =>
    detectFakeWrite({ content, registrationToolCalled: false })
  const P_GOAL_ONLY = 'Minha meta agora é 75 kg'

  it('o fixture tem as respostas do achado: 11 de concordância e 4 de lista', () => {
    expect(AGREEMENT_ANSWERS).toHaveLength(11)
    expect(OPEN_LIST_ANSWERS).toHaveLength(4)
    expect(new Set([...AGREEMENT_ANSWERS, ...OPEN_LIST_ANSWERS]).size).toBe(15)
    expect(AGREEMENT_ANSWERS[0]).toBe('Almoço: 520 kcal da meta já registradas ✅ 💪')
    expect(OPEN_LIST_ANSWERS[0]).toBe(
      'Registrei a meta e também: arroz, feijão e frango — 520 kcal 💪',
    )
  })

  // No patient text is given here: the rule of the answer fires by itself.
  it.each(
    AGREEMENT_ANSWERS,
  )('HIGH, o particípio concorda com as kcal e não com a meta — %j: dispara com a tool de meta no turno', (content) => {
    expect(withGoalTool(content)).toEqual({ isFake: true, kind: 'registration' })
    expect(asInTheParent(content)).toEqual({ isFake: true, kind: 'registration' })
  })

  it.each([
    [
      'dois nomes de meta na frase, sem "e" entre eles',
      'Almoço: 520 kcal da meta de recomposição já registradas ✅',
    ],
    ['idem, "da meta do protocolo"', '520 kcal da meta do protocolo registradas 💪'],
    ['o valor da meta e as kcal, particípio no plural', 'Meta 75 kg 520 kcal registradas 💪'],
    ['masculino depois de "meta"', 'Arroz: na meta anotado, 128 kcal'],
    ['feminino depois de "protocolo"', 'Salada do protocolo registrada — 120 kcal'],
    ['plural depois de "objetivo"', '430 kcal do objetivo registradas 💪'],
    [
      'singular que não concorda, depois de dois nomes de meta ligados por "e"',
      'Protocolo e meta registrado. 1.746 kcal por dia 💪',
    ],
  ])('concordância — %s: dispara', (_label, content) => {
    expect(withGoalTool(content).isFake).toBe(true)
  })

  it.each([
    ['feminino singular depois de "meta"', 'Meta de 75 kg registrada 💪'],
    ['masculino singular depois de "protocolo"', 'Protocolo de manutenção registrado 💪'],
    [
      'o particípio concorda com o núcleo ("meta"), não com "recomposição"',
      'Meta de recomposição atualizada 💪',
    ],
    ['masculino depois de "IMC"', 'IMC 23 registrado como objetivo 💪'],
    ['feminino plural depois de "metas"', 'Metas registradas: 75 kg e 15%. 💪'],
    [
      'plural sobre dois nomes de meta ligados por "e"',
      'Protocolo e meta registrados. 1.746 kcal por dia 💪',
    ],
    ['idem, com artigos e auxiliar', 'O protocolo e a meta foram registrados 💪'],
    ['idem, os dois femininos', 'Meta e recomposição registradas 💪'],
    ['idem, o primeiro com o valor', 'Meta de 75 kg e protocolo registrados 💪'],
  ])('concordância, resposta fiel (%s): continua isenta', (_label, content) => {
    expect(withGoalTool(content)).toEqual({ isFake: false, kind: null })
    expect(asInTheParent(content).isFake).toBe(true)
  })

  it.each(
    OPEN_LIST_ANSWERS,
  )('MEDIUM, o verbo rege a lista depois dos dois-pontos — %j: dispara com a tool de meta no turno', (content) => {
    expect(withGoalTool(content)).toEqual({ isFake: true, kind: 'registration' })
    expect(asInTheParent(content)).toEqual({ isFake: true, kind: 'registration' })
  })

  it.each([
    ['"e ainda:"', 'Meta registrada e ainda: arroz com frango, 430 kcal'],
    ['"e mais:"', 'Registrei também a meta e mais: 2 ovos e pão — 310 kcal 💪'],
    ['"também:" sem "e"', 'Meta registrada, também:\n• 2 ovos\n• 1 pão\n310 kcal'],
  ])('lista depois dos dois-pontos — %s: dispara', (_label, content) => {
    expect(withGoalTool(content).isFake).toBe(true)
  })

  it.each([
    ['os dois-pontos logo depois do particípio', 'Meta registrada: 75 kg. 1.746 kcal por dia 💪'],
    [
      '"também" fechando a frase, sem dois-pontos',
      'Protocolo registrado. Meta registrada também. 1.746 kcal por dia 💪',
    ],
    ['"com:" não é coordenação', 'Protocolo registrado com: 1.746 kcal e 120 g de proteína 💪'],
    [
      'coordenação antes dos dois-pontos numa frase SEM verbo',
      'Meta registrada. Seu plano, e também: 1.746 kcal por dia 💪',
    ],
  ])('lista depois dos dois-pontos, resposta fiel (%s): continua isenta', (_label, content) => {
    expect(withGoalTool(content)).toEqual({ isFake: false, kind: null })
  })

  it.each([
    [
      'particípio que não concorda com o nome da meta',
      'Meta registrado: 75 kg. 1.746 kcal por dia 💪',
    ],
    [
      'frase do verbo terminando em coordenação antes dos dois-pontos',
      'Protocolo registrado e também: 1.746 kcal por dia 💪',
    ],
  ])('caracterização (pendência RC R4), resposta fiel — %s: dispara, como no commit pai', (_label, content) => {
    expect(withGoalTool(content)).toEqual({ isFake: true, kind: 'registration' })
    expect(asInTheParent(content)).toEqual({ isFake: true, kind: 'registration' })
  })

  // What the rule of the answer still lets through. Each of these fires as
  // soon as the patient's text of the turn names a meal or a workout.
  const STILL_SILENT_BY_THE_ANSWER_ALONE = [
    // RC R4 "refeição mostrada sem verbo próprio" — the fifth is the example
    // the third check added ("meta do dia" as a word of the food day).
    'Frango com arroz — 430 kcal. Meta registrada 💪',
    'Meta registrada. Arroz com frango também. 430 kcal 💪',
    'Arroz com frango: meta registrada — 430 kcal',
    'Registrei a meta e 430 kcal 💪',
    'Registrei a meta do dia: 520 kcal de arroz, feijão e frango.',
    // RC R4 "particípio que concorda com o nome da meta".
    '520 kcal da meta registrada 💪',
    '520 kcal do protocolo e meta registradas 💪',
  ]

  it.each(
    STILL_SILENT_BY_THE_ANSWER_ALONE,
  )('caracterização (pendência RC R4), o que ainda passa — %j: em silêncio sem palavra de refeição no texto do paciente, dispara com ela', (content) => {
    expect(asInTheParent(content)).toEqual({ isFake: true, kind: 'registration' })
    // Silent: with no patient text, and with one that only states the goal.
    expect(withGoalTool(content)).toEqual({ isFake: false, kind: null })
    expect(withGoalTool(content, P_GOAL_ONLY)).toEqual({ isFake: false, kind: null })
    // The patient reported the meal in the same turn: read whole, as the parent.
    expect(withGoalTool(content, P_GOAL_AND_MEAL)).toEqual({ isFake: true, kind: 'registration' })
  })

  // ── STRUCTURAL: the patient's text of the turn ──────────────────────────────

  const PATIENT_TEXTS_WITH_A_MEAL_OR_WORKOUT_WORD = [
    P_GOAL_AND_MEAL,
    'Minha meta agora é 75 kg. Fiz 40 minutos de treino hoje.',
    'Minha meta agora é 75 kg. Corrige o almoço: o feijão era 180g.',
    'Quero recomposição. Tomei café: 2 ovos e pão.',
    'Fome moderada, sigo na recomposição. Jantei 2 bananas.',
    'Minha meta agora é 75 kg. Fiz duas caminhadas de 60 minutos hoje.',
    // Typed text first, then what the WhatsApp worker writes for a photo of a
    // plate (process-message.ts): the typed text has no meal word.
    'Minha meta agora é 75 kg\n[1/1 foto(s) analisada(s) — análise visual automática abaixo]\n\nFoto [refeição]:\n  - arroz branco: 150g (conf 90%)\n  - frango grelhado: 120g (conf 88%)\n\nRelato do usuário: "Minha meta agora é 75 kg"',
    // Not a report (RC R4): the word is there, so the exemption is off.
    'Peso 79 kg, treino 4 vezes por semana, fome moderada, não vou mandar fotos. Minha meta agora é 7% de gordura',
  ]
  const PATIENT_TEXTS_WITHOUT_ONE = [
    P_GOAL_ONLY,
    'Quero recomposição',
    'Peso 79 kg, fome moderada, não vou mandar fotos. Minha meta agora é 7% de gordura',
    '',
    // A photo of the body in a reassessment turn names no meal and no workout.
    'Minha meta agora é 7% de gordura\n[1/1 foto(s) analisada(s) — análise visual automática abaixo]\n\nFoto [corporal · frente]:\n  BF% estimado: 14 (conf 70%)\n  abdômen com definição moderada',
    // Reports with no word of the list (RC R4).
    'Minha meta agora é 75 kg. Comi 2 fatias de pizza.',
    'Minha meta agora é 75 kg. Joguei 40 minutos de futsal.',
    'My goal is now 75 kg. I had rice, beans and chicken.',
    // "peso" and "força" are not meal-or-workout words (a weight goal uses
    // them), and the workout signature (an hour + "peso") is not applied to
    // the patient's text.
    'Minha meta de peso agora é 75 kg, com força!',
    'Acordo às 7h, durmo às 23h, peso 80 kg. Minha meta agora é 75 kg',
  ]
  const EVERY_ANSWER: string[] = [
    ...PHANTOM_ANSWERS.map((probe) => probe.answer),
    ...GOAL_ONLY_ANSWERS.map((probe) => probe.answer),
    ...OTHER_RULE_ANSWERS.map((probe) => probe.answer),
    ...ADVERSARIAL_ANSWERS.map((probe) => probe.answer),
    ...AGREEMENT_ANSWERS,
    ...OPEN_LIST_ANSWERS,
    ...STILL_SILENT_BY_THE_ANSWER_ALONE,
  ]

  it('os corpora dos checadores estão inteiros: 45 + 17 + 9 da segunda checagem, 71 + 11 + 4 da terceira', () => {
    expect(PHANTOM_ANSWERS).toHaveLength(45)
    expect(GOAL_ONLY_ANSWERS).toHaveLength(17)
    expect(OTHER_RULE_ANSWERS).toHaveLength(9)
    expect(ADVERSARIAL_ANSWERS).toHaveLength(71)
    expect(EVERY_ANSWER).toHaveLength(164)
  })

  it('as 45 respostas de escrita fantasma da segunda checagem disparam com a tool de meta, com o tipo de retry do fixture', () => {
    for (const { answer, kind } of PHANTOM_ANSWERS)
      expect([answer, withGoalTool(answer)]).toEqual([answer, { isFake: true, kind }])
  })

  it('com palavra de refeição ou treino no texto do paciente, as 45 + 11 + 4 disparam — e qualquer resposta que o commit pai lia como afirmação também', () => {
    const phantom = [
      ...PHANTOM_ANSWERS.map((probe) => probe.answer),
      ...AGREEMENT_ANSWERS,
      ...OPEN_LIST_ANSWERS,
    ]
    expect(phantom).toHaveLength(60)
    for (const patient of PATIENT_TEXTS_WITH_A_MEAL_OR_WORKOUT_WORD) {
      for (const answer of phantom)
        expect([patient, answer, withGoalTool(answer, patient).isFake]).toEqual([
          patient,
          answer,
          true,
        ])
      // Whatever the wording: the verdict is the parent's, answer by answer.
      for (const answer of EVERY_ANSWER)
        expect([patient, answer, withGoalTool(answer, patient).isFake]).toEqual([
          patient,
          answer,
          asInTheParent(answer).isFake,
        ])
    }
  })

  it('o texto do paciente só faz o guard disparar MAIS: o que dispara sem ele dispara com ele, com o mesmo tipo de retry', () => {
    let firing = 0
    let added = 0
    for (const answer of EVERY_ANSWER) {
      const alone = withGoalTool(answer)
      if (alone.isFake) firing += 1
      for (const patient of [
        ...PATIENT_TEXTS_WITH_A_MEAL_OR_WORKOUT_WORD,
        ...PATIENT_TEXTS_WITHOUT_ONE,
      ]) {
        const withPatient = withGoalTool(answer, patient)
        if (alone.isFake) expect([patient, answer, withPatient]).toEqual([patient, answer, alone])
        else if (withPatient.isFake) added += 1
      }
    }
    // Not vacuous. 126 of the 164 answers fire by themselves: 45 + 11 + 4, 56
    // of the 58 adversarial phantom answers, 6 faithful ones declared as
    // pending and 4 of other rules.
    expect(firing).toBe(126)
    // Of the other 38, the parent read 31 as a claim: each of them fires with
    // each of the 8 patient texts that name a meal or a workout.
    expect(added).toBe(31 * PATIENT_TEXTS_WITH_A_MEAL_OR_WORKOUT_WORD.length)
    expect(PATIENT_TEXTS_WITH_A_MEAL_OR_WORKOUT_WORD).toHaveLength(8)
  })

  it('sem palavra de refeição ou treino no texto do paciente, nada muda', () => {
    for (const patient of PATIENT_TEXTS_WITHOUT_ONE)
      for (const answer of EVERY_ANSWER)
        expect([patient, answer, withGoalTool(answer, patient)]).toEqual([
          patient,
          answer,
          withGoalTool(answer),
        ])
  })

  it('sem a tool de meta no turno o texto do paciente não é lido por esta regra', () => {
    for (const patient of PATIENT_TEXTS_WITH_A_MEAL_OR_WORKOUT_WORD)
      for (const answer of EVERY_ANSWER)
        expect([
          patient,
          answer,
          detectFakeWrite({
            content: answer,
            registrationToolCalled: false,
            patientTurnText: patient,
          }),
        ]).toEqual([patient, answer, asInTheParent(answer)])
  })

  it('com a tool de registro no turno nada dispara, com ou sem o texto do paciente', () => {
    expect(
      detectFakeWrite({
        content:
          'Meta registrada: 75 kg. Almoço registrado: arroz, feijão e frango grelhado — 520 kcal. 💪',
        registrationToolCalled: true,
        goalToolCalled: true,
        patientTurnText: P_GOAL_AND_MEAL,
      }),
    ).toEqual({ isFake: false, kind: null })
  })

  it.each([
    'Meta registrada: 75 kg. Vamos focar! 💪',
    'Protocolo registrado. Sua nova meta é 1.746 kcal por dia. A meta de 7% de gordura corporal não foi registrada: fica abaixo de 10%, que é o limite inferior seguro do método. Posso registrar uma meta a partir de 10%. Qual você prefere? 💪',
  ])('resposta fiel, só de meta — %j: isenta quando o paciente só falou da meta; dispara quando ele relatou a refeição no mesmo turno (nada foi registrado)', (content) => {
    expect(withGoalTool(content, P_GOAL_ONLY)).toEqual({ isFake: false, kind: null })
    expect(withGoalTool(content, P_GOAL_AND_MEAL)).toEqual({ isFake: true, kind: 'registration' })
  })

  it('caracterização (pendência RC R4) — o paciente cita "treino" sem relatar treino: a resposta fiel dispara, como no commit pai', () => {
    const patient =
      'Peso 79 kg, treino 4 vezes por semana, fome moderada, não vou mandar fotos. Minha meta agora é 7% de gordura'
    const content =
      'Protocolo registrado. Sua nova meta é 1.746 kcal por dia. A meta de 7% de gordura corporal não foi registrada: fica abaixo de 10%, que é o limite inferior seguro do método. Posso registrar uma meta a partir de 10%. Qual você prefere? 💪'
    expect(withGoalTool(content, patient)).toEqual({ isFake: true, kind: 'registration' })
    expect(withGoalTool(content)).toEqual({ isFake: false, kind: null })
  })

  it.each([
    'Minha meta agora é 75 kg. Comi 2 fatias de pizza.',
    'Minha meta agora é 75 kg. Joguei 40 minutos de futsal.',
    'My goal is now 75 kg. I had rice, beans and chicken.',
  ])('caracterização (pendência RC R4) — relato sem palavra da lista (%j): a isenção continua, "520 kcal da meta registrada 💪" passa', (patient) => {
    expect(withGoalTool('520 kcal da meta registrada 💪', patient)).toEqual({
      isFake: false,
      kind: null,
    })
    // An answer the rule of the answer catches still fires in that turn.
    expect(withGoalTool('520 kcal da meta registradas 💪', patient)).toEqual({
      isFake: true,
      kind: 'registration',
    })
  })

  it('o tipo do retry continua vindo do que sobra fora das frases de meta, mesmo com o texto do paciente', () => {
    // Read whole, as the parent did, "atualizado" would ask for replace=true on
    // a meal that is new.
    const content =
      'Protocolo atualizado: recomposição. Almoço registrado: arroz, feijão e frango — 430 kcal.'
    expect(withGoalTool(content, 'Quero recomposição. Almocei arroz, feijão e frango.')).toEqual({
      isFake: true,
      kind: 'registration',
    })
    expect(asInTheParent(content)).toEqual({ isFake: true, kind: 'correction' })
    // Only when nothing is left outside the goal sentences is the kind the
    // parent's: here the only verb is the protocol's.
    expect(
      withGoalTool(
        'Protocolo atualizado: recomposição. Arroz, feijão e frango — 430 kcal.',
        'Quero recomposição. Almocei arroz, feijão e frango.',
      ),
    ).toEqual({ isFake: true, kind: 'correction' })
  })

  // ── LOW: the bound-claim regex reads each text one way ──────────────────────

  it.each([
    [
      'números separados por dois espaços (a entrada do achado)',
      (n: number) => `Registrado na meta${'  1'.repeat(n)} x 💪`,
    ],
    ['tabela em colunas', (n: number) => `Atualizado. Meta   ${'1.746   '.repeat(n)}x 💪`],
    ['"75 kg" repetido', (n: number) => `Registrado na meta${' 75 kg'.repeat(n)} x 💪`],
    ['"75  kg" com dois espaços', (n: number) => `Registrado na meta${'  75  kg'.repeat(n)} x 💪`],
    [
      '"1.746  kcal" e "7 %"',
      (n: number) => `Registrado na meta${' 1.746  kcal 7 %'.repeat(n)} x 💪`,
    ],
    ['nome de meta que também é valor', (n: number) => `Registrado ${'imc '.repeat(n)}x 💪`],
    ['nomes de meta ligados por "e"', (n: number) => `${'meta e '.repeat(n)}meta registrados x 💪`],
    [
      'coordenação e espaços antes dos dois-pontos',
      (n: number) => `Registrei a meta ${'e    '.repeat(n)}: x 💪`,
    ],
  ] as const)('sem retrocesso exponencial — %s: 60 repetições em menos de 100 ms', (_label, build) => {
    // Before the fix the first shape took 0.9 s at 26 repetitions and 3.7 s at
    // 28, doubling with each one more (other shapes grew faster). The ladder
    // makes a regression fail on a low step, in seconds, instead of hanging
    // the suite at 60.
    for (const repetitions of [8, 12, 16, 20, 23, 26, 60]) {
      const content = build(repetitions)
      const start = performance.now()
      const result = withGoalTool(content)
      const elapsedMs = performance.now() - start
      expect([repetitions, elapsedMs < 100]).toEqual([repetitions, true])
      // No participle bound to the goal: the verb is left and the guard fires.
      expect(result.isFake).toBe(true)
    }
  })

  it.each([
    ['unidade colada', 'Meta de 75kg registrada 💪'],
    ['"%" depois de espaço', 'Meta de 7 % registrada 💪'],
    ['kcal depois de espaço', 'Meta de 1.746 kcal registrada 💪'],
    ['kcal colada', 'Meta de 1.746kcal registrada 💪'],
    ['dois espaços antes de "kg"', 'Meta de peso 75  kg registrada 💪'],
    ['decimal com vírgula', 'Meta de 72,5 kg registrada 💪'],
  ])('o valor da meta entre o nome e o particípio continua aceito (%s)', (_label, content) => {
    expect(withGoalTool(content)).toEqual({ isFake: false, kind: null })
  })
})
