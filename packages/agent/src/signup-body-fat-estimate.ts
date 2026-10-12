/**
 * Sign-up photos. D1, Eduardo2026-10-11: arithmetic mean of the three SLOT
 * readings, equal weights. This does not assess precision or change clinical
 * cuts, targets, the legacy aggregate, or a patient's profile.
 */
export type SignupBodyFatPose = 'front' | 'side' | 'back'
export interface SignupBodyFatReading {
  pose: SignupBodyFatPose
  bodyFatPercent: number | null
}
export type SignupBodyFatDecision =
  | { usable: true; body_fat_percent: number }
  | { usable: false; reason: 'out_of_range' }
export interface SignupBodyFatEstimate {
  is_estimate: true
  readings: Array<{ pose: SignupBodyFatPose; body_fat_percent: number }>
  by_sex: { masculino: SignupBodyFatDecision; feminino: SignupBodyFatDecision }
}
const POSES = ['front', 'side', 'back'] as const

function orderedFiniteReadings(
  readings: readonly SignupBodyFatReading[],
): Array<{ pose: SignupBodyFatPose; body_fat_percent: number }> | null {
  if (!Array.isArray(readings) || readings.length !== 3) return null
  if (readings.some((row) => !row || typeof row !== 'object')) return null
  if (new Set(readings.map((row) => row.pose)).size !== 3) return null
  const ordered = POSES.map((pose) => readings.find((row) => row.pose === pose))
  if (
    ordered.some(
      (row) =>
        !row || typeof row.bodyFatPercent !== 'number' || !Number.isFinite(row.bodyFatPercent),
    )
  )
    return null
  return ordered.map((row, index) => ({
    pose: POSES[index] as SignupBodyFatPose,
    body_fat_percent: row?.bodyFatPercent as number,
  }))
}

/** Decimal inputs as PostgreSQL receives their JSON number texts. */
function decimalSum(values: readonly number[]): { sum: bigint; divisor: bigint } {
  const parts = values.map((value) => String(value).split('.'))
  const places = Math.max(...parts.map(([, fraction = '']) => fraction.length))
  const scale = 10n ** BigInt(places)
  const sum = parts.reduce(
    (total, [whole = '0', fraction = '']) =>
      total + BigInt(whole) * scale + BigInt(fraction.padEnd(places, '0') || '0'),
    0n,
  )
  return { sum, divisor: scale * 3n }
}

/** Raw arithmetic mean, separate from the canonical profile value. */
export function rawSignupBodyFatMean(readings: readonly SignupBodyFatReading[]): number | null {
  const ordered = orderedFiniteReadings(readings)
  if (!ordered || ordered.some((row) => row.body_fat_percent < 3 || row.body_fat_percent > 60))
    return null
  const { sum, divisor } = decimalSum(ordered.map((row) => row.body_fat_percent))
  return Number(sum) / Number(divisor)
}

/**
 * The exposed usable value uses the SAME two decimal places/half-away-from-zero
 * policy as numeric(4,2), so display, confirmation and stored eligibility agree.
 * Round the exact decimal rational, never a binary sum beside a clinical cut.
 * Out-of-range readings remain unusable even when their mean is in range.
 */
export function estimateSignupBodyFat(
  readings: readonly SignupBodyFatReading[],
): SignupBodyFatEstimate | null {
  const ordered = orderedFiniteReadings(readings)
  if (!ordered) return null
  const outside = ordered.some((row) => row.body_fat_percent < 3 || row.body_fat_percent > 60)
  if (outside)
    return {
      is_estimate: true,
      readings: ordered,
      by_sex: {
        masculino: { usable: false, reason: 'out_of_range' },
        feminino: { usable: false, reason: 'out_of_range' },
      },
    }
  const { sum, divisor } = decimalSum(ordered.map((row) => row.body_fat_percent))
  const hundredths = (sum * 100n * 2n + divisor) / (divisor * 2n)
  const value = Number(hundredths) / 100
  return {
    is_estimate: true,
    readings: ordered,
    by_sex: {
      masculino: { usable: true, body_fat_percent: value },
      feminino: { usable: true, body_fat_percent: value },
    },
  }
}
