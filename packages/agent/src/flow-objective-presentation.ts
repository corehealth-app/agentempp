/** C3/C4 presentation copies. Never derives an objective from historical energy. */

import { normalizeProtocol, type Protocol } from '@mpp/core'
import { type FlowClinicalPolicy, readFlowClinicalPolicy } from './flow-current-clinical.js'
import { flowStatusExplanation } from './flow-status-presentation.js'

export interface FlowPresentationObjective {
  currentProtocol: Protocol | null
  clinicalPolicy?: FlowClinicalPolicy
}

export function flowBlockExplanation(
  objective: FlowPresentationObjective,
  locale: string | null,
): string {
  if (objective.clinicalPolicy && readFlowClinicalPolicy(objective.clinicalPolicy).hide.block)
    return ''
  if (!flowStatusExplanation(objective.currentProtocol)) return ''
  return locale?.startsWith('en')
    ? 'The 7,700 Block is displayed only for body recomposition.'
    : flowStatusExplanation(objective.currentProtocol)
}

const normalize = (text: string) => text.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase()
/** Prescriptions need neither a "target" label nor an imperative reduction.
 * Match advice/purpose separately from factual food energy, past intake and
 * preserved target/balance labels. This guard also projects stored replies. */
function suspendedLossPrescription(statement: string): boolean {
  const value = normalize(statement.replace(/[_*~`]/gu, ''))
  const directive =
    /\b(?:reduza|reduzir|diminua|diminuir|corte|cortar|faca|fazer|adote|adotar|estabeleca|busque|procure|tente|mire|almeje|acelere|consuma|consumir|coma|comer|ingira|ingerir|limite|limitar|deve|deveria|recomendo|aconselho|mantenha|manter|reduce|cut|lower|maintain|keep|create|achieve|establish|adopt|aim|try|consume|eat|limit|should|must|recommend|recommended)\b/u.test(
      value,
    )
  const intakeOrDeficit =
    /\b(?:kcal|calorias?|calories?|ingestao|intake|comida|food|porcoes|portions|deficit|shortfall)\b|\b(?:balanco (?:energetico )?negativo|negative energy balance)\b/u.test(
      value,
    )
  const lossGoal =
    /\b(?:emagrec\p{L}*|perd(?:a|er) (?:de )?(?:peso|gordura)|secar|lose weight|weight loss|slim down|get leaner|reduce body fat|burn fat)\b/u.test(
      value,
    )
  const purpose =
    /\b(?:para|to)\s+(?:emagrec\p{L}*|perder (?:peso|gordura)|secar|lose weight|slim down|get leaner|reduce body fat|burn fat)\b/u.test(
      value,
    )
  const promisedLoss = lossGoal && /\b(?:vai|ira|ajuda|ajudara|will|can|help|helps)\b/u.test(value)
  return (
    (directive && (intakeOrDeficit || lossGoal)) ||
    purpose ||
    promisedLoss ||
    /\b(?:coma menos|eat less|emagreca|lose weight)\b/u.test(value)
  )
}
const blockLabel = /\b(?:bloco(?:\(s\)|s)?(?:\s+de)?\s*7[.,]?700|7[.,]?700[ -]*blocks?)\b/u
const budgetLabel =
  /\b(?:(?:orcamento|budget)(?:\s+(?:de|para|of|for))?\s+(?:14\s*(?:dias?|days?|d)|quatorze dias)|14[ -]*(?:dias?|days?|d)[ -]*(?:budget|orcamento))\b/u
const metricLabelSample = (text: string) => text.replace(/[_*~`]/gu, '')
// A qualified label remains C4 in headers/tables or emphasized copy. The
// ordinary English noun "dam" alone is not a metric.
const qualifiedDam = (text: string) =>
  /\b(?:days above target|dias acima da meta)\s*\(\s*dam\s*\)/iu.test(metricLabelSample(text))
const hasBudget = (text: string) =>
  budgetLabel.test(normalize(text)) || /\bDAM\b/u.test(text) || qualifiedDam(text)

/** Relative paths start with a named segment; a numeric fraction is not a path. */
const referencePattern = () =>
  /(?:[a-z][a-z0-9+.-]*:\/\/|www\.|[a-z]:\\|\.\.?\/|(?<![\p{L}\p{N}])(?:[\p{L}_][\p{L}\p{N}_.-]*\/)+|(?<![\p{L}\p{N}])\/|(?<=\]\())[^\s<>"`]+/giu

/** Only the language sample excludes opaque destinations; original copy is retained. */
export function flowObjectiveLanguageSample(text: string): string {
  return text.replace(referencePattern(), '')
}

/** Policy copy is not progress. Numbers other than the qualified block reject the exception. */
function isBlockPolicy(text: string): boolean {
  const value = normalize(text).trim()
  return (
    /^(?:o bloco 7[.,]?700 e exibido apenas na recomposicao corporal|the 7[.,]?700 block is displayed only for body recomposition)[.!]?$/u.test(
      value,
    ) ||
    /^(?:nao exiba o bloco 7[.,]?700 fora da recomposicao|do not show the 7[.,]?700 block outside body recomposition)[.!]?$/u.test(
      value,
    )
  )
}

interface Projection {
  text: string
  changed: boolean
  removedBlock: boolean
}

export function projectFlowObjectiveText(
  text: string,
  objective: FlowPresentationObjective,
  replacement: string,
): Projection {
  const protocol = normalizeProtocol(objective.currentProtocol)
  const clinical =
    objective.clinicalPolicy === undefined
      ? undefined
      : readFlowClinicalPolicy(objective.clinicalPolicy)
  let changed = false
  let removedBlock = false
  const protectedSpans: string[] = []
  let marker = '\uE000FLOWURL'
  while (text.includes(marker)) marker += '\uE000'
  const restricted = (statement: string): boolean => {
    const value = normalize(statement)
    const block =
      (clinical?.hide.block || protocol !== 'recomposicao') &&
      blockLabel.test(value) &&
      !isBlockPolicy(statement)
    const budget = hasBudget(statement)
    const calories =
      clinical?.hide.calories &&
      /\b(?:meta(?:s)?\s+(?:caloric[ao]s?|de\s+calorias|(?:de\s+)?hoje)|(?:sua|minha|tua)\s+meta|(?:your|my)\s+(?:calorie\s+)?target|calorie\s+target|daily\s+(?:calorie\s+)?target)\b|\b(?:meta|target)\b[^.;!?]*\bkcal\b|\b(?:restam|restante|remaining|left)\b[^.;!?]*(?:comida|comer|food|eat|kcal)/u.test(
        value,
      )
    const protein =
      clinical?.hide.protein &&
      /\b(?:meta|alvo|target)\b[^.;!?]*(?:proteina|protein)|\bprotein\s+target\b/u.test(value)
    const balance =
      clinical?.hide.balance &&
      /\b(?:balanco|saldo)(?:\s+(?:calorico|energetico|do dia|de hoje|diario))?\b|\b(?:day|daily|calorie|energy)\s+balance\b/u.test(
        value,
      )
    const phase =
      clinical?.hide.objective &&
      /\b(?:protocolo atual|fase atual|seu objetivo|sua fase|current protocol|current phase|your objective|your phase)\b/u.test(
        value,
      )
    const loss = clinical?.pause_weight_loss_guidance && suspendedLossPrescription(statement)
    return block || budget || !!calories || !!protein || !!balance || !!phase || !!loss
  }
  const remove = (statement: string): string => {
    changed = true
    if (
      protocol !== 'recomposicao' &&
      blockLabel.test(normalize(statement)) &&
      !isBlockPolicy(statement)
    ) {
      removedBlock = true
    }
    return replacement
  }
  const projectLine = (line: string): string => {
    if (!restricted(line)) return line
    const withoutParentheticals = line.replace(
      /(\s*)([_*~`]*)\(([^()]*(?:\([^()]*\)[^()]*)*)\)\2/gu,
      (whole, space: string, emphasis: string, inner: string, offset: number, source: string) => {
        // Bind each known qualifier to its preceding label, before extracting
        // standalone parenthetic metrics. Lists, tables and emphasized values
        // do not change that association; outer public facts remain separate.
        const prefix = normalize(metricLabelSample(source.slice(0, offset)))
        const qualifier = normalize(metricLabelSample(inner))
        const blockQualifier =
          /\b(?:deficit acumulado|accumulated deficit)\s*$/u.test(prefix) &&
          blockLabel.test(qualifier)
        const damQualifier =
          /\b(?:days above target|dias acima da meta)\s*$/u.test(prefix) &&
          /^\s*dam\s*$/u.test(qualifier)
        if (blockQualifier || damQualifier || !restricted(inner)) return whole
        const kept = projectLine(inner)
        return kept ? `${space}${emphasis}(${kept})${emphasis}` : ''
      },
    )
    if (!restricted(withoutParentheticals)) return withoutParentheticals
    const separators =
      /;\s*|(?<=[.!?])\s+|\s+[|·—–-]\s+|:\s+|\s+(?:e|mas|and|but)\s+|,\s+(?:mas\s+|but\s+)?/giu
    const parts: string[] = []
    let start = 0
    for (const match of withoutParentheticals.matchAll(separators)) {
      const index = match.index
      const left = withoutParentheticals.slice(start, index)
      const right = withoutParentheticals.slice(index + match[0].length)
      const startsValue =
        /^(?:[+−-]?\d|(?:estimad[oa]|estimated|approximately|cerca de|about)\b)/iu.test(
          right.replace(/^[\s*_~`(]+/u, ''),
        )
      // A clinical label also owns nonnumeric values such as 'déficit de…' or a phase name.
      if (clinical && match[0].startsWith(':') && restricted(left)) continue
      // Labels and their values must disappear together, including the DAM sublabel.
      if (
        (match[0].startsWith(':') || /[|·—–-]/u.test(match[0])) &&
        startsValue &&
        (restricted(left) || !restricted(right))
      )
        continue
      // The budget and its DAM count form one restricted statement.
      if (hasBudget(left) && /^(?:DAM|janela|window)\b/iu.test(right)) continue
      parts.push(left, match[0])
      start = index + match[0].length
    }
    parts.push(withoutParentheticals.slice(start))
    let result = ''
    for (let i = 0; i < parts.length; i += 2) {
      const statement = parts[i] ?? ''
      const kept = restricted(statement) ? remove(statement) : statement
      if (!kept.trim()) continue
      result += result ? `${parts[i - 1] ?? ' '}${kept}` : kept.trimStart()
    }
    return result.trim()
  }
  // A fully restricted visible link label becomes the original bare destination.
  // Mixed labels retain their public words. Neither path invents a link caption.
  const labelled = text.replace(
    /\[([^\]\n]*)\]\(([^\s)]+)\)/gu,
    (whole, label: string, target: string) => {
      if (!restricted(label)) return whole
      const kept = projectLine(label)
      if (!kept) return target
      const caption = kept === '[referência interna omitida]' ? 'referência interna omitida' : kept
      return `[${caption}](${target})`
    },
  )
  // Protect targets before classifying or splitting the surrounding statements.
  const masked = labelled.replace(referencePattern(), (span) => {
    protectedSpans.push(span)
    return `${marker}${protectedSpans.length - 1}\uE001`
  })
  const projected = masked
    .split('\n')
    .flatMap((line) => {
      const result = projectLine(line)
      // Keep existing paragraph separators; remove only emptied restricted lines.
      return line.trim() && !result.trim() ? [] : [result]
    })
    .join('\n')
  const restored = projected.replace(
    new RegExp(`${marker}(\\d+)\uE001`, 'gu'),
    (_whole, index: string) => protectedSpans[Number(index)] ?? '',
  )
  return { text: changed ? restored : text, changed, removedBlock }
}
