/** Dormant executable authority foundation. No provider, formula, database or
 * legacy intent/writer is reachable; unsupported discourse requires a reply. */
import { isDeepStrictEqual } from 'node:util'
import {
  type CapturedConversationWorkoutSource,
  parseConversationWorkoutSource,
  workoutDigest,
  workoutSnapshot,
} from './conversation-workout-contracts'

const normalize = (s: string) =>
  s
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .replace(/\s+/gu, ' ')
    .trim()
type Intensity = 'leve' | 'moderada' | 'alta'
interface Activity {
  workout_type: string
  duration_min: number
  intensity: Intensity | null
}
function pinned(source: CapturedConversationWorkoutSource) {
  const parsed = parseConversationWorkoutSource(source.command, {
    source_hash: source.sourceHash,
    context: source.context,
  })
  if (!isDeepStrictEqual(source, parsed)) throw new Error('Changed workout source ports')
  return parsed
}
function binding(source: CapturedConversationWorkoutSource) {
  return {
    owner_id: source.command.ownerId,
    command_id: source.command.commandId,
    input_hash: source.command.inputHash,
    source_hash: source.sourceHash,
    epoch: source.epoch,
  }
}
function question(source: CapturedConversationWorkoutSource, field: 'duration_min' | 'activity') {
  return workoutSnapshot({
    ...binding(source),
    status: 'needs_reply' as const,
    question: {
      key: workoutDigest({ source_hash: source.sourceHash, field }),
      field,
      text:
        field === 'duration_min'
          ? 'Quantos minutos durou essa atividade?'
          : 'Qual atividade você realizou e por quantos minutos?',
    },
  })
}
const forbidden =
  /\?|\b(?:nao|nunca|amanha|ontem|sempre|costumo|faco|fazia|farei|faria|vou|iria|se|sonh\w*|pai|mae|ele|ela|voce|voces|todos|toda|todo|semanalmente|diariamente)\b/u
const durationPattern =
  '(?:\\d{1,4}\\s*(?:minutos?|min)|\\d{1,2}(?:[.,]\\d{1,2})?\\s*(?:horas?|h)(?:\\s*(?:e\\s+)?\\d{1,2}\\s*(?:minutos?|min)?)?|meia hora)'
const durationOnly = new RegExp(`^${durationPattern}$`, 'u')
function durationMinutes(text: string): number | null {
  if (text === 'meia hora') return 30
  const minutes = /^(\d{1,4})\s*(?:minutos?|min)$/u.exec(text)
  if (minutes) return Number(minutes[1])
  const hours =
    /^(\d{1,2})(?:[.,](\d{1,2}))?\s*(?:horas?|h)(?:\s*(?:e\s+)?(\d{1,2})\s*(?:minutos?|min)?)?$/u.exec(
      text,
    )
  if (!hours) return null
  const fraction = hours[2] ?? '',
    scale = 10 ** fraction.length,
    extra = Number(hours[3] ?? 0),
    total = ((Number(hours[1]) * scale + Number(fraction)) * 60) / scale + extra
  return extra < 60 && Number.isInteger(total) ? total : null
}
interface PerformedClause {
  name: string
  duration: number | null
  intensity: Intensity | null
  intensityLabel: string | null
}
const intensitySuffix = /(?: em ritmo| com intensidade)? (leve|moderad[oa]|alt[oa])$/u
function intensityForLabel(label: string | null): Intensity | null {
  if (label === null) return null
  if (label === 'leve') return 'leve'
  return label.startsWith('moderad') ? 'moderada' : 'alta'
}
/** Closed complete clauses only. These aliases identify an activity, never a
 * rate, intensity, weight or calorie default. The captured catalogue must still
 * resolve the name uniquely. All other discourse stays unresolved. */
function performedClause(original: string): PerformedClause | null {
  let text = original.replace(/[.!]$/u, '').trim()
  if (text.startsWith('hoje ')) text = text.slice(5)
  if (text.endsWith(' hoje')) text = text.slice(0, -5)
  const explicit = intensitySuffix.exec(text),
    label = explicit?.[1] ?? null,
    intensity = intensityForLabel(label)
  if (explicit) text = text.slice(0, explicit.index)
  const natural = /^(?:eu )?(caminhei|corri|pedalei|nadei)(?:\s+|(?=\d)|$)(.*)$/u.exec(text)
  if (natural) {
    const names: Record<string, string> = {
      caminhei: 'caminhada',
      corri: 'corrida',
      pedalei: 'bicicleta',
      nadei: 'natacao',
    }
    const tail = (natural[2] ?? '').replace(/^(?:por|durante) /u, ''),
      name = names[natural[1] ?? '']
    if (!name || (tail !== '' && !durationOnly.test(tail))) return null
    return {
      name,
      duration: tail === '' ? null : durationMinutes(tail),
      intensity,
      intensityLabel: label,
    }
  }
  const literal = /^(?:eu )?(?:fiz|realizei|pratiquei|treinei) (.+)$/u.exec(text)
  if (!literal?.[1]) return null
  const prefix = new RegExp(`^(${durationPattern}) de ([\\p{L} _-]+)$`, 'u').exec(literal[1]),
    suffix = new RegExp(`^([\\p{L} _-]+?) (?:por |durante |de )?(${durationPattern})$`, 'u').exec(
      literal[1],
    ),
    name = (prefix?.[2] ?? suffix?.[1] ?? literal[1]).replace(/^(?:um|uma) /u, ''),
    duration = prefix?.[1] ?? suffix?.[2],
    embedded = intensitySuffix.exec(name),
    resolvedLabel = label ?? embedded?.[1] ?? null
  if (!/^[\p{L} _-]+$/u.test(name)) return null
  // A duration after the activity must not turn its intensity adjective into
  // a different catalogue identity. Repeated/conflicting labels stay unresolved.
  if (embedded && label !== null) return null
  return {
    name: embedded ? name.slice(0, embedded.index) : name,
    duration: duration === undefined ? null : durationMinutes(duration),
    intensity: intensityForLabel(resolvedLabel),
    intensityLabel: resolvedLabel,
  }
}
/** Every owned source unit must independently describe the same completed
 * activity. This is not permission to dispatch from an unsealed generic intake. */
export function resolveConversationWorkoutReport(original: CapturedConversationWorkoutSource) {
  const source = pinned(original),
    evidence: { unit: string; text: string }[] = []
  let activity: Activity | null = null,
    missingDuration = false
  if (!source.sources.length) return question(source, 'activity')
  for (const unit of source.sources) {
    const text = normalize(unit.text)
    if (forbidden.test(text))
      return workoutSnapshot({
        ...binding(source),
        status: 'not_reported' as const,
        reason: 'non_performed_or_conflicting_source' as const,
      })
    const clause = performedClause(text)
    if (!clause) return question(source, 'activity')
    const name = clause.name,
      rows = source.context.catalogue.filter(
        (row) =>
          normalize(row.slug.replace(/_/gu, ' ')) === name || normalize(row.display_name) === name,
      )
    // A real catalogue label may contain an intensity word. Preserve ambiguity
    // instead of silently choosing a different slug/rate.
    if (
      clause.intensityLabel &&
      source.context.catalogue.some((row) =>
        [clause.intensityLabel, clause.intensity].some(
          (word) =>
            normalize(row.slug.replace(/_/gu, ' ')) === `${name} ${word}` ||
            normalize(row.display_name) === `${name} ${word}`,
        ),
      )
    )
      return question(source, 'activity')
    const selected = rows[0]
    if (rows.length !== 1 || !selected || selected.slug === 'outro')
      return question(source, 'activity')
    const duration = clause.duration
    if (duration === null) {
      missingDuration = true
      continue
    }
    if (duration < 1 || duration > 1440) return question(source, 'duration_min')
    const next: Activity = {
      workout_type: selected.slug,
      duration_min: duration,
      intensity: clause.intensity,
    }
    if (activity && !isDeepStrictEqual(next, activity)) return question(source, 'activity')
    activity = next
    evidence.push({ unit: unit.unit, text: unit.text })
  }
  if (missingDuration || !activity) return question(source, 'duration_min')
  return workoutSnapshot({ ...binding(source), status: 'ready' as const, activity, evidence })
}
export interface WorkoutEstimateRequest {
  readonly slug: string
  readonly duration_min: number
  readonly intensity: Intensity
  readonly weight_kg: number
  readonly source_hash: string
}
export interface ConversationWorkoutPreparationPorts {
  /** Must observe current Auth/admin/patient/epoch. This source is historical. */
  checkCurrentScope(scope: ReturnType<typeof binding>): Promise<boolean>
  /** Optional existing calc_workout_kcal result, with captured catalogue/current
   * body validated by its backend under the writer's lock. No default exists. */
  estimate?(request: WorkoutEstimateRequest): Promise<number | null>
}
export async function prepareConversationWorkout(
  original: CapturedConversationWorkoutSource,
  ports: ConversationWorkoutPreparationPorts,
) {
  const source = pinned(original),
    check = ports.checkCurrentScope.bind(ports),
    estimate = ports.estimate?.bind(ports)
  const held = () =>
    workoutSnapshot({
      ...binding(source),
      status: 'held' as const,
      reason: 'scope_changed' as const,
    })
  let closed = false
  async function current() {
    if (closed) throw new Error('Closed workout scope')
    try {
      if ((await check(binding(source))) !== true || closed)
        throw new Error('Changed workout scope')
    } catch {
      closed = true
      throw new Error('Closed workout scope')
    }
  }
  try {
    await current()
    const decision = resolveConversationWorkoutReport(source)
    if (decision.status !== 'ready') {
      await current()
      return decision
    }
    const weight = source.clinical.body.weight_kg,
      intensity = decision.activity.intensity
    let kcal: number | null = null
    if (estimate && weight !== null && intensity !== null) {
      await current()
      try {
        const value = await estimate(
          workoutSnapshot({
            slug: decision.activity.workout_type,
            duration_min: decision.activity.duration_min,
            intensity,
            weight_kg: weight,
            source_hash: source.sourceHash,
          }),
        )
        if (value !== null && Number.isSafeInteger(value) && value >= 0 && value <= 10000)
          kcal = value
      } catch {
        /* Optional estimate cannot invent energy or repeat a writer. */
      }
      await current()
    }
    await current()
    return workoutSnapshot({
      ...decision,
      activity: { ...decision.activity, estimated_kcal: kcal },
      performed_at: source.admittedAt,
      local_date: source.localDate,
      time_zone: source.clinical.timezone,
      energy:
        kcal === null
          ? { status: 'unavailable' as const }
          : {
              status: 'available' as const,
              source: 'calc_workout_kcal' as const,
              weight_kg: weight,
            },
    })
  } catch {
    return held()
  }
}
