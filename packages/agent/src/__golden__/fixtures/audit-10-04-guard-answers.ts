/**
 * Model answers used to probe the phantom-write guard in a turn with a goal
 * tool (define_protocolo / define_meta_peso). Audit of 2026-10-04.
 *
 * NONE of these is a patient print: no print of a goal turn exists. Every
 * answer and every patient sentence is the probe of an independent checker,
 * copied verbatim from the checker's files (scratchpad, outside the
 * repository): `reviewC/lensB/corpus.ts` (second check), and
 * `reviewD/lensB/corpus.ts`, `adv-corpus.ts` and the two findings of the third
 * check. The ids are the checker's.
 *
 * Read by fake-write-detector.test.ts (the detector alone) and by
 * audit-10-04-goal-ladder-floors.test.ts (the same answers through
 * processMessage).
 */

export interface GuardProbe {
  id: string
  /** What the patient wrote in the checker's turn. */
  patient: string
  /** What the scripted model answers, with no registration tool called. */
  answer: string
}

export interface PhantomProbe extends GuardProbe {
  /** Kind of the forced retry (it decides the retry message). */
  kind: 'registration' | 'correction'
}

/** The patient sentence of the two findings of the third check. */
export const P_GOAL_AND_MEAL = 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.'

/**
 * Second check: the 45 answers that claim a meal, a workout or a correction
 * (class "phantom"). The parent 279ba09 fired on all of them; the first
 * per-sentence exemption on 29; since the fix of the second check, on 45.
 */
export const PHANTOM_ANSWERS: PhantomProbe[] = [
  {
    id: 'M01',
    patient: 'Fome moderada, sigo na recomposição. Almocei arroz, feijão e frango.',
    answer:
      'Almoço registrado.\n\n🔥 Consumido: 1.433 / 1.843 kcal\n🎯 Restam: 410 kcal\n📊 Bloco 7700: 5.757 / 7.700',
    kind: 'registration',
  },
  {
    id: 'M02',
    patient: 'Fome moderada, sigo na recomposição. E corrige o feijão do almoço: eram 180 g.',
    answer:
      'Corrigido.\n\n**Almoço:**\n• Feijão carioca (180 g): 137 kcal\n🔥 Consumido: 1.433 / 1.843 kcal\n🎯 Restam: 410 kcal\n📊 Bloco 7700: 5.757 / 7.700',
    kind: 'correction',
  },
  {
    id: 'M03',
    patient: 'Fome moderada, sigo na recomposição. Jantei 2 bananas.',
    answer:
      'Jantar salvo, Paulo.\n• Banana (2 un): 178 kcal\n🔥 Consumido: 1.433 / 1.843 kcal\n🎯 Restam: 410 kcal\n📊 Bloco 7700: 5.757 / 7.700',
    kind: 'registration',
  },
  {
    id: 'M04',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer:
      'Meta registrada: 75 kg. Almoço registrado: arroz, feijão e frango grelhado — 520 kcal. 💪',
    kind: 'registration',
  },
  {
    id: 'M05',
    patient: 'Quero recomposição, fome moderada. Almocei arroz, feijão e frango.',
    answer:
      'Protocolo registrado: recomposição.\n\nAlmoço registrado. ✅\n🔥 Consumido: 521 / 1.746 kcal\n💪 Proteína: 38 / 120 g',
    kind: 'registration',
  },
  {
    id: 'M06',
    patient: 'Minha meta agora é 7% de gordura. Almocei arroz, feijão e frango grelhado.',
    answer:
      'Não registrei essa meta: 7% fica abaixo de 10%. Almoço registrado: arroz, feijão e frango grelhado — 520 kcal.',
    kind: 'registration',
  },
  {
    id: 'M07',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Almoço registrado. Você está em 520 kcal da meta de 1.746.',
    kind: 'registration',
  },
  {
    id: 'M08',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer:
      'Meta registrada: 75 kg. Registrei arroz, feijão e frango grelhado. Você está em 520 kcal da meta de 1.746.',
    kind: 'registration',
  },
  {
    id: 'M09',
    patient: 'Quero recomposição. Almocei arroz, feijão e frango.',
    answer:
      'Protocolo registrado: recomposição. Registrei: arroz (150 g), feijão (100 g) e frango (120 g) — 520 kcal, dentro da sua meta.',
    kind: 'registration',
  },
  {
    id: 'M10',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Meta registrada e arroz com frango anotado — 430 kcal.',
    kind: 'registration',
  },
  {
    id: 'M11',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Registrado! Faltam 410 kcal para a meta.',
    kind: 'registration',
  },
  {
    id: 'M12',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer:
      'Anotei os 2 ovos e o pão integral. Com isso você soma 780 kcal da meta de 1.746 kcal 💪',
    kind: 'registration',
  },
  {
    id: 'M13',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Meta registrada: 75 kg. Salvei também seu shake de whey com banana — 310 kcal.',
    kind: 'registration',
  },
  {
    id: 'M14',
    patient: 'Quero recomposição. Almocei arroz, feijão e frango.',
    answer:
      'Protocolo atualizado: recomposição. Almoço registrado: arroz, feijão e frango — 430 kcal.',
    kind: 'registration',
  },
  {
    id: 'M15',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer:
      'Meta registrada: 75 kg.\n\n**Almoço:**\n• Arroz 150 g\n• Frango 120 g\n**Total refeição: 430 kcal**',
    kind: 'registration',
  },
  {
    id: 'M16',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Registrei seu almoço dentro da meta: 520 kcal 💪',
    kind: 'registration',
  },
  {
    id: 'M17',
    patient: 'Quero recomposição. Comi frango e arroz.',
    answer: 'Tudo certo com o protocolo de recomposição: registrei o frango e o arroz, 430 kcal.',
    kind: 'registration',
  },
  {
    id: 'M18',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Registrei o frango e o arroz na sua meta de hoje: 430 kcal 💪',
    kind: 'registration',
  },
  {
    id: 'M19',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer:
      'Sua meta foi registrada e o frango com arroz do meio-dia também foi anotado. Hoje você está com 430 kcal de 1.746 kcal da meta.',
    kind: 'registration',
  },
  {
    id: 'M20',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Meta de 75 kg registrada, e já deixei anotado o pão com ovo de hoje cedo (310 kcal).',
    kind: 'registration',
  },
  {
    id: 'M21',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer:
      'Registrei a sua janta: omelete de 3 ovos. Meta do dia: 1.746 kcal, consumido 980 kcal.',
    kind: 'registration',
  },
  {
    id: 'M22',
    patient: 'Minha meta agora é 75 kg. Comi 2 fatias de pizza.',
    answer:
      'Adicionei ao seu diário: 2 fatias de pizza. Isso dá 560 kcal, e você passa da meta em 120 kcal.',
    kind: 'registration',
  },
  {
    id: 'M23',
    patient: 'Quero recomposição. Tomei café: 2 ovos e pão.',
    answer: 'Protocolo registrado: recomposição. Café da manhã anotado ✅ Restam 1.226 kcal.',
    kind: 'registration',
  },
  {
    id: 'M24',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Meta de 75 kg registrada. Sobre o que você comeu: registrei tudo — 520 kcal no total.',
    kind: 'registration',
  },
  {
    id: 'M25',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Registrado o almoço e a meta: 520 kcal 💪',
    kind: 'registration',
  },
  {
    id: 'M26',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer:
      'Meta registrada: 75 kg ✅\nPrato registrado: arroz, feijão e frango.\n🎯 Meta do dia: 1.746 kcal — você consumiu 520 kcal.',
    kind: 'registration',
  },
  {
    id: 'M27',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer:
      'Anotado: arroz, feijão e frango. Seu objetivo de hoje é 1.746 kcal e você já está em 520 kcal 💪',
    kind: 'registration',
  },
  {
    id: 'M28',
    patient: 'Quero manutenção. Almocei arroz, feijão e frango.',
    answer:
      'Protocolo de manutenção registrado. Também registrei o que você comeu: 520 kcal de 2.500 da manutenção.',
    kind: 'registration',
  },
  {
    id: 'W01',
    patient: 'Minha meta agora é 75 kg. Fiz duas caminhadas de 60 minutos hoje.',
    answer: 'Meta registrada: 75 kg. Registrei as duas caminhadas de 60 minutos cada.',
    kind: 'registration',
  },
  {
    id: 'W02',
    patient: 'Minha meta agora é 75 kg. Fiz 40 minutos de treino hoje.',
    answer: 'Meta registrada: 75 kg. Registrei 45 min de musculação.',
    kind: 'registration',
  },
  {
    id: 'W03',
    patient: 'Minha meta agora é 75 kg. Fiz 40 minutos de treino hoje.',
    answer: 'Meta registrada: 75 kg. Registrei 30 minutos de esteira — 250 kcal queimadas.',
    kind: 'registration',
  },
  {
    id: 'W04',
    patient: 'Minha meta agora é 75 kg. Fiz 40 minutos de treino hoje.',
    answer: 'Meta registrada: 75 kg. Treino salvo: 40 min de bike.',
    kind: 'registration',
  },
  {
    id: 'W05',
    patient: 'Minha meta agora é 75 kg. Fiz 40 minutos de treino hoje.',
    answer: 'Registrei sua caminhada de 60 minutos, que ajuda na meta de 75 kg.',
    kind: 'registration',
  },
  {
    id: 'W06',
    patient: 'Minha meta agora é 75 kg. Fiz 40 minutos de treino hoje.',
    answer: 'Meta registrada: 75 kg. Registrei os 40 minutos de levantamento de peso.',
    kind: 'registration',
  },
  {
    id: 'W07',
    patient: 'Quero ganho de massa. Fiz 40 minutos de treino de força.',
    answer: 'Registrei 40 minutos de treino de força para a sua meta de ganho de massa.',
    kind: 'registration',
  },
  {
    id: 'W08',
    patient: 'Minha meta agora é 75 kg. Fiz 40 minutos de treino hoje.',
    answer: 'Registrei 50 minutos de natação. Isso acelera sua meta: 320 kcal a mais no bloco 💪',
    kind: 'registration',
  },
  {
    id: 'W09',
    patient: 'Minha meta agora é 75 kg. Joguei 40 minutos de futsal.',
    answer: 'Anotei os 40 minutos de futsal. Meta do dia mantida em 1.746 kcal.',
    kind: 'registration',
  },
  {
    id: 'W10',
    patient: 'Minha meta agora é 75 kg. Fiz 40 minutos de força hoje.',
    answer: 'Meta registrada: 75 kg. Registrei 40 minutos de força, bom para a meta.',
    kind: 'registration',
  },
  {
    id: 'W11',
    patient: 'Minha meta agora é 75 kg. Levantei peso por 1 hora.',
    answer: 'Registrei 1 hora de peso livre para a sua meta de 75 kg.',
    kind: 'registration',
  },
  {
    id: 'C01',
    patient: 'Minha meta agora é 75 kg. Corrige o almoço: o feijão era 180g.',
    answer: 'Meta registrada: 75 kg. Corrigido. Feijão 180g — almoço agora com 610 kcal.',
    kind: 'correction',
  },
  {
    id: 'C02',
    patient: 'Minha meta agora é 75 kg. Corrige o almoço: o feijão era 180g.',
    answer: 'Meta registrada: 75 kg. Troquei o arroz por batata-doce no almoço: agora 480 kcal.',
    kind: 'correction',
  },
  {
    id: 'C03',
    patient: 'Minha meta agora é 75 kg. Corrige o almoço: o feijão era 180g.',
    answer: 'Atualizei o jantar: 2 ovos em vez de 3 — 156 kcal. Sua meta segue 1.746 kcal.',
    kind: 'correction',
  },
  {
    id: 'C04',
    patient: 'Minha meta agora é 75 kg. Corrige o almoço: o feijão era 180g.',
    answer: 'Correção feita. O total de hoje fica em 1.433 kcal, dentro da meta de 1.843.',
    kind: 'correction',
  },
  {
    id: 'C05',
    patient: 'Minha meta agora é 75 kg. Corrige o almoço: o feijão era 180g.',
    answer: 'Corrigido: feijão 180 g. Total do dia: 1.433 kcal de 1.843 da meta.',
    kind: 'correction',
  },
  {
    id: 'C06',
    patient: 'Minha meta agora é 75 kg. Corrige o almoço: o feijão era 180g.',
    answer: 'Meta registrada: 75 kg. Substituí o feijão: agora são 180 g (137 kcal).',
    kind: 'correction',
  },
]

/**
 * Third check, HIGH: the participle agrees with the kcal eaten, not with the
 * goal. The 11 answers quoted in the finding; the patient wrote
 * P_GOAL_AND_MEAL. All passed in silence in the three goal-tool modes.
 */
export const AGREEMENT_ANSWERS: string[] = [
  'Almoço: 520 kcal da meta já registradas ✅ 💪',
  'Meta registrada: 75 kg. Almoço: arroz, feijão e frango. 520 kcal da meta diária já registradas 💪',
  '520 kcal da meta registradas 💪',
  'Meta registrada: 75 kg.\nArroz, feijão e frango no almoço.\nDa meta de 1.746 kcal 520 já foram registradas 💪',
  'Consumo: 520 kcal da meta diária registradas',
  'Hoje: 520 de 1.746 kcal da meta registradas 💪',
  '🔥 520 / 1.746 kcal da meta registradas',
  'Frango com arroz: na meta registrado ✅ 430 kcal',
  'Arroz, feijão e frango: 520 kcal do objetivo diário salvas 💪',
  'Almoço: 520 kcal do protocolo registradas.',
  'Meta registrada: 75 kg. Almoço: 520 kcal. Da meta de 1.746 kcal já foram registradas 520 💪',
]

/**
 * Third check, MEDIUM: the sentence break at ": " cut the verb from the list
 * it governs. The four answers quoted in the finding; same patient sentence.
 */
export const OPEN_LIST_ANSWERS: string[] = [
  'Registrei a meta e também: arroz, feijão e frango — 520 kcal 💪',
  'Registrei a meta e também:\n• arroz\n• feijão\n• frango\nTotal: 520 kcal',
  'Meta registrada, e também:\n- 2 ovos\n- 1 pão integral\n310 kcal 💪',
  'Registrei a meta e:\n• frango (120 g)\n• arroz (150 g)\n520 kcal',
]

/** Second check: the 17 faithful answers, only about the goal or the protocol. */
export const GOAL_ONLY_ANSWERS: GuardProbe[] = [
  {
    id: 'G01',
    patient: 'Minha meta agora é 7% de gordura',
    answer:
      'Sua nova meta é 1.746 kcal e 118,5 g de proteína por dia. A meta de 7% de gordura corporal não foi registrada: fica abaixo de 10%, que é o limite inferior seguro do método. Posso registrar uma meta a partir de 10%. Qual você prefere?',
  },
  {
    id: 'G02',
    patient: 'Minha meta agora é 7% de gordura',
    answer:
      'A meta de 7% de gordura corporal não foi registrada: fica abaixo de 10%, que é o limite inferior seguro do método. Posso registrar uma meta a partir de 10%. Qual você prefere? 💪',
  },
  {
    id: 'G03',
    patient: 'Minha meta agora é 7% de gordura',
    answer:
      'Protocolo registrado. Sua nova meta é 1.746 kcal por dia. A meta de 7% de gordura corporal não foi registrada: fica abaixo de 10%, que é o limite inferior seguro do método. Posso registrar uma meta a partir de 10%. Qual você prefere? 💪',
  },
  {
    id: 'G04',
    patient: 'Minha meta agora é 7% de gordura',
    answer:
      'Não registrei essa meta: 7% fica abaixo de 10% de gordura corporal, que é o limite inferior seguro do método. O método não reduz a gordura corporal abaixo de 10%. Nada mudou no seu cadastro. Posso registrar uma meta a partir de 10%. Qual você prefere? Sua meta diária segue em 1.746 kcal 💪',
  },
  {
    id: 'G05',
    patient: 'Minha meta agora é 75 kg',
    answer: 'Meta registrada: 75 kg. Vamos focar! 💪',
  },
  {
    id: 'G06',
    patient: 'Quero recomposição',
    answer:
      'Protocolo registrado: recomposição. Sua meta diária é 1.746 kcal e 120 g de proteína. 💪',
  },
  {
    id: 'G07',
    patient: 'Quero recomposição',
    answer:
      'Protocolo atualizado para recomposição ✅\n\n🔥 Meta diária: 1.746 kcal\n💪 Proteína: 120 g',
  },
  {
    id: 'G08',
    patient: 'Quero recomposição com meta de 7% de gordura',
    answer:
      'Registrei o protocolo de recomposição. A meta de 7% de gordura corporal não foi registrada: fica abaixo de 10%. Sua meta diária segue em 1.746 kcal 💪',
  },
  {
    id: 'G09',
    patient: 'Minha meta agora é 75 kg',
    answer: 'Registrado! Sua meta agora é 1.746 kcal por dia.',
  },
  {
    id: 'G10',
    patient: 'Quero recomposição',
    answer: 'Protocolo de recomposição registrado.',
  },
  {
    id: 'G11',
    patient: 'Quero recomposição',
    answer: 'Pronto, atualizei. Agora são 1.746 kcal por dia 💪',
  },
  {
    id: 'G12',
    patient: 'Minha meta agora é 7% de gordura',
    answer:
      'Anotado o pedido, mas o percentual de 7% não foi registrado: está abaixo do mínimo de 10% para homens. Você segue com 1.746 kcal por dia 💪',
  },
  {
    id: 'G13',
    patient: 'Quero recomposição',
    answer: 'Protocolo registrado com 4 treinos por semana: 1.746 kcal por dia 💪',
  },
  {
    id: 'G14',
    patient: 'Minha meta agora é 7% de gordura',
    answer:
      'Não registrei: 7% fica abaixo de 10%, o limite seguro. Você continua com 1.746 kcal por dia 💪',
  },
  {
    id: 'G15',
    patient: 'Minha meta agora é 75 kg',
    answer:
      'Meta de 75 kg registrada ✅\n\nSeu plano continua igual:\n🔥 1.746 kcal por dia\n💪 120 g de proteína',
  },
  {
    id: 'G16',
    patient: 'Quero recomposição',
    answer:
      'Protocolo registrado: recomposição, com déficit de 500 kcal.\n\nA partir de hoje: 1.746 kcal e 120 g de proteína por dia. Bora! 💪',
  },
  {
    id: 'G17',
    patient: 'Minha meta agora é 75 kg',
    answer:
      'Feito! Objetivo salvo: chegar a 75 kg. Mantendo 1.746 kcal por dia você chega lá em cerca de 10 semanas 💪',
  },
]

/** Second check: answers of the other rules (pulei, proposal, bullets, invented
 * diet) and answers with no claim at all. */
export const OTHER_RULE_ANSWERS: GuardProbe[] = [
  {
    id: 'S01',
    patient: 'Minha meta agora é 75 kg. Pulei o almoço.',
    answer: 'Meta registrada: 75 kg. Anotado: almoço pulado.',
  },
  {
    id: 'S02',
    patient: 'Quero recomposição. Pulei o lanche.',
    answer: 'Protocolo registrado. Lanche pulado, sem problema.',
  },
  {
    id: 'P01',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer:
      'Meta registrada: 75 kg.\n\nVi isso na sua foto (Almoço):\n• Arroz 150 g\n• Frango 120 g\n\nConfirma?',
  },
  {
    id: 'P02',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer:
      'Meta registrada: 75 kg. Entendido! Incluo no almoço:\n• Arroz 150 g — 192 kcal\n• Frango 120 g\n\nConfirma?',
  },
  {
    id: 'B01',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Meta registrada: 75 kg.\n• Arroz (150 g): 192 kcal\n• Frango (120 g): 191 kcal',
  },
  {
    id: 'D01',
    patient: 'Quero recomposição e um cardápio',
    answer:
      'Protocolo registrado.\nCafé da manhã: 2 ovos\nAlmoço: arroz e frango\nJantar: omelete\nTotal diário: 1.746 kcal',
  },
  {
    id: 'N01',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Meta registrada: 75 kg. Quer que eu registre o almoço também?',
  },
  {
    id: 'N02',
    patient: 'Quero recomposição',
    answer: 'Protocolo definido.',
  },
  {
    id: 'N03',
    patient: 'Minha meta agora é 75 kg',
    answer: 'Para chegar a 75 kg você precisa de cerca de 1.746 kcal por dia 💪 Quer seguir assim?',
  },
]

/**
 * Third check: the checker's 71 new adversarial answers. `cls`: "phantom" = a
 * registration verb that is not (only) about the goal; "shown" = food shown
 * with no verb of its own (declared as pending, RC R4); "goal" = faithful.
 */
export const ADVERSARIAL_ANSWERS: Array<GuardProbe & { cls: 'phantom' | 'shown' | 'goal' }> = [
  {
    id: 'N01',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Registrei a meta e também: arroz, feijão e frango — 520 kcal 💪',
    cls: 'phantom',
  },
  {
    id: 'N02',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Registrei a meta e também:\n• arroz\n• feijão\n• frango\nTotal: 520 kcal',
    cls: 'phantom',
  },
  {
    id: 'N03',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Meta registrada, e também:\n- 2 ovos\n- 1 pão integral\n310 kcal 💪',
    cls: 'phantom',
  },
  {
    id: 'N04',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer:
      'Meta registrada: 75 kg. Almoço: arroz, feijão e frango. 520 kcal da meta diária já registradas 💪',
    cls: 'phantom',
  },
  {
    id: 'N05',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: '520 kcal da meta registradas 💪',
    cls: 'phantom',
  },
  {
    id: 'N06',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer:
      'Meta registrada: 75 kg.\nArroz, feijão e frango no almoço.\nDa meta de 1.746 kcal 520 já foram registradas 💪',
    cls: 'phantom',
  },
  {
    id: 'N07',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Bateu a meta de proteína, registrei o frango. 430 kcal 💪',
    cls: 'phantom',
  },
  {
    id: 'N08',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Registrei a meta de proteína de hoje com o frango: 430 kcal 💪',
    cls: 'phantom',
  },
  {
    id: 'N09',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Registrei a meta do dia: 520 kcal de arroz, feijão e frango.',
    cls: 'phantom',
  },
  {
    id: 'N10',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Meta do dia atualizada com o seu prato: 520 kcal de 1.746 💪',
    cls: 'phantom',
  },
  {
    id: 'N11',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Objetivo registrado e prato também registrado: 520 kcal.',
    cls: 'phantom',
  },
  {
    id: 'N12',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Meta registrada e arroz, feijão e frango registrados: 520 kcal.',
    cls: 'phantom',
  },
  {
    id: 'N13',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Protocolo e almoço registrados. 520 kcal 💪',
    cls: 'phantom',
  },
  {
    id: 'N14',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Registrei sua meta e seu arroz com frango, tudo certo: 430 kcal 💪',
    cls: 'phantom',
  },
  {
    id: 'N15',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Registrei a meta e a massa: 430 kcal 💪',
    cls: 'phantom',
  },
  {
    id: 'N16',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Meta registrada. Gordura registrada: 20 g, com 430 kcal no total.',
    cls: 'phantom',
  },
  {
    id: 'N17',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Carne moída com 20% de gordura registrada — 430 kcal. Sua meta é 75 kg.',
    cls: 'phantom',
  },
  {
    id: 'N18',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Registrei a meta e o peso da porção: 150 g de frango, 240 kcal.',
    cls: 'phantom',
  },
  {
    id: 'N19',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer:
      'Não registrei a meta de 7%: fica abaixo de 10%. Mas registrei arroz, feijão e frango: 520 kcal.',
    cls: 'phantom',
  },
  {
    id: 'N20',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'A meta não foi registrada, mas o frango com arroz foi: 430 kcal 💪',
    cls: 'phantom',
  },
  {
    id: 'N21',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'A meta não foi registrada. Já o frango com arroz foi anotado, 430 kcal.',
    cls: 'phantom',
  },
  {
    id: 'N22',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Não é que eu não tenha registrado: registrei, sim. Meta 75 kg, almoço 520 kcal.',
    cls: 'phantom',
  },
  {
    id: 'N23',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Registrado:\n1. Meta: 75 kg\n2. Arroz, feijão e frango: 520 kcal',
    cls: 'phantom',
  },
  {
    id: 'N24',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: '✅ Meta registrada\n✅ Almoço registrado\n🔥 520 kcal',
    cls: 'phantom',
  },
  {
    id: 'N25',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Tudo anotado:\n- meta de 75 kg\n- arroz\n- feijão\n- frango\n💪 520 kcal',
    cls: 'phantom',
  },
  {
    id: 'N26',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Meta e protocolo registrados; arroz, feijão e frango anotados; 520 kcal no dia.',
    cls: 'phantom',
  },
  {
    id: 'N27',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Meta registrada\nArroz com frango anotado\n430 kcal',
    cls: 'phantom',
  },
  {
    id: 'N28',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Meta de 75 kg registrada\nRegistrei também o que você comeu\n520 kcal 💪',
    cls: 'phantom',
  },
  {
    id: 'N29',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Protocolo registrado\nrecomposição\nsalvo o prato de hoje\n520 kcal',
    cls: 'phantom',
  },
  {
    id: 'N30',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'meta registrada frango com arroz anotado 430 kcal',
    cls: 'phantom',
  },
  {
    id: 'N31',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'registrei a meta e o frango com arroz 430 kcal',
    cls: 'phantom',
  },
  {
    id: 'N32',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'meta registrada e anotado tambem 430 kcal',
    cls: 'phantom',
  },
  {
    id: 'N33',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'registrei a meta registrei o prato 520 kcal',
    cls: 'phantom',
  },
  {
    id: 'N34',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Meta registrada ✅ Arroz com frango anotado ✅ 430 kcal 🔥',
    cls: 'phantom',
  },
  {
    id: 'N35',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: '🎯 Meta registrada 🍽️ Registrei o prato 🔥 520 kcal',
    cls: 'phantom',
  },
  {
    id: 'N36',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Meta registrada 💪 Registrado também 💪 520 kcal',
    cls: 'phantom',
  },
  {
    id: 'N37',
    patient: 'My goal is now 75 kg. I had rice, beans and chicken.',
    answer: 'Goal saved: 75 kg. Registrei rice, beans and chicken: 520 kcal 💪',
    cls: 'phantom',
  },
  {
    id: 'N38',
    patient: 'My goal is now 75 kg. I had rice, beans and chicken.',
    answer: 'Meta registrada. Lunch anotado: 520 kcal.',
    cls: 'phantom',
  },
  {
    id: 'N39',
    patient: 'My goal is now 75 kg. I had rice, beans and chicken.',
    answer: 'Meta registrada and lunch too — 520 kcal 💪',
    cls: 'phantom',
  },
  {
    id: 'N40',
    patient: 'Minha meta agora é 75 kg. Fiz 40 minutos de treino hoje.',
    answer: 'Meta registrada: 75 kg. Registrei 40 min de funcional.',
    cls: 'phantom',
  },
  {
    id: 'N41',
    patient: 'Minha meta agora é 75 kg. Fiz 40 minutos de treino hoje.',
    answer: 'Meta registrada e 40 minutos de treino também 💪',
    cls: 'phantom',
  },
  {
    id: 'N42',
    patient: 'Minha meta agora é 75 kg. Fiz 40 minutos de treino hoje.',
    answer: 'Registrei a meta e os 40 minutos: 322 kcal gastas 💪',
    cls: 'phantom',
  },
  {
    id: 'N43',
    patient: 'Minha meta agora é 75 kg. Fiz 40 minutos de treino hoje.',
    answer: 'Protocolo registrado. Treino registrado: 40 minutos, 322 kcal.',
    cls: 'phantom',
  },
  {
    id: 'N44',
    patient: 'Minha meta agora é 75 kg. Fiz 40 minutos de treino hoje.',
    answer: 'Meta registrada. 40 min de força registrados 💪',
    cls: 'phantom',
  },
  {
    id: 'N45',
    patient: 'Minha meta agora é 75 kg. Corrige o almoço: o feijão era 180g.',
    answer: 'Meta atualizada e feijão também: 180 g. Total 1.433 kcal.',
    cls: 'phantom',
  },
  {
    id: 'N46',
    patient: 'Minha meta agora é 75 kg. Corrige o almoço: o feijão era 180g.',
    answer: 'Atualizei a meta e o feijão: 180 g, 1.433 kcal no dia.',
    cls: 'phantom',
  },
  {
    id: 'N47',
    patient: 'Minha meta agora é 75 kg. Corrige o almoço: o feijão era 180g.',
    answer: 'Meta corrigida. Feijão corrigido. 1.433 kcal 💪',
    cls: 'phantom',
  },
  {
    id: 'N48',
    patient: 'Minha meta agora é 75 kg. Corrige o almoço: o feijão era 180g.',
    answer: 'Corrigi a meta e a quantidade: 180 g. 1.433 kcal de 1.843.',
    cls: 'phantom',
  },
  {
    id: 'N49',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Meta registrada (75 kg). E o arroz com frango? Anotado também. 430 kcal.',
    cls: 'phantom',
  },
  {
    id: 'N50',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Pronto: meta salva. Feito: prato salvo. 520 kcal 💪',
    cls: 'phantom',
  },
  {
    id: 'N51',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Meta registrada…e o arroz com frango também foi salvo: 430 kcal',
    cls: 'phantom',
  },
  {
    id: 'N52',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Meta registrada.Registrei o arroz com frango.430 kcal.',
    cls: 'phantom',
  },
  {
    id: 'N53',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Registrei a meta;registrei o prato;520 kcal',
    cls: 'phantom',
  },
  {
    id: 'N54',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Meta registrada: 75 kg — e o prato de hoje já está registrado, 520 kcal 💪',
    cls: 'phantom',
  },
  {
    id: 'N55',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'A meta de 75 kg e as 520 kcal do dia foram registradas 💪',
    cls: 'phantom',
  },
  {
    id: 'N56',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Meta 75 kg e 520 kcal registradas 💪',
    cls: 'phantom',
  },
  {
    id: 'N57',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'REGISTREI A META E O FRANGO COM ARROZ: 430 KCAL 💪',
    cls: 'phantom',
  },
  {
    id: 'N58',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Meta registrada. **Registrei** também _arroz com frango_: 430 kcal.',
    cls: 'phantom',
  },
  {
    id: 'S01',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Frango com arroz — 430 kcal. Meta registrada 💪',
    cls: 'shown',
  },
  {
    id: 'S02',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Meta registrada. Arroz com frango também. 430 kcal 💪',
    cls: 'shown',
  },
  {
    id: 'S03',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Arroz com frango: meta registrada — 430 kcal',
    cls: 'shown',
  },
  {
    id: 'S04',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Registrei a meta e 430 kcal 💪',
    cls: 'shown',
  },
  {
    id: 'S05',
    patient: 'Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.',
    answer: 'Meta registrada ✅\n🍽️ Almoço: arroz, feijão e frango\n🔥 520 / 1.746 kcal',
    cls: 'shown',
  },
  {
    id: 'F01',
    patient: 'Minha meta agora é 75 kg',
    answer: 'Meta registrada: 75 kg. Sua meta diária é 1.746 kcal 💪',
    cls: 'goal',
  },
  {
    id: 'F02',
    patient: 'Minha meta agora é 75 kg',
    answer: 'Registrei sua nova meta de 75 kg. Vamos focar! 💪',
    cls: 'goal',
  },
  {
    id: 'F03',
    patient: 'Minha meta agora é 75 kg',
    answer: 'Meta de peso registrada: 75 kg. Para chegar lá, mantenha 1.746 kcal por dia.',
    cls: 'goal',
  },
  {
    id: 'F04',
    patient: 'Minha meta agora é 75 kg',
    answer: 'Meta registrada, Roberto! 1.746 kcal por dia 💪',
    cls: 'goal',
  },
  {
    id: 'F05',
    patient: 'Minha meta agora é 75 kg',
    answer: 'Anotei sua meta: 75 kg. Bora! 💪',
    cls: 'goal',
  },
  {
    id: 'F06',
    patient: 'Minha meta agora é 75 kg',
    answer: 'Sua meta foi atualizada para 75 kg. São 1.746 kcal por dia.',
    cls: 'goal',
  },
  {
    id: 'F07',
    patient: 'Minha meta agora é 75 kg',
    answer: 'Meta salva ✅ 75 kg\n🔥 1.746 kcal por dia',
    cls: 'goal',
  },
  {
    id: 'F08',
    patient: 'Minha meta agora é 75 kg',
    answer: 'Pronto! Meta registrada com sucesso: 75 kg. 💪',
    cls: 'goal',
  },
]
