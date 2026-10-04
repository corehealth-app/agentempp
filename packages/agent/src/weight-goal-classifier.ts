/**
 * Classifier puro pra meta de peso (Roberto 2026-06-01).
 *
 * Quando o paciente diz "quero pesar X kg", esse helper:
 *   1. Calcula IMC alvo + IMC atual
 *   2. Classifica em 1 dos 4 buckets
 *   3. Devolve faixa saudável + estimativa de tempo + texto sugerido
 *
 * Sem LLM — totalmente determinístico, testável. O LLM só REDIGE a resposta
 * variando a forma, mas com base nos números/classification daqui.
 *
 * Faixa OMS: IMC saudável = 18.5-24.9. Velocidade segura de variação de peso:
 *   - Perda: 0.5-1 kg/semana (≈ 0.5-1% do peso corporal por semana)
 *   - Ganho: 0.25-0.5 kg/semana
 *
 * Floor (R4, docs/CALCULO-MPP.md §8b): a goal that leaves the BMI under 18.5
 * while LOSING weight is REFUSED (`refused`) and the tool does not save it.
 * Stated by the client on 2026-06-09 (typed: "esses valores muito abaixo não
 * podemos fazer"; manual 3.5: the agent does not ask "quer continuar mesmo
 * assim"), after he had approved the warning on 2026-06-01. Implemented on
 * 2026-10-04 at Eduardo's request; the client's confirmation is pending.
 * Gaining weight towards a goal still under 18.5 stays the warning it was.
 *
 * The floor judges the BMI as computed, not the one-decimal figure shown, and
 * it is judged before the "manter" band (a change under 2% of the weight):
 * 54 → 53 kg and 55 → 53.4 kg at 170 cm were both saved. A goal EQUAL to the
 * current weight is not a loss and stays "manter".
 */
export type WeightGoalClass =
  | 'unhealthy_low' // alvo < IMC 18.5 — abaixo do saudável
  | 'aggressive_pace' // alvo saudável mas pra chegar em <X semanas é rápido demais
  | 'overweight_remaining' // alvo > IMC 25 — ainda sobrepeso
  | 'obesity_remaining' // alvo > IMC 30 — ainda obesidade
  | 'ideal' // alvo na faixa saudável + velocidade ok
  | 'maintenance' // alvo = peso atual (±2%)

const IMC_MIN_SAUDAVEL = 18.5
/** BMI under which a goal is not saved (losing weight here; any IMC goal in
 * define_protocolo). One constant: to revert R4 for weight and BMI, set it to
 * 0 (the goal is warned about and saved, as before; the BMI is judged on the
 * rounded figure and the minimum weight is rounded to nearest, as before; the
 * tool descriptions drop the floor sentences). */
export const IMC_GOAL_FLOOR = 18.5
const IMC_MAX_SAUDAVEL = 24.9
const IMC_OBESIDADE = 30
// Velocidade segura: 1% do peso por semana (lado conservador)
const PERDA_SAUDAVEL_PCT_SEMANA = 0.01
const GANHO_SAUDAVEL_PCT_SEMANA = 0.005

export interface WeightGoalInput {
  currentWeightKg: number
  targetWeightKg: number
  heightCm: number
}

export interface WeightGoalAssessment {
  classification: WeightGoalClass
  /** IMC atual do paciente. */
  imcAtual: number
  /** IMC que ele teria se chegasse ao peso alvo. One decimal, for display: a
   * value under 18.5 is never shown as 18.5 (18.478 reads 18.4). */
  imcAlvo: number
  /** Peso (kg) que dá IMC 18.5 pra essa altura — limite inferior saudável.
   * Rounded UP to one decimal, so the weight offered is itself accepted. */
  pesoMinimoSaudavelKg: number
  /** Peso (kg) que dá IMC 24.9 pra essa altura — limite superior saudável. */
  pesoMaximoSaudavelKg: number
  /** Estimativa em semanas pra chegar à meta (caso a meta seja saudável). null se meta não-saudável. */
  semanasParaMetaSeguro: number | null
  /** Direção da meta. */
  direction: 'perder' | 'ganhar' | 'manter'
  /** kg que precisa perder/ganhar (sempre positivo, magnitude). */
  deltaKg: number
  /** True when the goal leaves the BMI under 18.5 while losing weight (any
   * amount, even under 2% of the weight): the caller must NOT save it. */
  refused: boolean
  /** Mensagem-base pro LLM redigir variando (mantém conteúdo factual). */
  message: string
}

export function classifyWeightGoal(input: WeightGoalInput): WeightGoalAssessment {
  const { currentWeightKg, targetWeightKg, heightCm } = input
  const alturaM = heightCm / 100
  const altura2 = alturaM * alturaM
  const imcAtual = round1(currentWeightKg / altura2)
  // With the floor on, what is judged is the BMI as computed: rounding to one
  // decimal lifted 18.45–18.499 to 18.5 and the goal passed as "ideal". With
  // the floor off (revert), the rounded figure is judged, as before R4.
  const floorOn = IMC_GOAL_FLOOR > 0
  const imcAlvoRaw = targetWeightKg / altura2
  const imcAlvo = floorOn ? round1NeverUpTo(imcAlvoRaw, IMC_MIN_SAUDAVEL) : round1(imcAlvoRaw)
  const imcAlvoJudged = floorOn ? imcAlvoRaw : imcAlvo
  // Rounded up, or the tool would offer a weight it then refuses (150 cm:
  // 41.6 kg is BMI 18.49).
  const pesoMinimoSaudavelKg = floorOn
    ? lowestWeightAtOrAbove(IMC_MIN_SAUDAVEL, altura2)
    : round1(IMC_MIN_SAUDAVEL * altura2)
  const pesoMaximoSaudavelKg = round1(IMC_MAX_SAUDAVEL * altura2)
  const deltaKg = round1(Math.abs(currentWeightKg - targetWeightKg))
  // Judged before the "manter" band below, as classifyBfGoal does: losing less
  // than 2% of the weight to a BMI under the floor was saved as maintenance.
  const refused = targetWeightKg < currentWeightKg && imcAlvoRaw < IMC_GOAL_FLOOR
  const direction: 'perder' | 'ganhar' | 'manter' = refused
    ? 'perder'
    : Math.abs(currentWeightKg - targetWeightKg) < currentWeightKg * 0.02
      ? 'manter'
      : currentWeightKg > targetWeightKg
        ? 'perder'
        : 'ganhar'

  // Estimativa de semanas seguras (perda 1%/sem ou ganho 0.5%/sem)
  let semanasParaMetaSeguro: number | null = null
  if (direction === 'perder') {
    const kgSeguroPorSemana = currentWeightKg * PERDA_SAUDAVEL_PCT_SEMANA
    semanasParaMetaSeguro = Math.ceil(deltaKg / kgSeguroPorSemana)
  } else if (direction === 'ganhar') {
    const kgSeguroPorSemana = currentWeightKg * GANHO_SAUDAVEL_PCT_SEMANA
    semanasParaMetaSeguro = Math.ceil(deltaKg / kgSeguroPorSemana)
  }

  // Classificação
  let classification: WeightGoalClass
  if (refused) {
    classification = 'unhealthy_low'
    semanasParaMetaSeguro = null
  } else if (direction === 'manter') {
    classification = 'maintenance'
  } else if (imcAlvoJudged < IMC_MIN_SAUDAVEL) {
    classification = 'unhealthy_low'
    semanasParaMetaSeguro = null
  } else if (imcAlvo >= IMC_OBESIDADE) {
    classification = 'obesity_remaining'
  } else if (imcAlvo > IMC_MAX_SAUDAVEL) {
    classification = 'overweight_remaining'
  } else if (semanasParaMetaSeguro != null && deltaKg / currentWeightKg > 0.15) {
    // Meta saudável MAS perda/ganho > 15% do peso atual = leva muito tempo, mas é factível
    classification = 'aggressive_pace'
  } else {
    classification = 'ideal'
  }

  const message = composeMessage({
    classification,
    refused,
    direction,
    deltaKg,
    targetWeightKg,
    imcAlvo,
    pesoMinimoSaudavelKg,
    pesoMaximoSaudavelKg,
    semanasParaMetaSeguro,
  })

  return {
    classification,
    imcAtual,
    imcAlvo,
    pesoMinimoSaudavelKg,
    pesoMaximoSaudavelKg,
    semanasParaMetaSeguro,
    direction,
    deltaKg,
    refused,
    message,
  }
}

function composeMessage(d: {
  classification: WeightGoalClass
  refused: boolean
  direction: 'perder' | 'ganhar' | 'manter'
  deltaKg: number
  targetWeightKg: number
  imcAlvo: number
  pesoMinimoSaudavelKg: number
  pesoMaximoSaudavelKg: number
  semanasParaMetaSeguro: number | null
}): string {
  switch (d.classification) {
    case 'unhealthy_low':
      return (
        `Essa meta (${d.targetWeightKg}kg) te deixaria com IMC ${d.imcAlvo}, abaixo do saudável (mínimo OMS é 18.5). ` +
        `Pra sua altura, o peso mínimo saudável é ${d.pesoMinimoSaudavelKg}kg. ` +
        (d.refused
          ? `Por segurança, não registrei essa meta e nada mudou no seu cadastro. ` +
            `Posso registrar uma meta entre ${d.pesoMinimoSaudavelKg} e ${d.pesoMaximoSaudavelKg}kg. Qual você prefere?`
          : `Sugiro ajustar a meta pra algo entre ${d.pesoMinimoSaudavelKg} e ${d.pesoMaximoSaudavelKg}kg — quer rever?`)
      )
    case 'obesity_remaining':
      return (
        `Essa meta (${d.targetWeightKg}kg) ainda fica em obesidade (IMC ${d.imcAlvo}). ` +
        `Vamos por etapas: chegar em ${d.pesoMaximoSaudavelKg}kg (limite da faixa saudável) já é um avanço enorme. ` +
        `Aí na reavaliação a gente decide se continua descendo. Topa essa estratégia?`
      )
    case 'overweight_remaining':
      return (
        `Boa meta de partida (${d.targetWeightKg}kg) — vai melhorar muito sua saúde. ` +
        `Pra info: ainda fica em sobrepeso leve (IMC ${d.imcAlvo}). Se quiser ir pra faixa saudável completa, o alvo seria entre ${d.pesoMinimoSaudavelKg} e ${d.pesoMaximoSaudavelKg}kg. ` +
        `Vamos pelo seu objetivo agora — daqui ${d.semanasParaMetaSeguro} semanas reavaliamos.`
      )
    case 'aggressive_pace':
      return (
        `Meta saudável (IMC ${d.imcAlvo}), mas ${d.direction === 'perder' ? 'perder' : 'ganhar'} ${d.deltaKg}kg vai levar ${d.semanasParaMetaSeguro} semanas no ritmo seguro. ` +
        `É um processo longo — vamos juntos com calma. Reavaliamos a cada 14 dias.`
      )
    case 'maintenance':
      return (
        `Beleza — manter o peso atual. Vou ajustar pro protocolo de Manutenção, onde o foco é estabilidade e composição corporal (mais músculo, menos gordura).`
      )
    case 'ideal':
      return (
        `Ótima meta — IMC ${d.imcAlvo} cai bem na faixa saudável. ` +
        `Ritmo seguro pra ${d.direction} ${d.deltaKg}kg: cerca de ${d.semanasParaMetaSeguro} semanas. Vamos por esse caminho.`
      )
  }
}

function round1(n: number): number {
  return Math.round(n * 10) / 10
}

/** One decimal for display that never lifts a value under `limit` up to it:
 * a BMI of 18.478 reads 18.4, so the text never says "18.5 is under 18.5". */
function round1NeverUpTo(n: number, limit: number): number {
  const rounded = round1(n)
  return n < limit && rounded >= limit ? Math.floor(n * 10) / 10 : rounded
}

/** Lowest weight, in steps of 0.1 kg, whose BMI as computed is at or above
 * `imc`. The loop only guards the rounding of the division. */
function lowestWeightAtOrAbove(imc: number, altura2: number): number {
  let tenths = Math.ceil(imc * altura2 * 10 - 1e-9)
  while (tenths / 10 / altura2 < imc) tenths += 1
  return tenths / 10
}
