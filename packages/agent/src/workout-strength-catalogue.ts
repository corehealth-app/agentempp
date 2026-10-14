/** Auxiliary read-only observer. Shape/port/flag never authenticate DB provenance.
 * Full active-set SQL, trusted caller and transactional CAS remain separate gates.
 * Factory/config and parser/classifier defects intentionally stay outside RPC catch.
 */
import {
  classifyConfirmedWorkoutType,
  type WorkoutCatalogueCategory,
  type WorkoutCatalogueRead,
  type WorkoutCatalogueRow,
  type WorkoutClassification,
} from '@mpp/core/workout-strength-classification'
import { exactKeys, isRecord, isUTCUS6, isUUID } from './workout-strength-wire.js'

export interface WorkoutStrengthCataloguePort {
  rpc(
    name: 'get_workout_strength_catalogue_context',
    args: Readonly<Record<string, never>>,
  ): PromiseLike<{ data: unknown; error: unknown | null }>
}
export type WorkoutStrengthCatalogueObservationResult =
  | { readonly status: 'disabled' }
  | {
      readonly status: 'observed'
      readonly originalOperationType: string
      readonly read: WorkoutCatalogueRead
      readonly classification: WorkoutClassification
    }
type UnavailableRead = Extract<WorkoutCatalogueRead, { status: 'unavailable' }>
type UnavailableReason = UnavailableRead['reason']

export async function observeWorkoutStrengthCatalogue(
  rawType: string,
  options: {
    readonly enabled?: boolean
    readonly createClient: () => WorkoutStrengthCataloguePort
  },
): Promise<WorkoutStrengthCatalogueObservationResult> {
  if (options.enabled !== true) return { status: 'disabled' }
  const client = options.createClient()
  const rpc = client?.rpc
  if (typeof rpc !== 'function') throw new TypeError('Catalogue port requires a callable rpc')

  let reply: unknown
  try {
    reply = await rpc.call(client, 'get_workout_strength_catalogue_context', {})
  } catch {
    return observed(rawType, unavailable('catalogue_read_error'))
  }
  return observed(rawType, parseReply(reply))
}

function observed(
  rawType: string,
  read: WorkoutCatalogueRead,
): WorkoutStrengthCatalogueObservationResult {
  return {
    status: 'observed',
    originalOperationType: rawType,
    read,
    classification: classifyConfirmedWorkoutType(rawType, read),
  }
}

function parseReply(reply: unknown): WorkoutCatalogueRead {
  if (!isRecord(reply) || reply.error === undefined) return unavailable('catalogue_invalid')
  if (reply.error !== null) return unavailable('catalogue_read_error')
  const value = reply.data
  if (!isRecord(value)) return unavailable('catalogue_invalid')
  if (value.status === 'unavailable') {
    return exactKeys(value, ['status', 'reason']) && isUnavailableReason(value.reason)
      ? unavailable(value.reason)
      : unavailable('catalogue_invalid')
  }
  if (
    !exactKeys(value, [
      'status',
      'observationKey',
      'observedAt',
      'matcherVersion',
      'complete',
      'rowCount',
      'activeRows',
    ]) ||
    value.status !== 'available' ||
    !isUUID(value.observationKey) ||
    !isUTCUS6(value.observedAt) ||
    value.matcherVersion !== 'active_slug_then_unique_canonical_display_v1' ||
    typeof value.complete !== 'boolean' ||
    typeof value.rowCount !== 'string' ||
    !/^(0|[1-9][0-9]*)$/u.test(value.rowCount) ||
    !Array.isArray(value.activeRows)
  ) {
    return unavailable('catalogue_invalid')
  }

  const rawRows: readonly unknown[] = value.activeRows
  const rows: WorkoutCatalogueRow[] = []
  const slugs = new Set<string>()
  let previousID: string | null = null
  for (const row of rawRows) {
    if (
      !exactKeys(row, ['id', 'slug', 'displayName', 'category', 'isActive', 'updatedAtLiteral']) ||
      !isUUID(row.id) ||
      typeof row.slug !== 'string' ||
      typeof row.displayName !== 'string' ||
      !isCategory(row.category) ||
      row.isActive !== true ||
      !isUTCUS6(row.updatedAtLiteral) ||
      (previousID !== null && row.id <= previousID) ||
      slugs.has(row.slug)
    ) {
      return unavailable('catalogue_invalid')
    }
    previousID = row.id
    slugs.add(row.slug)
    rows.push({
      id: row.id,
      slug: row.slug,
      displayName: row.displayName,
      category: row.category,
      isActive: true,
      updatedAtLiteral: row.updatedAtLiteral,
    })
  }

  const count = BigInt(value.rowCount)
  const length = BigInt(rows.length)
  if (count < length) return unavailable('catalogue_invalid')
  if (!value.complete || count > length) return unavailable('catalogue_incomplete')
  return {
    status: 'complete',
    observation: {
      observationKey: value.observationKey,
      observedAt: value.observedAt,
      matcherVersion: value.matcherVersion,
    },
    activeRows: rows,
  }
}

function isCategory(value: unknown): value is WorkoutCatalogueCategory {
  return (
    value === 'musculacao' || value === 'cardio' || value === 'esporte' || value === 'mobilidade'
  )
}

function isUnavailableReason(value: unknown): value is UnavailableReason {
  return (
    value === 'catalogue_read_error' ||
    value === 'catalogue_invalid' ||
    value === 'catalogue_incomplete'
  )
}

function unavailable(reason: UnavailableReason): UnavailableRead {
  return { status: 'unavailable', reason }
}
