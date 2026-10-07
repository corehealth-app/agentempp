/**
 * Sign-up eligibility: who is placed in recomposição without being asked and
 * who may choose among the three objectives (docs/CALCULO-MPP.md §10).
 *
 * Pure, no I/O, no text. Called by the sign-up eligibility check of the app
 * (apps/admin/src/lib/mobile-api/protocol-eligibility-service.ts), which
 * rounds the body values to what the profile stores before calling and writes
 * nothing. The completion of the sign-up still records the objective that was
 * sent, with no check. `resolveProtocol` (protocol-router.ts) is the legacy
 * path, still feeds the "Decisão automática" context line, and is not
 * touched: the two share no code on purpose.
 *
 * THE RULE, as the client (Dr. Roberto) wrote it — it is NOT a new decision.
 * Thresholds are read from `CalcConfig` (`bf_limits`, `imc_limit_recomp`,
 * `training_min`); the numbers below are the code defaults.
 *
 *  C0  Body fat informed → body fat decides. Not informed → BMI decides.
 *      "IMC ≥ 25 (quando BF não disponível)" (rule "Regra de Decisão
 *      Automática de Protocolo — Quando NÃO perguntar ao usuário"); manual
 *      9.4.1: body fat is the "padrão-ouro", BMI a "ferramenta substituta
 *      temporária".
 *  C1  Man, body fat ≥ 20%   → recomposição, not asked.
 *  C2  Woman, body fat ≥ 28% → recomposição, not asked.
 *  C3  No body fat, BMI ≥ 25 → recomposição, not asked. 25.0 itself is in:
 *      01/02/2026 (typed) "o IMC de 25 entra mesmo na recomposiçõa corporal";
 *      25/03/2026 (typed) "Isso, menor q 25" / "Sem o igual".
 *      C1–C3: same rule, "conduzir automaticamente para o protocolo de
 *      Recomposição Corporal, sem oferecer opção de escolha"; also 3.1 and 8.2.
 *      For these people manutenção is 'not_offered' and ganho de massa is
 *      'blocked' with 'composition' always among the reasons ("se o usuário
 *      solicitar ganho de massa, aplicar a frase de bloqueio educada").
 *  C4  Otherwise (man < 20%, woman < 28%, or no body fat and BMI < 25) → the
 *      person chooses; "apresentar as 3 opções" (same rule, "Quando
 *      perguntar"; rule "Pergunta de qual objetivo, se usuário dentro da
 *      faixa saudável"; audio of 24/01/2026).
 *  C5  In C4, recomposição: available.
 *  C6  In C4, manutenção: available — also when ganho de massa is blocked.
 *  C7  In C4, ganho de massa: available only with (a) composition — body fat
 *      ≤ 19% (man) / ≤ 27% (woman) when informed; nothing further when it is
 *      not, because BMI < 25 was already required by C4 — and (b) strength
 *      training ≥ 3 times a week. Rule "Ganho de massa muscular - Critérios de
 *      entrada" (the same text in the table of 02/02/2026 and in the list of
 *      01/06/2026); audio of 28/12/2025 ("pelo [menos] 3 vezes por semana de
 *      musculação").
 *  C8, C9  Which text each result shows is not decided here: the caller
 *      picks it (protocol-messages.ts) from `outcome`, `basis`, the `reasons`
 *      of ganho de massa and `limits`.
 *  C10 Sleep (≥ 6h30) and organised eating are not read: they neither open
 *      nor block anything here.
 *  C11 Very low weight and C12 body fat of 10% or less: no rule, nothing
 *      special happens (see the pendencies in the doc).
 *
 * CONTRADICTION (written text × later audio), about C7 without body fat: the
 * entry criterion still reads "IMC ≤ 24 com aparência funcional adequada" (the
 * list of 01/06/2026 included); "≤ 24" exists only there and in 3.2. On
 * 25/03/2026 19:43, about the "menor ou igual do 24" of a print of the rules,
 * the client said in audio "No que tá aí menor = 24 aí você tira o igual …
 * menor que 25 na verdade … incluiria o 24 e não o 25 … o 25 estaria fora da
 * faixa da normalidade". Implemented: the later statement — one BMI cut (25),
 * no "≤ 24" constant. Implemented on 2026-10-07 at Eduardo's request; the
 * client's confirmation is pending.
 * What that evening was about (same day, 19:16 audio and 19:42:59 typed) was
 * the range of who CHOOSES: whether 25 is inside "a faixa da normalidade pra
 * poder escolher o protocolo", and "a opção de manutenção pro 25". Applying the
 * "menor que 25" to the ENTRY criterion of ganho de massa is OUR READING — it
 * rests only on the "≤ 24" existing in no rule other than that criterion and
 * 3.2 — and is what the client is asked to confirm (doc §10c, §10k-1).
 *
 * NATURAL READINGS — each implemented on 2026-10-07 at Eduardo's request; the
 * client's confirmation is pending:
 *  - C0: body fat typed by the person counts as "BF disponível";
 *  - C6: manutenção stays available when ganho de massa is blocked (rule 8.2
 *    and the blocking phrase 3.4.1 would lead to recomposição);
 *  - C7: with body fat informed the BMI is not checked for ganho de massa
 *    ("pelo menos um" of the entry criterion × "cumprir todos" of 3.2);
 *  - C7: man above 19% and below 20%, woman above 27% and below 28%: they
 *    choose between recomposição and manutenção and ganho de massa is blocked
 *    by composition — although "pelo menos um" would open it through the BMI
 *    (the active rule "Ganho de massa muscular - Critérios de bloqueio do
 *    protocolo" blocks the phase on "BF acima dos limites de entrada");
 *  - C7: without body fat only the BMI counts ("aparência funcional adequada"
 *    is not assessed: there are no photos at sign-up);
 *  - C10: sleep and organised eating do not gate (the manual of 27/12/2025
 *    required both; the current entry criterion lists only composition and
 *    strength training; the data-collection rule of the 01/06/2026 list still
 *    calls structured eating a criterion; on 15/05/2026 the client typed that
 *    the question about it "atrapalhou a confirmação do protocolo"; the active
 *    rule "Ganho de massa muscular - Critérios de bloqueio do protocolo" still
 *    says to "bloquear ou pausar a fase de ganho" on "alimentação
 *    inconsistente" and "histórico recente de perda de controle alimentar" —
 *    it speaks of a phase in progress and gives no measure for the sign-up.
 *    Blocking or pausing an ongoing phase is NOT this function: declared in
 *    the doc, §10j).
 */
import { type CalcConfig, DEFAULT_CALC_CONFIG } from './calc-config.js'
import { calcIMC } from './nutrition.js'
import type { Protocol, Sex } from './types.js'

/**
 * Slack of the BMI comparison. A rounding fix, NOT a clinical number and not
 * a number the client stated: `calcIMC` divides in binary floating point, so
 * 64 kg at 160 cm gives 24.999999999999996 where the arithmetic gives 25.0,
 * and a plain `>= 25` would let that person choose. A BMI less than this far
 * below the cut is read as being on the cut. Body fat is typed, not computed,
 * so it is compared as it is.
 */
export const SIGNUP_IMC_ROUNDING_TOLERANCE = 1e-9

/** What decided C1–C4: the informed body fat or, without it, the BMI. */
export type SignupEligibilityBasis = 'BF' | 'IMC'

/**
 * 'available'   — may be recorded for this person;
 * 'blocked'     — the client's rule bars it, `reasons` says why;
 * 'not_offered' — the rule offers no choice here and names no blocking reason
 *                 (manutenção of someone placed in recomposição).
 */
export type SignupObjectiveStatus = 'available' | 'blocked' | 'not_offered'

/**
 * Entry criterion of ganho de massa that is not met: 'composition' (C7a, or
 * the person is above the range) and 'training' (C7b). Always in this order.
 */
export type SignupBlockReason = 'composition' | 'training'

export type SignupEligibilityField =
  | 'sex'
  | 'heightCm'
  | 'weightKg'
  | 'bodyFatPercent'
  | 'trainingFrequency'

export interface SignupEligibilityInput {
  sex: Sex | null | undefined
  heightCm: number | null | undefined
  weightKg: number | null | undefined
  /** Optional. `null` or absent = not informed: the BMI decides (C0). */
  bodyFatPercent?: number | null
  /** Strength-training ("musculação") sessions per week. */
  trainingFrequency: number | null | undefined
}

export interface SignupObjectiveEligibility {
  status: SignupObjectiveStatus
  /** Empty unless `status` is 'blocked'. */
  reasons: SignupBlockReason[]
}

/** The cuts that were applied, for the caller that has to cite one. */
export interface SignupEligibilityLimits {
  /** `bf_limits[sex].recomp`: body fat from this up is placed in recomposição. */
  bodyFatRecomp: number
  /** `bf_limits[sex].gain`: body fat up to this meets C7a. */
  bodyFatGain: number
  /** `imc_limit_recomp`: without body fat, BMI from this up is placed in recomposição. */
  imcRecomp: number
  /** `training_min`: strength sessions per week from this up meet C7b. */
  trainingMin: number
}

interface SignupEligibilityDecided {
  basis: SignupEligibilityBasis
  /** As `calcIMC` gives it, not rounded (64 kg / 160 cm: 24.999999999999996). */
  imc: number
  objectives: Record<Protocol, SignupObjectiveEligibility>
  limits: SignupEligibilityLimits
}

/**
 * 'assigned'      — C1, C2 or C3: recomposição, not asked;
 * 'choice'        — C4: the person is asked;
 * 'invalid_input' — the rule cannot be computed; nothing is decided.
 */
export type SignupEligibility =
  | ({ outcome: 'assigned'; assignedProtocol: 'recomposicao' } & SignupEligibilityDecided)
  | ({ outcome: 'choice' } & SignupEligibilityDecided)
  | { outcome: 'invalid_input'; invalidFields: SignupEligibilityField[] }

/** Every field of the input, in the order of `SignupEligibilityInput`. */
const SIGNUP_ELIGIBILITY_FIELDS: readonly SignupEligibilityField[] = [
  'sex',
  'heightCm',
  'weightKg',
  'bodyFatPercent',
  'trainingFrequency',
]

function isSex(value: unknown): value is Sex {
  return value === 'masculino' || value === 'feminino'
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value)
}

function isPositiveNumber(value: unknown): value is number {
  return isFiniteNumber(value) && value > 0
}

function isNonNegativeNumber(value: unknown): value is number {
  return isFiniteNumber(value) && value >= 0
}

/**
 * One cut out of the config. At runtime the config rows come from
 * `global_config`, copied as they are by the loader, so each is read as
 * `unknown` (same reading as `imcGoalStepPoints`): a row that does not hold a
 * number (text such as "25", null, a missing sex) is a typing mistake and
 * gives the code default — it must never open the choice, nor throw.
 */
function configLimit(raw: unknown, codeDefault: number): number {
  return isFiniteNumber(raw) ? raw : codeDefault
}

type BodyFatLimitsRow = Partial<Record<Sex, { recomp?: unknown; gain?: unknown } | null>> | null

function readLimits(sex: Sex, config: CalcConfig): SignupEligibilityLimits {
  const row = (config.bf_limits as BodyFatLimitsRow | undefined)?.[sex]
  return {
    bodyFatRecomp: configLimit(row?.recomp, DEFAULT_CALC_CONFIG.bf_limits[sex].recomp),
    bodyFatGain: configLimit(row?.gain, DEFAULT_CALC_CONFIG.bf_limits[sex].gain),
    imcRecomp: configLimit(config.imc_limit_recomp, DEFAULT_CALC_CONFIG.imc_limit_recomp),
    trainingMin: configLimit(config.training_min, DEFAULT_CALC_CONFIG.training_min),
  }
}

/**
 * Applies C0–C7 to the data of the sign-up. See the header for the table, its
 * sources and what is still to be confirmed by the client.
 *
 * Invalid input — a sex that is not one of the two, a height or weight that is
 * not a number above zero (the BMI would be undefined), a body fat that is
 * informed but is not a number between 0 and 100 (exclusive), a training
 * frequency that is not a number from zero up — returns `invalid_input` with
 * the fields at fault, in the order of `SignupEligibilityInput`, and decides
 * nothing: neither "recomposição" nor "may choose" is a safe guess for data
 * the rule cannot read, and the client's text has no rule for it. Height and
 * weight are required even when body fat decides. Plausibility (a height typed
 * in metres, 9 sessions a week) is the contract's job, not this function's:
 * whatever can be computed is compared as it is.
 *
 * Outside the declared types, so that the function never throws: an `input`
 * that is not an object (absent, `null`, a number, a text) returns
 * `invalid_input` with the five fields, since none could be read; a `config`
 * passed as `null` is read as absent and gives the code default.
 */
export function decideSignupEligibility(
  input: SignupEligibilityInput,
  config: CalcConfig = DEFAULT_CALC_CONFIG,
): SignupEligibility {
  if (typeof input !== 'object' || input === null) {
    return { outcome: 'invalid_input', invalidFields: [...SIGNUP_ELIGIBILITY_FIELDS] }
  }
  // The default parameter covers only `undefined`.
  const cuts: CalcConfig = config ?? DEFAULT_CALC_CONFIG

  const { sex, heightCm, weightKg, trainingFrequency } = input
  const bodyFat: unknown = input.bodyFatPercent ?? null
  const bodyFatValid = bodyFat === null || (isPositiveNumber(bodyFat) && bodyFat < 100)

  if (
    !isSex(sex) ||
    !isPositiveNumber(heightCm) ||
    !isPositiveNumber(weightKg) ||
    !bodyFatValid ||
    !isNonNegativeNumber(trainingFrequency)
  ) {
    const invalidFields: SignupEligibilityField[] = []
    if (!isSex(sex)) invalidFields.push('sex')
    if (!isPositiveNumber(heightCm)) invalidFields.push('heightCm')
    if (!isPositiveNumber(weightKg)) invalidFields.push('weightKg')
    if (!bodyFatValid) invalidFields.push('bodyFatPercent')
    if (!isNonNegativeNumber(trainingFrequency)) invalidFields.push('trainingFrequency')
    return { outcome: 'invalid_input', invalidFields }
  }

  const imc = calcIMC(weightKg, heightCm)
  // Two valid numbers can still overflow the division (a height near zero).
  if (!isPositiveNumber(imc)) {
    return { outcome: 'invalid_input', invalidFields: ['heightCm', 'weightKg'] }
  }

  const limits = readLimits(sex, cuts)
  const informedBodyFat = isFiniteNumber(bodyFat) ? bodyFat : null
  const basis: SignupEligibilityBasis = informedBodyFat !== null ? 'BF' : 'IMC'

  // C1–C3: above the range → recomposição, not asked.
  const aboveRange =
    informedBodyFat !== null
      ? informedBodyFat >= limits.bodyFatRecomp
      : imc >= limits.imcRecomp - SIGNUP_IMC_ROUNDING_TOLERANCE

  // C7: every entry criterion of ganho de massa that is not met.
  const reasons: SignupBlockReason[] = []
  const compositionMet =
    !aboveRange && (informedBodyFat === null || informedBodyFat <= limits.bodyFatGain)
  if (!compositionMet) reasons.push('composition')
  if (trainingFrequency < limits.trainingMin) reasons.push('training')
  const ganhoMassa: SignupObjectiveEligibility =
    reasons.length === 0 ? { status: 'available', reasons: [] } : { status: 'blocked', reasons }

  if (aboveRange) {
    return {
      outcome: 'assigned',
      assignedProtocol: 'recomposicao',
      basis,
      imc,
      objectives: {
        recomposicao: { status: 'available', reasons: [] },
        ganho_massa: ganhoMassa,
        manutencao: { status: 'not_offered', reasons: [] },
      },
      limits,
    }
  }

  // C4–C6: within the range → the person chooses.
  return {
    outcome: 'choice',
    basis,
    imc,
    objectives: {
      recomposicao: { status: 'available', reasons: [] },
      ganho_massa: ganhoMassa,
      manutencao: { status: 'available', reasons: [] },
    },
    limits,
  }
}
