/**
 * The texts the app shows about the objective: the entry message of each of
 * the three protocols, and what the sign-up says about its decision
 * (docs/CALCULO-MPP.md §10m). Pure, no I/O. Portuguese (pt-BR) and English
 * (en-US).
 *
 * WHOSE WORDS THESE ARE
 *  - The three entry messages and the blocking phrase of ganho de massa are
 *    the client's own texts (rules "Recomposição corporal - Introdução e frase
 *    de boas vindas ao protocolo", "Ganho de massa muscular - introdução de
 *    boas vindas ao protocolo", "Manutenção - Frase de boas vindas ao
 *    protocolo de manutenção" and "Bloqueio de ganho de massa para quem está
 *    acima do peso", 3.4.1) with the edits listed one by one in the doc and
 *    nothing else: the method's name is out; the sentences that promise a
 *    reassessment every 14 (or 15) days, adjustments made for the person or
 *    "tell me when your training frequency changes" are cut until the app does
 *    those things; the internal headers written for the agent are not shown.
 *    No number was put inside a sentence of his.
 *  - The notice for a person placed in recomposição and the two short reasons
 *    for an unavailable ganho de massa are OUR wording. The cuts they cite
 *    come from the caller (`SignupEligibilityLimits`), never from this file.
 *  - English is OUR translation of all of them: the client wrote no English.
 * Implemented on 2026-10-07 at Eduardo's request; the client's confirmation of
 * every edit, of our wordings and of the translation is pending.
 *
 * SHAPE. Every function returns paragraphs. A paragraph may hold line breaks
 * ('\n'), as the client's texts do. The person's name goes into the first
 * paragraph only and is never split on.
 *
 * NOT HERE: the phrases of a change of phase (the change is not part of this
 * stage) and the phrase that hands over the targets.
 */
import type { SignupEligibilityBasis } from './protocol-eligibility.js'
import type { Protocol } from './types.js'

export type ProtocolMessageLocale = 'pt-BR' | 'en-US'

/** Paragraph → its lines. The first line of the first paragraph follows the name. */
type MessageLines = readonly (readonly string[])[]

// Editorial IDs used by both the original welcome and recurring Flow facts.
// Exact PT source phrases; EN welcomes remain their original translations.
const SHARED_PT = {
  recompositionGoal:
    'Isso significa reduzir gordura de forma progressiva, preservando ao máximo ou, idealmente, ganhando massa muscular e manter um processo sustentável no dia a dia — sem extremos e sem improviso.',
  gainTraining:
    'Neste protocolo, a musculação não é opcional. O ganho de massa muscular só acontece quando existe estímulo mecânico consistente. Sem treino de força regular, o superávit calórico perde a função construtiva e o risco de ganho de gordura aumenta significativamente — por isso, sem musculação, não é possível prosseguir no protocolo de ganho.',
  gainTarget:
    'Todos os dias você terá uma meta de calorias definida em leve superávit, ou seja, sobrando. O ideal é terminar o dia o mais próximo possível desse valor:',
  gainProtein:
    'Nesta fase, a meta de proteína é fundamental. Bater proteína todos os dias é o que fornece ao corpo o material necessário para construir músculo, sustentar a recuperação e transformar o estímulo do treino em resultado. Sem proteína consistente, não há hipertrofia relevante — mesmo com mais calorias.',
  gainProgress:
    'O progresso aqui não é medido apenas pela balança. A principal referência é a evolução no treino: mais carga, mais repetições, mais volume ao longo das semanas. Peso e medidas entram como apoio, nunca como decisão isolada.',
  maintenanceTarget:
    'Nesta etapa, você terá uma meta de calorias de manutenção (sem déficit e sem superávit). A regra é simples: terminar o dia o mais próximo possível da meta.',
  maintenanceConsistency:
    'O objetivo aqui não é “acertar perfeito todo dia”, é manter estabilidade semanal com consistência real.',
  maintenanceActive:
    'manutenção não é pausa e não é “soltar o plano”. É a fase que protege o que você conquistou, reduz o risco de efeito sanfona e consolida seus hábitos para o próximo ciclo, se necessário.',
} as const

const WELCOME: Record<ProtocolMessageLocale, Record<Protocol, MessageLines>> = {
  'pt-BR': {
    recomposicao: [
      [
        'a partir de agora você entra oficialmente na fase de recomposição corporal.',
        SHARED_PT.recompositionGoal,
      ],
      [
        'Todos os dias você terá uma meta de calorias clara. A ideia é terminar o dia o mais próximo possível desse valor:',
        'nem muito abaixo, para evitar fome e quebra de consistência, nem acima, para não anular o déficit do dia.',
        'Esse equilíbrio diário é o que mantém o processo funcionando de forma previsível.',
      ],
      [
        'Durante essa fase, usamos também os blocos de 7.700 kcal como referência do método. Cada bloco completo representa, de forma aproximada, a perda de 1 kg de gordura corporal. Isso serve para você acompanhar o progresso, ver que o método está funcionando e ter clareza de que sua execução diária está fazendo efeito.',
      ],
      [
        'Sua missão é simples: executar o básico bem feito todos os dias.',
        'A estratégia e a leitura dos dados ficam comigo. Estamos construindo constância — e é isso que gera resultado.',
      ],
    ],
    ganho_massa: [
      [
        'agora você entra na fase de ganho de massa muscular. Aqui o objetivo é claro: fazer o músculo ganhar a corrida, com controle total do ganho de gordura e foco em performance no treino.',
      ],
      [SHARED_PT.gainTraining],
      [
        SHARED_PT.gainTarget,
        'abaixo da meta, pode faltar energia para treinar bem e sustentar a construção muscular;',
        'acima da meta, o risco é acelerar ganho de gordura sem benefício real.',
        'O equilíbrio diário é o que mantém o ganho limpo, previsível e sob controle.',
      ],
      [
        'Importante: a sua meta calórica diária está diretamente ligada à frequência semanal de treino que você informou. Quanto mais sessões de musculação na semana, maior a demanda energética; quanto menos treinos, menor a necessidade.',
        'Se você treinar mais vezes do que o combinado sem ajuste, as calorias podem se tornar insuficientes e limitar o ganho muscular.',
        'Se você treinar menos vezes do que o informado, o excesso calórico deixa de ser utilizado pelo músculo e tende a virar gordura.',
      ],
      [SHARED_PT.gainProtein],
      [SHARED_PT.gainProgress],
      [
        'Sua missão é simples: treinar com consistência, bater proteína e respeitar a meta calórica alinhada à sua frequência real de treino.',
        'Eu cuido da estratégia, para garantir que o ganho seja real, controlado e sustentável.',
      ],
    ],
    manutencao: [
      [
        `agora você entra na fase de manutenção — e aqui vai um ponto importante: ${SHARED_PT.maintenanceActive}`,
      ],
      [
        SHARED_PT.maintenanceTarget,
        'muito abaixo disso costuma gerar fome, compulsão e instabilidade;',
        'muito acima disso tende a virar ganho de gordura ao longo das semanas.',
        SHARED_PT.maintenanceConsistency,
      ],
      [
        'A proteína e a atividade física continuam obrigatórias porque elas que sustentam sua composição corporal e evita que você perca qualidade muscular enquanto aumenta a flexibilidade alimentar. Manutenção com proteína baixa e sem atividade física vira manutenção fraca — e isso abre brecha para regressão silenciosa.',
      ],
      [
        'Sua missão é simples: manter o básico bem feito com mais flexibilidade e zero bagunça.',
        'Eu cuido do monitoramento e de manter o processo estável — porque é isso que faz você evoluir sem precisar recomeçar do zero.',
      ],
    ],
  },
  'en-US': {
    recomposicao: [
      [
        'as of now you are officially entering the body recomposition phase.',
        'That means reducing fat progressively, preserving muscle mass as much as possible or, ideally, gaining it, and keeping a process that is sustainable day to day — no extremes and no improvisation.',
      ],
      [
        'Every day you will have a clear calorie target. The idea is to end the day as close to that number as possible:',
        "not far below it, to avoid hunger and a break in consistency, and not above it, so the day's deficit is not canceled out.",
        'That daily balance is what keeps the process working predictably.',
      ],
      [
        "During this phase, we also use the 7,700 kcal blocks as the method's reference. Each completed block represents, approximately, the loss of 1 kg of body fat. This lets you follow your progress, see that the method is working and be clear that your daily execution is having an effect.",
      ],
      [
        'Your mission is simple: do the basics well, every day.',
        'The strategy and the reading of the data stay with me. We are building consistency — and that is what produces results.',
      ],
    ],
    ganho_massa: [
      [
        'you are now entering the muscle gain phase. The goal here is clear: make muscle win the race, with full control of fat gain and a focus on training performance.',
      ],
      [
        'In this protocol, strength training is not optional. Muscle gain only happens when there is a consistent mechanical stimulus. Without regular strength training, the calorie surplus loses its building function and the risk of fat gain rises significantly — that is why, without strength training, it is not possible to continue in the gain protocol.',
      ],
      [
        'Every day you will have a calorie target set at a slight surplus, that is, with some to spare. The ideal is to end the day as close to that number as possible:',
        'below the target, you may lack the energy to train well and sustain muscle building;',
        'above the target, the risk is speeding up fat gain with no real benefit.',
        'The daily balance is what keeps the gain clean, predictable and under control.',
      ],
      [
        'Important: your daily calorie target is directly tied to the weekly training frequency you reported. The more strength training sessions in the week, the higher the energy demand; the fewer the sessions, the lower the need.',
        'If you train more often than agreed without an adjustment, the calories may become insufficient and limit muscle gain.',
        'If you train less often than you reported, the calorie excess stops being used by the muscle and tends to turn into fat.',
      ],
      [
        'In this phase, the protein target is essential. Hitting your protein every day is what gives the body the material it needs to build muscle, sustain recovery and turn the training stimulus into results. Without consistent protein, there is no meaningful hypertrophy — even with more calories.',
      ],
      [
        'Progress here is not measured by the scale alone. The main reference is how your training evolves: more load, more repetitions, more volume over the weeks. Weight and measurements come in as support, never as a decision on their own.',
      ],
      [
        'Your mission is simple: train consistently, hit your protein and respect the calorie target aligned with your real training frequency.',
        'I take care of the strategy, to make sure the gain is real, controlled and sustainable.',
      ],
    ],
    manutencao: [
      [
        'you are now entering the maintenance phase — and here is an important point: maintenance is not a break and it is not “letting go of the plan”. It is the phase that protects what you have achieved, reduces the risk of the yo-yo effect and consolidates your habits for the next cycle, if needed.',
      ],
      [
        'At this stage, you will have a maintenance calorie target (no deficit and no surplus). The rule is simple: end the day as close to the target as possible.',
        'far below it usually brings hunger, compulsive eating and instability;',
        'far above it tends to become fat gain over the weeks.',
        'The goal here is not to “get it perfect every day”; it is to keep weekly stability with real consistency.',
      ],
      [
        'Protein and physical activity remain mandatory because they are what sustains your body composition and keeps you from losing muscle quality while dietary flexibility increases. Maintenance with low protein and no physical activity becomes weak maintenance — and that opens the door to silent regression.',
      ],
      [
        'Your mission is simple: keep the basics well done, with more flexibility and zero mess.',
        'I take care of the monitoring and of keeping the process stable — because that is what lets you progress without having to start over from scratch.',
      ],
    ],
  },
}

/** A name as one line: trimmed, inner runs of white space as one space. */
function singleLineName(name: string | null | undefined): string {
  return typeof name === 'string' ? name.trim().replace(/\s+/g, ' ') : ''
}

function capitalised(text: string): string {
  return text.charAt(0).toUpperCase() + text.slice(1)
}

/**
 * The entry message of a protocol, addressed to the person by name, as the
 * client wrote it ("{nome}, a partir de agora …").
 *
 * Without a name (absent, empty or only white space — an account whose name
 * was never recorded) the vocative is left out and the sentence starts with a
 * capital letter; nothing else changes.
 */
export function protocolWelcomeMessage(
  protocol: Protocol,
  name: string | null | undefined,
  locale: ProtocolMessageLocale,
): string[] {
  const person = singleLineName(name)
  return WELCOME[locale][protocol].map((lines, paragraph) => {
    if (paragraph > 0) return lines.join('\n')
    const [opening = '', ...rest] = lines
    return [person ? `${person}, ${opening}` : capitalised(opening), ...rest].join('\n')
  })
}

/**
 * Canonical PT instructions for Flow, independent of response locale/style.
 * Common fragments come from B0's SHARED_PT above. Additional explanatory
 * wording comes from the same editorial sources, explicitly mapped in
 * docs/CALCULO-MPP.md; it is not an approved clinical decision or a capability.
 * Pure selection, fresh array, no owner/cache/I/O; never changes a phase/target.
 */
export function protocolPhaseExplanation(protocol: unknown): readonly string[] {
  switch (protocol) {
    case 'recomposicao':
      return [
        SHARED_PT.recompositionGoal,
        'O bloco de 7.700 kcal é uma referência teórica e aproximada do processo, associada em modelos populacionais a cerca de 1 kg de gordura; não mede a perda individual de gordura nem garante um resultado.',
        'O exercício registrado participa do balanço do dia e do bloco, mas não altera a meta de calorias nem libera comida extra.',
        'Um prazo estimado é referência de planejamento, nunca promessa individual. Não crie uma data ou projeção sem dados oficiais.',
        'Explique um ajuste confirmado como calibração natural do processo, nunca como correção de erro. Não apresente sugestão como ajuste realizado.',
      ]
    case 'ganho_massa':
      return [
        SHARED_PT.gainTarget,
        SHARED_PT.gainTraining,
        SHARED_PT.gainProtein,
        SHARED_PT.gainProgress,
        'Hipertrofia não é comer mais indiscriminadamente: primeiro se audita o treino — depois a dieta. Não use peso semanal isolado como gatilho nem anuncie ajuste sem confirmação.',
      ]
    case 'manutencao':
      return [
        SHARED_PT.maintenanceActive,
        SHARED_PT.maintenanceTarget,
        SHARED_PT.maintenanceConsistency,
        'Manutenção é uma fase ativa: estabilizar peso e composição corporal, consolidar hábitos e aumentar flexibilidade com consistência. Não anuncie pausa, troca de fase ou ajuste sem confirmação.',
      ]
    default:
      return []
  }
}

/**
 * Notice for a person placed in recomposição without being asked (C1 to C3 of
 * `decideSignupEligibility`). Our wording: the client gave only its content
 * (audio of 24/01/2026) — say that the person is outside the normal range and
 * is being placed in recomposição automatically.
 */
export function signupAssignedNotice(locale: ProtocolMessageLocale): string[] {
  return [
    locale === 'en-US'
      ? 'Based on the data you reported, you are above the healthy range at this moment. For that reason, your protocol is set automatically: body recomposition.'
      : 'Pelos dados que você informou, você está acima da faixa saudável neste momento. Por isso, o seu protocolo é definido automaticamente: recomposição corporal.',
  ]
}

/**
 * The client's standard blocking phrase of ganho de massa (3.4.1), for a
 * person PLACED in recomposição — the only case it was written for: it ends by
 * leading to recomposição. `basis` says which of the two the sentence names,
 * the one that decided: the body fat percentage or the BMI.
 *
 * Not for a person within the range whose ganho de massa is unavailable: that
 * person may still choose manutenção, and gets one of the reasons below.
 */
export function gainBlockedAboveRangeMessage(
  basis: SignupEligibilityBasis,
  locale: ProtocolMessageLocale,
): string[] {
  if (locale === 'en-US') {
    const measure = basis === 'BF' ? 'your current body fat percentage' : 'your current BMI'
    return [
      `Based on the data we have collected so far, ${measure} places you in a range above what is recommended for starting a muscle gain protocol at this moment. It is important to explain this to you with transparency: muscle gain presupposes a calorie surplus, which under these conditions tends to cause more body fat accumulation, and that would be neither safe nor strategic right now. For this reason, the best course of action at this moment is for us to start a body recomposition protocol. In that protocol, you will keep stimulating muscle gain, but in a controlled way and together with body fat loss. Muscle gain has not been denied, only postponed: it comes back into consideration when your indicators are in a more suitable range, if that is still your goal.`,
    ]
  }
  const measure = basis === 'BF' ? 'seu percentual de gordura atual' : 'seu IMC atual'
  return [
    `Com base nos dados que coletamos até aqui, ${measure} coloca você em uma faixa acima do recomendado para iniciar, neste momento, um protocolo de ganho de massa muscular. É importante te explicar isso com transparência: o ganho de massa muscular pressupõe um superávit calórico, que nessas condições tende a gerar mais acúmulo de gordura corporal, o que não seria seguro nem estratégico agora. Por esse motivo, a melhor conduta neste momento é iniciarmos um protocolo de recomposição corporal. Nesse protocolo, você continuará estimulando ganho de massa muscular, porém de forma controlada e acompanhada de perda de gordura corporal. O ganho de massa muscular não foi negado, apenas adiado: ele volta a ser considerado quando seus índices estiverem em uma faixa mais adequada, caso esse ainda seja o seu objetivo.`,
  ]
}

/**
 * A number as the person reads it: at most two decimal places, no trailing
 * zeros, decimal comma in Portuguese. Written by hand so that the text never
 * depends on the locale data of the runtime.
 */
function readableNumber(value: number, locale: ProtocolMessageLocale): string {
  const rounded = Math.round(value * 100) / 100
  const text = Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(2).replace(/0+$/, '')
  return locale === 'pt-BR' ? text.replace('.', ',') : text
}

/**
 * Reason shown to a person WITHIN the range whose ganho de massa is
 * unavailable because the informed body fat is above the entry cut of the
 * protocol (`limits.bodyFatGain` of the decision: the cut of the person's
 * sex). Our wording; the number is the caller's.
 */
export function gainUnavailableBodyFatReason(
  bodyFatGainLimit: number,
  locale: ProtocolMessageLocale,
): string[] {
  const cut = readableNumber(bodyFatGainLimit, locale)
  return [
    locale === 'en-US'
      ? `The muscle gain protocol requires a body fat percentage of ${cut}% or less. The percentage you reported is above that limit.`
      : `O protocolo de ganho de massa muscular exige percentual de gordura corporal de até ${cut}%. O percentual que você informou está acima desse limite.`,
  ]
}

/** n39: a BF report never opens gain when the independent BMI criterion fails. */
export function gainUnavailableBmiReason(
  bmiLimit: number,
  locale: ProtocolMessageLocale,
): string[] {
  const cut = readableNumber(bmiLimit, locale)
  return [
    locale === 'en-US'
      ? `The muscle gain protocol requires a BMI below ${cut}, calculated from your weight and height. The reported body fat percentage does not replace this criterion. You may choose body recomposition or maintenance.`
      : `O protocolo de ganho de massa muscular exige IMC abaixo de ${cut}, calculado a partir do seu peso e da sua altura. O percentual de gordura informado não substitui esse critério. Você pode escolher recomposição corporal ou manutenção.`,
  ]
}

/**
 * Reason shown to a person WITHIN the range whose ganho de massa is
 * unavailable because the strength training is below the minimum
 * (`limits.trainingMin`). Our wording, built from the client's entry criterion
 * ("musculação ≥ 3x por semana" / "Sem esse critério, superávit calórico vira
 * gordura."); the minimum and the sessions the person informed are the
 * caller's.
 */
export function gainUnavailableTrainingReason(
  trainingMin: number,
  informedSessions: number,
  locale: ProtocolMessageLocale,
): string[] {
  const minimum = readableNumber(trainingMin, locale)
  const informed = readableNumber(informedSessions, locale)
  return [
    locale === 'en-US'
      ? `The muscle gain protocol requires strength training at least ${minimum} ${trainingMin === 1 ? 'time' : 'times'} a week. Without this criterion, a calorie surplus turns into fat. You reported ${informed} a week.`
      : `O protocolo de ganho de massa muscular exige musculação pelo menos ${minimum} ${trainingMin === 1 ? 'vez' : 'vezes'} por semana. Sem esse critério, superávit calórico vira gordura. Você informou ${informed} por semana.`,
  ]
}
