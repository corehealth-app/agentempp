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
/** This first increment handles one complete literal performed clause, not a
 * generic NLP promise. Future interpreter evidence must preserve this guard's
 * complete-source requirement before any atomic writer is composed. */
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
    const match =
      /^(?:eu )?(?:fiz|realizei) (?:(\d{1,4}) (?:min|minuto|minutos) de )?([\p{L} _-]+?)(?: (leve|moderada|alta))?[.!]?$/u.exec(
        text,
      )
    if (!match) return question(source, 'activity')
    const name = match[2] ?? '',
      rows = source.context.catalogue.filter(
        (row) =>
          normalize(row.slug.replace(/_/gu, ' ')) === name || normalize(row.display_name) === name,
      )
    // A real catalogue label may contain an intensity word. Preserve ambiguity
    // instead of silently choosing a different slug/rate.
    if (
      match[3] &&
      source.context.catalogue.some(
        (row) =>
          normalize(row.slug.replace(/_/gu, ' ')) === `${name} ${match[3]}` ||
          normalize(row.display_name) === `${name} ${match[3]}`,
      )
    )
      return question(source, 'activity')
    const selected = rows[0]
    if (rows.length !== 1 || !selected || selected.slug === 'outro')
      return question(source, 'activity')
    const duration = match[1] === undefined ? null : Number(match[1])
    if (duration === null) {
      missingDuration = true
      continue
    }
    if (duration < 1 || duration > 1440) return question(source, 'duration_min')
    const next: Activity = {
      workout_type: selected.slug,
      duration_min: duration,
      intensity: (match[3] as Intensity | undefined) ?? null,
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
