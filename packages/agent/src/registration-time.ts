import { getLocalDateString, getTzOffset } from './timezone-utils.js'

export interface RegistrationTimeInput {
  timezone: string
  referenceTimestamp?: Date | null
  explicitDate?: string | null
  detectedDate?: string | null
}

export interface RegistrationTime {
  localDate: string
  occurredAtIso: string
  source: 'reference_timestamp' | 'explicit_date' | 'detected_date'
}

function validTimestamp(value: Date | null | undefined): Date {
  return value && Number.isFinite(value.getTime()) ? value : new Date()
}

function validDate(value: string | null | undefined): value is string {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)
}

export function resolveRegistrationTime(input: RegistrationTimeInput): RegistrationTime {
  const referenceTimestamp = validTimestamp(input.referenceTimestamp)
  const referenceLocalDate = getLocalDateString(input.timezone, referenceTimestamp)
  const explicitDate = validDate(input.explicitDate) ? input.explicitDate : null
  const detectedDate = validDate(input.detectedDate) ? input.detectedDate : null
  const localDate = explicitDate ?? detectedDate ?? referenceLocalDate
  const source = explicitDate
    ? 'explicit_date'
    : detectedDate
      ? 'detected_date'
      : 'reference_timestamp'

  if (localDate === referenceLocalDate) {
    return { localDate, occurredAtIso: referenceTimestamp.toISOString(), source }
  }

  const offsetReference = new Date(`${localDate}T12:00:00.000Z`)
  const offset = getTzOffset(input.timezone, offsetReference)
  return {
    localDate,
    occurredAtIso: `${localDate}T12:00:00${offset}`,
    source,
  }
}

export function buildPendingTiming(timezone: string, referenceTimestamp: Date) {
  const timestamp = validTimestamp(referenceTimestamp)
  return {
    source_timestamp: timestamp.toISOString(),
    source_timezone: timezone,
    source_local_date: getLocalDateString(timezone, timestamp),
  }
}

export function burstCrossesLocalDate(timezone: string, timestamps: Date[]): boolean {
  const dates = new Set(
    timestamps
      .filter((timestamp) => Number.isFinite(timestamp.getTime()))
      .map((timestamp) => getLocalDateString(timezone, timestamp)),
  )
  return dates.size > 1
}
