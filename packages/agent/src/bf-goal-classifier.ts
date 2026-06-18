/**
 * Classifier puro pra meta de BF% (Roberto 2026-06-18).
 *
 * Paralelo de weight-goal-classifier mas pra percentual de gordura corporal.
 * Quando o paciente diz "quero chegar em X% de gordura", esse helper:
 *   1. Calcula delta atual → alvo (perder gordura ou ganhar)
 *   2. Classifica em 1 dos 5 buckets
 *   3. Devolve faixa saudável (depende de sexo + protocolo MPP) +
 *      estimativa de tempo + texto sugerido
 *
 * Sem LLM — totalmente determinístico, testável. O LLM só REDIGE a resposta
 * variando a forma, com base nos números/classification daqui.
 *
 * Limites MPP (Notion + calc-config bf_limits):
 *   - masculino: recomp limit 20%, gain limit 19%
 *   - feminino: recomp limit 28%, gain limit 27%
 *
 * Velocidade segura: perda de gordura sustentável ~0.5pp/semana (em torno
 * de 1% do peso/semana → ~0.5pp de BF/semana pra paciente médio). Mais que
 * isso indica déficit agressivo demais (perda muscular).
 *
 * Faixa "saudável" (BF essencial não-cumprido):
 *   - masculino: 8-19% atlético/fitness, 20-25% aceitável, >25 obesidade
 *   - feminino: 16-24% atlético/fitness, 25-31% aceitável, >32 obesidade
 *   abaixo do "essencial" (homem <5%, mulher <12%) é unhealthy_low.
 */
export type BfGoalClass =
  | 'unhealthy_low' // alvo < BF essencial (homem <5, mulher <12) — risco
  | 'aggressive_pace' // alvo saudável mas chegar em <4 semanas é rápido demais (perda muscular)
  | 'overweight_remaining' // alvo > limite recomp (homem >20, mulher >28) — ainda obeso/sobrepeso
  | 'long_term' // alvo saudável MAS exige >26 semanas (~6 meses) — sugerir degrau intermediário
  | 'ideal' // alvo dentro do recomp limit + velocidade factível (4-26 semanas)
  | 'maintenance' // alvo ≈ BF atual (±1pp, inclusivo nos extremos via <=)

export type Sex = 'masculino' | 'feminino'

const BF_ESSENTIAL = { masculino: 5, feminino: 12 }
const BF_RECOMP_LIMIT = { masculino: 20, feminino: 28 } // espelhado de calc-config
// Velocidade segura: 0.5pp/semana de BF — perda sustentável típica
const BF_LOSS_SAFE_PP_PER_WEEK = 0.5
// Threshold de "manutenção" — diferença ≤1pp considera manter. Usa `<=` em
// vez de `<` pra incluir delta=1.0 (review HIGH: ruído de bioimpedância é
// ~2-3pp, threshold strict criava cliff em 1.0).
const BF_MAINT_THRESHOLD = 1
// Aggressive pace só pra delta significativo (review HIGH): delta de
// 1-2pp em <4 semanas é factível (1pp ≈ 1kg gordura). Aggressive só pra
// delta >=2pp E semanas<4.
const BF_AGGRESSIVE_DELTA_MIN = 2
const BF_AGGRESSIVE_WEEKS_MAX = 4
// Long-term: meta saudável mas precisa mais de 26 semanas no ritmo seguro
// — recomenda fragmentar em degraus intermediários.
const BF_LONG_TERM_WEEKS_MIN = 26

export interface BfGoalInput {
  currentBfPercent: number
  targetBfPercent: number
  sex: Sex
}

export interface BfGoalAssessment {
  classification: BfGoalClass
  /** BF atual do paciente (%). */
  bfAtual: number
  /** BF alvo do paciente (%). */
  bfAlvo: number
  /** BF essencial mínimo pro sexo (homem 5%, mulher 12%). */
  bfMinimoSaudavel: number
  /** Limite recomp pro sexo (homem 20%, mulher 28%) — acima disso protocolo
   * MPP recomenda foco em perda de gordura antes de recomp pura. */
  bfRecompLimit: number
  /** Estimativa em semanas pra chegar (caso a meta seja saudável). null se
   * meta não-saudável ou paciente em manutenção. */
  semanasParaMetaSeguro: number | null
  /** Direção da meta. */
  direction: 'perder' | 'ganhar' | 'manter'
  /** pp (pontos percentuais) que precisa variar (sempre positivo). */
  deltaPp: number
  /** Mensagem-base pro LLM redigir variando (mantém conteúdo factual). */
  message: string
}

export function classifyBfGoal(input: BfGoalInput): BfGoalAssessment {
  const { currentBfPercent, targetBfPercent, sex } = input
  const bfAtual = round1(currentBfPercent)
  const bfAlvo = round1(targetBfPercent)
  const bfMinimoSaudavel = BF_ESSENTIAL[sex]
  const bfRecompLimit = BF_RECOMP_LIMIT[sex]
  const deltaPp = round1(Math.abs(bfAtual - bfAlvo))
  const direction: 'perder' | 'ganhar' | 'manter' =
    deltaPp <= BF_MAINT_THRESHOLD
      ? 'manter'
      : bfAtual > bfAlvo
        ? 'perder'
        : 'ganhar'

  // Estimativa de semanas (perda 0.5pp/semana — referência conservadora)
  let semanasParaMetaSeguro: number | null = null
  if (direction === 'perder') {
    semanasParaMetaSeguro = Math.ceil(deltaPp / BF_LOSS_SAFE_PP_PER_WEEK)
  } else if (direction === 'ganhar') {
    // Ganhar gordura intencionalmente é raro (cutting reverso); usa mesma
    // velocidade conservadora — modelo MPP não otimiza pra isso.
    semanasParaMetaSeguro = Math.ceil(deltaPp / BF_LOSS_SAFE_PP_PER_WEEK)
  }

  // Classificação
  let classification: BfGoalClass
  if (direction === 'manter') {
    classification = 'maintenance'
  } else if (bfAlvo < bfMinimoSaudavel) {
    classification = 'unhealthy_low'
    semanasParaMetaSeguro = null
  } else if (bfAlvo > bfRecompLimit) {
    classification = 'overweight_remaining'
  } else {
    // Alvo está na faixa razoável. Buckets por ritmo (review HIGH):
    //   - aggressive: delta >= 2pp E semanas < 4 (déficit alto, risco
    //     perda muscular). Delta 1-2pp em 1-2 sem é factível → ideal.
    //   - long_term: semanas >26 (~6 meses) com delta >10pp — sugerir
    //     degrau intermediário antes que o paciente desista.
    //   - ideal: o resto (4-26 semanas, ritmo sustentável).
    if (
      semanasParaMetaSeguro != null &&
      semanasParaMetaSeguro < BF_AGGRESSIVE_WEEKS_MAX &&
      deltaPp >= BF_AGGRESSIVE_DELTA_MIN
    ) {
      classification = 'aggressive_pace'
    } else if (
      semanasParaMetaSeguro != null &&
      semanasParaMetaSeguro > BF_LONG_TERM_WEEKS_MIN &&
      deltaPp > 10
    ) {
      classification = 'long_term'
    } else {
      classification = 'ideal'
    }
  }

  const message = buildMessage({
    classification,
    direction,
    bfAtual,
    bfAlvo,
    bfMinimoSaudavel,
    bfRecompLimit,
    deltaPp,
    semanasParaMetaSeguro,
    sex,
  })

  return {
    classification,
    bfAtual,
    bfAlvo,
    bfMinimoSaudavel,
    bfRecompLimit,
    semanasParaMetaSeguro,
    direction,
    deltaPp,
    message,
  }
}

interface BuildMessageInput {
  classification: BfGoalClass
  direction: 'perder' | 'ganhar' | 'manter'
  bfAtual: number
  bfAlvo: number
  bfMinimoSaudavel: number
  bfRecompLimit: number
  deltaPp: number
  semanasParaMetaSeguro: number | null
  sex: Sex
}

function buildMessage(i: BuildMessageInput): string {
  const sexLabel = i.sex === 'masculino' ? 'pra homem' : 'pra mulher'
  switch (i.classification) {
    case 'maintenance':
      return (
        `Beleza — manter o BF atual em ${i.bfAtual}%. Vou ajustar pro protocolo de ` +
        `Manutenção, onde o foco é estabilidade e composição corporal (preservar massa).`
      )
    case 'unhealthy_low':
      return (
        `Cuidado — ${i.bfAlvo}% está ABAIXO do limite essencial ${sexLabel} ` +
        `(mínimo ${i.bfMinimoSaudavel}%). Perder gordura abaixo desse limite ` +
        `compromete hormônios, recuperação muscular e saúde geral. ` +
        `Sugiro mirar pelo menos ${i.bfMinimoSaudavel + 3}% — ainda atlético, mas seguro. ` +
        `Faz sentido revisar a meta?`
      )
    case 'overweight_remaining':
      return (
        `Meta de ${i.bfAlvo}% ainda acima do limite ideal ${sexLabel} ` +
        `(${i.bfRecompLimit}% — a partir daí o protocolo MPP foca em perda de gordura). ` +
        `Faz sentido como degrau intermediário: do ${i.bfAtual}% atual cair pra ${i.bfAlvo}% ` +
        `(${i.deltaPp}pp) leva ~${i.semanasParaMetaSeguro} semanas no ritmo seguro. ` +
        `Depois revisamos a meta pra refinar.`
      )
    case 'aggressive_pace':
      return (
        `Meta de ${i.bfAlvo}% é saudável, mas chegar lá do ${i.bfAtual}% atual ` +
        `(${i.deltaPp}pp) em <4 semanas exige déficit alto demais (perde músculo junto). ` +
        `Sustentável: ${i.semanasParaMetaSeguro} semanas no ritmo de ~0.5pp/sem. ` +
        `Topa esse cronograma?`
      )
    case 'long_term':
      return (
        `Meta saudável (${i.bfAlvo}%) mas LONGO PRAZO: do ${i.bfAtual}% atual ` +
        `(delta ${i.deltaPp}pp) leva ~${i.semanasParaMetaSeguro} semanas (~${Math.round((i.semanasParaMetaSeguro ?? 0) / 4)} meses) ` +
        `no ritmo seguro. Risco alto de desistência. Sugiro fragmentar em degrau intermediário: ` +
        `mirar primeiro ${Math.round(i.bfAtual - 5)}% (3 meses, ritmo factível), reavaliar, ` +
        `depois continuar até ${i.bfAlvo}%. Topa esse formato?`
      )
    case 'ideal':
      return (
        `Meta saudável: ${i.bfAlvo}% (${i.direction === 'perder' ? 'abaixo' : 'acima'} ` +
        `dos ${i.bfAtual}% atuais, delta ${i.deltaPp}pp). No ritmo seguro de ` +
        `~0.5pp/semana, ~${i.semanasParaMetaSeguro} semanas. Boa meta — vamos focar.`
      )
    default:
      return `Meta de ${i.bfAlvo}% registrada.`
  }
}

function round1(n: number): number {
  return Math.round(n * 10) / 10
}
