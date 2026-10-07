/**
 * Audit 2026-10-07 — rule B: the texts the app shows about the objective — the
 * entry message of each of the three protocols and what the sign-up says about
 * its decision. Rule, every edit and the pendencies: docs/CALCULO-MPP.md §10l
 * to §10n. Code: packages/core/src/protocol-messages.ts (pure functions).
 *
 * WHO SHOWS THEM. The server only: the sign-up eligibility check
 * (POST /api/mobile/v1/onboarding/eligibility), the completion of the sign-up
 * (`protocol_welcome`) and the read of the current objective
 * (GET /api/mobile/v1/protocol). The published app does not read any of them
 * yet. The legacy WhatsApp entry never calls this code.
 *
 * WHOSE WORDS THESE ARE
 *   The three entry messages and the blocking phrase of ganho de massa are the
 *   client's (Dr. Roberto) own texts, from his rules "Recomposição corporal -
 *   Introdução e frase de boas vindas ao protocolo", "Ganho de massa muscular -
 *   introdução de boas vindas ao protocolo", "Manutenção - Frase de boas vindas
 *   ao protocolo de manutenção" and "Bloqueio de ganho de massa para quem está
 *   acima do peso" (3.4.1). They are copied below AS HE WROTE THEM, and each
 *   text served is rebuilt from his original with the edits listed in `EDITS`
 *   — the same list of docs/CALCULO-MPP.md §10m — and nothing else: the
 *   method's name is out; the sentences that promise a reassessment every 14
 *   (or 15) days, adjustments made for the person or "tell me when your
 *   training frequency changes" are cut until the app does those things. No
 *   number was put inside a sentence of his.
 *   The notice for a person placed in recomposição and the two short reasons
 *   for an unavailable ganho de massa are OUR wording; the cuts they cite come
 *   from the decision (`limits`), never from the text.
 *   English is OUR translation of everything: the client wrote no English.
 * Implementado em 2026-10-07 a pedido do Eduardo; confirmação do cliente
 * pendente para cada edição, para as redações nossas e para a tradução.
 *
 * WHAT IS PINNED: every text, word for word, in pt-BR and en-US; that none
 * carries the method's name, the physician's name, "BodyFlow", "BMR", "TDEE",
 * "BF" as an abbreviation or an emoji, in either language and for either sex;
 * that the Flow's public-name projection (flow-public-names.ts) hands each one
 * back untouched; where the person's name goes.
 *
 * NUMBERS AND NAMES — no patient here. "Marina" is a made-up name. 19 / 27 and
 * 3 are the client's entry cuts of ganho de massa, read from the decision.
 *
 * Declared pendencies (CLAUDE.md criterion 2; same lines in docs/CALCULO-MPP.md §10n):
 *
 * > RC B — cenário texto de entrada dos três protocolos variante promessa de reavaliação a cada 14 (ou 15) dias e de ajustes do plano (frases cortadas até a reavaliação existir no app) NÃO coberta nesta PR (pendência da audit 2026-10-07)
 * > RC B — cenário texto de entrada do ganho de massa variante avisar mudança de frequência de treino (frase cortada: no app não há onde informar) NÃO coberta nesta PR (pendência da audit 2026-10-07)
 * > RC B — cenário texto de entrada do ganho de massa variante meta de calorias ligada à frequência semanal de treino, como o texto diz (no app a meta de calorias usa o nível de atividade; a musculação por semana entra na proteína) NÃO coberta nesta PR (pendência da audit 2026-10-07)
 * > RC B — cenário frase de bloqueio do ganho de massa para quem é colocado em recomposição variante promessa de voltar a considerar o ganho quando os índices melhorarem (o app não percebe a mudança de faixa e não tem saída da recomposição) NÃO coberta nesta PR (pendência da audit 2026-10-07)
 * > RC B — cenário textos em inglês variante tradução aprovada pelo cliente (ele não escreveu nenhum texto em inglês; a tradução é nossa) NÃO coberta nesta PR (pendência da audit 2026-10-07)
 * > RC B — cenário edições nos textos do cliente e redações nossas (aviso de recomposição definida, motivo da gordura entre os cortes, motivo da musculação abaixo do mínimo) variante aprovação do cliente e do Eduardo NÃO coberta nesta PR (pendência da audit 2026-10-07)
 * > RC B — cenário frase de entrega das metas do cliente ("plano inicial … organizado", com água, sono e passos) variante uso depois do cadastro NÃO coberta nesta PR (pendência da audit 2026-10-07)
 * > RC B — cenário conferência do objetivo chamada antes do aceite dos documentos variante recusa no servidor (a ordem das telas é do app; a rota responde a qualquer conta autenticada e não guarda nada) NÃO coberta nesta PR (pendência da audit 2026-10-07)
 * > RC B — cenário app publicado hoje (ignora o campo novo e não chama as duas rotas novas) variante mensagem de entrada, conferência e objetivo no Perfil visíveis na tela NÃO coberta nesta PR (pendência da audit 2026-10-07)
 * > RC B — cenário valor com mais de duas casas decimais variante conferência do arredondamento contra o banco real (o arredondamento do numeric foi reproduzido em código; nenhum banco foi lido nesta etapa) NÃO coberta nesta PR (pendência da audit 2026-10-07)
 * > RC B — cenário repetição da conclusão do cadastro com altura, peso ou gordura de mais de duas casas decimais variante mesma resposta na repetição (a função SQL compara o valor gravado, arredondado, com o enviado, e a repetição vira 409 onboarding_already_completed; comportamento anterior a esta mudança) NÃO coberta nesta PR (pendência da audit 2026-10-07)
 */

import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import {
  DEFAULT_CALC_CONFIG,
  decideSignupEligibility,
  gainBlockedAboveRangeMessage,
  gainUnavailableBodyFatReason,
  gainUnavailableTrainingReason,
  type Protocol,
  type ProtocolMessageLocale,
  protocolWelcomeMessage,
  type Sex,
  signupAssignedNotice,
} from '@mpp/core'
import { describe, expect, it } from 'vitest'
import { projectFlowPublicNames } from '../flow-public-names.js'

const HERE = dirname(fileURLToPath(import.meta.url))
const DOC = readFileSync(resolve(HERE, '../../../../docs/CALCULO-MPP.md'), 'utf8')
const MESSAGES_SOURCE = readFileSync(
  resolve(HERE, '../../../core/src/protocol-messages.ts'),
  'utf8',
)

const NAME = 'Marina'
const PROTOCOLS: Protocol[] = ['recomposicao', 'ganho_massa', 'manutencao']
const LOCALES: ProtocolMessageLocale[] = ['pt-BR', 'en-US']
const SEXES: Sex[] = ['masculino', 'feminino']

/** One line: every run of white space (line separators included) as one space. */
function oneLine(text: string): string {
  return text.replace(/\s+/g, ' ').trim()
}

// ── The client's texts, AS HE WROTE THEM ────────────────────────────────────
// From the export of his rules, from the vocative on (the header above it is
// an instruction for the agent). The line separators of the export are shown
// as one space; not a letter was changed.

const CLIENT_ORIGINAL = {
  recomposicao:
    '{nome}, a partir de agora você entra oficialmente na fase de recomposição corporal do MPP. Isso significa reduzir gordura de forma progressiva, preservando ao máximo ou, idealmente, ganhando massa muscular e manter um processo sustentável no dia a dia — sem extremos e sem improviso. Todos os dias você terá uma meta de calorias clara. A ideia é terminar o dia o mais próximo possível desse valor: nem muito abaixo, para evitar fome e quebra de consistência, nem acima, para não anular o déficit do dia. Esse equilíbrio diário é o que mantém o processo funcionando de forma previsível. Durante essa fase, usamos também os blocos de 7.700 kcal como referência do método. Para o MPP, cada bloco completo representa, de forma aproximada, a perda de 1 kg de gordura corporal. Isso serve para você acompanhar o progresso, ver que o método está funcionando e ter clareza de que sua execução diária está fazendo efeito. A cada 14 dias, fazemos uma reavaliação rápida para ajustar o plano, confirmar que tudo está no ritmo certo e manter o processo confortável e eficiente. Sua missão é simples: executar o básico bem feito todos os dias. A estratégia, os ajustes e a leitura dos dados ficam comigo. Estamos construindo constância — e é isso que gera resultado.',
  ganho_massa:
    '{nome}, agora você entra na fase de ganho de massa muscular do MPP. Aqui o objetivo é claro: fazer o músculo ganhar a corrida, com controle total do ganho de gordura e foco em performance no treino. Neste protocolo, a musculação não é opcional. O ganho de massa muscular só acontece quando existe estímulo mecânico consistente. Sem treino de força regular, o superávit calórico perde a função construtiva e o risco de ganho de gordura aumenta significativamente — por isso, sem musculação, não é possível prosseguir no protocolo de ganho. Todos os dias você terá uma meta de calorias definida em leve superávit, ou seja, sobrando. O ideal é terminar o dia o mais próximo possível desse valor: abaixo da meta, pode faltar energia para treinar bem e sustentar a construção muscular; acima da meta, o risco é acelerar ganho de gordura sem benefício real. O equilíbrio diário é o que mantém o ganho limpo, previsível e sob controle. Importante: a sua meta calórica diária está diretamente ligada à frequência semanal de treino que você informou. Quanto mais sessões de musculação na semana, maior a demanda energética; quanto menos treinos, menor a necessidade. 👉 Se houver qualquer mudança na sua frequência de treino — aumento ou redução — isso precisa ser informado. Se você treinar mais vezes do que o combinado sem ajuste, as calorias podem se tornar insuficientes e limitar o ganho muscular. Se você treinar menos vezes do que o informado, o excesso calórico deixa de ser utilizado pelo músculo e tende a virar gordura. Nesta fase, a meta de proteína é fundamental. Bater proteína todos os dias é o que fornece ao corpo o material necessário para construir músculo, sustentar a recuperação e transformar o estímulo do treino em resultado. Sem proteína consistente, não há hipertrofia relevante — mesmo com mais calorias. O progresso aqui não é medido apenas pela balança. A principal referência é a evolução no treino: mais carga, mais repetições, mais volume ao longo das semanas. Peso e medidas entram como apoio, nunca como decisão isolada. A cada 15 dias, fazemos reavaliações para confirmar que: o treino está progredindo, as calorias estão adequadas ao seu nível de treino, e a gordura segue dentro dos limites do método. Se algo sair do eixo, o plano é ajustado antes que vire problema. Sua missão é simples: treinar com consistência, bater proteína e respeitar a meta calórica alinhada à sua frequência real de treino. Eu cuido dos ajustes, dos limites e da estratégia, para garantir que o ganho seja real, controlado e sustentável.',
  manutencao:
    '{nome}, agora você entra na fase de manutenção MPP — e aqui vai um ponto importante: manutenção não é pausa e não é “soltar o plano”. É a fase que protege o que você conquistou, reduz o risco de efeito sanfona e consolida seus hábitos para o próximo ciclo, se necessário. Nesta etapa, você terá uma meta de calorias de manutenção (sem déficit e sem superávit). A regra é simples: terminar o dia o mais próximo possível da meta. muito abaixo disso costuma gerar fome, compulsão e instabilidade; muito acima disso tende a virar ganho de gordura ao longo das semanas. O objetivo aqui não é “acertar perfeito todo dia”, é manter estabilidade semanal com consistência real. A proteína e a atividade física continuam obrigatórias porque elas que sustentam sua composição corporal e evita que você perca qualidade muscular enquanto aumenta a flexibilidade alimentar. Manutenção com proteína baixa e sem atividade física vira manutenção fraca — e isso abre brecha para regressão silenciosa. Nesta fase, a gente também faz ajustes pequenos e inteligentes: se o peso começar a derivar, a correção é leve (geralmente ±100 kcal), baseada em tendência — não em um dia isolado. As reavaliações acontecem a cada 14 dias (ou antes, se sua rotina mudar, principalmente rotina de treinos), justamente para garantir que você continue no controle sem precisar ficar obcecado por números. Sua missão é simples: manter o básico bem feito com mais flexibilidade e zero bagunça. Eu cuido do monitoramento, dos ajustes e de manter o processo estável — porque é isso que faz você evoluir sem precisar recomeçar do zero.',
  /** The phrase between quotes at the end of rule 3.4.1. */
  bloqueio:
    'Com base nos dados que coletamos até aqui, seu percentual de gordura/IMC atual o coloca em uma faixa acima do recomendado para iniciar, neste momento, um protocolo de ganho de massa muscular. É importante te explicar isso com transparência: o ganho de massa muscular pressupõe um superávit calórico, que nessas condições tende a gerar mais acúmulo de gordura corporal, o que não seria seguro nem estratégico agora. Por esse motivo, a melhor conduta neste momento é iniciarmos um protocolo de recomposição corporal. Nesse protocolo, você continuará estimulando ganho de massa muscular, porém de forma controlada e acompanhada de perda de gordura corporal. Assim que seus índices estiverem em uma faixa mais adequada, eu mesmo irei te conduzir para o protocolo de ganho de massa muscular, caso esse ainda seja o seu objetivo.',
} as const

// ── Every edit, one by one (docs/CALCULO-MPP.md §10m) ───────────────────────

/** `to: ''` = the passage was cut. */
type Edit = { from: string; to: string }

const EDITS: Record<Protocol, Edit[]> = {
  recomposicao: [
    { from: 'na fase de recomposição corporal do MPP.', to: 'na fase de recomposição corporal.' },
    { from: 'Para o MPP, cada bloco completo representa', to: 'Cada bloco completo representa' },
    {
      from: 'A cada 14 dias, fazemos uma reavaliação rápida para ajustar o plano, confirmar que tudo está no ritmo certo e manter o processo confortável e eficiente.',
      to: '',
    },
    {
      from: 'A estratégia, os ajustes e a leitura dos dados ficam comigo.',
      to: 'A estratégia e a leitura dos dados ficam comigo.',
    },
  ],
  ganho_massa: [
    {
      from: 'na fase de ganho de massa muscular do MPP.',
      to: 'na fase de ganho de massa muscular.',
    },
    {
      from: '👉 Se houver qualquer mudança na sua frequência de treino — aumento ou redução — isso precisa ser informado.',
      to: '',
    },
    {
      from: 'A cada 15 dias, fazemos reavaliações para confirmar que: o treino está progredindo, as calorias estão adequadas ao seu nível de treino, e a gordura segue dentro dos limites do método. Se algo sair do eixo, o plano é ajustado antes que vire problema.',
      to: '',
    },
    {
      from: 'Eu cuido dos ajustes, dos limites e da estratégia, para garantir',
      to: 'Eu cuido da estratégia, para garantir',
    },
  ],
  manutencao: [
    { from: 'na fase de manutenção MPP —', to: 'na fase de manutenção —' },
    {
      from: 'Nesta fase, a gente também faz ajustes pequenos e inteligentes: se o peso começar a derivar, a correção é leve (geralmente ±100 kcal), baseada em tendência — não em um dia isolado.',
      to: '',
    },
    {
      from: 'As reavaliações acontecem a cada 14 dias (ou antes, se sua rotina mudar, principalmente rotina de treinos), justamente para garantir que você continue no controle sem precisar ficar obcecado por números.',
      to: '',
    },
    {
      from: 'Eu cuido do monitoramento, dos ajustes e de manter o processo estável',
      to: 'Eu cuido do monitoramento e de manter o processo estável',
    },
  ],
}

/** The blocking phrase names only what decided: the body fat or the BMI. */
function blockEdits(measure: 'seu percentual de gordura atual' | 'seu IMC atual'): Edit[] {
  return [
    { from: 'seu percentual de gordura/IMC atual o coloca', to: `${measure} coloca você` },
    {
      from: 'Assim que seus índices estiverem em uma faixa mais adequada, eu mesmo irei te conduzir para o protocolo de ganho de massa muscular, caso esse ainda seja o seu objetivo.',
      to: 'O ganho de massa muscular não foi negado, apenas adiado: ele volta a ser considerado quando seus índices estiverem em uma faixa mais adequada, caso esse ainda seja o seu objetivo.',
    },
  ]
}

/** Applies each edit where the passage occurs exactly once; fails otherwise. */
function withEdits(original: string, edits: Edit[]): string {
  let text = original
  for (const edit of edits) {
    expect(text.split(edit.from), `trecho único no original: ${edit.from}`).toHaveLength(2)
    text = oneLine(text.split(edit.from).join(edit.to))
  }
  return text
}

// ── The texts served, word for word ─────────────────────────────────────────

const WELCOME_PT: Record<Protocol, string[]> = {
  recomposicao: [
    'Marina, a partir de agora você entra oficialmente na fase de recomposição corporal.\nIsso significa reduzir gordura de forma progressiva, preservando ao máximo ou, idealmente, ganhando massa muscular e manter um processo sustentável no dia a dia — sem extremos e sem improviso.',
    'Todos os dias você terá uma meta de calorias clara. A ideia é terminar o dia o mais próximo possível desse valor:\nnem muito abaixo, para evitar fome e quebra de consistência, nem acima, para não anular o déficit do dia.\nEsse equilíbrio diário é o que mantém o processo funcionando de forma previsível.',
    'Durante essa fase, usamos também os blocos de 7.700 kcal como referência do método. Cada bloco completo representa, de forma aproximada, a perda de 1 kg de gordura corporal. Isso serve para você acompanhar o progresso, ver que o método está funcionando e ter clareza de que sua execução diária está fazendo efeito.',
    'Sua missão é simples: executar o básico bem feito todos os dias.\nA estratégia e a leitura dos dados ficam comigo. Estamos construindo constância — e é isso que gera resultado.',
  ],
  ganho_massa: [
    'Marina, agora você entra na fase de ganho de massa muscular. Aqui o objetivo é claro: fazer o músculo ganhar a corrida, com controle total do ganho de gordura e foco em performance no treino.',
    'Neste protocolo, a musculação não é opcional. O ganho de massa muscular só acontece quando existe estímulo mecânico consistente. Sem treino de força regular, o superávit calórico perde a função construtiva e o risco de ganho de gordura aumenta significativamente — por isso, sem musculação, não é possível prosseguir no protocolo de ganho.',
    'Todos os dias você terá uma meta de calorias definida em leve superávit, ou seja, sobrando. O ideal é terminar o dia o mais próximo possível desse valor:\nabaixo da meta, pode faltar energia para treinar bem e sustentar a construção muscular;\nacima da meta, o risco é acelerar ganho de gordura sem benefício real.\nO equilíbrio diário é o que mantém o ganho limpo, previsível e sob controle.',
    'Importante: a sua meta calórica diária está diretamente ligada à frequência semanal de treino que você informou. Quanto mais sessões de musculação na semana, maior a demanda energética; quanto menos treinos, menor a necessidade.\nSe você treinar mais vezes do que o combinado sem ajuste, as calorias podem se tornar insuficientes e limitar o ganho muscular.\nSe você treinar menos vezes do que o informado, o excesso calórico deixa de ser utilizado pelo músculo e tende a virar gordura.',
    'Nesta fase, a meta de proteína é fundamental. Bater proteína todos os dias é o que fornece ao corpo o material necessário para construir músculo, sustentar a recuperação e transformar o estímulo do treino em resultado. Sem proteína consistente, não há hipertrofia relevante — mesmo com mais calorias.',
    'O progresso aqui não é medido apenas pela balança. A principal referência é a evolução no treino: mais carga, mais repetições, mais volume ao longo das semanas. Peso e medidas entram como apoio, nunca como decisão isolada.',
    'Sua missão é simples: treinar com consistência, bater proteína e respeitar a meta calórica alinhada à sua frequência real de treino.\nEu cuido da estratégia, para garantir que o ganho seja real, controlado e sustentável.',
  ],
  manutencao: [
    'Marina, agora você entra na fase de manutenção — e aqui vai um ponto importante: manutenção não é pausa e não é “soltar o plano”. É a fase que protege o que você conquistou, reduz o risco de efeito sanfona e consolida seus hábitos para o próximo ciclo, se necessário.',
    'Nesta etapa, você terá uma meta de calorias de manutenção (sem déficit e sem superávit). A regra é simples: terminar o dia o mais próximo possível da meta.\nmuito abaixo disso costuma gerar fome, compulsão e instabilidade;\nmuito acima disso tende a virar ganho de gordura ao longo das semanas.\nO objetivo aqui não é “acertar perfeito todo dia”, é manter estabilidade semanal com consistência real.',
    'A proteína e a atividade física continuam obrigatórias porque elas que sustentam sua composição corporal e evita que você perca qualidade muscular enquanto aumenta a flexibilidade alimentar. Manutenção com proteína baixa e sem atividade física vira manutenção fraca — e isso abre brecha para regressão silenciosa.',
    'Sua missão é simples: manter o básico bem feito com mais flexibilidade e zero bagunça.\nEu cuido do monitoramento e de manter o processo estável — porque é isso que faz você evoluir sem precisar recomeçar do zero.',
  ],
}

/** Our translation: same paragraphs, same lines. */
const WELCOME_EN: Record<Protocol, string[]> = {
  recomposicao: [
    'Marina, as of now you are officially entering the body recomposition phase.\nThat means reducing fat progressively, preserving muscle mass as much as possible or, ideally, gaining it, and keeping a process that is sustainable day to day — no extremes and no improvisation.',
    "Every day you will have a clear calorie target. The idea is to end the day as close to that number as possible:\nnot far below it, to avoid hunger and a break in consistency, and not above it, so the day's deficit is not canceled out.\nThat daily balance is what keeps the process working predictably.",
    "During this phase, we also use the 7,700 kcal blocks as the method's reference. Each completed block represents, approximately, the loss of 1 kg of body fat. This lets you follow your progress, see that the method is working and be clear that your daily execution is having an effect.",
    'Your mission is simple: do the basics well, every day.\nThe strategy and the reading of the data stay with me. We are building consistency — and that is what produces results.',
  ],
  ganho_massa: [
    'Marina, you are now entering the muscle gain phase. The goal here is clear: make muscle win the race, with full control of fat gain and a focus on training performance.',
    'In this protocol, strength training is not optional. Muscle gain only happens when there is a consistent mechanical stimulus. Without regular strength training, the calorie surplus loses its building function and the risk of fat gain rises significantly — that is why, without strength training, it is not possible to continue in the gain protocol.',
    'Every day you will have a calorie target set at a slight surplus, that is, with some to spare. The ideal is to end the day as close to that number as possible:\nbelow the target, you may lack the energy to train well and sustain muscle building;\nabove the target, the risk is speeding up fat gain with no real benefit.\nThe daily balance is what keeps the gain clean, predictable and under control.',
    'Important: your daily calorie target is directly tied to the weekly training frequency you reported. The more strength training sessions in the week, the higher the energy demand; the fewer the sessions, the lower the need.\nIf you train more often than agreed without an adjustment, the calories may become insufficient and limit muscle gain.\nIf you train less often than you reported, the calorie excess stops being used by the muscle and tends to turn into fat.',
    'In this phase, the protein target is essential. Hitting your protein every day is what gives the body the material it needs to build muscle, sustain recovery and turn the training stimulus into results. Without consistent protein, there is no meaningful hypertrophy — even with more calories.',
    'Progress here is not measured by the scale alone. The main reference is how your training evolves: more load, more repetitions, more volume over the weeks. Weight and measurements come in as support, never as a decision on their own.',
    'Your mission is simple: train consistently, hit your protein and respect the calorie target aligned with your real training frequency.\nI take care of the strategy, to make sure the gain is real, controlled and sustainable.',
  ],
  manutencao: [
    'Marina, you are now entering the maintenance phase — and here is an important point: maintenance is not a break and it is not “letting go of the plan”. It is the phase that protects what you have achieved, reduces the risk of the yo-yo effect and consolidates your habits for the next cycle, if needed.',
    'At this stage, you will have a maintenance calorie target (no deficit and no surplus). The rule is simple: end the day as close to the target as possible.\nfar below it usually brings hunger, compulsive eating and instability;\nfar above it tends to become fat gain over the weeks.\nThe goal here is not to “get it perfect every day”; it is to keep weekly stability with real consistency.',
    'Protein and physical activity remain mandatory because they are what sustains your body composition and keeps you from losing muscle quality while dietary flexibility increases. Maintenance with low protein and no physical activity becomes weak maintenance — and that opens the door to silent regression.',
    'Your mission is simple: keep the basics well done, with more flexibility and zero mess.\nI take care of the monitoring and of keeping the process stable — because that is what lets you progress without having to start over from scratch.',
  ],
}

const WELCOME: Record<ProtocolMessageLocale, Record<Protocol, string[]>> = {
  'pt-BR': WELCOME_PT,
  'en-US': WELCOME_EN,
}

const BLOCK_BODY_FAT_PT =
  'Com base nos dados que coletamos até aqui, seu percentual de gordura atual coloca você em uma faixa acima do recomendado para iniciar, neste momento, um protocolo de ganho de massa muscular. É importante te explicar isso com transparência: o ganho de massa muscular pressupõe um superávit calórico, que nessas condições tende a gerar mais acúmulo de gordura corporal, o que não seria seguro nem estratégico agora. Por esse motivo, a melhor conduta neste momento é iniciarmos um protocolo de recomposição corporal. Nesse protocolo, você continuará estimulando ganho de massa muscular, porém de forma controlada e acompanhada de perda de gordura corporal. O ganho de massa muscular não foi negado, apenas adiado: ele volta a ser considerado quando seus índices estiverem em uma faixa mais adequada, caso esse ainda seja o seu objetivo.'
const BLOCK_BMI_PT =
  'Com base nos dados que coletamos até aqui, seu IMC atual coloca você em uma faixa acima do recomendado para iniciar, neste momento, um protocolo de ganho de massa muscular. É importante te explicar isso com transparência: o ganho de massa muscular pressupõe um superávit calórico, que nessas condições tende a gerar mais acúmulo de gordura corporal, o que não seria seguro nem estratégico agora. Por esse motivo, a melhor conduta neste momento é iniciarmos um protocolo de recomposição corporal. Nesse protocolo, você continuará estimulando ganho de massa muscular, porém de forma controlada e acompanhada de perda de gordura corporal. O ganho de massa muscular não foi negado, apenas adiado: ele volta a ser considerado quando seus índices estiverem em uma faixa mais adequada, caso esse ainda seja o seu objetivo.'
const BLOCK_BODY_FAT_EN =
  'Based on the data we have collected so far, your current body fat percentage places you in a range above what is recommended for starting a muscle gain protocol at this moment. It is important to explain this to you with transparency: muscle gain presupposes a calorie surplus, which under these conditions tends to cause more body fat accumulation, and that would be neither safe nor strategic right now. For this reason, the best course of action at this moment is for us to start a body recomposition protocol. In that protocol, you will keep stimulating muscle gain, but in a controlled way and together with body fat loss. Muscle gain has not been denied, only postponed: it comes back into consideration when your indicators are in a more suitable range, if that is still your goal.'
const BLOCK_BMI_EN =
  'Based on the data we have collected so far, your current BMI places you in a range above what is recommended for starting a muscle gain protocol at this moment. It is important to explain this to you with transparency: muscle gain presupposes a calorie surplus, which under these conditions tends to cause more body fat accumulation, and that would be neither safe nor strategic right now. For this reason, the best course of action at this moment is for us to start a body recomposition protocol. In that protocol, you will keep stimulating muscle gain, but in a controlled way and together with body fat loss. Muscle gain has not been denied, only postponed: it comes back into consideration when your indicators are in a more suitable range, if that is still your goal.'

const NOTICE_PT =
  'Pelos dados que você informou, você está acima da faixa saudável neste momento. Por isso, o seu protocolo é definido automaticamente: recomposição corporal.'
const NOTICE_EN =
  'Based on the data you reported, you are above the healthy range at this moment. For that reason, your protocol is set automatically: body recomposition.'

const BODY_FAT_REASON_MAN_PT =
  'O protocolo de ganho de massa muscular exige percentual de gordura corporal de até 19%. O percentual que você informou está acima desse limite.'
const BODY_FAT_REASON_WOMAN_PT =
  'O protocolo de ganho de massa muscular exige percentual de gordura corporal de até 27%. O percentual que você informou está acima desse limite.'
const BODY_FAT_REASON_MAN_EN =
  'The muscle gain protocol requires a body fat percentage of 19% or less. The percentage you reported is above that limit.'
const BODY_FAT_REASON_WOMAN_EN =
  'The muscle gain protocol requires a body fat percentage of 27% or less. The percentage you reported is above that limit.'

/** Minimum 3, the person informed 2. */
const TRAINING_REASON_PT =
  'O protocolo de ganho de massa muscular exige musculação pelo menos 3 vezes por semana. Sem esse critério, superávit calórico vira gordura. Você informou 2 por semana.'
const TRAINING_REASON_EN =
  'The muscle gain protocol requires strength training at least 3 times a week. Without this criterion, a calorie surplus turns into fat. You reported 2 a week.'

// ── The cuts, from the real decision ────────────────────────────────────────

/** A person within the range, body fat between the two cuts of the sex, 2 sessions. */
function limitsOf(sex: Sex) {
  const decided = decideSignupEligibility({
    sex,
    heightCm: sex === 'masculino' ? 180 : 165,
    weightKg: sex === 'masculino' ? 80 : 62,
    bodyFatPercent: sex === 'masculino' ? 19.5 : 27.5,
    trainingFrequency: 2,
  })
  if (decided.outcome !== 'choice') throw new Error(`esperava escolha: ${decided.outcome}`)
  expect(decided.objectives.ganho_massa).toEqual({
    status: 'blocked',
    reasons: ['composition', 'training'],
  })
  return decided.limits
}

/** Every text the server can show to a person of this sex, in this language. */
function everyText(locale: ProtocolMessageLocale, sex: Sex): Array<[string, string]> {
  const limits = limitsOf(sex)
  const texts: Array<[string, string[]]> = [
    ...PROTOCOLS.map(
      (protocol) =>
        [`entrada ${protocol}`, protocolWelcomeMessage(protocol, NAME, locale)] as [
          string,
          string[],
        ],
    ),
    ...PROTOCOLS.map(
      (protocol) =>
        [`entrada ${protocol}, sem nome`, protocolWelcomeMessage(protocol, null, locale)] as [
          string,
          string[],
        ],
    ),
    ['aviso de recomposição definida', signupAssignedNotice(locale)],
    ['bloqueio pela gordura', gainBlockedAboveRangeMessage('BF', locale)],
    ['bloqueio pelo IMC', gainBlockedAboveRangeMessage('IMC', locale)],
    ['motivo da gordura', gainUnavailableBodyFatReason(limits.bodyFatGain, locale)],
    ...[0, 1, 2].map(
      (sessions) =>
        [
          `motivo da musculação, ${sessions} por semana`,
          gainUnavailableTrainingReason(limits.trainingMin, sessions, locale),
        ] as [string, string[]],
    ),
  ]
  return texts.map(([label, paragraphs]) => [`${locale} ${sex} ${label}`, paragraphs.join('\n\n')])
}

const EVERY_TEXT = LOCALES.flatMap((locale) => SEXES.flatMap((sex) => everyText(locale, sex)))

// ── What no text may carry ──────────────────────────────────────────────────

const FORBIDDEN: Array<[string, RegExp]> = [
  ['the method, abbreviated', /MPP/i],
  ['the method, spelled out', /muscular[\s-]*power[\s-]*plant/i],
  ["the physician's surname", /menescal/i],
  ["the physician's first name", /\broberto?\b/i],
  ["the physician's title", /\b(?:dr|dra|doutor|doutora|doctor)\b/i],
  ['the old product name', /body[\s-]*flow/i],
  ['BMR', /\bBMR\b/i],
  ['TDEE', /\bTDEE\b/i],
  ['BF as an abbreviation', /\bBF\b/i],
]

const EMOJI = /\p{Extended_Pictographic}|[\u{1F1E6}-\u{1F1FF}]|\u{FE0F}|\u{200D}|\u{20E3}/u

describe('audit 2026-10-07 — B: os três textos de entrada, palavra por palavra', () => {
  it.each(
    LOCALES.flatMap((locale) => PROTOCOLS.map((protocol) => [locale, protocol] as const)),
  )('%s, %s', (locale, protocol) => {
    expect(protocolWelcomeMessage(protocol, NAME, locale)).toEqual(WELCOME[locale][protocol])
  })

  it('os parágrafos servidos: 4 na recomposição, 7 no ganho de massa, 4 na manutenção', () => {
    for (const locale of LOCALES) {
      expect(WELCOME[locale].recomposicao).toHaveLength(4)
      expect(WELCOME[locale].ganho_massa).toHaveLength(7)
      expect(WELCOME[locale].manutencao).toHaveLength(4)
    }
  })

  it('inglês: os mesmos parágrafos e as mesmas linhas do português', () => {
    for (const protocol of PROTOCOLS) {
      const lines = (paragraphs: string[]) => paragraphs.map((text) => text.split('\n').length)
      expect(lines(WELCOME_EN[protocol])).toEqual(lines(WELCOME_PT[protocol]))
    }
  })
})

describe('audit 2026-10-07 — B: cada texto do cliente é o original dele com as edições listadas, e só elas', () => {
  it.each(PROTOCOLS)('texto de entrada, %s', (protocol) => {
    const served = oneLine(protocolWelcomeMessage(protocol, '{nome}', 'pt-BR').join(' '))
    expect(served).toBe(withEdits(CLIENT_ORIGINAL[protocol], EDITS[protocol]))
  })

  it('frase de bloqueio 3.4.1, quando decidiu a gordura', () => {
    expect(gainBlockedAboveRangeMessage('BF', 'pt-BR')).toEqual([
      withEdits(CLIENT_ORIGINAL.bloqueio, blockEdits('seu percentual de gordura atual')),
    ])
  })

  it('frase de bloqueio 3.4.1, quando decidiu o IMC', () => {
    expect(gainBlockedAboveRangeMessage('IMC', 'pt-BR')).toEqual([
      withEdits(CLIENT_ORIGINAL.bloqueio, blockEdits('seu IMC atual')),
    ])
  })

  it('cada edição está registrada em docs/CALCULO-MPP.md §10m, com o trecho original entre aspas', () => {
    const section = oneLine(DOC.slice(DOC.indexOf('### 10m.'), DOC.indexOf('### 10n.')))
    expect(section).toContain('Confirmação do cliente pendente')
    const edits = [
      ...PROTOCOLS.flatMap((protocol) => EDITS[protocol]),
      ...blockEdits('seu percentual de gordura atual'),
      ...blockEdits('seu IMC atual'),
    ]
    expect(edits).toHaveLength(16)
    for (const edit of edits) {
      expect(section, edit.from).toContain(`"${edit.from}"`)
      if (edit.to) expect(section, edit.to).toContain(`"${edit.to}"`)
    }
  })
})

describe('audit 2026-10-07 — B: o que o cadastro diz sobre a decisão, palavra por palavra', () => {
  it('aviso de recomposição definida sem pergunta (redação nossa)', () => {
    expect(signupAssignedNotice('pt-BR')).toEqual([NOTICE_PT])
    expect(signupAssignedNotice('en-US')).toEqual([NOTICE_EN])
  })

  it('frase de bloqueio do ganho de massa: escreve só o que decidiu', () => {
    expect(gainBlockedAboveRangeMessage('BF', 'pt-BR')).toEqual([BLOCK_BODY_FAT_PT])
    expect(gainBlockedAboveRangeMessage('IMC', 'pt-BR')).toEqual([BLOCK_BMI_PT])
    expect(gainBlockedAboveRangeMessage('BF', 'en-US')).toEqual([BLOCK_BODY_FAT_EN])
    expect(gainBlockedAboveRangeMessage('IMC', 'en-US')).toEqual([BLOCK_BMI_EN])
    expect(BLOCK_BODY_FAT_PT).not.toContain('IMC')
    expect(BLOCK_BMI_PT).not.toContain('percentual')
    expect(BLOCK_BODY_FAT_EN).not.toContain('BMI')
    expect(BLOCK_BMI_EN).not.toContain('percentage')
  })

  it('motivo da gordura entre os cortes (redação nossa): o corte é o da decisão — 19 para homem, 27 para mulher', () => {
    expect(limitsOf('masculino').bodyFatGain).toBe(19)
    expect(limitsOf('feminino').bodyFatGain).toBe(27)
    expect(gainUnavailableBodyFatReason(limitsOf('masculino').bodyFatGain, 'pt-BR')).toEqual([
      BODY_FAT_REASON_MAN_PT,
    ])
    expect(gainUnavailableBodyFatReason(limitsOf('feminino').bodyFatGain, 'pt-BR')).toEqual([
      BODY_FAT_REASON_WOMAN_PT,
    ])
    expect(gainUnavailableBodyFatReason(limitsOf('masculino').bodyFatGain, 'en-US')).toEqual([
      BODY_FAT_REASON_MAN_EN,
    ])
    expect(gainUnavailableBodyFatReason(limitsOf('feminino').bodyFatGain, 'en-US')).toEqual([
      BODY_FAT_REASON_WOMAN_EN,
    ])
  })

  it('motivo da musculação abaixo do mínimo (redação nossa): o mínimo é o da decisão — 3 — e o segundo número é o informado', () => {
    expect(limitsOf('masculino').trainingMin).toBe(3)
    expect(DEFAULT_CALC_CONFIG.training_min).toBe(3)
    expect(gainUnavailableTrainingReason(limitsOf('masculino').trainingMin, 2, 'pt-BR')).toEqual([
      TRAINING_REASON_PT,
    ])
    expect(gainUnavailableTrainingReason(limitsOf('feminino').trainingMin, 2, 'en-US')).toEqual([
      TRAINING_REASON_EN,
    ])
  })

  it('nenhum corte está escrito no código dos textos: muda a configuração, muda o número', () => {
    expect(MESSAGES_SOURCE).not.toMatch(/\d\s*%/)
    expect(MESSAGES_SOURCE).not.toMatch(/(?:pelo menos|at least) \d/)
    expect(gainUnavailableBodyFatReason(18, 'pt-BR')).toEqual([
      BODY_FAT_REASON_MAN_PT.replace('19%', '18%'),
    ])
    expect(gainUnavailableTrainingReason(4, 3, 'pt-BR')).toEqual([
      TRAINING_REASON_PT.replace('pelo menos 3', 'pelo menos 4').replace(
        'informou 2',
        'informou 3',
      ),
    ])
  })
})

describe('audit 2026-10-07 — B: nenhum nome proibido e nenhum emoji, nos dois idiomas e nos dois sexos', () => {
  it('são 52 textos: 13 por idioma e sexo', () => {
    expect(EVERY_TEXT).toHaveLength(52)
    expect(new Set(EVERY_TEXT.map(([label]) => label)).size).toBe(52)
  })

  it.each(EVERY_TEXT)('%s', (_label, text) => {
    for (const [what, pattern] of FORBIDDEN) expect(text, what).not.toMatch(pattern)
    expect(text).not.toMatch(EMOJI)
    // No placeholder left behind, no separator of the export, no doubled space.
    expect(text).not.toMatch(/[{}]|\u2028|\u00A0| {2}/)
  })

  it('a conferência tem dentes: os originais do cliente não passariam', () => {
    const [, method] = FORBIDDEN[0] as [string, RegExp]
    for (const protocol of PROTOCOLS) expect(CLIENT_ORIGINAL[protocol]).toMatch(method)
    expect(CLIENT_ORIGINAL.ganho_massa).toMatch(EMOJI)
    expect('Gasto basal (BMR) e TDEE; BF de 20%').toMatch(/\bBMR\b/i)
    expect('Gasto basal (BMR) e TDEE; BF de 20%').toMatch(/\bTDEE\b/i)
    expect('Gasto basal (BMR) e TDEE; BF de 20%').toMatch(/\bBF\b/i)
  })
})

describe('audit 2026-10-07 — B: a projeção de nomes do Flow devolve cada texto sem troca', () => {
  it.each(EVERY_TEXT)('%s', (_label, text) => {
    const projected = projectFlowPublicNames(text)
    expect(projected.text).toBe(text)
    expect(projected).toEqual({
      text,
      method: 0,
      personaSelf: 0,
      personaOther: 0,
      personaFirstNameOnly: 0,
    })
  })

  it('a projeção tem dentes: o original do cliente sairia trocado', () => {
    for (const protocol of PROTOCOLS) {
      const projected = projectFlowPublicNames(CLIENT_ORIGINAL[protocol])
      expect(projected.method).toBeGreaterThan(0)
      expect(projected.text).not.toBe(CLIENT_ORIGINAL[protocol])
    }
  })
})

describe('audit 2026-10-07 — B: o nome da pessoa', () => {
  it.each(
    LOCALES.flatMap((locale) => PROTOCOLS.map((protocol) => [locale, protocol] as const)),
  )('%s, %s: abre o primeiro parágrafo e não aparece em mais nenhum lugar', (locale, protocol) => {
    const paragraphs = protocolWelcomeMessage(protocol, NAME, locale)
    expect(paragraphs[0]?.startsWith(`${NAME}, `)).toBe(true)
    expect(paragraphs.join('\n\n').split(NAME)).toHaveLength(2)
  })

  it('nome composto entra inteiro; o resto do texto é o mesmo', () => {
    for (const locale of LOCALES) {
      for (const protocol of PROTOCOLS) {
        const paragraphs = protocolWelcomeMessage(protocol, 'Ana Clara', locale)
        expect(paragraphs).toEqual(
          WELCOME[locale][protocol].map((text, index) =>
            index === 0 ? text.replace(`${NAME}, `, 'Ana Clara, ') : text,
          ),
        )
      }
    }
  })

  it('conta sem nome: sem vocativo, a frase começa com maiúscula e nada mais muda', () => {
    expect(protocolWelcomeMessage('recomposicao', null, 'pt-BR')[0]).toBe(
      (WELCOME_PT.recomposicao[0] ?? '').replace(`${NAME}, a partir`, 'A partir'),
    )
    expect(protocolWelcomeMessage('ganho_massa', '', 'pt-BR')[0]).toBe(
      (WELCOME_PT.ganho_massa[0] ?? '').replace(`${NAME}, agora`, 'Agora'),
    )
    expect(protocolWelcomeMessage('manutencao', '   ', 'pt-BR')[0]).toBe(
      (WELCOME_PT.manutencao[0] ?? '').replace(`${NAME}, agora`, 'Agora'),
    )
    expect(protocolWelcomeMessage('recomposicao', undefined, 'en-US')[0]).toBe(
      (WELCOME_EN.recomposicao[0] ?? '').replace(`${NAME}, as of now`, 'As of now'),
    )
    expect(protocolWelcomeMessage('ganho_massa', null, 'en-US')[0]).toBe(
      (WELCOME_EN.ganho_massa[0] ?? '').replace(`${NAME}, you are`, 'You are'),
    )
    expect(protocolWelcomeMessage('manutencao', null, 'en-US')[0]).toBe(
      (WELCOME_EN.manutencao[0] ?? '').replace(`${NAME}, you are`, 'You are'),
    )
    for (const locale of LOCALES) {
      for (const protocol of PROTOCOLS) {
        expect(protocolWelcomeMessage(protocol, null, locale).slice(1)).toEqual(
          WELCOME[locale][protocol].slice(1),
        )
      }
    }
  })

  it('os textos do cadastro não levam o nome', () => {
    for (const [label, text] of EVERY_TEXT) {
      if (label.includes('entrada') && !label.includes('sem nome')) continue
      expect(text, label).not.toContain(NAME)
    }
  })
})

describe('audit 2026-10-07 — B: nenhum número foi colocado dentro de frase do cliente', () => {
  const numbers = (paragraphs: string[]) => paragraphs.join(' ').match(/\d+(?:[.,]\d+)*/g) ?? []

  it('recomposição: só os dois números que ele escreveu — o bloco de 7.700 kcal e 1 kg', () => {
    expect(numbers(protocolWelcomeMessage('recomposicao', NAME, 'pt-BR'))).toEqual(['7.700', '1'])
    expect(numbers(protocolWelcomeMessage('recomposicao', NAME, 'en-US'))).toEqual(['7,700', '1'])
  })

  it('ganho de massa, manutenção e frase de bloqueio: nenhum número (o "15 dias" e o "14 dias" saíram com os trechos cortados; o "±100 kcal" também)', () => {
    for (const locale of LOCALES) {
      expect(numbers(protocolWelcomeMessage('ganho_massa', NAME, locale))).toEqual([])
      expect(numbers(protocolWelcomeMessage('manutencao', NAME, locale))).toEqual([])
      expect(numbers(gainBlockedAboveRangeMessage('BF', locale))).toEqual([])
      expect(numbers(gainBlockedAboveRangeMessage('IMC', locale))).toEqual([])
      expect(numbers(signupAssignedNotice(locale))).toEqual([])
    }
  })
})

describe('declared pendencies', () => {
  it('every "RC B" line of this header is in docs/CALCULO-MPP.md §10n, identical', () => {
    const header = readFileSync(fileURLToPath(import.meta.url), 'utf8')
    const fromHeader = Array.from(header.matchAll(/^ \* (> RC B — .*)$/gm), (match) => match[1])
    const fromDoc = Array.from(DOC.matchAll(/^(> RC B — .*)$/gm), (match) => match[1])
    expect(fromHeader).toHaveLength(11)
    expect(fromDoc).toEqual(fromHeader)
    for (const line of fromHeader) {
      expect(line).toMatch(
        /^> RC B — cenário .+ variante .+ NÃO coberta nesta PR \(pendência da audit 2026-10-07\)$/,
      )
    }
  })
})
